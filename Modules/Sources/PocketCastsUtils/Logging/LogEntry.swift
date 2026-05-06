import Foundation

struct LogEntry {

    // MARK: - Public Properties

    let message: String
    let timestamp: Date

    var formattedForLog: String {
        "\(formatter.string(from: timestamp)) \(message)"
    }

    // MARK: - Private Properties

    private static let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "dd/MM HH:mm"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()

    private var formatter: DateFormatter { Self.formatter }

    // MARK: - Initializers

    init(_ message: String, timestamp: Date) {
        self.message = message
        self.timestamp = timestamp
    }
}
