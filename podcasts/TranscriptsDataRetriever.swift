import Foundation
import PocketCastsUtils
import PocketCastsServer
import PocketCastsDataModel

actor TranscriptsDataRetriever {

    typealias Transcript = Episode.Metadata.Transcript

    private var dataRequestMap: [URL: Task<Data, Error>] = [:]

    /// Posted when a transcript starts or finishes loading, with its `urlKey`, and with
    /// `loadedKey` once it's done (whether it's now cached).
    static let loadStateChangedNotification = Notification.Name("TranscriptsDataRetrieverLoadStateChanged")
    static let urlKey = "url"
    static let loadedKey = "loaded"

    /// Shared by every retriever, so whether a transcript is cached can be checked without one.
    private static let sharedCache = URLCache(memoryCapacity: 1.megabytes, diskCapacity: 100.megabytes, diskPath: "transcripts")

    private let cache: URLCache

    public init() {
        cache = Self.sharedCache
    }

    /// Whether the transcript at `url` has been downloaded before. Reads the disk cache, so
    /// call it off the main thread.
    static func hasCachedTranscript(url: URL) -> Bool {
        guard let data = sharedCache.cachedResponse(for: URLRequest(url: url))?.data else { return false }
        return !(String(data: data, encoding: .utf8)?.trim().isEmpty ?? true)
    }

    private static func postLoadState(url: URL, loaded: Bool?) {
        var userInfo: [String: Any] = [urlKey: url]
        userInfo[loadedKey] = loaded
        NotificationCenter.default.post(name: loadStateChangedNotification, object: nil, userInfo: userInfo)
    }

    public func loadTranscript(url: URL) async throws -> String? {
        let request = URLRequest(url: url)

        if let cachedResponse = cache.cachedResponse(for: request),
           let result = String(data: cachedResponse.data, encoding: .utf8),
           !result.trim().isEmpty {
            FileLog.shared.addMessage("Transcripts Data Retriever: returning cached data for transcript")
            Self.postLoadState(url: url, loaded: true)
            Task {
                // trigger a background refresh to force cache update
                try? await loadTranscriptFromServer(url, previousResponse: cachedResponse)
            }
            return result
        }

        return try await loadTranscriptFromServer(url)
    }

    private func loadTranscriptFromServer(_ url: URL, previousResponse: CachedURLResponse? = nil) async throws -> String? {
        if let task = dataRequestMap[url] {
            return try await String(data: task.value, encoding: .utf8)
        }
        FileLog.shared.addMessage("Transcripts Data Retriever: requesting transcript data \(url)")
        if previousResponse == nil {
            Self.postLoadState(url: url, loaded: nil)
        }

        let task = Task<Data, Error> {
            do {
                var request = URLRequest(url: url, cachePolicy: .reloadRevalidatingCacheData)
                if let previousResponse {
                    request.setEtagAndLastModifiedHeaders(cachedResponse: previousResponse)
                }
                let (data, response) = try await urlSession.data(for: request)
                defer {
                    dataRequestMap[url] = nil
                }

                guard response.extractStatusCode() == 200 else {
                    FileLog.shared.addMessage("Transcripts Data Retriever: request failed for transcript url \(url).")
                    Self.postLoadState(url: url, loaded: previousResponse != nil)
                    return data
                }

                let responseToCache = CachedURLResponse(response: response, data: data)
                cache.storeCachedResponse(responseToCache, for: request)
                FileLog.shared.addMessage("Transcripts Data Retriever: request succeeded for url \(url).")
                Self.postLoadState(url: url, loaded: true)

                return data
            } catch {
                FileLog.shared.addMessage("Transcripts Data Retriever: request failed for url \(url): \(error.localizedDescription).")
                Self.postLoadState(url: url, loaded: previousResponse != nil)
                dataRequestMap[url] = nil
                throw error
            }
        }
        dataRequestMap[url] = task

        return try await String(data: task.value, encoding: .utf8)
    }

    private lazy var urlSession: URLSession = {
        return URLSession(configuration: .ephemeral)
    }()
}
