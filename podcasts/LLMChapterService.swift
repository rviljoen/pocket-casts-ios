import AVFoundation
import Foundation
import PocketCastsUtils

/// Extracts chapters from show notes by calling the Anthropic Messages API directly.
/// Requires an API key, entered in the LLM Chapters settings screen and stored in the Keychain.
actor LLMChapterService {
    static let shared = LLMChapterService()

    private static let baseURL = URL(string: "https://api.anthropic.com/v1")!
    private static let apiVersion = "2023-06-01"
    private static let fallbackBeta = "server-side-fallback-2026-07-01"

    /// Models that accept `fallbacks: "default"`. Other models either reject it or ignore it.
    private static let serverSideFallbackModels: Set<String> = ["claude-fable-5-1", "claude-opus-5-5", "claude-opus-5", "claude-sonnet-5-5"]

    private static let systemPrompt = """
    You are a podcast chapter extractor. Given podcast show notes (which may be HTML or plain text), extract any chapter/timestamp information.

    For each chapter return:
    - "start_time": the timestamp exactly as written in the show notes, in HH:MM:SS or MM:SS format
    - "title": the chapter title
    - "url": a URL associated with the chapter, or null if there is none

    Rules:
    - Only include entries that have both a timestamp AND a title.
    - Ignore sponsor mentions, links, or social media handles that don't have timestamps.
    - Return an empty chapters array if no chapter timestamps are found.
    - If chapters are found but the first one does not start at 00:00, prepend {"start_time": "00:00", "title": "Intro", "url": null}.
    - Do not add a 00:00 Intro entry if no chapters were found.
    """

    private static let outputSchema: [String: Any] = [
        "type": "object",
        "properties": [
            "chapters": [
                "type": "array",
                "items": [
                    "type": "object",
                    "properties": [
                        "start_time": ["type": "string"],
                        "title": ["type": "string"],
                        "url": ["anyOf": [["type": "string"], ["type": "null"]]]
                    ],
                    "required": ["start_time", "title", "url"],
                    "additionalProperties": false
                ]
            ]
        ],
        "required": ["chapters"],
        "additionalProperties": false
    ]

    private struct MessagesResponse: Decodable {
        struct Block: Decodable {
            let type: String
            let text: String?
        }

        let content: [Block]
        let stopReason: String?

        enum CodingKeys: String, CodingKey {
            case content
            case stopReason = "stop_reason"
        }
    }

    private struct ChapterOutput: Decodable {
        struct Chapter: Decodable {
            let startTime: String
            let title: String
            let url: String?

            enum CodingKeys: String, CodingKey {
                case startTime = "start_time"
                case title
                case url
            }
        }

        let chapters: [Chapter]
    }

    private enum ExtractionError: LocalizedError {
        case missingAPIKey
        case httpStatus(Int, String)
        case stopReason(String)

        var errorDescription: String? {
            switch self {
            case .missingAPIKey:
                "no Anthropic API key set"
            case .httpStatus(let status, let body):
                "HTTP \(status) - \(body)"
            case .stopReason(let reason):
                "unusable response (stop_reason: \(reason))"
            }
        }
    }

    /// How long a failed extraction is remembered before the next chapter load may retry it.
    private static let failureRetryInterval: TimeInterval = 10 * 60

    private let cache = LLMChapterCache()

    /// Requests in progress, so loading the same episode again while one runs waits for it
    /// instead of paying for a second request. The actor re-enters across `await`, so this
    /// is what keeps concurrent loads to a single request.
    private var inFlight: [LLMChapterCache.Key: Task<[LLMChapterCache.Entry.CachedChapter]?, Never>] = [:]

    /// When each recent extraction failed. Failures aren't cached on disk, so this stops
    /// every chapter load from re-sending a request that just failed.
    private var recentFailures: [LLMChapterCache.Key: Date] = [:]

    func extractChapters(episodeUUID: String, showNotes: String, episodeTitle: String?, duration: TimeInterval) async -> [ChapterInfo] {
        let key = LLMChapterCache.Key(episodeUUID: episodeUUID, model: Settings.llmChapterModel, showNotes: showNotes)

        // Empty results are cached too, so show notes without timestamps cost one request, not one per load.
        if let cached = cache.load(key) {
            FileLog.shared.addMessage("LLMChapterService: returning \(cached.chapters.count) cached chapters for \(episodeUUID)")
            return convert(cached.chapters, episodeDuration: duration)
        }

        if let failedAt = recentFailures[key], Date().timeIntervalSince(failedAt) < Self.failureRetryInterval {
            FileLog.shared.addMessage("LLMChapterService: skipping \(episodeUUID), extraction failed \(Int(Date().timeIntervalSince(failedAt)))s ago")
            return []
        }

        // A missing key isn't remembered as a failure, so entering one takes effect on the next load.
        guard let apiKey = Settings.llmChapterAPIKey else {
            FileLog.shared.addMessage("LLMChapterService: error - \(ExtractionError.missingAPIKey.localizedDescription)")
            return []
        }

        let task: Task<[LLMChapterCache.Entry.CachedChapter]?, Never>
        if let existing = inFlight[key] {
            task = existing
        } else {
            task = Task {
                defer { self.inFlight[key] = nil }
                do {
                    let chapters = try await self.requestChapters(apiKey: apiKey, model: key.model, showNotes: showNotes, episodeTitle: episodeTitle, duration: duration)
                    FileLog.shared.addMessage("LLMChapterService: extracted \(chapters.count) chapters from show notes")
                    self.recentFailures[key] = nil
                    self.cache.save(LLMChapterCache.Entry(key: key, chapters: chapters))
                    return chapters
                } catch {
                    FileLog.shared.addMessage("LLMChapterService: error - \(error.localizedDescription)")
                    self.recentFailures[key] = Date()
                    return nil
                }
            }
            inFlight[key] = task
        }

        guard let chapters = await task.value else { return [] }
        return convert(chapters, episodeDuration: duration)
    }

    /// Runs a real extraction without reading or writing the cache, and throws instead of
    /// returning an empty list, so the settings screen can show what went wrong.
    func testExtraction(showNotes: String, episodeTitle: String?, duration: TimeInterval) async throws -> [ChapterInfo] {
        guard let apiKey = Settings.llmChapterAPIKey else { throw ExtractionError.missingAPIKey }

        let chapters = try await requestChapters(apiKey: apiKey, model: Settings.llmChapterModel, showNotes: showNotes, episodeTitle: episodeTitle, duration: duration)
        return convert(chapters, episodeDuration: duration)
    }

    private func requestChapters(apiKey: String, model: String, showNotes: String, episodeTitle: String?, duration: TimeInterval) async throws -> [LLMChapterCache.Entry.CachedChapter] {
        var userParts: [String] = []
        if let episodeTitle {
            userParts.append("Episode: \(episodeTitle)")
        }
        if duration > 0 {
            userParts.append("Episode duration: \(Int(duration) / 60):\(String(format: "%02d", Int(duration) % 60))")
        }
        userParts.append("Show notes:\n\n\(showNotes)")

        var body: [String: Any] = [
            "model": model,
            "max_tokens": 16000,
            "system": Self.systemPrompt,
            "messages": [["role": "user", "content": userParts.joined(separator: "\n")]],
            "output_config": [
                "effort": "low",
                "format": ["type": "json_schema", "schema": Self.outputSchema]
            ]
        ]

        // Thinking on current models can make even a low-effort request take a while.
        var request = Self.request(url: Self.baseURL.appendingPathComponent("messages"), apiKey: apiKey, timeout: 90)
        if Self.serverSideFallbackModels.contains(model) {
            body["fallbacks"] = "default"
            request.setValue(Self.fallbackBeta, forHTTPHeaderField: "anthropic-beta")
        }
        request.httpMethod = "POST"
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        try Self.checkStatus(response, data: data)

        let message = try JSONDecoder().decode(MessagesResponse.self, from: data)
        // A refusal or truncated response may not match the schema, so don't try to parse it.
        guard message.stopReason == "end_turn" else {
            throw ExtractionError.stopReason(message.stopReason ?? "none")
        }

        // Thinking blocks come back alongside the text, so only read the text blocks.
        let text = message.content.filter { $0.type == "text" }.compactMap(\.text).joined()
        do {
            let output = try JSONDecoder().decode(ChapterOutput.self, from: Data(text.utf8))
            return Self.cleanUp(output.chapters)
        } catch {
            FileLog.shared.addMessage("LLMChapterService: failed to parse response: \(text)")
            throw error
        }
    }

    /// Converts timestamps to seconds, then sorts and removes duplicates. Chapters past the
    /// end of the episode are dropped in `convert`, since the duration may not be known yet.
    private static func cleanUp(_ chapters: [ChapterOutput.Chapter]) -> [LLMChapterCache.Entry.CachedChapter] {
        var seen = Set<String>()
        return chapters
            .compactMap { chapter -> LLMChapterCache.Entry.CachedChapter? in
                guard let startTime = seconds(fromTimestamp: chapter.startTime) else { return nil }
                return LLMChapterCache.Entry.CachedChapter(startTime: startTime, title: chapter.title, url: chapter.url)
            }
            .sorted { $0.startTime < $1.startTime }
            .filter { seen.insert("\($0.startTime)|\($0.title)").inserted }
    }

    /// Parses HH:MM:SS, MM:SS or SS into seconds.
    private static func seconds(fromTimestamp timestamp: String) -> Double? {
        let parts = timestamp.trimmingCharacters(in: .whitespaces).split(separator: ":").map { Double($0) }
        guard !parts.isEmpty, parts.count <= 3, !parts.contains(nil) else { return nil }
        return parts.compactMap { $0 }.reduce(0) { $0 * 60 + $1 }
    }

    private static func request(url: URL, apiKey: String, timeout: TimeInterval) -> URLRequest {
        var request = URLRequest(url: url, timeoutInterval: timeout)
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue(apiVersion, forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        return request
    }

    private static func checkStatus(_ response: URLResponse, data: Data) throws {
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else {
            throw ExtractionError.httpStatus(status, String(data: data, encoding: .utf8) ?? "")
        }
    }

    /// A zero `episodeDuration` means it isn't known yet: no chapters are dropped, and the
    /// last chapter gets a zero duration rather than a negative one.
    private func convert(_ chapters: [LLMChapterCache.Entry.CachedChapter], episodeDuration: TimeInterval) -> [ChapterInfo] {
        let chapters = episodeDuration > 0 ? chapters.filter { $0.startTime <= episodeDuration } : chapters
        return chapters.enumerated().map { index, chapter in
            let info = ChapterInfo()
            info.title = chapter.title
            info.index = index
            info.startTime = CMTime(seconds: chapter.startTime, preferredTimescale: 1000000)
            if let next = chapters[safe: index + 1] {
                info.duration = next.startTime - chapter.startTime
            } else {
                info.duration = max(episodeDuration - chapter.startTime, 0)
            }
            if let urlString = chapter.url {
                info.url = urlString
            }
            return info
        }
    }
}
