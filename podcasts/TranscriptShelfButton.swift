import UIKit
import PocketCastsDataModel

class TranscriptShelfButton: UIButton, CheckTranscriptAvailability {
    var hasGeneratedTranscripts: Bool = false
    var isTranscriptVisible = false {
        didSet {
            updateAppearance()
        }
    }
    var isTranscriptEnabled: Bool {
        didSet {
            updateAppearance()
        }
    }

    override init(frame: CGRect) {
        isTranscriptEnabled = false
        super.init(frame: frame)
        addObservers()
        checkTranscriptAvailability()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func addObservers() {
        addTranscriptObservers()
    }

    private func updateAppearance() {
        if !isTranscriptEnabled {
            imageView?.tintColor = ThemeColor.playerContrast06()
        } else if isTranscriptVisible {
            imageView?.tintColor = PlayerColorHelper.playerHighlightColor01(for: .dark)
        } else {
            imageView?.tintColor = ThemeColor.playerContrast01()
        }
    }
}

protocol CheckTranscriptAvailability: AnyObject {
    var isTranscriptEnabled: Bool { get set }
    var hasGeneratedTranscripts: Bool { get set }

    func addTranscriptObservers()
    func checkTranscriptAvailability()
}

extension CheckTranscriptAvailability {
    func addTranscriptObservers() {
        NotificationCenter.default.addObserver(forName: Constants.Notifications.episodeTranscriptAvailabilityChanged, object: nil, queue: .main) { [weak self] notification in
            guard let episodeUuid = notification.userInfo?["episodeUuid"] as? String,
                  let isAvailable = notification.userInfo?["isAvailable"] as? Bool,
                  let hasGeneratedTranscripts = notification.userInfo?["hasGeneratedTranscripts"] as? Bool,
                  episodeUuid == PlaybackManager.shared.currentEpisode()?.uuid else {
                return
            }

            self?.isTranscriptEnabled = isAvailable
            self?.hasGeneratedTranscripts = hasGeneratedTranscripts
        }

        NotificationCenter.default.addObserver(forName: Constants.Notifications.playbackTrackChanged, object: nil, queue: .main) { [weak self] notification in
            self?.checkTranscriptAvailability()
        }
    }

    func checkTranscriptAvailability() {
        isTranscriptEnabled = false
        hasGeneratedTranscripts = false
        let currentEpisode = PlaybackManager.shared.currentEpisode() as? Episode
        currentEpisode?.checkTranscriptAvailability()
    }
}
