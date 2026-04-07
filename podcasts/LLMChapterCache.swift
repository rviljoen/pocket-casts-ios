import CryptoKit
import Foundation

struct LLMChapterCache {
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    /// Identifies one extraction: changing the model or the show notes invalidates it.
    struct Key: Hashable {
        let episodeUUID: String
        let model: String
        let showNotesHash: String

        init(episodeUUID: String, model: String, showNotes: String) {
            self.episodeUUID = episodeUUID
            self.model = model
            showNotesHash = SHA256.hash(data: Data(showNotes.utf8))
                .map { String(format: "%02x", $0) }
                .joined()
        }
    }

    struct Entry: Codable {
        let episodeUUID: String
        let model: String
        let showNotesHash: String
        let chapters: [CachedChapter]

        struct CachedChapter: Codable {
            let startTime: Double
            let title: String
            let url: String?
        }

        init(key: Key, chapters: [CachedChapter]) {
            episodeUUID = key.episodeUUID
            model = key.model
            showNotesHash = key.showNotesHash
            self.chapters = chapters
        }
    }

    /// Returns the cached entry for `key`. An entry left by a different model or older
    /// show notes doesn't match, and is overwritten by the next save for the episode.
    func load(_ key: Key) -> Entry? {
        guard let fileURL = try? cacheFileURL(for: key.episodeUUID),
              FileManager.default.fileExists(atPath: fileURL.path),
              let data = try? Data(contentsOf: fileURL),
              let entry = try? decoder.decode(Entry.self, from: data),
              entry.model == key.model,
              entry.showNotesHash == key.showNotesHash else {
            return nil
        }
        return entry
    }

    func save(_ entry: Entry) {
        guard let fileURL = try? cacheFileURL(for: entry.episodeUUID),
              let data = try? encoder.encode(entry) else {
            return
        }
        try? data.write(to: fileURL, options: .atomic)
    }

    private func cacheFileURL(for episodeUUID: String) throws -> URL {
        let fileManager = FileManager.default
        let baseURL = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let cacheURL = baseURL
            .appendingPathComponent("PocketCasts", isDirectory: true)
            .appendingPathComponent("LLMChapters", isDirectory: true)

        if !fileManager.fileExists(atPath: cacheURL.path) {
            try fileManager.createDirectory(at: cacheURL, withIntermediateDirectories: true)
        }

        return cacheURL.appendingPathComponent("\(episodeUUID).json")
    }
}
