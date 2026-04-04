import CoreMedia
import Foundation

/// Converts raw Speech API attributed strings into timed words and derives
/// paragraph structure from pauses and sentence boundaries.
@available(iOS 26.0, *)
enum OnDeviceTranscriptFormatter {

    // MARK: - Word extraction

    static func words(
        from text: AttributedString,
        fallbackRange: CMTimeRange,
        startingAt startID: Int
    ) -> [OnDeviceTranscriptWord] {
        var result: [OnDeviceTranscriptWord] = []
        var nextID = startID

        for run in text.runs {
            let fragment = String(text[run.range].characters)
            let tokens = fragment
                .split(whereSeparator: \.isWhitespace)
                .map(String.init)

            guard !tokens.isEmpty else { continue }

            let timeRange = run.audioTimeRange ?? fallbackRange
            let startTime = CMTimeGetSeconds(timeRange.start)
            let totalDuration = max(CMTimeGetSeconds(timeRange.duration), 0)
            let tokenDurations = distributedDurations(for: tokens, totalDuration: totalDuration)

            var tokenStart = startTime
            for (index, token) in tokens.enumerated() {
                let tokenDuration = tokenDurations[index]
                result.append(OnDeviceTranscriptWord(
                    id: nextID,
                    text: token,
                    displayText: compactDisplayText(for: token),
                    startTime: tokenStart,
                    duration: tokenDuration
                ))
                nextID += 1
                tokenStart += tokenDuration
            }
        }

        return result
    }

    // MARK: - Paragraph generation

    static func paragraphs(from words: [OnDeviceTranscriptWord]) -> [OnDeviceTranscriptParagraph] {
        guard !words.isEmpty else { return [] }

        var groups: [[OnDeviceTranscriptWord]] = []
        var currentGroup: [OnDeviceTranscriptWord] = []

        for word in words {
            if let previous = currentGroup.last,
               shouldStartNewParagraph(after: previous, before: word, currentGroup: currentGroup) {
                groups.append(currentGroup)
                currentGroup = []
            }
            currentGroup.append(word)
        }

        if !currentGroup.isEmpty {
            groups.append(currentGroup)
        }

        return groups.enumerated().map { index, group in
            let startTime = group.first?.startTime ?? 0
            let endTime = group.last.map { $0.startTime + max($0.duration, 0.01) } ?? startTime
            return OnDeviceTranscriptParagraph(
                id: index,
                words: group,
                startTime: startTime,
                endTime: endTime
            )
        }
    }

    // MARK: - Active word lookup (binary search)

    static func currentWordIndex(in words: [OnDeviceTranscriptWord], at time: TimeInterval) -> Int? {
        guard !words.isEmpty else { return nil }

        var low = 0
        var high = words.count - 1

        while low <= high {
            let mid = (low + high) / 2
            let word = words[mid]

            if time < word.startTime {
                high = mid - 1
            } else if time >= word.startTime + max(word.duration, 0.01) {
                low = mid + 1
            } else {
                return mid
            }
        }

        if high >= 0 && high < words.count {
            let prev = words[high]
            let nextStart = high + 1 < words.count ? words[high + 1].startTime : prev.startTime + prev.duration + 0.5
            let gap = nextStart - (prev.startTime + prev.duration)
            if gap < 0.5 && time < prev.startTime + prev.duration + gap {
                return high
            }
        }

        return nil
    }

    // MARK: - Private helpers

    private static func shouldStartNewParagraph(
        after previous: OnDeviceTranscriptWord,
        before current: OnDeviceTranscriptWord,
        currentGroup: [OnDeviceTranscriptWord]
    ) -> Bool {
        let previousEnd = previous.startTime + max(previous.duration, 0.01)
        let gap = current.startTime - previousEnd
        let endsSentence = previous.text.last.map(sentenceEnders.contains) ?? false

        if gap >= 3.0 { return true }
        if gap >= 1.5 && endsSentence { return true }
        if endsSentence && currentGroup.count >= 28 { return true }
        if currentGroup.count >= 60 { return true }

        return false
    }

    private static func distributedDurations(for tokens: [String], totalDuration: TimeInterval) -> [TimeInterval] {
        guard !tokens.isEmpty else { return [] }
        guard totalDuration > 0 else { return Array(repeating: 0, count: tokens.count) }

        let weights = tokens.map { Double(max($0.count, 1)) }
        let totalWeight = weights.reduce(0, +)
        guard totalWeight > 0 else {
            return Array(repeating: totalDuration / Double(tokens.count), count: tokens.count)
        }

        return weights.map { totalDuration * ($0 / totalWeight) }
    }

    private static func compactDisplayText(for token: String) -> String {
        let prefix = String(token.prefix { "$€£¥".contains($0) })
        let suffix = String(token.reversed().prefix { ",.;:!?)]}\"'".contains($0) }.reversed())
        let coreStart = token.index(token.startIndex, offsetBy: prefix.count)
        let coreEnd = token.index(token.endIndex, offsetBy: -suffix.count)
        guard coreStart <= coreEnd else { return token }

        let core = String(token[coreStart..<coreEnd])
        let normalized = core.replacingOccurrences(of: ",", with: "")

        guard normalized.count >= 4,
              normalized.allSatisfy(\.isNumber),
              let value = Double(normalized) else {
            return token
        }

        return prefix + compactNumber(value) + suffix
    }

    private static func compactNumber(_ value: Double) -> String {
        let thresholds: [(Double, String)] = [
            (1_000_000_000_000, "T"),
            (1_000_000_000, "B"),
            (1_000_000, "M"),
            (1_000, "K")
        ]

        for (threshold, suffix) in thresholds where value >= threshold {
            let scaled = value / threshold
            let decimals = scaled >= 100 ? 0 : scaled >= 10 ? 1 : 2
            let formatted = String(format: "%.\(decimals)f", scaled)
                .replacingOccurrences(of: #"\.?0+$"#, with: "", options: .regularExpression)
            return formatted + suffix
        }

        return String(Int(value))
    }
}

private let sentenceEnders: Set<Character> = [".", "!", "?"]
