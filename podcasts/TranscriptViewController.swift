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
    private var onDeviceViewModel: OnDeviceTranscriptViewModel?

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
        }
    }

    override func willBeRemovedFromPlayer() {
        removeAllCustomObservers()
        onDeviceViewModel?.stopSync()
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
        view.addSubview(closeButton)
        closeButton.translatesAutoresizingMaskIntoConstraints = false
        let topMargin = showFromEpisode ? 24.0 : 0.0
        NSLayoutConstraint.activate([
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

        let viewModel = onDeviceViewModel ?? OnDeviceTranscriptViewModel(playbackManager: playbackManager)
        self.onDeviceViewModel = viewModel
        viewModel.observe(episodeUUID: episode.uuid)

        let swiftUIView = OnDeviceTranscriptView(viewModel: viewModel) { [weak self] in
            self?.closeTapped()
        }
            .environmentObject(Theme.sharedTheme)
        let hostingVC = UIHostingController(rootView: AnyView(swiftUIView))
        hostingVC.view.backgroundColor = .clear
        hostingVC.view.translatesAutoresizingMaskIntoConstraints = false

        addChild(hostingVC)
        view.insertSubview(hostingVC.view, at: 0)
        NSLayoutConstraint.activate([
            hostingVC.view.topAnchor.constraint(equalTo: view.topAnchor),
            hostingVC.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            hostingVC.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            hostingVC.view.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        ])
        hostingVC.didMove(toParent: self)
        onDeviceHostingController = hostingVC
        closeButton.isHidden = true
    }

    private func removeOnDeviceHostingController() {
        onDeviceHostingController?.willMove(toParent: nil)
        onDeviceHostingController?.view.removeFromSuperview()
        onDeviceHostingController?.removeFromParent()
        onDeviceHostingController = nil
        closeButton.isHidden = false
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
