#if !APPCLIP
import Agrume
#endif
import AVKit
import SafariServices
import UIKit
import PocketCastsUtils
import SwiftUI
import PocketCastsServer

class NowPlayingPlayerItemViewController: PlayerItemViewController {
    private enum PlayerOverlayMode {
        case none
        case transcript
        case chapters
    }

    var showingCustomImage = false
    var lastChapterIndexRendered = -1

    private var bannerTask: Task<Void, Never>? = nil

    // Detect Display Zoom (zoomed display makes UI elements appear larger).
    // Scale controls down slightly when zoomed to avoid oversized buttons.
    private var isZoomed: Bool {
        A11y.isDisplayZoomed
    }

    var videoViewController: VideoViewController?

    @IBOutlet var skipBackBtn: SkipButton! {
        didSet {
            skipBackBtn.skipBack = true
        }
    }

    @IBOutlet var skipFwdBtn: SkipButton! {
        didSet {
            skipFwdBtn.skipBack = false
            skipFwdBtn.longPressed = { [weak self] in
                self?.skipForwardLongPressed()
            }
        }
    }

    @IBOutlet var playPauseBtn: PlayPauseButton!

    @IBOutlet var episodeImage: UIImageView! {
        didSet {
            let tapGesture = UITapGestureRecognizer(target: self, action: #selector(imageTapped))
            tapGesture.numberOfTapsRequired = 1
            tapGesture.numberOfTouchesRequired = 1
            episodeImage.addGestureRecognizer(tapGesture)
        }
    }

    @IBOutlet var episodeName: ThemeableLabel! {
        didSet {
#if APPCLIP
            episodeName.text = ""
#endif
            episodeName.style = .playerContrast01
            episodeName.adjustsFontForContentSizeCategory = true
            episodeName.font = .font(ofSize: 18, weight: .semibold, scalingWith: .largeTitle)
        }
    }

    @IBOutlet var podcastName: ThemeableLabel! {
        didSet {
#if APPCLIP
            podcastName.text = ""
#endif
            podcastName.style = .playerContrast02
            podcastName.adjustsFontForContentSizeCategory = true
            podcastName.font = .font(ofSize: 14, weight: .medium, scalingWith: .largeTitle)

            let tapGesture = UITapGestureRecognizer(target: self, action: #selector(podcastNameTapped))
            podcastName.addGestureRecognizer(tapGesture)

            podcastName.accessibilityTraits = .button
            podcastName.accessibilityHint = L10n.accessibilityHintPlayerNavigateToPodcastLabel
        }
    }

    @IBOutlet var chapterName: ThemeableLabel! {
        didSet {
#if APPCLIP
            chapterName.text = ""
#endif
            chapterName.style = .playerContrast01
            chapterName.adjustsFontForContentSizeCategory = true
            chapterName.font = .font(ofSize: 18, weight: .semibold, scalingWith: .largeTitle)

            let tapGesture = UITapGestureRecognizer(target: self, action: #selector(chapterNameTapped))
            chapterName.addGestureRecognizer(tapGesture)
        }
    }

    @IBOutlet var floatingVideoView: FloatingVideoView! {
        didSet {
            let tapGesture = UITapGestureRecognizer(target: self, action: #selector(videoTapped))
            tapGesture.numberOfTapsRequired = 1
            tapGesture.numberOfTouchesRequired = 1
            floatingVideoView.addGestureRecognizer(tapGesture)
        }
    }

    // MARK: - Chapters

    @IBOutlet var chapterSkipBackBtn: UIButton! {
        didSet {
            chapterSkipBackBtn.tintColor = ThemeColor.playerContrast01()
        }
    }

    @IBOutlet var chapterSkipFwdBtn: UIButton! {
        didSet {
            chapterSkipFwdBtn.tintColor = ThemeColor.playerContrast01()
        }
    }

    @IBOutlet var chapterCounter: ThemeableLabel! {
        didSet {
            chapterCounter.style = .playerContrast02
            chapterCounter.adjustsFontForContentSizeCategory = true
            chapterCounter.font = .font(ofSize: 12, weight: .semibold, scalingWith: .largeTitle)
        }
    }

    @IBOutlet var chapterTimeLeftLabel: UILabel! {
        didSet {
            chapterTimeLeftLabel.adjustsFontForContentSizeCategory = true
            chapterTimeLeftLabel.font = .font(ofSize: 11, weight: .semibold, scalingWith: .largeTitle).monospaced()
        }
    }

    @IBOutlet var chapterProgress: ProgressCircleView! {
        didSet {
            chapterProgress.lineWidth = 2
            chapterProgress.lineColor = ThemeColor.playerContrast03()
        }
    }

    @IBOutlet var chapterLink: UIView! {
        didSet {
            let tapGesture = UITapGestureRecognizer(target: self, action: #selector(chapterLinkTapped))
            chapterLink.addGestureRecognizer(tapGesture)
        }
    }

    @IBOutlet var chapterInfoView: UIView!
    @IBOutlet var episodeInfoView: UIView!

    @IBOutlet var shelfBg: ThemeableView! {
        didSet {
            shelfBg.style = .playerContrast06
        }
    }

    // MARK: - Time Slider

    @IBOutlet var timeSlider: TimeSlider! {
        didSet {
            timeSlider.accessibilityLabel = L10n.accessibilityEpisodePlayback
            timeSlider.delegate = self
        }
    }

    @IBOutlet var playerControlsStackView: UIStackView!

    @IBOutlet var timeSliderHolderView: UIView!

    @IBOutlet var timeElapsed: ThemeableLabel! {
        didSet {
            timeElapsed.style = .playerContrast02
            let baseFont = UIFont.monospacedDigitSystemFont(ofSize: 12, weight: UIFont.Weight.medium)
            let metrics = UIFontMetrics(forTextStyle: .largeTitle)
            timeElapsed.font = metrics.scaledFont(for: baseFont)
            timeElapsed.adjustsFontForContentSizeCategory = true
        }
    }

    @IBOutlet var timeRemaining: ThemeableLabel! {
        didSet {
            timeRemaining.style = .playerContrast02
            let baseFont = UIFont.monospacedDigitSystemFont(ofSize: 12, weight: UIFont.Weight.medium)
            let metrics = UIFontMetrics(forTextStyle: .largeTitle)
            timeRemaining.font = metrics.scaledFont(for: baseFont)
            timeRemaining.adjustsFontForContentSizeCategory = true

        }
    }

    @IBOutlet var playPauseHeightConstraint: NSLayoutConstraint!

    @IBOutlet weak var fillView: UIView!

    @IBOutlet weak var bottomControlsStackView: UIStackView!

    @IBOutlet weak var errorContainer: ThemeableView! {
        didSet {
            errorContainer.style = .playerContrast06
            let tapRecognizer = UITapGestureRecognizer(target: self, action: #selector(errorTapped))
            errorContainer.addGestureRecognizer(tapRecognizer)
        }
    }

    @IBOutlet weak var errorLabel: ThemeableLabel! {
        didSet {
            errorLabel.font = .font(ofSize: 14, weight: .medium, scalingWith: .subheadline)
            errorLabel.style = .playerContrast02
        }
    }

    @IBOutlet weak var playerBottomSpacing: NSLayoutConstraint!

    @IBOutlet weak var errorBottomSpacing: NSLayoutConstraint!

    var errorAutoDismissWork: DispatchWorkItem?

    #if !APPCLIP
    let chromecastBtn = PCAlwaysVisibleCastBtn()
    #endif
    let routePicker = PCRoutePickerView(frame: CGRect.zero)

    #if !APPCLIP
    private lazy var upNextController = UpNextViewController(source: .nowPlaying)
    #endif

    #if !APPCLIP
    lazy var upNextViewController: UIViewController = {
        let controller = SJUIUtils.navController(for: upNextController, iconStyle: .secondaryText01, themeOverride: upNextController.themeOverride)
        controller.modalPresentationStyle = .pageSheet

        return controller
    }()
    #endif

    var lastShelfLoadState = ShelfLoadState()

    private var bannerAdHostingController: PCHostingController<AnyView>?
    private var bannerAdHeightConstraint: NSLayoutConstraint?
    weak var transcriptShelfButton: UIButton?
    #if !APPCLIP
    private lazy var transcriptControlButton: TranscriptShelfButton = {
        let button = TranscriptShelfButton(frame: .zero)
        button.isPointerInteractionEnabled = true
        button.setImage(UIImage(named: "transcript"), for: .normal)
        button.accessibilityLabel = L10n.transcript
        button.contentHorizontalAlignment = .center
        button.addTarget(self, action: #selector(transcriptControlTapped(_:)), for: .touchUpInside)
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()
    #endif
    lazy var chaptersControlButton: UIButton = {
        let button = UIButton(type: .system)
        button.isPointerInteractionEnabled = true
        button.setImage(UIImage(systemName: "list.bullet"), for: .normal)
        button.accessibilityLabel = L10n.chapters
        button.contentHorizontalAlignment = .center
        button.tintColor = ThemeColor.playerContrast01()
        button.addTarget(self, action: #selector(chaptersControlTapped(_:)), for: .touchUpInside)
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()

    private let analyticsPlaybackHelper = AnalyticsPlaybackHelper.shared

    override func viewDidLoad() {
        super.viewDidLoad()

        configurePrimaryControlButtons()
        fillView.setContentHuggingPriority(.defaultLow, for: .vertical)
        fillView.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        bottomControlsStackView.setContentHuggingPriority(.required, for: .vertical)
        bottomControlsStackView.setContentCompressionResistancePriority(.required, for: .vertical)
        timeSliderHolderView.setContentHuggingPriority(.required, for: .vertical)
        timeSliderHolderView.setContentCompressionResistancePriority(.required, for: .vertical)
        playSkipStackView?.setContentHuggingPriority(.required, for: .vertical)
        playSkipStackView?.setContentCompressionResistancePriority(.required, for: .vertical)
        shelfBg.setContentHuggingPriority(.required, for: .vertical)
        shelfBg.setContentCompressionResistancePriority(.required, for: .vertical)

        #if !APPCLIP
        let upNextPan = UIPanGestureRecognizer(target: self, action: #selector(panGestureRecognizerHandler(_:)))
        upNextPan.delegate = self
        view.addGestureRecognizer(upNextPan)

        chromecastBtn.inactiveTintColor = ThemeColor.playerContrast02()
        chromecastBtn.addTarget(self, action: #selector(googleCastTapped), for: .touchUpInside)
        chromecastBtn.isPointerInteractionEnabled = true

        routePicker.delegate = self

        #endif
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        #if !APPCLIP
        // Show the overflow menu
        if AnnouncementFlow.current == .bookmarksPlayer {
            overflowTapped()
        }
        #endif
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        loadBannerAd()
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        bannerTask?.cancel()
    }

    private var lastBoundsAdjustedFor = CGRect.zero

    var analyticsSource: AnalyticsSource {
        .player
    }

    private var overlayMode: PlayerOverlayMode = .none {
        didSet {
#if !APPCLIP
            guard oldValue != overlayMode else { return }
            transitionOverlay(from: oldValue, to: overlayMode)
#endif
        }
    }

    var displayTranscript: Bool {
        get { overlayMode == .transcript }
        set {
            if newValue {
                overlayMode = .transcript
            } else if overlayMode == .transcript {
                overlayMode = .none
            }
        }
    }

    private var displayChapters: Bool {
        get { overlayMode == .chapters }
        set {
            if newValue {
                overlayMode = .chapters
            } else if overlayMode == .chapters {
                overlayMode = .none
            }
        }
    }

    private var isOverlayVisible: Bool {
        overlayMode != .none
    }

    private func loadBannerAd() {
#if !APPCLIP
        if SubscriptionHelper.shouldDisplayPlayerBannerAd {
            DiscoverServerHandler.shared.blazePromotion(for: .player) { [weak self] promotion, shouldAnimate in
                guard let self = self else { return }

                if shouldAnimate {
                    self.bannerTask = Task { [weak self] in
                        try? await Task.sleep(for: .seconds(2))
                        await MainActor.run {
                            self?.addAdBanner(promotion: promotion, animated: true)
                        }
                    }
                } else {
                    self.addAdBanner(promotion: promotion, animated: false)
                }
            }
        }
#endif
    }

    private var playerContainer: PlayerContainerViewController? {
        parent as? PlayerContainerViewController
    }

    private var playerContentStackView: UIStackView? {
        episodeImage?.superview as? UIStackView
    }

    private var titleInfoContainerView: UIView? {
        episodeInfoView?.superview
    }

    private var playSkipStackView: UIView? {
        bottomControlsStackView.arrangedSubviews.first {
            $0 !== timeSliderHolderView && $0 !== shelfBg
        }
    }

    private func configurePrimaryControlButtons() {
        guard let playSkipStackView = playSkipStackView as? UIStackView else {
            return
        }
        #if !APPCLIP
        if !playSkipStackView.arrangedSubviews.contains(transcriptControlButton) {
            playSkipStackView.insertArrangedSubview(transcriptControlButton, at: 0)
        }
        #endif
        if !playSkipStackView.arrangedSubviews.contains(chaptersControlButton) {
            playSkipStackView.addArrangedSubview(chaptersControlButton)
        }

        #if !APPCLIP
        NSLayoutConstraint.activate([
            transcriptControlButton.widthAnchor.constraint(equalToConstant: 44),
            transcriptControlButton.heightAnchor.constraint(equalToConstant: 44),
            chaptersControlButton.widthAnchor.constraint(equalToConstant: 44),
            chaptersControlButton.heightAnchor.constraint(equalToConstant: 44)
        ])
        #else
        NSLayoutConstraint.activate([
            chaptersControlButton.widthAnchor.constraint(equalToConstant: 44),
            chaptersControlButton.heightAnchor.constraint(equalToConstant: 44)
        ])
        #endif

        playSkipStackView.spacing = 12
        playSkipStackView.isLayoutMarginsRelativeArrangement = true
        playSkipStackView.directionalLayoutMargins = NSDirectionalEdgeInsets(top: 0, leading: 8, bottom: 0, trailing: 8)
        updatePrimaryControlButtonState()
    }

    func updatePrimaryControlButtonState() {
        #if !APPCLIP
        transcriptControlButton.isTranscriptVisible = displayTranscript
        #endif

        let chaptersAvailable = PlaybackManager.shared.chapterCount() > 0
        chaptersControlButton.isEnabled = chaptersAvailable
        if !chaptersAvailable {
            chaptersControlButton.tintColor = ThemeColor.playerContrast06()
        } else if displayChapters {
            chaptersControlButton.tintColor = PlayerColorHelper.playerHighlightColor01(for: .dark)
        } else {
            chaptersControlButton.tintColor = ThemeColor.playerContrast01()
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()

        // there's some expensive operations in resizeControls,
        // so only do them if the bounds has actually changed
        if lastBoundsAdjustedFor == view.bounds { return }
        lastBoundsAdjustedFor = view.bounds

        resizeControls()

        #if !APPCLIP
        if FeatureFlag.bannerAdPlayer.enabled {
            updateBannerAdHeight()
        }
        #endif
    }

    private func resizeControls() {
        updateTranscriptSpacerPosition()
        (playSkipStackView as? UIStackView)?.spacing = 12

        let spacing: CGFloat
        if view.bounds.width <= 320 {
            spacing = 8
        } else if view.bounds.width <= 375 {
            spacing = 20
        } else {
            spacing = 30
        }

        if playerControlsStackView.spacing != spacing { playerControlsStackView.spacing = spacing }

        if bottomControlsStackView.spacing != 30 { bottomControlsStackView.spacing = 30 }
        if bottomControlsStackView.distribution != .equalSpacing { bottomControlsStackView.distribution = .equalSpacing }

        let baseHeight: CGFloat = view.bounds.height > 710 ? 52 : 44
        let scaledHeight: CGFloat = isZoomed ? baseHeight * 0.9 : baseHeight
        if playPauseHeightConstraint.constant != scaledHeight { playPauseHeightConstraint.constant = scaledHeight }

        let skipSize: SkipButton.Size = .small
        skipBackBtn.changeSize(to: skipSize)
        skipFwdBtn.changeSize(to: skipSize)

        bottomControlsStackView.setCustomSpacing(30, after: timeSliderHolderView)
        if let playSkipStackView {
            bottomControlsStackView.setCustomSpacing(30, after: playSkipStackView)
        }

        fillView.isHidden = !isOverlayVisible
        updatePrimaryControlButtonState()

        view.layoutIfNeeded()
    }

    private func updateTranscriptSpacerPosition() {
        guard let playerContentStackView,
              let titleInfoContainerView else {
            return
        }

        playerContentStackView.removeArrangedSubview(fillView)

        let arrangedSubviews = playerContentStackView.arrangedSubviews.filter { $0 !== fillView }
        guard let titleInfoIndex = arrangedSubviews.firstIndex(of: titleInfoContainerView) else {
            return
        }

        let insertIndex = isOverlayVisible ? titleInfoIndex : titleInfoIndex + 1
        playerContentStackView.insertArrangedSubview(fillView, at: insertIndex)
    }

    override func willBeAddedToPlayer() {
        update(notification: nil)
        addObservers()
    }

    override func willBeRemovedFromPlayer() {
        removeAllCustomObservers()

        #if !APPCLIP
        if FeatureFlag.bannerAdPlayer.enabled {
            removeBannerAd()
        }
        #endif
    }

    override func themeDidChange() {
        lastShelfLoadState = ShelfLoadState()
        update(notification: nil)
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)

        #if !APPCLIP
        if FeatureFlag.bannerAdPlayer.enabled {
            // Update banner height when text size category changes
            if traitCollection.preferredContentSizeCategory != previousTraitCollection?.preferredContentSizeCategory {
                updateBannerAdHeight()
            }
        }
        #endif

        if traitCollection.preferredContentSizeCategory != previousTraitCollection?.preferredContentSizeCategory {
            updateSize()
        }
    }

    var shelfIconSize: CGFloat {
        let metrics = UIFontMetrics(forTextStyle: .largeTitle)
        let iconSize = min(45, max(32, metrics.scaledValue(for: 32)))
        return iconSize
    }

    private func updateSize() {
        let iconSize = shelfIconSize
        for view in playerControlsStackView.subviews {
            view.updateSizeConstraints(to: iconSize)
        }
    }

    // MARK: - Interface Actions

    @IBAction func skipBackTapped(_ sender: Any) {
        analyticsPlaybackHelper.currentSource = analyticsSource
        HapticsHelper.triggerSkipBackHaptic()
        PlaybackManager.shared.skipBack()
    }

    @IBAction func playPauseTapped(_ sender: Any) {
        analyticsPlaybackHelper.currentSource = analyticsSource
        HapticsHelper.triggerPlayPauseHaptic()
        PlaybackManager.shared.playPause()
    }

    @IBAction func skipFwdTapped(_ sender: Any) {
        analyticsPlaybackHelper.currentSource = analyticsSource
        HapticsHelper.triggerSkipForwardHaptic()
        PlaybackManager.shared.skipForward()
    }

    #if !APPCLIP
    @objc private func transcriptControlTapped(_ sender: UIButton) {
        guard transcriptControlButton.isTranscriptEnabled else {
            Toast.show(TranscriptError.notAvailable.localizedDescription)
            return
        }

        shelfButtonTapped(.transcript)
        displayTranscript.toggle()
    }
    #endif

    @objc private func chaptersControlTapped(_ sender: UIButton) {
        guard PlaybackManager.shared.chapterCount() > 0 else {
            return
        }

        #if !APPCLIP
        displayChapters.toggle()
        #else
        containerDelegate?.scrollToCurrentChapter()
        #endif
    }

    @IBAction func chapterSkipBackTapped(_ sender: Any) {
        PlaybackManager.shared.skipToPreviousChapter()
        Analytics.track(.playerPreviousChapterTapped)
    }

    @IBAction func chapterSkipForwardTapped(_ sender: Any) {
        PlaybackManager.shared.skipToNextChapter()
        Analytics.track(.playerNextChapterTapped)
    }

    @objc private func chapterLinkTapped() {
        let chapters = PlaybackManager.shared.currentChapters()
        guard let urlString = chapters.url, let url = URL(string: urlString) else { return }

        #if APPCLIP
        //TODO: Prompt to install app
        #else
            if Settings.openLinks {
                UIApplication.shared.open(url, options: [:], completionHandler: nil)
            } else {
                present(SFSafariViewController(with: url), animated: true)
            }
        #endif
    }

    @objc private func imageTapped() {
#if !APPCLIP
        guard let artwork = episodeImage.image else { return }

        let agrume = Agrume(image: artwork, background: .blurred(.regular))
        agrume.show(from: self)
#endif
    }

    @objc private func videoTapped() {
        guard let episode = PlaybackManager.shared.currentEpisode() else { return }

        if episode.videoPodcast() {
            let videoController = VideoViewController()
            videoViewController = videoController
            videoViewController?.modalTransitionStyle = .crossDissolve
            videoViewController?.modalPresentationStyle = .fullScreen
            videoViewController?.willAttachPlayer = { [weak self] in
                self?.floatingVideoView.player = nil
            }
            videoViewController?.willDeattachPlayer = { [weak self] in
                self?.floatingVideoView.player = PlaybackManager.shared.internalPlayerForVideoPlayback()
            }

            present(videoController, animated: true, completion: nil)
        }
    }

    @objc private func chapterNameTapped() {
        containerDelegate?.scrollToCurrentChapter()
    }

    @objc private func podcastNameTapped() {
        Analytics.track(.playerPodcastNameTapped)
        containerDelegate?.navigateToPodcast()
    }

    private func skipForwardLongPressed() {
        guard let episode = PlaybackManager.shared.currentEpisode() else { return }

        let options = OptionsPicker(title: nil, themeOverride: .dark)

        let markPlayedOption = OptionAction(label: L10n.markPlayedShort, icon: nil) {
            AnalyticsEpisodeHelper.shared.currentSource = .playerSkipForwardLongPress
            EpisodeManager.markAsPlayed(episode: episode, fireNotification: true)
        }
        options.addAction(action: markPlayedOption)

        if PlaybackManager.shared.queue.upNextCount() > 0 {
            let skipToNextAction = OptionAction(label: L10n.nextEpisode, icon: nil) {
                let currentlyPlayingEpisode = PlaybackManager.shared.currentEpisode()
                PlaybackManager.shared.removeIfPlayingOrQueued(episode: currentlyPlayingEpisode, fireNotification: true, userInitiated: true)
            }
            options.addAction(action: skipToNextAction)
        }

        options.show(statusBarStyle: preferredStatusBarStyle)
    }

    #if !APPCLIP
    @objc func googleCastTapped() {
        shelfButtonTapped(.chromecast)

        let themeOverride = Theme.sharedTheme.activeTheme.isDark ? Theme.sharedTheme.activeTheme : .dark
        let castController = CastToViewController(themeOverride: themeOverride)
        let navController = SJUIUtils.navController(for: castController, themeOverride: themeOverride)
        navController.modalPresentationStyle = .fullScreen

        present(navController, animated: true, completion: nil)
    }

    private func transitionOverlay(from oldMode: PlayerOverlayMode, to newMode: PlayerOverlayMode) {
        if oldMode != .none, newMode != .none {
            hideOverlay(oldMode)
            showOverlay(newMode)
            playerContainer?.setTranscriptHeaderHidden(true)
            resizeControls()
            playerContainer?.view.setNeedsLayout()
            playerContainer?.scrollView(isEnabled: false)
            playerContainer?.transcriptContainerView.isHidden = false
            playerContainer?.transcriptContainerView.layer.opacity = 1
            episodeImage.layer.opacity = 0
            (transcriptShelfButton as? TranscriptShelfButton)?.isTranscriptVisible = displayTranscript
            transcriptControlButton.isTranscriptVisible = displayTranscript
            updatePrimaryControlButtonState()
            return
        }

        let isShowing = newMode != .none

        playerContainer?.transcriptContainerView.layer.opacity = isShowing ? 0 : 1
        playerContainer?.setTranscriptHeaderHidden(isShowing)
        resizeControls()
        playerContainer?.view.setNeedsLayout()

        episodeImage.layer.opacity = 1
        (transcriptShelfButton as? TranscriptShelfButton)?.isTranscriptVisible = displayTranscript
        transcriptControlButton.isTranscriptVisible = displayTranscript
        updatePrimaryControlButtonState()

        if isShowing {
            showOverlay(newMode)
        }

        UIView.animate(withDuration: 0.25, delay: 0, options: [.curveEaseInOut], animations: { [weak self] in
            guard let self else { return }

            playerContainer?.transcriptContainerView.isHidden = false
            playerContainer?.transcriptContainerView.layer.opacity = isShowing ? 1 : 0
            playerContainer?.scrollView(isEnabled: !isShowing)
        }, completion: { [weak self] _ in
            guard let self else { return }

            playerContainer?.transcriptContainerView.isHidden = isShowing ? false : true

            if !isShowing {
                hideOverlay(oldMode)
            } else {
                episodeImage.layer.opacity = 0
            }
        })
    }

    private func showOverlay(_ mode: PlayerOverlayMode) {
        switch mode {
        case .none:
            break
        case .transcript:
            playerContainer?.showTranscript()
        case .chapters:
            playerContainer?.showChaptersOverlay()
        }
    }

    private func hideOverlay(_ mode: PlayerOverlayMode) {
        switch mode {
        case .none:
            break
        case .transcript:
            playerContainer?.hideTranscript()
        case .chapters:
            playerContainer?.hideChaptersOverlay()
        }
    }

    // MARK: Banner Ad

    func addAdBanner(promotion: BlazePromotion, animated: Bool = true) {
        removeBannerAd()

        guard let stackView = episodeImage.superview as? UIStackView else { return }

        let model = BannerAdModel(promotion: promotion) {
            UIApplication.shared.openSafariVCIfPossible(promotion.urlApple)
        }

        let adView = BannerAdView(model: model, colors: .playerColors(Theme.sharedTheme)).padding(16)
        let hostingController = PCHostingController(rootView: AnyView(adView))

        hostingController.view.translatesAutoresizingMaskIntoConstraints = false
        hostingController.view.backgroundColor = .clear

        let targetSize = CGSize(width: stackView.bounds.width, height: UIView.layoutFittingCompressedSize.height)
        let size = hostingController.sizeThatFits(in: targetSize)

        addChild(hostingController)
        let adUiView = hostingController.view!

        stackView.insertArrangedSubview(adUiView, at: 0)

        adUiView.alpha = 0
        let topConstraint = adUiView.topAnchor.constraint(equalTo: view.topAnchor, constant: -120)

        let heightConstraint = hostingController.view.heightAnchor.constraint(equalToConstant: size.height)
        NSLayoutConstraint.activate([
            heightConstraint,
            topConstraint,
        ])

        hostingController.didMove(toParent: self)
        bannerAdHostingController = hostingController
        bannerAdHeightConstraint = heightConstraint

        view.layoutIfNeeded()

        if animated {
            // Animate move first
            UIView.animate(withDuration: 0.25, delay: 0, options: [.curveEaseOut]) {
                topConstraint.constant = 0
                self.view.layoutIfNeeded()
            }

            // Animate opacity second so it's more noticeable
            UIView.animate(withDuration: 0.2, delay: 0.05) {
                adUiView.alpha = 1
            }
        } else {
            topConstraint.constant = 0
            adUiView.alpha = 1
        }
    }

    private func removeBannerAd() {
        guard let hostingController = bannerAdHostingController else { return }

        hostingController.willMove(toParent: nil)
        hostingController.view.removeFromSuperview()
        hostingController.removeFromParent()
        bannerAdHostingController = nil
        bannerAdHeightConstraint = nil
    }

    private func updateBannerAdHeight() {
        guard let hostingController = bannerAdHostingController,
              let heightConstraint = bannerAdHeightConstraint,
              let stackView = episodeImage.superview as? UIStackView else { return }

        let targetSize = CGSize(width: stackView.bounds.width, height: UIView.layoutFittingCompressedSize.height)
        let size = hostingController.sizeThatFits(in: targetSize)

        heightConstraint.constant = size.height
        view.layoutIfNeeded()
    }

    #endif
}
