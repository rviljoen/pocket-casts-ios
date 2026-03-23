import Foundation
import PocketCastsDataModel
import PocketCastsServer
import PocketCastsUtils

class MiniPlayerViewController: SimpleNotificationsViewController {
    enum PlayerOpenState {
        case closed, beingDragged, open, animating
    }

    var playerOpenState = PlayerOpenState.closed

    @IBOutlet var playPauseBtn: PlayPauseButton!
    @IBOutlet var skipBackBtn: UIButton!
    @IBOutlet var skipFwdBtn: UIButton!

    @IBOutlet var upNextBtn: UpNextButton!

    @IBOutlet var playbackProgressView: ProgressLine!

    @IBOutlet var podcastArtwork: PodcastImageView!
    @IBOutlet var mainView: UIView!
    @IBOutlet var glassEffectView: UIVisualEffectView!

    private var lastEpisodeUuidImageLoaded = ""
    private var lastEpisodeUuidAutoOpened = ""
    var fullScreenPlayer: PlayerContainerViewController?

    var panUpRecognizer: UIPanGestureRecognizer!
    var longPressRecognizer: UILongPressGestureRecognizer!

    var heightConstraint: NSLayoutConstraint?

    var upNextViewController: UpNextViewController?

    private let analyticsPlaybackHelper = AnalyticsPlaybackHelper.shared

    override func viewDidLoad() {
        super.viewDidLoad()

        addGestureRecognizers()

        view.isHidden = false

        // UITabAccessory will handle sizing automatically
        // Tab accessory trait handling will be added later

        setupCorners()
        addUINotificationObservers()
        playbackStateDidChange()
        themeChanged()
    }

    private func setupCorners() {
        // Use capsule shape (height / 2) for modern look
        let capsuleRadius = desiredHeight() / 2

        // Only apply capsule radius to the glass effect view - let it handle all visual styling
        glassEffectView.layer.cornerRadius = capsuleRadius
        glassEffectView.clipsToBounds = true

        // Remove corner radius from main view to avoid double-layered appearance
        mainView.layer.cornerRadius = 0
        mainView.layer.masksToBounds = false
        mainView.clipsToBounds = false  // Disable clipping set in XIB

        // Initialize with UIGlassEffect
        setupGlassEffect()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()

        // Ensure perfect capsule corners after any layout changes
        setupCorners()
    }

    deinit {
        removeAllCustomObservers()
    }

    @IBAction func playPauseTapped(_ sender: Any) {
        analyticsPlaybackHelper.currentSource = analyticsSource
        HapticsHelper.triggerPlayPauseHaptic()
        PlaybackManager.shared.playPause()
    }

    @IBAction func upNextTapped(_ sender: Any) {
        showUpNext(from: .miniPlayer)
    }

    @IBAction func skipBackTapped(_ sender: Any) {
        analyticsPlaybackHelper.currentSource = analyticsSource
        HapticsHelper.triggerSkipBackHaptic()
        PlaybackManager.shared.skipBack()
    }

    @IBAction func skipForwardTapped(_ sender: Any) {
        analyticsPlaybackHelper.currentSource = analyticsSource
        HapticsHelper.triggerSkipForwardHaptic()
        PlaybackManager.shared.skipForward()
    }

    func desiredHeight() -> CGFloat {
        // Increase height for UITabAccessory for better visual balance
        if #available(iOS 26.0, *),
           let tabController = rootViewController(),
           tabController.bottomAccessory?.contentView == self.view {
            return 200  // Taller for tab accessory
        }
        return 70  // Standard height for traditional layout
    }

    // MARK: - UITabAccessory Support
    // UITabAccessory automatically handles view sizing based on constraints

