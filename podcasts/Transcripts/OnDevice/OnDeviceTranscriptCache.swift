import CryptoKit
import Foundation

struct OnDeviceTranscriptCache {
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    func audioHash(for fileURL: URL) throws -> String {
        let data = try Data(contentsOf: fileURL)
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    func loadTranscript(forHash audioHash: String) throws -> CachedOnDeviceTranscript? {
        let fileURL = try cacheFileURL(forHash: audioHash)
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return nil
        }
        let data = try Data(contentsOf: fileURL)
        return try decoder.decode(CachedOnDeviceTranscript.self, from: data)
    }

    func saveTranscript(_ transcript: CachedOnDeviceTranscript) throws {
        let fileURL = try cacheFileURL(forHash: transcript.audioHash)
        let data = try encoder.encode(transcript)
        try data.write(to: fileURL, options: .atomic)
    }

    private func cacheFileURL(forHash audioHash: String) throws -> URL {
        let baseURL = try cacheDirectoryURL()
        return baseURL.appendingPathComponent("\(audioHash).json")
    }

    private func cacheDirectoryURL() throws -> URL {
        let fileManager = FileManager.default
        let baseURL = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let cacheURL = baseURL
            .appendingPathComponent("PocketCasts", isDirectory: true)
            .appendingPathComponent("OnDeviceTranscripts", isDirectory: true)

        if !fileManager.fileExists(atPath: cacheURL.path) {
            try fileManager.createDirectory(at: cacheURL, withIntermediateDirectories: true)
        }

        return cacheURL
    }
}
