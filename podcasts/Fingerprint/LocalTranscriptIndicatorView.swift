import PocketCastsDataModel
import UIKit

/// A small icon for episode rows showing where the episode's transcript comes from:
/// - Green: made on this device, because its file has dynamically inserted ads. An outline
///   while it's queued or being made, filled once it's done.
/// - Blue: a transcript from the server. Filled once one is downloaded: the podcast's own
///   (a text page icon when it's untimed text), or the Pocket Casts generated one. An outline
///   while a generated one is on the server but not downloaded yet (or downloading).
/// - Grey: the server hasn't generated one yet.
///
/// Hidden when there's nothing to show. Keeps itself up to date as transcripts change.
final class LocalTranscriptIndicatorView: UIImageView {
    var episode: BaseEpisode? {
        didSet { refresh() }
    }

    /// The theme to color the icon for, when the row overrides the app's (the player's Up Next).
    var themeOverride: Theme.ThemeType? {
        didSet { refresh() }
    }

    init() {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        contentMode = .scaleAspectFit
        preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 11, weight: .medium)
        isHidden = true
        NotificationCenter.default.addObserver(self, selector: #selector(stateChanged(_:)), name: LocalTranscripts.stateChangedNotification, object: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// Adds an indicator to the stack view holding `icon` (one of the row's status icons),
    /// just after it and the same size.
    static func insert(after icon: UIView) -> LocalTranscriptIndicatorView? {
        guard let stack = icon.superview as? UIStackView,
              let index = stack.arrangedSubviews.firstIndex(of: icon) else {
            return nil
        }
        let indicator = LocalTranscriptIndicatorView()
        stack.insertArrangedSubview(indicator, at: index + 1)
        NSLayoutConstraint.activate([
            indicator.widthAnchor.constraint(equalTo: icon.widthAnchor),
            indicator.heightAnchor.constraint(equalTo: icon.heightAnchor)
        ])
        return indicator
    }

    func refresh() {
        let appearance = episode.flatMap(Self.appearance(for:))
        image = appearance.flatMap { UIImage(systemName: $0.symbolName) }
        tintColor = appearance?.color ?? ThemeColor.primaryIcon02(for: themeOverride)
        if isHidden != (appearance == nil) {
            isHidden = appearance == nil
        }
    }

    private static let outline = "captions.bubble"
    private static let filled = "captions.bubble.fill"
    private static let text = "text.bubble.fill"

    /// The icon's tint (nil for the theme's grey) and symbol, or nil to hide it.
    private static func appearance(for episode: BaseEpisode) -> (color: UIColor?, symbolName: String)? {
        if LocalTranscripts.progress(for: episode.uuid) != nil || LocalTranscripts.isQueued(episode.uuid) {
            return (.systemGreen, outline)
        }
        if LocalTranscripts.hasTranscript(for: episode) {
            return (.systemGreen, filled)
        }

        let server = ServerTranscriptStatus.shared
        switch server.state(for: episode) {
        case .podcast(let isTimed)?:
            return (.systemBlue, isTimed ? filled : text)
        case .downloaded? where !server.isLoading(episode.uuid):
            return (.systemBlue, filled)
        case .downloaded?, .available?:
            return (.systemBlue, outline)
        case .notGenerated?:
            return (nil, filled)
        case nil:
            return nil
        }
    }

    @objc private func stateChanged(_ notification: Notification) {
        // Without an episode, the whole index changed.
        let episodeUUID = notification.userInfo?[LocalTranscripts.episodeUUIDKey] as? String
        guard episodeUUID == nil || episodeUUID == episode?.uuid else { return }
        DispatchQueue.main.async { [weak self] in
            self?.refresh()
        }
    }
}
