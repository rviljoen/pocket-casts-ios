import AVFoundation
import Foundation
import PocketCastsUtils

/// Builds chapters with the Anthropic Messages API, called directly. Requires an API key,
/// entered in the LLM Chapters settings screen and stored in the Keychain.
///
/// Two requests are involved:
/// - `extractChapters` reads the show notes. It returns timestamped chapters when the show
///   notes have them, or else the episode's topic list when the show notes have one without
///   timestamps.
/// - `alignTopics` places such a topic list on the timeline of the server-generated
///   transcript, so the resulting chapters share the generated chapters' reference timeline.
actor LLMChapterService {
    static let shared = LLMChapterService()

    /// What `extractChapters` found in the show notes.
    struct ShowNotesExtraction {
        /// Timestamped chapters, when the show notes have them.
        let chapters: [ChapterInfo]
        /// The episode's topics, when the show notes list or describe them without
        /// timestamps. Empty whenever `chapters` isn't.
        let topics: [String]
        /// Whether `topics` follow the episode's running order. True for a list of topics;
        /// false for topics drawn from a prose summary, which may mention them in any order.
        var topicsInOrder = true

        static let empty = ShowNotesExtraction(chapters: [], topics: [])
    }

    private static let baseURL = URL(string: "https://api.anthropic.com/v1")!
    private static let apiVersion = "2023-06-01"
    private static let fallbackBeta = "server-side-fallback-2026-07-01"

    /// Models that accept `fallbacks: "default"`. Other models either reject it or ignore it.
    private static let serverSideFallbackModels: Set<String> = ["claude-fable-5-1", "claude-opus-5-5", "claude-opus-5", "claude-sonnet-5-5"]

    // MARK: - Show notes extraction

    /// Bump when `showNotesPrompt` or `showNotesSchema` changes, so cached results are requested again.
    private static let showNotesPromptVersion = 4

    private static let showNotesPrompt = """
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

    Topics:
    - Only when no chapter timestamps are found: if the show notes list the topics or segments discussed in the episode, in the order they come up (for example a bulleted rundown, or a "Topics" / "In this episode" / "We discuss" list), return them in "topics", in that order.
    - Write each topic as a short chapter title, keeping the show notes' own wording where possible.
    - A topic is a story or segment, not a list item. News rundowns often list several links or headlines about the same story (for example the same company's announcement reported by different outlets, or a launch and the reaction to it); combine those into one topic named for the story, rather than one topic per link.
    - Leave out sponsors, ads, promo codes, links, credits, calls to action, social handles, and guest bios.
    - A prose summary can also give the topics, when it names at least 3 distinct, concrete things the episode discusses (for example "we discuss why X, how Y, and whether Z; we also cover W"). Then make each one a topic, in the order the summary mentions them. Leave out the guest's bio, the umbrella theme of the whole episode, and calls to action like "tune in" or "hit play". A vague teaser that doesn't name specific discussion points gives no topics.
    - "topics_in_order": true when the topics come from a list laid out in running order, false when they come from a prose summary, whose order may not follow the episode.
    - Return an empty topics array if chapters were found, or if the show notes neither list nor describe the topics.
    """

    private static let showNotesSchema: [String: Any] = [
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
            ],
            "topics": [
                "type": "array",
                "items": ["type": "string"]
            ],
            "topics_in_order": ["type": "boolean"]
        ],
        "required": ["chapters", "topics", "topics_in_order"],
        "additionalProperties": false
    ]

    private struct ShowNotesOutput: Decodable {
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
        let topics: [String]
        let topicsInOrder: Bool?

        enum CodingKeys: String, CodingKey {
            case chapters
            case topics
            case topicsInOrder = "topics_in_order"
        }
    }

    // MARK: - Transcript alignment

    /// Bump when `alignmentPrompt`, `alignmentSchema` or the transcript formatting changes.
    private static let alignmentPromptVersion = 9

    /// Show notes need at least this many topics before they're worth aligning.
    static let minimumTopicCount = 3

    /// Consecutive transcript cues are merged into one timestamped line covering about this long.
    /// Chapter and ad boundaries snap to line starts, so this is also their precision. Each
    /// extra line only adds a timestamp, so going finer costs little.
    private static let transcriptLineInterval: TimeInterval = 10

    /// Ads shorter than this are treated as noise and dropped.
    private static let minimumAdDuration: TimeInterval = 10

    /// A topic chapter shorter than this before the next chapter is folded into the one before
    /// it: it's a passing mention, or several show notes items covering one story.
    private static let minimumTopicDuration: TimeInterval = 45

    /// When the next topic starts within this long after an ad, it's moved to the end of the
    /// ad instead of the interrupted topic getting a chapter that short where it resumes.
    private static let minimumResumedDuration: TimeInterval = 30

    /// Prefix for ad chapter titles. Keeping it fixed lets the chapter filter keywords
    /// setting deselect every ad chapter with one keyword.
    private static let adTitlePrefix = "AD:"

    /// A condensed transcript longer than this is skipped rather than sent. An hour of
    /// speech condenses to roughly 50k characters, so this only rules out extreme cases.
    private static let maxTranscriptCharacters = 600_000

    /// When the first aligned topic starts within this many seconds of the beginning, it's
    /// moved to 0:00 rather than getting an "Intro" chapter in front of it.
    private static let introThreshold: TimeInterval = 30

    private static let alignmentPrompt = """
    You place chapter markers in a podcast episode. You are given the episode's topics, numbered in the order the show notes list them, and a transcript of the episode in which every line starts with a [H:MM:SS] timestamp.

    For each topic, find the transcript line where the discussion of that topic begins, and return:
    - "topic_index": the topic's number from the list
    - "start_time": the timestamp of that transcript line, copied exactly as written without the brackets
    - "start_quote": the first 5 to 8 words of the discussion of the topic, copied exactly from the transcript, including any transcription mistakes
    - "title": a short chapter title for the topic, based on the show notes wording; don't invent new topics

    Rules:
    - Topics are usually discussed in the order listed, so start times should increase with topic_index. When the topics are marked as coming from a summary, they can come up in any order; place each where it's mainly discussed.
    - A chapter starts where the topic itself is introduced, not at an ad break, sponsor read, or housekeeping that comes before it.
    - If a topic isn't discussed, or you can't locate where it begins with reasonable confidence, leave it out rather than guessing.
    - Each topic appears at most once.
    - A topic may end with "(show notes time H:MM:SS)": where the show notes say it starts, in a version of the episode that can differ from this transcript (inserted ads shift everything after them). Use it as a hint to find the right place, but go by where the transcript shows the topic begins, and leave the time out of the title.

    Music:
    - The transcript may contain lines marking music detected in the audio, with how sure the detection is:
      - "[0:12:41] [music until 0:12:47, confidence 62%]": music in its own right, possibly with someone talking over it, like a show's intro, a jingle between segments, or a sting going into or out of an ad break.
      - "[0:09:37] [music bed under speech until 0:10:26, confidence 30%]": quiet background music under talking, which in podcasts usually means an ad or promo is being read. Plain conversation and news reading normally have none.
    - Use them as hints for where topics and ads start and end, together with what's being said; music alone doesn't make a topic or an ad.
    - Never use a music line's timestamp as a start_time or end_time, and never quote a music line: use the timestamp of the transcript line with the words.

    Ads:
    - Also list every ad break in "ads": sponsor reads, ad spots, and promos for other podcasts, including ones the hosts read themselves.
    - "start_time": the timestamp of the transcript line where the ad starts.
    - "start_quote": the first 5 to 8 words of the ad, copied exactly from the transcript. A line often holds the end of the episode's content and the start of the ad, so quote where the ad itself begins (for example "This episode is brought to you by").
    - "end_time": the timestamp of the first transcript line after the ad, where the episode's content resumes, or null if the ad runs to the end of the episode.
    - "end_quote": the last 5 to 8 words of the ad, copied exactly from the transcript, ending where the episode's content resumes, or null if the ad runs to the end of the episode.
    - "sponsor": the brand, product, or show being advertised, as a short name (for example "Squarespace"), or null if it isn't clear.
    - Back-to-back ads for different sponsors are separate entries.
    - Don't count the hosts' own calls to action (rate the show, join our Patreon, follow us) as ads.
    - Return an empty ads array if there are none.
    """

    private static let alignmentSchema: [String: Any] = [
        "type": "object",
        "properties": [
            "chapters": [
                "type": "array",
                "items": [
                    "type": "object",
                    "properties": [
                        "topic_index": ["type": "integer"],
                        "start_time": ["type": "string"],
                        "start_quote": ["type": "string"],
                        "title": ["type": "string"]
                    ],
                    "required": ["topic_index", "start_time", "start_quote", "title"],
                    "additionalProperties": false
                ]
            ],
            "ads": [
                "type": "array",
                "items": [
                    "type": "object",
                    "properties": [
                        "start_time": ["type": "string"],
                        "start_quote": ["type": "string"],
                        "end_time": ["anyOf": [["type": "string"], ["type": "null"]]],
                        "end_quote": ["anyOf": [["type": "string"], ["type": "null"]]],
                        "sponsor": ["anyOf": [["type": "string"], ["type": "null"]]]
                    ],
                    "required": ["start_time", "start_quote", "end_time", "end_quote", "sponsor"],
                    "additionalProperties": false
                ]
            ]
        ],
        "required": ["chapters", "ads"],
        "additionalProperties": false
    ]

    private struct AlignmentOutput: Decodable {
        struct Chapter: Decodable {
            let topicIndex: Int
            let startTime: String
            /// Optional so responses cached before quotes were asked for still decode.
            let startQuote: String?
            let title: String

            enum CodingKeys: String, CodingKey {
                case topicIndex = "topic_index"
                case startTime = "start_time"
                case startQuote = "start_quote"
                case title
            }
        }

        struct Ad: Decodable {
            let startTime: String
            let startQuote: String?
            let endTime: String?
            let endQuote: String?
            let sponsor: String?

            enum CodingKeys: String, CodingKey {
                case startTime = "start_time"
                case startQuote = "start_quote"
                case endTime = "end_time"
                case endQuote = "end_quote"
                case sponsor
            }
        }

        let chapters: [Chapter]
        let ads: [Ad]
    }

    /// One line of the condensed transcript sent for alignment.
    private struct TranscriptLine {
        let startTime: TimeInterval
        let text: String
        /// A music marker rather than words, which boundaries never snap to.
        var isMarker = false
    }

    // MARK: - Shared

    private struct MessagesResponse: Decodable {
        struct Block: Decodable {
            let type: String
            let text: String?
        }

        struct Usage: Decodable {
            let inputTokens: Int?
            let outputTokens: Int?

            enum CodingKeys: String, CodingKey {
                case inputTokens = "input_tokens"
                case outputTokens = "output_tokens"
            }
        }

        let content: [Block]
        let stopReason: String?
        let usage: Usage?

        enum CodingKeys: String, CodingKey {
            case content
            case stopReason = "stop_reason"
            case usage
        }
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

    /// How long a failed request is remembered before the next chapter load may retry it.
    private static let failureRetryInterval: TimeInterval = 10 * 60

    private let cache = LLMChapterCache()

    /// Requests in progress, so loading the same episode again while one runs waits for it
    /// instead of paying for a second request. The actor re-enters across `await`, so this
    /// is what keeps concurrent loads to a single request.
    private var inFlight: [LLMChapterCache.Key: Task<LLMChapterCache.Entry?, Never>] = [:]

    /// When each recent request failed. Failures aren't cached on disk, so this stops
    /// every chapter load from re-sending a request that just failed.
    private var recentFailures: [LLMChapterCache.Key: Date] = [:]

    // MARK: - Public API

    func extractChapters(episodeUUID: String, showNotes: String, episodeTitle: String?, duration: TimeInterval) async -> ShowNotesExtraction {
        let key = LLMChapterCache.Key(
            episodeUUID: episodeUUID,
            kind: .showNotes,
            model: Settings.llmChapterModel,
            version: Self.showNotesPromptVersion,
            inputs: [showNotes]
        )

        // Empty results are cached too, so show notes without chapters cost one request, not one per load.
        let entry = await cachedRequest(key) { apiKey in
            let output = try await self.requestShowNotesExtraction(apiKey: apiKey, model: key.model, showNotes: showNotes, episodeTitle: episodeTitle, duration: duration)
            let chapters = Self.cleanUp(output.chapters)
            let topics = chapters.isEmpty ? Self.cleanUp(output.topics) : []
            FileLog.shared.addMessage("LLMChapterService: extracted \(chapters.count) chapters and \(topics.count) untimed topics from show notes")
            return LLMChapterCache.Entry(key: key, chapters: chapters, topics: topics, topicsInOrder: output.topicsInOrder ?? true)
        }

        guard let entry else { return .empty }
        let topicsInOrder = entry.topicsInOrder ?? true
        Self.debugLog(
            "show notes for \(episodeUUID): \(entry.chapters.count) timestamped chapters, \(entry.topics.count) topics\(entry.topics.isEmpty ? "" : topicsInOrder ? " (listed in order)" : " (from a prose summary)")",
            body: entry.topics.enumerated().map { "\($0.offset). \($0.element)" }.joined(separator: "\n")
        )
        return ShowNotesExtraction(chapters: convert(entry.chapters, episodeDuration: duration), topics: entry.topics, topicsInOrder: topicsInOrder)
    }

    /// Places `topics` on the timeline of `transcript`, returning no chapters when too few
    /// topics could be located. `transcript` should be the server-generated transcript, so
    /// the chapters share the reference timeline that generated chapters use.
    /// - Parameters:
    ///   - topicHints: Where the show notes say each topic starts, when they give times.
    ///   - topicsInOrder: Whether the topics follow the episode's order, so a topic placed
    ///     out of order is a mistake.
    ///   - transcriptSource: Where `transcript` came from, for debug logging.
    func alignTopics(episodeUUID: String, topics: [String], topicHints: [TimeInterval]? = nil, topicsInOrder: Bool = true, transcript: TranscriptModel, transcriptSource: String, episodeTitle: String?, duration: TimeInterval) async -> [ChapterInfo] {
        let topics = zip(topics.indices, topics).map { index, topic in
            guard let hint = topicHints?[safe: index] else { return topic }
            return "\(topic) (show notes time \(Self.timestamp(hint)))"
        }

        let lines = Self.condense(transcript)
        guard !lines.isEmpty else {
            FileLog.shared.addMessage("LLMChapterService: transcript for \(episodeUUID) has no timed lines to align against")
            return []
        }

        let transcriptText = lines.map { "[\(Self.timestamp($0.startTime))] \($0.text)" }.joined(separator: "\n")
        guard transcriptText.count <= Self.maxTranscriptCharacters else {
            FileLog.shared.addMessage("LLMChapterService: transcript for \(episodeUUID) is too long to align (\(transcriptText.count) characters)")
            return []
        }

        let key = LLMChapterCache.Key(
            episodeUUID: episodeUUID,
            kind: .transcriptAligned,
            model: Settings.llmChapterModel,
            version: Self.alignmentPromptVersion,
            inputs: topics + [transcriptText, topicsInOrder ? "ordered" : "unordered"]
        )

        Self.debugLog("""
            aligning \(episodeUUID) "\(episodeTitle ?? "")" with \(key.model): \(topics.count) topics, \
            \(transcriptSource) transcript, \(transcript.cues.count) cues condensed to \(lines.count) lines with \(transcript.music.count) music markers (\(transcriptText.count) characters), \
            transcript spans \(Self.timestamp(lines.first?.startTime ?? 0))-\(Self.timestamp(transcript.cues.last?.endTime ?? 0)), \
            episode duration \(duration > 0 ? Self.timestamp(duration) : "unknown")
            """)
        Self.debugLog("topics sent", body: topics.enumerated().map { "\($0.offset). \($0.element)" }.joined(separator: "\n"))
        Self.debugLog("transcript sent", body: transcriptText)

        // Only the model's response is cached; turning it into chapters happens on every load,
        // so changes to that processing apply to cached episodes without a new request.
        let entry = await cachedRequest(key) { apiKey in
            let (_, rawResponse) = try await self.requestAlignment(apiKey: apiKey, model: key.model, topics: topics, topicsInOrder: topicsInOrder, transcriptText: transcriptText, episodeTitle: episodeTitle)
            return LLMChapterCache.Entry(key: key, chapters: [], rawResponse: rawResponse)
        }

        guard let rawResponse = entry?.rawResponse else { return [] }
        Self.debugLog("model response", body: rawResponse)
        guard let output = try? JSONDecoder().decode(AlignmentOutput.self, from: Data(rawResponse.utf8)) else {
            FileLog.shared.addMessage("LLMChapterService: cached alignment response for \(episodeUUID) doesn't decode")
            return []
        }

        let lineStarts = lines.filter { !$0.isMarker }.map(\.startTime)
        let quotes = QuoteLocator(transcript: transcript)
        let topicChapters = Self.placeTopics(output.chapters, topicCount: topics.count, inOrder: topicsInOrder, lineStarts: lineStarts, quotes: quotes)
        // Ads only make sense around topics that were placed; without them, fall back entirely.
        let ads = topicChapters.isEmpty ? [] : Self.placeAds(output.ads, lineStarts: lineStarts, quotes: quotes)
        if topicChapters.isEmpty, !output.ads.isEmpty {
            Self.debugLog("ignoring \(output.ads.count) ads because no topic chapters survived")
        }
        let chapters = Self.removeShortChapters(Self.insertAds(ads, into: topicChapters))
        FileLog.shared.addMessage("LLMChapterService: aligned \(topicChapters.count) chapters from \(topics.count) topics (model returned \(output.chapters.count)) with \(ads.count) ad chapters from \(output.ads.count) ads")
        Self.debugLog("final chapters", body: chapters.map { "\(Self.timestamp($0.startTime))  \($0.title)" }.joined(separator: "\n"))
        return convert(chapters, episodeDuration: duration)
    }

    /// Runs a real extraction without reading or writing the cache, and throws instead of
    /// returning an empty list, so the settings screen can show what went wrong.
    func testExtraction(showNotes: String, episodeTitle: String?, duration: TimeInterval) async throws -> [ChapterInfo] {
        guard let apiKey = Settings.llmChapterAPIKey else { throw ExtractionError.missingAPIKey }

        let output = try await requestShowNotesExtraction(apiKey: apiKey, model: Settings.llmChapterModel, showNotes: showNotes, episodeTitle: episodeTitle, duration: duration)
        return convert(Self.cleanUp(output.chapters), episodeDuration: duration)
    }

    // MARK: - Caching

    /// Returns the cached entry for `key`, or runs `perform` and caches what it returns.
    /// Returns nil when there's no API key or the request failed, which isn't cached.
    private func cachedRequest(_ key: LLMChapterCache.Key, perform: @escaping (_ apiKey: String) async throws -> LLMChapterCache.Entry) async -> LLMChapterCache.Entry? {
        let label = "\(key.kind.rawValue) for \(key.episodeUUID)"

        if let cached = cache.load(key) {
            FileLog.shared.addMessage("LLMChapterService: returning cached \(label) (\(cached.chapters.count) chapters, \(cached.topics.count) topics)")
            Self.debugLog("cache hit for \(label): no request sent, the logs below come from the cached response")
            return cached
        }

        if let failedAt = recentFailures[key], Date().timeIntervalSince(failedAt) < Self.failureRetryInterval {
            FileLog.shared.addMessage("LLMChapterService: skipping \(label), request failed \(Int(Date().timeIntervalSince(failedAt)))s ago")
            return nil
        }

        // A missing key isn't remembered as a failure, so entering one takes effect on the next load.
        guard let apiKey = Settings.llmChapterAPIKey else {
            FileLog.shared.addMessage("LLMChapterService: error - \(ExtractionError.missingAPIKey.localizedDescription)")
            return nil
        }

        let task: Task<LLMChapterCache.Entry?, Never>
        if let existing = inFlight[key] {
            task = existing
        } else {
            task = Task {
                defer { self.inFlight[key] = nil }
                do {
                    let entry = try await perform(apiKey)
                    self.recentFailures[key] = nil
                    self.cache.save(entry, kind: key.kind)
                    return entry
                } catch {
                    FileLog.shared.addMessage("LLMChapterService: error (\(label)) - \(error.localizedDescription)")
                    self.recentFailures[key] = Date()
                    return nil
                }
            }
            inFlight[key] = task
        }

        return await task.value
    }

    // MARK: - Requests

    private func requestShowNotesExtraction(apiKey: String, model: String, showNotes: String, episodeTitle: String?, duration: TimeInterval) async throws -> ShowNotesOutput {
        var userParts: [String] = []
        if let episodeTitle {
            userParts.append("Episode: \(episodeTitle)")
        }
        if duration > 0 {
            userParts.append("Episode duration: \(Int(duration) / 60):\(String(format: "%02d", Int(duration) % 60))")
        }
        userParts.append("Show notes:\n\n\(showNotes)")

        // Thinking on current models can make even a low-effort request take a while.
        return try await sendMessage(
            apiKey: apiKey,
            model: model,
            system: Self.showNotesPrompt,
            user: userParts.joined(separator: "\n"),
            schema: Self.showNotesSchema,
            effort: "low",
            timeout: 90
        ).output
    }

    private func requestAlignment(apiKey: String, model: String, topics: [String], topicsInOrder: Bool, transcriptText: String, episodeTitle: String?) async throws -> (output: AlignmentOutput, rawText: String) {
        var userParts: [String] = []
        if let episodeTitle {
            userParts.append("Episode: \(episodeTitle)")
        }
        let topicsHeading = topicsInOrder ? "Topics:" : "Topics (from a summary of the episode, so they may come up in any order):"
        userParts.append(topicsHeading + "\n" + topics.enumerated().map { "\($0.offset). \($0.element)" }.joined(separator: "\n"))
        userParts.append("Transcript:\n\(transcriptText)")

        // Reading a whole transcript is a much larger request than the show notes, so it
        // gets more effort and a longer timeout.
        return try await sendMessage(
            apiKey: apiKey,
            model: model,
            system: Self.alignmentPrompt,
            user: userParts.joined(separator: "\n\n"),
            schema: Self.alignmentSchema,
            effort: "medium",
            timeout: 180
        )
    }

    /// Sends one structured-output request and decodes its JSON text as `Output`, returning
    /// the raw text alongside it.
    private func sendMessage<Output: Decodable>(apiKey: String, model: String, system: String, user: String, schema: [String: Any], effort: String, timeout: TimeInterval) async throws -> (output: Output, rawText: String) {
        var body: [String: Any] = [
            "model": model,
            "max_tokens": 16000,
            "system": system,
            "messages": [["role": "user", "content": user]],
            "output_config": [
                "effort": effort,
                "format": ["type": "json_schema", "schema": schema]
            ]
        ]

        var request = Self.request(url: Self.baseURL.appendingPathComponent("messages"), apiKey: apiKey, timeout: timeout)
        if Self.serverSideFallbackModels.contains(model) {
            body["fallbacks"] = "default"
            request.setValue(Self.fallbackBeta, forHTTPHeaderField: "anthropic-beta")
        }
        request.httpMethod = "POST"
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let requestStart = Date()
        let (data, response) = try await URLSession.shared.data(for: request)
        try Self.checkStatus(response, data: data)

        let message = try JSONDecoder().decode(MessagesResponse.self, from: data)
        Self.debugLog("""
            \(model) responded in \(String(format: "%.1f", Date().timeIntervalSince(requestStart)))s, \
            stop_reason: \(message.stopReason ?? "none"), \
            tokens in/out: \(message.usage?.inputTokens.map(String.init) ?? "?")/\(message.usage?.outputTokens.map(String.init) ?? "?"), \
            blocks: \(message.content.map(\.type).joined(separator: ","))
            """)
        // A refusal or truncated response may not match the schema, so don't try to parse it.
        guard message.stopReason == "end_turn" else {
            throw ExtractionError.stopReason(message.stopReason ?? "none")
        }

        // Thinking blocks come back alongside the text, so only read the text blocks.
        let text = message.content.filter { $0.type == "text" }.compactMap(\.text).joined()
        do {
            return (try JSONDecoder().decode(Output.self, from: Data(text.utf8)), text)
        } catch {
            FileLog.shared.addMessage("LLMChapterService: failed to parse response: \(text)")
            throw error
        }
    }

    // MARK: - Processing

    /// Converts timestamps to seconds, then sorts and removes duplicates. Chapters past the
    /// end of the episode are dropped in `convert`, since the duration may not be known yet.
    private static func cleanUp(_ chapters: [ShowNotesOutput.Chapter]) -> [LLMChapterCache.Entry.CachedChapter] {
        var seen = Set<String>()
        return chapters
            .compactMap { chapter -> LLMChapterCache.Entry.CachedChapter? in
                guard let startTime = seconds(fromTimestamp: chapter.startTime) else { return nil }
                return LLMChapterCache.Entry.CachedChapter(startTime: startTime, title: chapter.title, url: chapter.url)
            }
            .sorted { $0.startTime < $1.startTime }
            .filter { seen.insert("\($0.startTime)|\($0.title)").inserted }
    }

    /// Trims topics and drops blank or repeated ones, keeping their order.
    private static func cleanUp(_ topics: [String]) -> [String] {
        var seen = Set<String>()
        return topics
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && seen.insert($0.lowercased()).inserted }
    }

    /// Merges transcript cues into lines covering about `transcriptLineInterval` each, which
    /// keeps the request small while leaving start times precise enough for chapters.
    ///
    /// Detected music becomes marker lines of its own ("[music until H:MM:SS]"), and a line
    /// ends where music starts or stops, so the words on either side of a jingle or around
    /// an ad's music bed start lines the model can point at.
    private static func condense(_ transcript: TranscriptModel) -> [TranscriptLine] {
        let text = transcript.attributedText.string as NSString
        var lines: [TranscriptLine] = []
        var lineStart: TimeInterval?
        var lineText: [String] = []

        func flush() {
            if let lineStart, !lineText.isEmpty {
                lines.append(TranscriptLine(startTime: lineStart, text: lineText.joined(separator: " ")))
            }
            lineStart = nil
            lineText = []
        }

        let music = transcript.music.sorted { $0.range.lowerBound < $1.range.lowerBound }
        var nextMusic = 0
        // Music starts and ends not yet passed: each ends the current line.
        var boundaries = music.flatMap { [$0.range.lowerBound, $0.range.upperBound] }.sorted()[...]

        for cue in transcript.cues.sorted(by: { $0.startTime < $1.startTime }) {
            guard NSMaxRange(cue.characterRange) <= text.length else { continue }
            let cueText = text.substring(with: cue.characterRange)
                .components(separatedBy: .whitespacesAndNewlines)
                .filter { !$0.isEmpty }
                .joined(separator: " ")
            guard !cueText.isEmpty else { continue }

            if let boundary = boundaries.first, boundary <= cue.startTime {
                flush()
                while let first = boundaries.first, first <= cue.startTime {
                    boundaries.removeFirst()
                }
            }
            while nextMusic < music.count, music[nextMusic].range.lowerBound <= cue.startTime {
                flush()
                lines.append(musicLine(music[nextMusic]))
                nextMusic += 1
            }

            if let start = lineStart, cue.startTime - start >= transcriptLineInterval {
                flush()
            }
            if lineStart == nil {
                lineStart = cue.startTime
            }
            lineText.append(cueText)
        }
        flush()
        lines += music[nextMusic...].map(musicLine)

        return lines
    }

    private static func musicLine(_ music: TranscriptMusic) -> TranscriptLine {
        let confidence = music.confidence.map { ", confidence \(Int(($0 * 100).rounded()))%" } ?? ""
        let kind = music.isBed ? "music bed under speech" : "music"
        return TranscriptLine(startTime: music.range.lowerBound, text: "[\(kind) until \(timestamp(music.range.upperBound))\(confidence)]", isMarker: true)
    }

    /// Turns the model's placements into chapters, distrusting it where it's cheap to check:
    /// times move to where the quoted words are, or else snap to the nearest transcript
    /// line, out-of-range topics and repeats are
    /// dropped, and the chapters must follow the show notes order. Returns nothing when fewer
    /// than half the topics survive, so the caller falls back to the generated chapters.
    private static func placeTopics(_ placed: [AlignmentOutput.Chapter], topicCount: Int, inOrder: Bool, lineStarts: [TimeInterval], quotes: QuoteLocator) -> [LLMChapterCache.Entry.CachedChapter] {
        var seenTopics = Set<Int>()
        var decisions: [String] = []
        let candidates = placed
            .compactMap { chapter -> (topic: Int, startTime: TimeInterval, title: String)? in
                let title = chapter.title.trimmingCharacters(in: .whitespacesAndNewlines)
                let description = "topic \(chapter.topicIndex) at \(chapter.startTime) \"\(title)\""
                guard (0..<topicCount).contains(chapter.topicIndex) else {
                    decisions.append("DROP \(description): topic index out of range")
                    return nil
                }
                guard !title.isEmpty else {
                    decisions.append("DROP \(description): empty title")
                    return nil
                }
                guard let time = seconds(fromTimestamp: chapter.startTime),
                      let snapped = lineStarts.min(by: { abs($0 - time) < abs($1 - time) }) else {
                    decisions.append("DROP \(description): unparseable timestamp")
                    return nil
                }
                guard seenTopics.insert(chapter.topicIndex).inserted else {
                    decisions.append("DROP \(description): topic already placed")
                    return nil
                }
                let (start, method) = refine(snapped, quote: chapter.startQuote, edge: .start, quotes: quotes)
                decisions.append("ok   \(description) -> \(timestamp(start)) (\(method))")
                return (chapter.topicIndex, start, title)
            }
            .sorted { $0.topic < $1.topic }

        // Topics from a summary have no order to check: keep each at its own time, dropping
        // only ones placed at the same time as an earlier topic.
        guard inOrder else {
            var seenTimes = Set<TimeInterval>()
            let byTime = candidates.sorted { $0.startTime < $1.startTime }.filter { seenTimes.insert($0.startTime).inserted }
            decisions += candidates.filter { candidate in !byTime.contains { $0.topic == candidate.topic } }
                .map { "DROP topic \($0.topic) at \(timestamp($0.startTime)) \"\($0.title)\": same time as another topic" }
            debugLog("topic placement, any order (\(byTime.count) kept of \(placed.count) returned, \(topicCount) sent)", body: decisions.joined(separator: "\n"))
            return finishPlacement(byTime, topicCount: topicCount)
        }

        // Keep the longest run whose start times increase in topic order. One misplaced
        // topic then costs only that chapter, instead of every chapter after it.
        var runLength = [Int](repeating: 1, count: candidates.count)
        var previous = [Int](repeating: -1, count: candidates.count)
        for i in candidates.indices {
            for j in 0..<i where candidates[j].startTime < candidates[i].startTime && runLength[j] + 1 > runLength[i] {
                runLength[i] = runLength[j] + 1
                previous[i] = j
            }
        }
        var ordered: [(topic: Int, startTime: TimeInterval, title: String)] = []
        var index = runLength.indices.max { runLength[$0] < runLength[$1] } ?? -1
        while index >= 0 {
            ordered.insert(candidates[index], at: 0)
            index = previous[index]
        }

        let outOfOrder = candidates.filter { candidate in !ordered.contains { $0.topic == candidate.topic } }
        decisions += outOfOrder.map { "DROP topic \($0.topic) at \(timestamp($0.startTime)) \"\($0.title)\": out of order with the other topics" }
        debugLog("topic placement (\(ordered.count) kept of \(placed.count) returned, \(topicCount) sent)", body: decisions.joined(separator: "\n"))

        return finishPlacement(ordered, topicCount: topicCount)
    }

    /// Turns placed topics, sorted by time, into chapters: nothing when fewer than half the
    /// topics were placed, and otherwise starting at 0:00, with an "Intro" when the first
    /// topic starts later.
    private static func finishPlacement(_ ordered: [(topic: Int, startTime: TimeInterval, title: String)], topicCount: Int) -> [LLMChapterCache.Entry.CachedChapter] {
        let minimumPlaced = max(2, (topicCount + 1) / 2)
        guard ordered.count >= minimumPlaced else {
            FileLog.shared.addMessage("LLMChapterService: only \(ordered.count) of \(topicCount) topics placed in order, need \(minimumPlaced)")
            return []
        }

        var chapters = ordered.map { LLMChapterCache.Entry.CachedChapter(startTime: $0.startTime, title: $0.title, url: nil) }
        if let first = chapters.first {
            if first.startTime <= introThreshold {
                chapters[0] = LLMChapterCache.Entry.CachedChapter(startTime: 0, title: first.title, url: nil)
            } else {
                chapters.insert(LLMChapterCache.Entry.CachedChapter(startTime: 0, title: "Intro", url: nil), at: 0)
            }
        }
        return chapters
    }

    private struct PlacedAd {
        let startTime: TimeInterval
        /// Where content resumes, or nil when the ad runs to the end of the episode.
        var endTime: TimeInterval?
        var sponsors: [String]

        var title: String {
            sponsors.isEmpty ? LLMChapterService.adTitlePrefix : "\(LLMChapterService.adTitlePrefix) \(sponsors.joined(separator: ", "))"
        }
    }

    /// Snaps ads to transcript lines, merges ones that overlap or share a start, then drops
    /// ones that are still too short.
    ///
    /// Merging comes first because back-to-back ads often snap to the same transcript line
    /// (a line covers about `transcriptLineInterval`), which leaves the first one with no
    /// length of its own. Dropping it would lose a real ad.
    private static func placeAds(_ ads: [AlignmentOutput.Ad], lineStarts: [TimeInterval], quotes: QuoteLocator) -> [PlacedAd] {
        func snap(_ timestamp: String) -> TimeInterval? {
            guard let time = seconds(fromTimestamp: timestamp) else { return nil }
            return lineStarts.min { abs($0 - time) < abs($1 - time) }
        }

        let lastLineStart = lineStarts.last ?? 0
        var decisions: [String] = []
        let candidates = ads
            .compactMap { ad -> PlacedAd? in
                let description = "ad \(ad.startTime)-\(ad.endTime ?? "end") sponsor: \(ad.sponsor ?? "nil")"
                guard let snappedStart = snap(ad.startTime) else {
                    decisions.append("DROP \(description): unparseable start")
                    return nil
                }
                if let endTime = ad.endTime, snap(endTime) == nil {
                    decisions.append("note \(description): unparseable end, treating as running to the end")
                }
                var snappedEnd = ad.endTime.flatMap(snap)
                // An ad ending on the last line runs to the end: there's nothing to resume.
                if let resume = snappedEnd, resume >= lastLineStart {
                    snappedEnd = nil
                }

                let (start, startMethod) = refine(snappedStart, quote: ad.startQuote, edge: .start, quotes: quotes)
                var end: TimeInterval?
                var endMethod = "end"
                if let snappedEnd {
                    let refined = refine(snappedEnd, quote: ad.endQuote, edge: .end, quotes: quotes)
                    end = refined.0
                    endMethod = refined.1
                }

                let sponsor = ad.sponsor?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                decisions.append("snap \(description) -> \(timestamp(start))-\(end.map(timestamp) ?? "end") (start \(startMethod), end \(endMethod))")
                return PlacedAd(startTime: start, endTime: end, sponsors: sponsor.isEmpty ? [] : [sponsor])
            }
            .sorted { $0.startTime < $1.startTime }

        var merged: [PlacedAd] = []
        for ad in candidates {
            if var previous = merged.last, ad.startTime == previous.startTime || ad.startTime < (previous.endTime ?? .infinity) {
                let endTime: TimeInterval? = if let previousEnd = previous.endTime, let adEnd = ad.endTime { max(previousEnd, adEnd) } else { nil }
                decisions.append("MERGE \(ad.title) at \(timestamp(ad.startTime)) into \(previous.title) at \(timestamp(previous.startTime))")
                previous.endTime = endTime
                previous.sponsors += ad.sponsors.filter { !previous.sponsors.contains($0) }
                merged[merged.count - 1] = previous
                continue
            }
            merged.append(ad)
        }

        let placed = merged.filter { ad in
            guard let end = ad.endTime, end - ad.startTime < minimumAdDuration else {
                decisions.append("ok   \(ad.title) \(timestamp(ad.startTime))-\(ad.endTime.map(timestamp) ?? "end")")
                return true
            }
            decisions.append("DROP \(ad.title) \(timestamp(ad.startTime))-\(timestamp(end)): shorter than \(Int(minimumAdDuration))s")
            return false
        }
        debugLog("ad placement (\(placed.count) ad chapters from \(ads.count) ads returned)", body: decisions.isEmpty ? "model returned no ads" : decisions.joined(separator: "\n"))
        return placed
    }

    /// Adds ad chapters to the topic chapters. A topic the model started inside an ad moves
    /// to where the ad ends, and a topic an ad interrupts gets a chapter where it resumes,
    /// so the content after an ad is never counted as part of the ad.
    private static func insertAds(_ ads: [PlacedAd], into topics: [LLMChapterCache.Entry.CachedChapter]) -> [LLMChapterCache.Entry.CachedChapter] {
        var chapters = topics
        for ad in ads {
            let adEnd = ad.endTime ?? .infinity
            let isInsideAd: (LLMChapterCache.Entry.CachedChapter) -> Bool = { $0.startTime >= ad.startTime && $0.startTime < adEnd }
            let inside = chapters.filter(isInsideAd)
            chapters.removeAll(where: isInsideAd)

            // The topic to resume after the ad: the latest one that started inside it, or
            // else the one that was running when it began.
            let resumed = inside.last ?? chapters.last { $0.startTime < ad.startTime }

            chapters.append(LLMChapterCache.Entry.CachedChapter(startTime: ad.startTime, title: ad.title, url: nil))
            if let end = ad.endTime, let resumed, !chapters.contains(where: { $0.startTime == end }) {
                // A topic starting just after the ad starts where it ends instead: a chapter
                // that short for the interrupted topic would only be noise, and what's between
                // ("and we're back") leads into the next topic anyway.
                if let nextIndex = chapters.firstIndex(where: { $0.startTime > end }),
                   chapters[nextIndex].startTime - end < minimumResumedDuration {
                    let next = chapters[nextIndex]
                    chapters[nextIndex] = LLMChapterCache.Entry.CachedChapter(startTime: end, title: next.title, url: next.url)
                } else {
                    chapters.append(LLMChapterCache.Entry.CachedChapter(startTime: end, title: resumed.title, url: nil))
                }
            }
            chapters.sort { $0.startTime < $1.startTime }
        }
        return chapters
    }

    /// Folds chapters too short to be worth a chapter into the one before them, by removing
    /// their start: topic chapters shorter than `minimumTopicDuration` before another topic,
    /// and any non-ad chapter shorter than `minimumResumedDuration` before an ad (a few seconds
    /// of the interrupted topic between back-to-back ads). Ad chapters always stay.
    private static func removeShortChapters(_ chapters: [LLMChapterCache.Entry.CachedChapter]) -> [LLMChapterCache.Entry.CachedChapter] {
        func isAd(_ chapter: LLMChapterCache.Entry.CachedChapter) -> Bool {
            chapter.title.hasPrefix(adTitlePrefix)
        }

        var kept: [LLMChapterCache.Entry.CachedChapter] = []
        var decisions: [String] = []
        for (index, chapter) in chapters.enumerated() {
            guard index > 0, !isAd(chapter), let next = chapters[safe: index + 1] else {
                kept.append(chapter)
                continue
            }
            let length = next.startTime - chapter.startTime
            let minimum = isAd(next) ? minimumResumedDuration : minimumTopicDuration
            if length < minimum {
                decisions.append("DROP \(timestamp(chapter.startTime)) \"\(chapter.title)\": \(Int(length))s before \(isAd(next) ? "an ad" : "the next topic"), shorter than \(Int(minimum))s")
                continue
            }
            kept.append(chapter)
        }
        if !decisions.isEmpty {
            debugLog("short chapters removed", body: decisions.joined(separator: "\n"))
        }
        return kept
    }

    // MARK: - Quotes

    /// Moves `snapped` (a transcript line start) to where `quote` is in the transcript, which
    /// is more precise than the line: a line covers about `transcriptLineInterval`, and often
    /// holds the end of one part and the start of the next. Returns the time and how it was
    /// found, for debug logging.
    private static func refine(_ snapped: TimeInterval, quote: String?, edge: QuoteLocator.Edge, quotes: QuoteLocator) -> (TimeInterval, String) {
        guard let quote, !quote.isEmpty else { return (snapped, "line, no quote") }
        // The quote is in the line the model named, or for an ad's end, usually the line
        // before the one where content resumes.
        let window: ClosedRange<TimeInterval> = switch edge {
        case .start: (snapped - 5)...(snapped + transcriptLineInterval * 2 + 5)
        case .end: (snapped - transcriptLineInterval * 3)...(snapped + transcriptLineInterval + 5)
        }
        guard let time = quotes.time(of: quote, edge: edge, near: snapped, within: window) else {
            return (snapped, "line, quote not found: \"\(quote)\"")
        }
        return (time, "quote")
    }

    // MARK: - Debug logging

    /// Longest console message. `os_log` truncates messages at about 1 KB.
    private static let debugLineLength = 900

    /// Writes diagnostics to the console only (not the file log), in debug builds. Each line
    /// of `body` becomes its own single-line message, since the Xcode console only shows the
    /// first line of a multi-line message, and lines too long for `os_log` are split. Filter
    /// the console on "LLMChapterService [debug]" to see just these.
    private static func debugLog(_ message: String, body: String? = nil) {
        #if DEBUG
        let prefix = "LLMChapterService [debug]"
        FileLog.shared.console("\(prefix): \(message)")
        guard let body else { return }

        for line in body.components(separatedBy: .newlines) where !line.isEmpty {
            var remaining = Substring(line)
            repeat {
                FileLog.shared.console("\(prefix) | \(remaining.prefix(debugLineLength))")
                remaining = remaining.dropFirst(debugLineLength)
            } while !remaining.isEmpty
        }
        #endif
    }

    /// Formats seconds as H:MM:SS, the form the transcript lines use.
    private static func timestamp(_ seconds: TimeInterval) -> String {
        let total = Int(seconds)
        return String(format: "%d:%02d:%02d", total / 3600, (total % 3600) / 60, total % 60)
    }

    /// Parses HH:MM:SS, MM:SS or SS into seconds.
    private static func seconds(fromTimestamp timestamp: String) -> Double? {
        let cleaned = timestamp.trimmingCharacters(in: CharacterSet.whitespaces.union(CharacterSet(charactersIn: "[]")))
        let parts = cleaned.split(separator: ":").map { Double($0) }
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

/// Finds quoted words in a transcript, and the time they're spoken at.
///
/// Text is compared in a normalized form (lowercase letters and digits, with anything else
/// between words read as one space), so punctuation and casing the model changed while
/// quoting don't matter. A time inside a cue is estimated from how far into the cue's
/// text the words are.
private struct QuoteLocator {
    enum Edge {
        /// Where the quote starts.
        case start
        /// Where the quote ends.
        case end
    }

    private struct Position {
        let cue: Int
        /// Where this character starts and ends, as fractions of its cue's text.
        let start: Double
        let end: Double
    }

    private let cues: [TranscriptCue]
    private let text: [Unicode.Scalar]
    private let positions: [Position]

    /// Shortest prefix or suffix of a quote tried when the whole quote isn't found.
    private static let minimumWords = 3

    init(transcript: TranscriptModel) {
        let source = transcript.attributedText.string as NSString
        cues = transcript.cues.sorted { $0.startTime < $1.startTime }
        var text: [Unicode.Scalar] = []
        var positions: [Position] = []
        for (index, cue) in cues.enumerated() {
            guard NSMaxRange(cue.characterRange) <= source.length else { continue }
            let normalized = Self.normalize(source.substring(with: cue.characterRange))
            guard !normalized.isEmpty else { continue }
            if !text.isEmpty {
                text.append(" ")
                positions.append(Position(cue: index, start: 0, end: 0))
            }
            let count = Double(normalized.count)
            for (offset, scalar) in normalized.enumerated() {
                text.append(scalar)
                positions.append(Position(cue: index, start: Double(offset) / count, end: Double(offset + 1) / count))
            }
        }
        self.text = text
        self.positions = positions
    }

    /// When the start or end of `quote` is spoken, using the occurrence closest to `near`
    /// among those in cues starting within `window`. When the whole quote isn't there, its
    /// opening words (for the start) or closing words (for the end) are tried instead, down
    /// to `minimumWords`.
    func time(of quote: String, edge: Edge, near: TimeInterval, within window: ClosedRange<TimeInterval>) -> TimeInterval? {
        let words = Self.normalize(quote).split(separator: " ").map(Array.init)
        guard words.count >= 1 else { return nil }

        for length in stride(from: words.count, through: min(words.count, Self.minimumWords), by: -1) {
            let part = edge == .start ? words.prefix(length) : words.suffix(length)
            let space: [Unicode.Scalar] = [" "]
            let needle = Array(part.joined(separator: space))
            let matches = occurrences(of: needle, within: window)
            guard let best = matches.min(by: { abs(cues[positions[$0].cue].startTime - near) < abs(cues[positions[$1].cue].startTime - near) }) else {
                continue
            }
            return edge == .start ? startTime(at: best) : endTime(at: best + needle.count - 1)
        }
        return nil
    }

    private func occurrences(of needle: [Unicode.Scalar], within window: ClosedRange<TimeInterval>) -> [Int] {
        guard !needle.isEmpty, needle.count <= text.count else { return [] }
        var matches: [Int] = []
        for start in 0...(text.count - needle.count) where window.contains(cues[positions[start].cue].startTime) {
            // Only match from the start of a word.
            if start > 0, text[start - 1] != " " { continue }
            if text[start..<(start + needle.count)].elementsEqual(needle) {
                // ... and to the end of one.
                let after = start + needle.count
                if after == text.count || text[after] == " " {
                    matches.append(start)
                }
            }
        }
        return matches
    }

    /// The time the character at `index` starts being spoken. Words at the very start of a
    /// cue start with the cue.
    private func startTime(at index: Int) -> TimeInterval {
        let position = positions[index]
        let cue = cues[position.cue]
        guard position.start > 0.1 else { return cue.startTime }
        return cue.startTime + position.start * (cue.endTime - cue.startTime)
    }

    /// The time the character at `index` has been spoken by. Words at the very end of a cue
    /// end where the next cue starts, so the boundary falls in the pause between them.
    private func endTime(at index: Int) -> TimeInterval {
        let position = positions[index]
        let cue = cues[position.cue]
        guard position.end < 0.9 else {
            if position.cue + 1 < cues.count, cues[position.cue + 1].startTime - cue.endTime < 3 {
                return cues[position.cue + 1].startTime
            }
            return cue.endTime
        }
        return cue.startTime + position.end * (cue.endTime - cue.startTime)
    }

    private static func normalize(_ string: String) -> [Unicode.Scalar] {
        var result: [Unicode.Scalar] = []
        var pendingSpace = false
        for scalar in string.lowercased().unicodeScalars {
            if CharacterSet.alphanumerics.contains(scalar) {
                if pendingSpace, !result.isEmpty {
                    result.append(" ")
                }
                pendingSpace = false
                result.append(scalar)
            } else {
                pendingSpace = true
            }
        }
        return result
    }
}
