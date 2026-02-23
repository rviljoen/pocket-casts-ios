import Foundation
import os

/// A dedicated log for playback events (started, stopped, etc.).
///
/// Reuses `FileLog`'s file writing and rotation, but writes through to disk on every message so
/// events are captured even when the app is suspended shortly after.
public final class PlayLog: @unchecked Sendable {
    public static let shared = PlayLog()

    /// The play log holds a short, human-readable history of playback rather than a full debug
    /// trace, so it rotates well before `FileLog` does.
    private static let maxFileSize = 65.kilobytes

    private static let timestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "dd/MM HH:mm"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()

    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.pocketcasts", category: "PlayLog")
    private let logFileWriter: LogFileWriter
    private let fileRotator: FileRotator

    /// Serializes every write and read, so entries reach the file in the order they were logged.
    /// Also guards `currentSectionID`.
    private let queue = DispatchQueue(label: "au.com.pocketcasts.PlayLogQueue")

    /// The section the log is currently writing into, so repeated events for one episode don't
    /// each repeat the header. `nil` until the first section starts. Only accessed on `queue`.
    private var currentSectionID: String?

    private init() {
        logFileWriter = LogFileWriter(writingToFileAtPath: LogFilePaths.mainPlayLogFilePath, loggingTo: logger)
        fileRotator = FileRotator(
            targetFilePath: LogFilePaths.mainPlayLogFilePath,
            backupFilePath: LogFilePaths.backupPlayLogFilePath,
            loggingTo: logger
        )
    }

    /// Writes the message to the console and the log file, blocking until the file write has finished.
    public func addMessage(_ message: String) {
        logger.log("\(message, privacy: .public)")

        let line = "\(Self.timestampFormatter.string(from: Date())) \(message)\n"
        queue.sync { write(line) }
    }

    /// Opens a section of the log identified by `id`, headed by `headerLines` written verbatim
    /// without a timestamp prefix.
    ///
    /// Calls naming the section already open are ignored, so a run of events for one episode
    /// groups under a single header instead of repeating it. Call this before every message that
    /// belongs to a section — whichever event happens first opens it.
    public func startSection(id: String, headerLines: [String]) {
        queue.sync {
            guard currentSectionID != id else { return }

            currentSectionID = id

            // A blank line separates this section from the one before it. The whole header goes
            // out as one write rather than one write per line.
            let header = ([""] + headerLines).map { "\($0)\n" }.joined()
            write(header)
        }
    }

    public func logFileAsString() async -> String {
        await withCheckedContinuation { continuation in
            queue.async(qos: .userInitiated) {
                let mainFileContents = (try? String(contentsOfFile: LogFilePaths.mainPlayLogFilePath)) ?? "Play log is empty"
                let backupFileContents = (try? String(contentsOfFile: LogFilePaths.backupPlayLogFilePath)) ?? ""
                continuation.resume(returning: "\(backupFileContents)\n\(mainFileContents)")
            }
        }
    }

    /// Always called on `queue`.
    private func write(_ text: String) {
        fileRotator.rotateFile(ifSizeExceeds: Self.maxFileSize)
        logFileWriter.write(text)
    }
}
