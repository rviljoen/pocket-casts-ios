import CryptoKit
import Foundation

struct LLMChapterCache {
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    /// Which request an entry holds. Each kind is stored in its own file per episode.
    enum Kind: String {
        /// Chapters (or an untimed topic list) read from the show notes.
        case showNotes
        /// Show notes topics placed on the generated transcript's timeline.
        case transcriptAligned
        /// Chapters made from the transcript alone, when the show notes don't list topics.
        case transcriptGenerated
        /// Ads found in the transcript, added to show notes chapters that don't mark them.
        case transcriptAds

        fileprivate var fileSuffix: String {
            switch self {
            case .showNotes: ""
            case .transcriptAligned: "-aligned"
            case .transcriptGenerated: "-generated"
            case .transcriptAds: "-ads"
            }
        }
    }

    /// Identifies one request: changing the model, the prompt version or any input invalidates it.
    struct Key: Hashable {
        let episodeUUID: String
        let kind: Kind
        let model: String
        let inputHash: String

        /// `version` should be bumped whenever the prompt or output format changes, so
        /// results produced by the old prompt are requested again.
        init(episodeUUID: String, kind: Kind, model: String, version: Int, inputs: [String]) {
            self.episodeUUID = episodeUUID
            self.kind = kind
            self.model = model
            let material = (["v\(version)"] + inputs).joined(separator: "\u{1F}")
            inputHash = SHA256.hash(data: Data(material.utf8))
                .map { String(format: "%02x", $0) }
                .joined()
        }
    }

    struct Entry: Codable {
        let episodeUUID: String
        let model: String
        let inputHash: String
        let chapters: [CachedChapter]
        /// Topics listed in the show notes without timestamps. Only set for `.showNotes`.
        let topics: [String]
        /// Whether `topics` follow the episode's order (see `ShowNotesExtraction.topicsInOrder`).
        /// Optional so entries saved before it was added still decode.
        let topicsInOrder: Bool?
        /// The model's JSON response, kept so debug logging can show it on a cache hit.
        /// Optional so entries saved before it was added still decode.
        let rawResponse: String?

        struct CachedChapter: Codable {
            let startTime: Double
            let title: String
            let url: String?
        }

        init(key: Key, chapters: [CachedChapter], topics: [String] = [], topicsInOrder: Bool = true, rawResponse: String? = nil) {
            episodeUUID = key.episodeUUID
            model = key.model
            inputHash = key.inputHash
            self.chapters = chapters
            self.topics = topics
            self.topicsInOrder = topicsInOrder
            self.rawResponse = rawResponse
        }
    }

    /// Returns the cached entry for `key`. An entry left by a different model, prompt version
    /// or older inputs doesn't match, and is overwritten by the next save for the episode.
    func load(_ key: Key) -> Entry? {
        guard let fileURL = try? cacheFileURL(for: key.episodeUUID, kind: key.kind),
              FileManager.default.fileExists(atPath: fileURL.path),
              let data = try? Data(contentsOf: fileURL),
              let entry = try? decoder.decode(Entry.self, from: data),
              entry.model == key.model,
              entry.inputHash == key.inputHash else {
            return nil
        }
        return entry
    }

    func save(_ entry: Entry, kind: Kind) {
        guard let fileURL = try? cacheFileURL(for: entry.episodeUUID, kind: kind),
              let data = try? encoder.encode(entry) else {
            return
        }
        try? data.write(to: fileURL, options: .atomic)
    }

    private func cacheFileURL(for episodeUUID: String, kind: Kind) throws -> URL {
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

        return cacheURL.appendingPathComponent("\(episodeUUID)\(kind.fileSuffix).json")
    }
}
