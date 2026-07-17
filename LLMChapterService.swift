import AVFoundation
import Foundation
import PocketCastsUtils

/// Calls the local LLM chapter server to extract chapters from show notes.
/// The server must be running on the local network at the configured host/port.
actor LLMChapterService {
    static let shared = LLMChapterService()

    private var baseURL: String { Settings.llmChapterServerURL }

    private struct LLMChapter: Decodable {
        let startTime: Double
        let title: String
        let url: String?

        enum CodingKeys: String, CodingKey {
            case startTime = "start_time"
            case title
            case url
        }
    }

    private struct Response: Decodable {
        let chapters: [LLMChapter]
    }

    private struct RequestBody: Encodable {
        let showNotes: String
        let episodeTitle: String?
        let durationSeconds: Double?

        enum CodingKeys: String, CodingKey {
            case showNotes = "show_notes"
            case episodeTitle = "episode_title"
            case durationSeconds = "duration_seconds"
        }
    }

    private let cache = LLMChapterCache()

    func extractChapters(episodeUUID: String, showNotes: String, episodeTitle: String?, duration: TimeInterval) async -> [ChapterInfo] {
        // Return cached result if available
        if let cached = cache.load(episodeUUID: episodeUUID) {
            FileLog.shared.addMessage("LLMChapterService: returning \(cached.chapters.count) cached chapters for \(episodeUUID)")
            return convertCached(cached.chapters, episodeDuration: duration)
        }

        guard let url = URL(string: "\(baseURL)/chapters") else { return [] }

        let body = RequestBody(
            showNotes: showNotes,
            episodeTitle: episodeTitle,
            durationSeconds: duration > 0 ? duration : nil
        )

        do {
            let data = try JSONEncoder().encode(body)

            var request = URLRequest(url: url, timeoutInterval: 30)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = data

            let (responseData, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                FileLog.shared.addMessage("LLMChapterService: non-200 response from server")
                return []
            }

            let result = try JSONDecoder().decode(Response.self, from: responseData)
            FileLog.shared.addMessage("LLMChapterService: extracted \(result.chapters.count) chapters from show notes")

            // Only cache non-empty results — caching a zero-chapter response would
            // permanently skip re-extraction for this episode, even after the server
            // or show notes improve.
            if !result.chapters.isEmpty {
                let entry = LLMChapterCache.Entry(
                    episodeUUID: episodeUUID,
                    chapters: result.chapters.map { LLMChapterCache.Entry.CachedChapter(startTime: $0.startTime, title: $0.title, url: $0.url) }
                )
                cache.save(entry)
            }

            return convert(result.chapters, episodeDuration: duration)
        } catch {
            FileLog.shared.addMessage("LLMChapterService: error - \(error.localizedDescription)")
            return []
        }
    }

    private func convertCached(_ cached: [LLMChapterCache.Entry.CachedChapter], episodeDuration: TimeInterval) -> [ChapterInfo] {
        cached.enumerated().map { index, chapter in
            let info = ChapterInfo()
            info.title = chapter.title
            info.index = index
            info.startTime = CMTime(seconds: chapter.startTime, preferredTimescale: 1000000)
            if let next = cached[safe: index + 1] {
                info.duration = next.startTime - chapter.startTime
            } else {
                info.duration = episodeDuration - chapter.startTime
            }
            if let urlString = chapter.url {
                info.url = urlString
            }
            return info
        }
    }

    private func convert(_ llmChapters: [LLMChapter], episodeDuration: TimeInterval) -> [ChapterInfo] {
        llmChapters.enumerated().map { index, chapter in
            let info = ChapterInfo()
            info.title = chapter.title
            info.index = index
            info.startTime = CMTime(seconds: chapter.startTime, preferredTimescale: 1000000)
            if let next = llmChapters[safe: index + 1] {
                info.duration = next.startTime - chapter.startTime
            } else {
                info.duration = episodeDuration - chapter.startTime
            }
            if let urlString = chapter.url {
                info.url = urlString
            }
            return info
        }
    }
}
