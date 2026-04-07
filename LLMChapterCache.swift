import Foundation

struct LLMChapterCache {
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    struct Entry: Codable {
        let episodeUUID: String
        let chapters: [CachedChapter]

        struct CachedChapter: Codable {
            let startTime: Double
            let title: String
            let url: String?
        }
    }

    func load(episodeUUID: String) -> Entry? {
        guard let fileURL = try? cacheFileURL(for: episodeUUID),
              FileManager.default.fileExists(atPath: fileURL.path),
              let data = try? Data(contentsOf: fileURL) else {
            return nil
        }
        return try? decoder.decode(Entry.self, from: data)
    }

    func save(_ entry: Entry) {
        guard let fileURL = try? cacheFileURL(for: entry.episodeUUID),
              let data = try? encoder.encode(entry) else {
            return
        }
        try? data.write(to: fileURL, options: .atomic)
    }

    func remove(episodeUUID: String) {
        guard let fileURL = try? cacheFileURL(for: episodeUUID) else { return }
        try? FileManager.default.removeItem(at: fileURL)
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
