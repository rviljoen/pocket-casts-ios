import Foundation
import PocketCastsUtils

class ShowNotesChapterExtractor {

    struct TimestampChapter {
        let title: String
        let startTime: TimeInterval
    }

    private static let timestampPattern = #"(?:^|\s|>|[^a-zA-Z_0-9/])(\d{0,2}:?\d{1,2}:\d{2})(?:$|\s|<|[^a-zA-Z_0-9"])"#
    private static let titleExtractionPatterns = [
        // Pattern: HTML structured chapters like <p><strong>00:33 Title</strong></p>
        #"<[^>]*>(?:<[^>]*>)*(\d{1,2}:\d{2})(?:</[^>]*>)?\s*([^<]+?)(?:<|$)"#,
        // Pattern: HTML structured chapters with longer timestamps
        #"<[^>]*>(?:<[^>]*>)*(\d{1,2}:\d{2}:\d{2})(?:</[^>]*>)?\s*([^<]+?)(?:<|$)"#,
        // Pattern: timestamps in parentheses - handles both (MM:SS) and (HH:MM:SS) formats
        #"\((\d{1,2}:\d{2}(?::\d{2})?)\)\s+([^\n\r\(<]+?)(?=</p>|\s*\(\d{1,2}:\d{2}|$)"#,
        // Pattern: timestamps in brackets - handles both [MM:SS] and [HH:MM:SS] formats
        #"\[(\d{1,2}:\d{2}(?::\d{2})?)\]\s+([^\n\r\[<]+?)(?=$|\n|\r|\[\d{1,2}:\d{2})"#,
        // Pattern: plain text timestamp followed by space and text
        #"(\d{1,2}:\d{2})\s+([A-Za-z][^0-9]*?)(?=\s+\d{1,2}:\d{2}|$)"#,
        // Pattern: timestamp followed by dash/colon and text
        #"(\d{1,2}:\d{2})\s*[-–—:]\s*([A-Za-z][^0-9]*?)(?=\s+\d{1,2}:\d{2}|$)"#
    ]

    static func extractChaptersFromShowNotes(_ showNotes: String) -> [TimestampChapter] {
        guard !showNotes.isEmpty else {
            return []
        }

        var extractedChapters: [TimestampChapter] = []
        var processedTimeStamps = Set<TimeInterval>()

        // First try HTML patterns on original show notes (first 2 patterns)
        for (index, pattern) in titleExtractionPatterns.prefix(2).enumerated() {
            let chapters = extractChaptersWithPattern(showNotes, pattern: pattern)
            FileLog.shared.addMessage("ShowNotesChapterExtractor: HTML Pattern \(index) found \(chapters.count) chapters")
            for chapter in chapters {
                if !processedTimeStamps.contains(chapter.startTime) {
                    extractedChapters.append(chapter)
                    processedTimeStamps.insert(chapter.startTime)
                    FileLog.shared.addMessage("ShowNotesChapterExtractor: Found chapter: '\(chapter.title)' at \(chapter.startTime)s")
                }
            }
        }

        // If HTML patterns didn't work, try parentheses and other patterns
        if extractedChapters.isEmpty {
            let cleanedNotes = cleanHTML(showNotes)

            // Try parentheses patterns first on original text, then cleaned text
            let testTexts = [("Original", showNotes), ("Cleaned", cleanedNotes)]

            for (textType, testText) in testTexts {
                for (index, pattern) in titleExtractionPatterns.dropFirst(2).enumerated() {
                    let chapters = extractChaptersWithPattern(testText, pattern: pattern)
                    FileLog.shared.addMessage("ShowNotesChapterExtractor: \(textType) Pattern \(index + 2) found \(chapters.count) chapters")
                    for chapter in chapters {
                        if !processedTimeStamps.contains(chapter.startTime) {
                            extractedChapters.append(chapter)
                            processedTimeStamps.insert(chapter.startTime)
                            FileLog.shared.addMessage("ShowNotesChapterExtractor: Found chapter: '\(chapter.title)' at \(chapter.startTime)s")
                        }
                    }

                    // If we found chapters with this pattern, stop trying more patterns
                    if !extractedChapters.isEmpty {
                        break
                    }
                }

                // If we found chapters, stop trying other text types
                if !extractedChapters.isEmpty {
                    break
                }
            }
        }

        // If no titled chapters found, extract plain timestamps and create generic titles
        if extractedChapters.isEmpty {
            FileLog.shared.addMessage("ShowNotesChapterExtractor: No titled chapters found, falling back to plain timestamps")
            let cleanedNotes = cleanHTML(showNotes)
            let plainTimestamps = extractPlainTimestamps(cleanedNotes)
            FileLog.shared.addMessage("ShowNotesChapterExtractor: Found \(plainTimestamps.count) plain timestamps")
            for (index, timestamp) in plainTimestamps.enumerated() {
                if !processedTimeStamps.contains(timestamp) {
                    let title = "Chapter \(index + 1)"
                    extractedChapters.append(TimestampChapter(title: title, startTime: timestamp))
                    processedTimeStamps.insert(timestamp)
                }
            }
        }

        // Sort by start time and filter out invalid timestamps
        return extractedChapters
            .filter { $0.startTime >= 0 }
            .sorted { $0.startTime < $1.startTime }
    }