    private func setupTabAccessoryTraitHandling() {
        // Register for trait changes when used as UITabAccessory
        if #available(iOS 26.0, *) {
            registerForTraitChanges([UITraitTabAccessoryEnvironment.self]) { (controller: MiniPlayerViewController, _) in
                let isInline = controller.traitCollection.tabAccessoryEnvironment == .inline
                controller.updatePlayerAppearance(inline: isInline)
            }
        }
    }

    // Automatic trait tracking with updateProperties()
    @available(iOS 26.0, *)
    override func updateProperties() {
        super.updateProperties()
        let environment = traitCollection.tabAccessoryEnvironment
        let isInline = environment == .inline
        updatePlayerAppearance(inline: isInline)
    }

    private func updatePlayerAppearance(inline: Bool) {
        // Hide artwork and up next button when inline (minimized)
        podcastArtwork.superview?.isHidden = inline
        upNextBtn.isHidden = inline
    }

    // Manual test method - call this to test inline mode
    func testInlineMode() {
        updatePlayerAppearance(inline: true)
    }

    func aboutToDisplayFullScreenPlayer() {
        guard let rootVC = rootViewController() else { return }

        if fullScreenPlayer == nil {
            fullScreenPlayer = PlayerContainerViewController()
        }
    }

    func finishedWithFullScreenPlayer() {
        guard let rootVC = rootViewController() else { return }

        rootViewController()?.setNeedsStatusBarAppearanceUpdate()
        rootViewController()?.setNeedsUpdateOfHomeIndicatorAutoHidden()

        fullScreenPlayer?.view.removeFromSuperview()
        fullScreenPlayer = nil

        // update the mini player on full screen player close
        playbackStateDidChange()
        playbackProgressDidChange()
    }

    func changeHeightTo(_ height: CGFloat) {
        // UITabAccessory will use existing height constraints automatically
        if heightConstraint == nil {
            heightConstraint = view.heightAnchor.constraint(equalToConstant: height)
            heightConstraint?.isActive = true
        } else {
            heightConstraint?.constant = height
        }

        // Reapply corner radius after height change to ensure perfect capsule shape
        DispatchQueue.main.async { [weak self] in
            self?.setupCorners()
        }
    }

    // MARK: - Liquid Glass Setup

    private func setupGlassEffect() {
        // Check if we're being used as a UITabAccessory
        if #available(iOS 26.0, *),
           let tabController = rootViewController(),
           tabController.bottomAccessory?.contentView == self.view {
            // When used as tab accessory, disable our glass effect - let the accessory handle it
            glassEffectView.effect = nil
            glassEffectView.isHidden = true
        } else {
            // Simple single UIGlassEffect implementation for standalone use
            if #available(iOS 26.0, *) {
                let glassEffect = UIGlassEffect()
                glassEffectView.effect = glassEffect
            } else {
                // Fallback to system material for older iOS versions
                glassEffectView.effect = UIBlurEffect(style: .systemThinMaterial)
            }
        }
    }

    func addUINotificationObservers() {
        addCustomObserver(Constants.Notifications.playbackStarting, selector: #selector(playbackStarting))
        addCustomObserver(Constants.Notifications.playbackStarted, selector: #selector(playbackStarted))
        addCustomObserver(Constants.Notifications.playbackEnded, selector: #selector(playbackStateDidChange))
        addCustomObserver(Constants.Notifications.playbackPaused, selector: #selector(playbackStateDidChange))
        addCustomObserver(Constants.Notifications.playbackTrackChanged, selector: #selector(playbackStateDidChange))
        addCustomObserver(Constants.Notifications.playbackProgress, selector: #selector(playbackProgressDidChange))
        addCustomObserver(Constants.Notifications.googleCastStatusChanged, selector: #selector(playbackStateDidChange))
        addCustomObserver(Constants.Notifications.statusBarHeightChanged, selector: #selector(statusBarHeightDidChange))

        addCustomObserver(Constants.Notifications.podcastImageReCacheRequired, selector: #selector(updateRequired))

        addCustomObserver(.episodeEmbeddedArtworkLoaded, selector: #selector(updateRequired))

        addCustomObserver(Constants.Notifications.upNextQueueChanged, selector: #selector(upNextListChanged))
        addCustomObserver(Constants.Notifications.podcastDeleted, selector: #selector(upNextListChanged))

        addCustomObserver(UIApplication.didBecomeActiveNotification, selector: #selector(playbackStateDidChange))

        addCustomObserver(Constants.Notifications.themeChanged, selector: #selector(themeChanged))
        addCustomObserver(Constants.Notifications.currentlyPlayingEpisodeUpdated, selector: #selector(updateRequired))
    }

    func rootViewController() -> MainTabBarController? {
        if let controller = view.window?.rootViewController as? MainTabBarController {
            return controller
        }

        return nil
    }

    private func rootNavController() -> UINavigationController? {
        if let rootNav = rootViewController()?.selectedViewController as? UINavigationController {
            return rootNav
        }

        return nil
    }

    func miniPlayerShowing() -> Bool {
        !view.isHidden
    }

    private func setupForEpisode(_ episode: BaseEpisode) {
        updateColors()

        if lastEpisodeUuidImageLoaded != episode.uuid {
            lastEpisodeUuidImageLoaded = episode.uuid
            podcastArtwork.setBaseEpisode(episode: episode, size: .list)
        }
    }

    @objc private func playbackStarted() {
        if let episode = PlaybackManager.shared.currentEpisode() {
            setupForEpisode(episode)
            showMiniPlayer()
            let shouldOpenAutomatically: Bool
            if FeatureFlag.newSettingsStorage.enabled {
                shouldOpenAutomatically = SettingsStore.appSettings.openPlayer
            } else {
                shouldOpenAutomatically = UserDefaults.standard.bool(forKey: Constants.UserDefaults.openPlayerAutomatically)
            }
            if shouldOpenAutomatically || episode.videoPodcast(), lastEpisodeUuidAutoOpened != episode.uuid {
                lastEpisodeUuidAutoOpened = episode.uuid

                // we called show mini player above, which might have spent time animating itself into view, so give that time to finish
                DispatchQueue.main.asyncAfter(deadline: .now() + Constants.Animation.defaultAnimationTime) {
                    self.openFullScreenPlayer()
                }
            }
        } else {
            hideMiniPlayer(true)
        }
    }

    @objc private func playbackStarting() {
        playbackStateDidChange()
    }

    @objc private func statusBarHeightDidChange() {
        if miniPlayerShowing() {
            hideMiniPlayer(false)
            showMiniPlayer()
        }
    }

    @objc private func upNextListChanged() {
        playbackStateDidChange()
    }

    @objc private func playbackStateDidChange() {
        guard let episodePlaying = PlaybackManager.shared.currentEpisode() else {
            hideMiniPlayer(true)

            return
        }

        setupForEpisode(episodePlaying)
        showMiniPlayer()
        playbackProgressDidChange()
    }

    @objc private func themeChanged() {
        updateColors()
    }

    @objc private func playbackProgressDidChange() {
        if playerOpenState == .open { return } // don't update the mini player while the full screen player is open

        let currentTime = PlaybackManager.shared.currentTime()
        let duration = PlaybackManager.shared.duration()

        var progress: CGFloat = 0
        if currentTime > 0, duration > 0 {
            progress = min(1, CGFloat(currentTime / duration))
        }

        playbackProgressView.progress = progress
        playbackProgressView.indeterminant = PlaybackManager.shared.buffering() && PlaybackManager.shared.playing()

        let amountBuferred = PlaybackManager.shared.futureBufferAvailable()
        if amountBuferred > 0 {
            playbackProgressView.buferredAmount = CGFloat(amountBuferred / (duration - currentTime))
        }
    }

    private func updateColors() {
        let actionColor: UIColor
        if let podcast = podcastForEpisode(PlaybackManager.shared.currentEpisode()) {
            actionColor = Theme.isDarkTheme() ? ColorManager.darkThemeTintForPodcast(podcast) : ColorManager.lightThemeTintForPodcast(podcast)
        } else {
            if let episode = PlaybackManager.shared.currentEpisode() as? UserEpisode, episode.imageColor > 0 {
                actionColor = AppTheme.userEpisodeColor(number: Int(episode.imageColor))
            } else {
                actionColor = AppTheme.userEpisodeColor(number: 1)
            }
        }
        view.backgroundColor = .clear

        let bgColor = ThemeColor.podcastUi02(podcastColor: actionColor)
        // Remove background - let glass do all the work
        mainView.backgroundColor = UIColor.clear
        playPauseBtn.playButtonColor = bgColor

        playbackProgressView.updateColors()

        let iconColor = ThemeColor.podcastIcon03(podcastColor: actionColor)
        playPauseBtn.circleColor = iconColor

        skipBackBtn.tintColor = iconColor
        skipFwdBtn.tintColor = iconColor
        upNextBtn.iconColor = iconColor

        playPauseBtn.isPlaying = PlaybackManager.shared.playing()
    }

    private func podcastForEpisode(_ episode: BaseEpisode?) -> Podcast? {
        if let episode = PlaybackManager.shared.currentEpisode() as? Episode {
            return episode.parentPodcast()
        }

        return nil
    }

    @objc private func updateRequired() {
        guard let episode = PlaybackManager.shared.currentEpisode() else { return }

        updateColors()

        if let userEpisode = episode as? UserEpisode {
            podcastArtwork.setUserEpisode(uuid: userEpisode.uuid, size: .list)
        } else {
            podcastArtwork.setBaseEpisode(episode: episode, size: .list)
        }
    }

    func showUpNext(from source: UpNextViewSource) {
        upNextViewController = UpNextViewController(source: source)
        guard let upNextController = upNextViewController else { return }

        let navWrapper = SJUIUtils.navController(for: upNextController, iconStyle: .secondaryText01, themeOverride: upNextController.themeOverride)
        navWrapper.modalPresentationStyle = .formSheet
        rootViewController()?.present(navWrapper, animated: true, completion: nil)
    }
}

extension MiniPlayerViewController: AnalyticsSourceProvider {
    var analyticsSource: AnalyticsSource {
        .miniplayer
    }
}
