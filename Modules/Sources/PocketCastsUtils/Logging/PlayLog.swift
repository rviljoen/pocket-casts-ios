import Foundation
import os

/// A dedicated log for playback events (started, stopped, etc.).
///
/// Shares `FileLog`'s buffering, rotation and file reading through `LogBuffer`, but writes through
/// to disk on every message so events are captured even when the app is suspended shortly after.
public final class PlayLog {
    public static let shared: PlayLog = {
        let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.pocketcasts", category: "PlayLog")

        let logFileWriter = LogFileWriter(
            writingToFileAtPath: LogFilePaths.mainPlayLogFilePath,
            loggingTo: logger
        )

        let fileRotator = FileRotator(
            targetFilePath: LogFilePaths.mainPlayLogFilePath,
            backupFilePath: LogFilePaths.backupPlayLogFilePath,
            loggingTo: logger
        )

        return PlayLog(
            logPersistence: logFileWriter,
            logRotator: fileRotator,
            loggingTo: logger
        )
    }()

    /// The play log holds a short, human-readable history of playback rather than a full debug
    /// trace, so it rotates well before `FileLog` does.
    private static let maxFileSize = 65.kilobytes

    private let logBuffer: LogBuffer
    private let logger: Logger?

    /// The section the log is currently writing into, so repeated events for one episode don't
    /// each repeat the header. `nil` until the first section starts.
    private let currentSectionID = OSAllocatedUnfairLock<String?>(initialState: nil)

    init(
        logPersistence: PersistentTextWriting,
        logRotator: FileRotating,
        mainFilePath: String = LogFilePaths.mainPlayLogFilePath,
        backupFilePath: String = LogFilePaths.backupPlayLogFilePath,
        loggingTo logger: Logger? = nil
    ) {
        self.logger = logger
        self.logBuffer = LogBuffer(
            logPersistence: logPersistence,
            logRotator: logRotator,
            // Never flush on a threshold; every write here is flushed explicitly instead, so a
            // whole section header reaches disk as one write rather than one write per line.
            bufferThreshold: .max,
            mainFilePath: mainFilePath,
            backupFilePath: backupFilePath,
            maxFileSize: Self.maxFileSize,
            emptyMainFileMessage: "Play log is empty",
            loggingTo: logger
        )
    }

    /// Writes the message to the given destinations, blocking until a file write has finished.
    public func addMessage(_ message: String, date: Date = Date(), to destinations: FileLog.LogDestination = .all) {
        if destinations.contains(.console) {
            logger?.log("\(message, privacy: .public)")
        }

        guard destinations.contains(.file) else { return }

        logBuffer.append(message, date: date)
        logBuffer.flush()
    }

    /// Opens a section of the log identified by `id`, headed by `headerLines` written verbatim
    /// without a timestamp prefix.
    ///
    /// Calls naming the section already open are ignored, so a run of events for one episode
    /// groups under a single header instead of repeating it. Call this before every message that
    /// belongs to a section — whichever event happens first opens it.
    public func startSection(id: String, headerLines: [String]) {
        let isAlreadyOpen = currentSectionID.withLock { currentID in
            guard currentID != id else { return true }

            currentID = id
            return false
        }

        guard !isAlreadyOpen else { return }

        // A blank line separates this section from the one before it.
        logBuffer.appendUnformatted("")
        headerLines.forEach { logBuffer.appendUnformatted($0) }
        logBuffer.flush()
    }

    public func logFileAsString() async -> String {
        await logBuffer.loadLogFileAsString()
    }
}
