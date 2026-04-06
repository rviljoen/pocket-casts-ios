import SwiftUI
import UIKit
import PocketCastsDataModel
import PocketCastsUtils

class TranscriptViewController: PlayerItemViewController, AnalyticsSourceProvider {
    let analyticsSource: AnalyticsSource

    private let playbackManager: TranscriptPlaybackManaging

    // Kept for compatibility with PlayerContainerViewController / TranscriptContainerViewController.
    var showGeneratedTranscriptsPremiumOverlay: (() -> Void)?
    var playButtonTapped: ((Bool) -> Void)?

    private var showFromEpisode: Bool {
        analyticsSource == .episode
    }

    // MARK: - On-device transcript

    private var onDeviceHostingController: UIViewController?
    private var onDeviceViewModelStorage: AnyObject?
    private let compactHeaderView = UIView()
    private let compactArtworkView = UIImageView()
    private let compactEpisodeTitleLabel = UILabel()
    private let compactPodcastTitleLabel = UILabel()

    // MARK: - Init

    init(playbackManager: TranscriptPlaybackManaging, source: AnalyticsSource = .player) {
        self.playbackManager = playbackManager
        self.analyticsSource = source
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Lifecycle

    public override func viewDidLoad() {
        super.viewDidLoad()
        setupViews()
    }

    func didDisappear() {
        track(.transcriptDismissed)
    }

    override func willBeAddedToPlayer() {
        updateColors()
        loadTranscript()
        if !showFromEpisode {
            addCustomObserver(Constants.Notifications.playbackTrackChanged, selector: #selector(trackChanged))
            addCustomObserver(Constants.Notifications.podcastChapterChanged, selector: #selector(playbackPresentationChanged))
            addCustomObserver(Constants.Notifications.podcastChaptersDidUpdate, selector: #selector(playbackPresentationChanged))
            addCustomObserver(.episodeEmbeddedArtworkLoaded, selector: #selector(playbackPresentationChanged))
        }
    }

    override func willBeRemovedFromPlayer() {
        removeAllCustomObservers()
        if #available(iOS 26.0, *),
           let onDeviceViewModel = onDeviceViewModelStorage as? OnDeviceTranscriptViewModel {
            onDeviceViewModel.stopSync()
        }
        closeButton.isHidden = false
    }

    override func themeDidChange() {
        updateColors()
    }

    // MARK: - Views

    private lazy var closeButton: TintableImageButton = {
        let button = TintableImageButton()
        button.setImage(UIImage(named: "close"), for: .normal)
        button.tintColor = showFromEpisode ? ThemeColor.primaryText01() : ThemeColor.primaryIcon02()
        button.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)
        return button
    }()

    private func setupViews() {
        compactHeaderView.translatesAutoresizingMaskIntoConstraints = false
        compactHeaderView.isHidden = true
        view.addSubview(compactHeaderView)

        compactArtworkView.translatesAutoresizingMaskIntoConstraints = false
        compactArtworkView.layer.cornerRadius = 8
        compactArtworkView.layer.masksToBounds = true
        compactArtworkView.contentMode = .scaleAspectFill
        compactHeaderView.addSubview(compactArtworkView)

        compactEpisodeTitleLabel.translatesAutoresizingMaskIntoConstraints = false
        compactEpisodeTitleLabel.font = .font(ofSize: 16, weight: .semibold, scalingWith: .title3)
        compactEpisodeTitleLabel.adjustsFontForContentSizeCategory = true
        compactEpisodeTitleLabel.textColor = ThemeColor.playerContrast01()
        compactEpisodeTitleLabel.numberOfLines = 2
        compactHeaderView.addSubview(compactEpisodeTitleLabel)

        compactPodcastTitleLabel.translatesAutoresizingMaskIntoConstraints = false
        compactPodcastTitleLabel.font = .font(ofSize: 13, weight: .medium, scalingWith: .body)
        compactPodcastTitleLabel.adjustsFontForContentSizeCategory = true
        compactPodcastTitleLabel.textColor = ThemeColor.playerContrast02()
        compactPodcastTitleLabel.numberOfLines = 1
        compactHeaderView.addSubview(compactPodcastTitleLabel)

        view.addSubview(closeButton)
        closeButton.translatesAutoresizingMaskIntoConstraints = false
        let topMargin = showFromEpisode ? 24.0 : 0.0
        NSLayoutConstraint.activate([
            compactHeaderView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 12),
            compactHeaderView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            compactHeaderView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            compactArtworkView.leadingAnchor.constraint(equalTo: compactHeaderView.leadingAnchor),
            compactArtworkView.topAnchor.constraint(equalTo: compactHeaderView.topAnchor),
            compactArtworkView.bottomAnchor.constraint(lessThanOrEqualTo: compactHeaderView.bottomAnchor),
            compactArtworkView.widthAnchor.constraint(equalToConstant: 56),
            compactArtworkView.heightAnchor.constraint(equalToConstant: 56),
            compactEpisodeTitleLabel.topAnchor.constraint(equalTo: compactHeaderView.topAnchor, constant: 2),
            compactEpisodeTitleLabel.leadingAnchor.constraint(equalTo: compactArtworkView.trailingAnchor, constant: 12),
            compactEpisodeTitleLabel.trailingAnchor.constraint(equalTo: compactHeaderView.trailingAnchor),
            compactPodcastTitleLabel.topAnchor.constraint(equalTo: compactEpisodeTitleLabel.bottomAnchor, constant: 6),
            compactPodcastTitleLabel.leadingAnchor.constraint(equalTo: compactEpisodeTitleLabel.leadingAnchor),
            compactPodcastTitleLabel.trailingAnchor.constraint(equalTo: compactEpisodeTitleLabel.trailingAnchor),
            compactPodcastTitleLabel.bottomAnchor.constraint(equalTo: compactHeaderView.bottomAnchor, constant: -2),
            closeButton.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: topMargin),
            closeButton.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 12),
            closeButton.heightAnchor.constraint(equalToConstant: 44),
            closeButton.widthAnchor.constraint(equalToConstant: 44)
        ])
    }

    // MARK: - Actions

    @objc private func closeTapped() {
        containerDelegate?.dismissTranscript()
    }

    @objc private func trackChanged() {
        updateColors()
        loadTranscript()
    }

    @objc private func playbackPresentationChanged() {
        guard let episodeUUID = playbackManager.episodeUUID,
              let episode = DataManager.sharedManager.findEpisode(uuid: episodeUUID),
              onDeviceHostingController != nil else {
            return
        }

        updateCompactHeader(for: episode)
    }

    // MARK: - Colors

    private func updateColors() {
        let primaryColor = showFromEpisode ? ThemeColor.primaryUi01() : PlayerColorHelper.playerBackgroundColor01()
        view.backgroundColor = primaryColor
    }

    // MARK: - Transcript loading

    private func loadTranscript() {
        guard let episodeUUID = playbackManager.episodeUUID else { return }

        if #available(iOS 26.0, *),
           let episode = DataManager.sharedManager.findEpisode(uuid: episodeUUID),
           episode.downloaded(pathFinder: DownloadManager.shared) {
            loadOnDeviceTranscript(for: episode)
        }
    }

    // MARK: - On-device transcript

    @available(iOS 26.0, *)
    private func loadOnDeviceTranscript(for episode: Episode) {
        removeOnDeviceHostingController()
        updateCompactHeader(for: episode)

        let viewModel = (onDeviceViewModelStorage as? OnDeviceTranscriptViewModel) ?? OnDeviceTranscriptViewModel(playbackManager: playbackManager)
        onDeviceViewModelStorage = viewModel
        viewModel.observe(episodeUUID: episode.uuid)

        let swiftUIView = OnDeviceTranscriptView(viewModel: viewModel)
            .environmentObject(Theme.sharedTheme)
        let hostingVC = UIHostingController(rootView: AnyView(swiftUIView))
        hostingVC.view.backgroundColor = .clear
        hostingVC.view.translatesAutoresizingMaskIntoConstraints = false

        addChild(hostingVC)
        view.insertSubview(hostingVC.view, at: 0)
        NSLayoutConstraint.activate([
            hostingVC.view.topAnchor.constraint(equalTo: compactHeaderView.bottomAnchor, constant: 12),
            hostingVC.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            hostingVC.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            hostingVC.view.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        ])
        hostingVC.didMove(toParent: self)
        onDeviceHostingController = hostingVC
        closeButton.isHidden = true
        compactHeaderView.isHidden = false
    }

    private func removeOnDeviceHostingController() {
        onDeviceHostingController?.willMove(toParent: nil)
        onDeviceHostingController?.view.removeFromSuperview()
        onDeviceHostingController?.removeFromParent()
        onDeviceHostingController = nil
        closeButton.isHidden = false
        compactHeaderView.isHidden = true
    }

    private func updateCompactHeader(for episode: Episode) {
        compactEpisodeTitleLabel.text = episode.displayableTitle()
        compactPodcastTitleLabel.text = episode.subTitle()

        if !showFromEpisode,
           playbackManager.isPlayingEpisode,
           let chapterArtwork = PlaybackManager.shared.currentChapters().artwork {
            compactArtworkView.image = chapterArtwork
            compactArtworkView.accessibilityLabel = L10n.playerArtwork(compactEpisodeTitleLabel.text ?? "")
        } else {
            ImageManager.sharedManager.loadImage(episode: episode, imageView: compactArtworkView, size: .list)
            compactArtworkView.accessibilityLabel = L10n.playerArtwork(compactEpisodeTitleLabel.text ?? "")
        }
    }

    // MARK: - Analytics

    func track(_ event: AnalyticsEvent, properties: [AnyHashable: Any] = [:]) {
        var properties = properties
        if let episodeUUID = playbackManager.episodeUUID,
           let parentIdentifier = playbackManager.parentIdentifier {
            properties["episode_uuid"] = episodeUUID
            properties["podcast_uuid"] = parentIdentifier
        }
        properties["source"] = analyticsSource.rawValue
        Analytics.track(event, properties: properties)
    }
}

// MARK: - RoundButton (used by EffectsViewController, DescriptiveActionView, TranscriptErrorView)

class RoundButton: UIButton {
    override func layoutSubviews() {
        super.layoutSubviews()
        layer.cornerRadius = bounds.height / 2
    }
}
