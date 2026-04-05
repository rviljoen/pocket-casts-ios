import Foundation

struct OnDeviceTranscriptWord: Identifiable, Sendable {
    let id: Int
    let text: String
    let displayText: String
    let startTime: TimeInterval
    let duration: TimeInterval
}

struct OnDeviceTranscriptParagraph: Identifiable, Sendable {
    let id: Int
    let words: [OnDeviceTranscriptWord]
    let startTime: TimeInterval
    let endTime: TimeInterval

    var text: String {
        words.map(\.displayText).joined(separator: " ")
    }
}

struct OnDeviceTranscriptPayload: Sendable {
    let audioHash: String
    let words: [OnDeviceTranscriptWord]
    let paragraphs: [OnDeviceTranscriptParagraph]
    let rawResults: [OnDeviceRawTranscriptionResult]
}

struct OnDeviceRawTranscriptionResult: Identifiable, Sendable {
    let id: Int
    let text: String
    let rangeDescription: String
    let finalizationDescription: String
}

// MARK: - Cache structs (Codable)

struct CachedOnDeviceTranscript: Codable, Sendable {
    let audioHash: String
    let words: [CachedOnDeviceTranscriptWord]
    let rawResults: [CachedOnDeviceRawResult]
}

struct CachedOnDeviceTranscriptWord: Codable, Sendable {
    let text: String
    let displayText: String
    let startTime: TimeInterval
    let duration: TimeInterval
}

struct CachedOnDeviceRawResult: Codable, Sendable {
    let text: String
    let rangeDescription: String
    let finalizationDescription: String
}

// MARK: - State

enum OnDeviceTranscriptionState: Equatable, Sendable {
    case idle
    case queued
    case unavailable
    case preparingAssets
    case transcribing
    case completed
    case error(String)
}
