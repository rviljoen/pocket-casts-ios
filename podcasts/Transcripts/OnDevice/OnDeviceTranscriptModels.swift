import Foundation

struct OnDeviceTranscriptWord: Identifiable {
    let id: Int
    let text: String
    let displayText: String
    let startTime: TimeInterval
    let duration: TimeInterval
}

struct OnDeviceTranscriptParagraph: Identifiable {
    let id: Int
    let words: [OnDeviceTranscriptWord]
    let startTime: TimeInterval
    let endTime: TimeInterval

    var text: String {
        words.map(\.displayText).joined(separator: " ")
    }
}

struct OnDeviceTranscriptPayload {
    let audioHash: String
    let words: [OnDeviceTranscriptWord]
    let paragraphs: [OnDeviceTranscriptParagraph]
    let rawResults: [OnDeviceRawTranscriptionResult]
}

struct OnDeviceRawTranscriptionResult: Identifiable {
    let id: Int
    let text: String
    let rangeDescription: String
    let finalizationDescription: String
}

// MARK: - Cache structs (Codable)

struct CachedOnDeviceTranscript: Codable {
    let audioHash: String
    let words: [CachedOnDeviceTranscriptWord]
    let rawResults: [CachedOnDeviceRawResult]
}

struct CachedOnDeviceTranscriptWord: Codable {
    let text: String
    let displayText: String
    let startTime: TimeInterval
    let duration: TimeInterval
}

struct CachedOnDeviceRawResult: Codable {
    let text: String
    let rangeDescription: String
    let finalizationDescription: String
}

// MARK: - State

enum OnDeviceTranscriptionState: Equatable {
    case idle
    case unavailable
    case preparingAssets
    case transcribing
    case completed
    case error(String)
}
