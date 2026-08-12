import Foundation
import os

public final class FileLog {
    public enum LogError: Error {
        case logCanceled
        case logGenerationFailed
    }

    /// The destinations a log message can be written to.
    public struct LogDestination: OptionSet, Sendable {
        public let rawValue: Int

        public init(rawValue: Int) {
            self.rawValue = rawValue
        }

        /// The rotating log file, which is what gets uploaded with support requests.
        public static let file = LogDestination(rawValue: 1 << 0)

        /// The unified logging system, visible in Console and Xcode.
        public static let console = LogDestination(rawValue: 1 << 1)

        public static let all: LogDestination = [.file, .console]
    }

    public static let shared: FileLog = {
        let logger = Logger()

        let logFileWriter = LogFileWriter(
            writingToFileAtPath: LogFilePaths.mainLogFilePath,
            loggingTo: logger
        )

        let fileRotator = FileRotator(
            targetFilePath: LogFilePaths.mainLogFilePath,
            backupFilePath: LogFilePaths.backupLogFilePath,
            loggingTo: logger
        )

        return FileLog(
            logPersistence: logFileWriter,
            logRotator: fileRotator,
            loggingTo: logger
        )
    }()

    private let logBuffer: LogBuffer
    private let logger: Logger?

    init(
        logPersistence: PersistentTextWriting,
        logRotator: FileRotating,
        bufferThreshold: UInt = 100,
        mainFilePath: String = LogFilePaths.mainLogFilePath,
        backupFilePath: String = LogFilePaths.backupLogFilePath,
        loggingTo logger: Logger? = nil
    ) {
        self.logger = logger
        self.logBuffer = LogBuffer(
            logPersistence: logPersistence,
            logRotator: logRotator,
            bufferThreshold: bufferThreshold,
            mainFilePath: mainFilePath,
            backupFilePath: backupFilePath,
            loggingTo: logger
        )
    }

    /// Writes the message to the given destinations.
    ///
    /// By default a message is written everywhere: if it's important enough to log to file,
    /// it's worth having in the debug console as well. Pass `.file` to opt out of the console
    /// copy when the caller already logs to the unified logging system itself.
    public func addMessage(_ message: String, date: Date = Date(), to destinations: LogDestination = .all) {
        if destinations.contains(.console) {
            logger?.log("\(message, privacy: .public)")
        }

        if destinations.contains(.file) {
            logBuffer.append(message, date: date)
        }
    }

    public func console(_ message: String) {
        logger?.log("\(message, privacy: .public)")
    }

    public func forceFlush() {
        logBuffer.flush()
    }

    public func loadLogFileAsString(completion: @escaping (String) -> Void) {
        Task {
            let log = await logBuffer.loadLogFileAsString()
            completion(log)
        }
    }

    public func logFileAsString() async -> String {
        return await logBuffer.loadLogFileAsString()
    }

    /// Creates a merged file from `mainLogFilePath` and `backupLogFilePath` to be used for enquing the file upload,
    /// returning the path it was written to.
    public func logFileForUpload() async throws -> String {
        let file = LogFilePaths.debugUploadLog
        let contents = await logBuffer.loadLogFileAsString()

        do {
            try contents.write(toFile: file, atomically: true, encoding: .utf8)
        } catch {
            throw LogError.logGenerationFailed
        }

        return file
    }
}

/// Buffers log entries in memory and writes them out in chunks once the buffer fills up.
///
/// Appending is synchronous and guarded by a lock rather than by an actor, so entries reach the
/// file in the order they were logged. Only the write itself is dispatched onto `flushQueue`,
/// which is serial, so flushes never overlap and a read always sees every preceding write.
final class LogBuffer: @unchecked Sendable {
    #if os(watchOS)
        static let defaultMaxFileSize = 65.kilobytes
    #else
        static let defaultMaxFileSize = 1.megabytes
    #endif

    private let bufferThreshold: UInt

    private let entries = OSAllocatedUnfairLock(initialState: [LogEntry]())

    private let flushQueue = DispatchQueue(label: "au.com.pocketcasts.FileLogQueue")

    private let logPersistence: PersistentTextWriting
    private let logRotator: FileRotating
    private let logger: Logger?
    private let mainFilePath: String
    private let backupFilePath: String
    private let maxFileSize: Int
    private let emptyMainFileMessage: String

    init(logPersistence: PersistentTextWriting,
         logRotator: FileRotating,
         bufferThreshold: UInt = 100,
         mainFilePath: String = LogFilePaths.mainLogFilePath,
         backupFilePath: String = LogFilePaths.backupLogFilePath,
         maxFileSize: Int = LogBuffer.defaultMaxFileSize,
         emptyMainFileMessage: String = "Main log is empty",
         loggingTo logger: Logger? = nil) {
        self.logPersistence = logPersistence
        self.logRotator = logRotator
        self.bufferThreshold = bufferThreshold
        self.mainFilePath = mainFilePath
        self.backupFilePath = backupFilePath
        self.maxFileSize = maxFileSize
        self.emptyMainFileMessage = emptyMainFileMessage
        self.logger = logger
    }

    func append(_ message: String, date: Date) {
        append(LogEntry(message, timestamp: date))
    }

    /// Appends `text` to be written verbatim, without the timestamp prefix a logged message gets.
    ///
    /// Used for the header lines that introduce a section of the log rather than record an event.
    func appendUnformatted(_ text: String) {
        append(LogEntry(text, timestamp: nil))
    }

    private func append(_ entry: LogEntry) {
        let hasReachedThreshold = entries.withLock { entries in
            entries.append(entry)
            return entries.count >= bufferThreshold
        }

        guard hasReachedThreshold else { return }

        flushQueue.async(qos: .utility) { [self] in
            writeBufferedEntriesToDisk()
        }
    }

    /// Writes the buffered entries to disk however few of them there are, blocking until that write finishes.
    func flush() {
        flushQueue.sync { [self] in
            writeBufferedEntriesToDisk(isForced: true)
        }
    }

    func loadLogFileAsString() async -> String {
        await withCheckedContinuation { continuation in
            flushQueue.async(qos: .userInitiated) { [self] in
                writeBufferedEntriesToDisk(isForced: true)
                continuation.resume(returning: readLogFiles())
            }
        }
    }

    /// Drains the buffer and appends its contents to the log file. Always called on `flushQueue`.
    private func writeBufferedEntriesToDisk(isForced: Bool = false) {
        let bufferedEntries = entries.withLock { entries in
            defer { entries.removeAll(keepingCapacity: true) }
            return entries
        }

        guard !bufferedEntries.isEmpty else { return }

        if isForced {
            logger?.debug("\(Self.self) forcibly flushing to disk.")
        }

        let newLogChunk = bufferedEntries.reduce(into: "") { resultChunk, logEntry in
            resultChunk.append("\(logEntry.formattedForLog)\n")
        }

        logRotator.rotateFile(ifSizeExceeds: maxFileSize)
        logPersistence.write(newLogChunk)
    }

    private func readLogFiles() -> String {
        let mainFileContents: String
        do {
            mainFileContents = try String(contentsOfFile: mainFilePath)
        } catch {
            mainFileContents = emptyMainFileMessage
        }

        let secondaryFileContents: String
        do {
            secondaryFileContents = try String(contentsOfFile: backupFilePath)
        } catch {
            secondaryFileContents = ""
        }

        return "\(secondaryFileContents)\n\(mainFileContents)"
    }
}
