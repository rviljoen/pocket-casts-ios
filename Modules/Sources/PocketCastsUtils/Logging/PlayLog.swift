import Combine
import Foundation
import os

/// A dedicated log for playback events (started, stopped, etc.).
/// Writes synchronously to disk on every message to ensure events
/// are captured even when the app is suspended shortly after.
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

    private let logPersistence: PersistentTextWriting
    private let logRotator: FileRotating
    private let logger: Logger?
    private let queue = DispatchQueue(label: "au.com.pocketcasts.playlog")

    #if os(watchOS)
        private let maxFileSize = 65.kilobytes
    #else
        private let maxFileSize = 1.megabytes
    #endif

    init(
        logPersistence: PersistentTextWriting,
        logRotator: FileRotating,
        loggingTo logger: Logger? = nil
    ) {
        self.logPersistence = logPersistence
        self.logRotator = logRotator
        self.logger = logger
    }

    public func addMessage(_ message: String, date: Date = Date()) {
        let entry = LogEntry(message, timestamp: date)
        let formatted = "\(entry.formattedForLog)\n"

        logger?.log("\(message, privacy: .public)")

        queue.sync {
            logRotator.rotateFile(ifSizeExceeds: maxFileSize)
            logPersistence.write(formatted)
        }
    }

    public func logFileAsString() async -> String {
        return await withCheckedContinuation { continuation in
            queue.async {
                let result = self.loadLogContents()
                continuation.resume(returning: result)
            }
        }
    }

    public func logFileForUpload() -> AnyPublisher<String, Error> {
        let file = LogFilePaths.playLogUploadLog

        return Future { promise in
            self.queue.async {
                let result = self.loadLogContents()
                do {
                    try result.write(toFile: file, atomically: true, encoding: .utf8)
                    promise(.success(file))
                } catch {
                    promise(.failure(FileLog.LogError.logGenerationFailed))
                }
            }
        }
        .eraseToAnyPublisher()
    }

    private func loadLogContents() -> String {
        let mainFileContents: String
        do {
            mainFileContents = try String(contentsOfFile: LogFilePaths.mainPlayLogFilePath)
        } catch {
            mainFileContents = "Play log is empty"
        }

        let backupFileContents: String
        do {
            backupFileContents = try String(contentsOfFile: LogFilePaths.backupPlayLogFilePath)
        } catch {
            backupFileContents = ""
        }

        return "\(backupFileContents)\n\(mainFileContents)"
    }
}