    private static func extractChaptersWithPattern(_ text: String, pattern: String) -> [TimestampChapter] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return []
        }

        var chapters: [TimestampChapter] = []
        let nsText = text as NSString
        let range = NSRange(location: 0, length: nsText.length)

        regex.enumerateMatches(in: text, options: [], range: range) { match, _, _ in
            guard let match = match,
                  match.numberOfRanges >= 3,
                  let timestampRange = Range(match.range(at: 1), in: text),
                  let titleRange = Range(match.range(at: 2), in: text) else {
                return
            }

            let timestampString = String(text[timestampRange])
            let titleString = cleanTitle(String(text[titleRange]))

            if let timestamp = parseTimestamp(timestampString), !titleString.isEmpty, titleString.count >= 3 {
                chapters.append(TimestampChapter(title: titleString, startTime: timestamp))
            } else {
                FileLog.shared.addMessage("Rejected chapter: timestamp=\(timestampString), title='\(titleString)' (length: \(titleString.count))")
            }
        }

        return chapters
    }

    private static func extractPlainTimestamps(_ text: String) -> [TimeInterval] {
        guard let regex = try? NSRegularExpression(pattern: timestampPattern, options: [.caseInsensitive]) else {
            return []
        }

        var timestamps: [TimeInterval] = []
        let nsText = text as NSString
        let range = NSRange(location: 0, length: nsText.length)

        regex.enumerateMatches(in: text, options: [], range: range) { match, _, _ in
            guard let match = match,
                  match.numberOfRanges >= 2,
                  let timestampRange = Range(match.range(at: 1), in: text) else {
                return
            }

            let timestampString = String(text[timestampRange])
            if let timestamp = parseTimestamp(timestampString), timestamp >= 0 {
                timestamps.append(timestamp)
            }
        }

        return timestamps
    }

    private static func parseTimestamp(_ timestampString: String) -> TimeInterval? {
        return SJCommonUtils.colonFormattedString(toTime: timestampString)
    }

    private static func cleanTitle(_ title: String) -> String {
        var cleaned = title

        // Remove HTML tags
        cleaned = cleaned.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)

        // Decode HTML entities
        let entities = [
            "&amp;": "&",
            "&lt;": "<",
            "&gt;": ">",
            "&quot;": "\"",
            "&#39;": "'",
            "&nbsp;": " ",
            "&mdash;": "—",
            "&ndash;": "–"
        ]

        for (entity, replacement) in entities {
            cleaned = cleaned.replacingOccurrences(of: entity, with: replacement)
        }

        // Clean up whitespace and common separators at start/end
        cleaned = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
        cleaned = cleaned.trimmingCharacters(in: CharacterSet(charactersIn: "-–—:•"))
        cleaned = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)

        return cleaned
    }

    private static func cleanHTML(_ html: String) -> String {
        var cleaned = html

        // Remove HTML tags but keep the content
        cleaned = cleaned.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)

        // Decode common HTML entities
        let entities = [
            "&amp;": "&",
            "&lt;": "<",
            "&gt;": ">",
            "&quot;": "\"",
            "&#39;": "'",
            "&nbsp;": " "
        ]

        for (entity, replacement) in entities {
            cleaned = cleaned.replacingOccurrences(of: entity, with: replacement)
        }

        // Normalize whitespace
        cleaned = cleaned.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)

        return cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
