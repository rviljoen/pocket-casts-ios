import PocketCastsUtils
import UIKit

class PlayerContainerViewController: SimpleNotificationsViewController, PlayerTabDelegate, PlayerItemContainerDelegate {
    @IBOutlet var headerView: UIView!
    @IBOutlet var tabsView: PlayerTabsView! {
        didSet {
            tabsView.setup()
            tabsView.tabDelegate = self
        }
    }

    #if APPCLIP
    @IBOutlet var upNextBtn: UIButton!
    #else
    @IBOutlet var upNextBtn: UpNextButton! {
        didSet {
            upNextBtn.themeOverride = .dark
            upNextBtn.iconColor = AppTheme.colorForStyle(.playerContrast01)
        }
    }
    #endif

    @IBOutlet var mainScrollView: RegionCancellingScrollView! {
        didSet {
            // We don't need to handle the scroll view because it is not dismissable in App Clip
            #if !APPCLIP
            mainScrollView.delegate = self
            #endif
        }
    }

    @IBOutlet var headerHeightConstraint: NSLayoutConstraint!

    @IBOutlet weak var transcriptContainerView: UIView!
    private var transcriptLeadingConstraint: NSLayoutConstraint?
    private var transcriptTopConstraint: NSLayoutConstraint?
    private var transcriptWidthConstraint: NSLayoutConstraint?
    private var transcriptHeightConstraint: NSLayoutConstraint?
    private var transcriptHeaderHidden = false

    lazy var nowPlayingItem: NowPlayingPlayerItemViewController = {
        let item = NowPlayingPlayerItemViewController()
        item.containerDelegate = self
        item.view.translatesAutoresizingMaskIntoConstraints = false

        return item
    }()

    #if !APPCLIP
    lazy var showNotesItem: ShowNotesPlayerItemViewController = {
        let item = ShowNotesPlayerItemViewController()
        item.scrollViewHandler = self
        item.containerDelegate = self
        item.view.translatesAutoresizingMaskIntoConstraints = false

        return item
    }()

    lazy var chaptersItem: ChaptersViewController = {
        let item = ChaptersViewController()
        item.scrollViewHandler = self
        item.containerDelegate = self
        item.view.translatesAutoresizingMaskIntoConstraints = false

        return item
    }()

    lazy var bookmarksItem: BookmarksPlayerTabController = {
        let playbackManager = PlaybackManager.shared
        let bookmarkManager = playbackManager.bookmarkManager
        let item = BookmarksPlayerTabController(bookmarkManager: bookmarkManager,
                                                playbackManager: playbackManager)

        item.view.translatesAutoresizingMaskIntoConstraints = false
        item.containerDelegate = self
        return item
    }()

    private func makeTranscriptViewController() -> TranscriptViewController {
        let playbackManager = PlaybackManager.shared
        let item = TranscriptViewController(playbackManager: playbackManager)

        item.view.translatesAutoresizingMaskIntoConstraints = false
        item.scrollViewHandler = self
        item.containerDelegate = self
        return item
    }

    private var transcriptsItem: TranscriptViewController?

    private func makeOverlayChaptersViewController() -> ChaptersViewController {
        let item = ChaptersViewController()
        item.showsCompactPlayerHeader = true
        item.scrollViewHandler = self
        item.containerDelegate = self
        item.view.translatesAutoresizingMaskIntoConstraints = false
        return item
    }

    private var overlayChaptersItem: ChaptersViewController?

    private lazy var generatedTranscriptsPremiumOverlay: GeneratedTranscriptsPremiumOverlay = {
        let playbackManager = PlaybackManager.shared
        let item = GeneratedTranscriptsPremiumOverlay(playbackManager: playbackManager)
        item.view.translatesAutoresizingMaskIntoConstraints = false
        item.dismissTranscript = { [weak self] in
            self?.dismissGeneratedTranscriptsPremiumOverlay(dismissTranscript: true)
        }
        item.purchaseSuccessfull = { [weak self] in
            self?.dismissGeneratedTranscriptsPremiumOverlay(dismissTranscript: false)
        }
        return item
    }()

    private lazy var upNextViewController = UpNextViewController(source: .player)
    #endif

    @IBOutlet var closeBtn: ThemeableUIButton! {
        didSet {
            closeBtn.style = .playerContrast02
        }
    }

    var initialTouchPoint = CGPoint(x: 0, y: 0)

    var showingChapters = false
    var showingNotes = false
    var showingBookmarks = false

    var finalScrollViewConstraint: NSLayoutConstraint?

    /// The velocity in which the player was dismissed
    var dismissVelocity: CGFloat = 0

    /// The final yPosition when dismissing
    var finalYPositionWhenDismissing: CGFloat = 0

    override func viewDidLoad() {
        super.viewDidLoad()
        view.accessibilityViewIsModal = true
        view.layer.cornerRadius = 55

        setupPlayer()
        setupGestures()
        setupObservers()
        update()

        NotificationCenter.default.addObserver(self, selector: #selector(handleAppWillBecomeActive), name: UIApplication.willEnterForegroundNotification, object: nil)

        #if !APPCLIP
        configureTranscriptContainerView()
        #endif
    }


    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
#if !APPCLIP
        showNotesItem.updateScrollSize()
#endif
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)

        #if !APPCLIP
        if nowPlayingItem.displayTranscript {
            transcriptsItem?.didDisappear()
            generatedTranscriptsPremiumOverlay.didDisappear()
        }
        #endif
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()

        adjustHeaderConstraintIfNeeded()
        adjustPlayerNoSlidingRegion()
        #if !APPCLIP
        updateTranscriptContainerLayout()
        #endif
    }

    @IBAction func upNextTapped(_ sender: Any) {
        showUpNext()
    }

    @IBAction func closeTapped(_ sender: Any) {
        #if APPCLIP
        // Close doesn't exist in the App Clip
        #else
        appDelegate()?.miniPlayer()?.closeFullScreenPlayer()
        #endif
    }

    @objc private func showUpNext() {
        #if APPCLIP
        //TODO: Show install banner
        #else
        let navController = SJUIUtils.navController(for: upNextViewController, iconStyle: .secondaryText01, themeOverride: upNextViewController.themeOverride)
        present(navController, animated: true, completion: nil)
        #endif
    }

    // MARK: - Orientation

    // we implement this here to lock all views (except presented modal VCs to portrait)
    override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        .portrait
    }

    // MARK: - PlayerItemContainerDelegate

    func scrollToCurrentChapter() {
        guard scroll(to: .chapters) else {
            return
        }

        #if !APPCLIP
        chaptersItem.scrollToCurrentlyPlayingChapter(animated: false)
        #endif
    }

    func scrollToNowPlaying() {
        scroll(to: .nowPlaying)
    }

    func scrollToBookmarks() {
        scroll(to: .bookmarks)
    }

    func navigateToPodcast() {
        guard let podcast = PlaybackManager.shared.currentPodcast else {
            return
        }

        #if APPCLIP
        //TODO: Show install banner
        #else
        NavigationManager.sharedManager.navigateTo(NavigationManager.podcastPageKey, data: [NavigationManager.podcastKey: podcast])
        #endif
    }

    func dismissTranscript() {
        nowPlayingItem.displayTranscript = false
    }

    // MARK: - PlayerTabDelegate

    func didSwitchToTab(index: Int) {
        scroll(to: index)
    }

    private func setupObservers() {
        addCustomObserver(Constants.Notifications.playbackEnded, selector: #selector(playbackFinished))
        addCustomObserver(Constants.Notifications.playbackStarted, selector: #selector(update))
        addCustomObserver(Constants.Notifications.playbackTrackChanged, selector: #selector(update))
        addCustomObserver(Constants.Notifications.podcastChaptersDidUpdate, selector: #selector(update))
        addCustomObserver(Constants.Notifications.themeChanged, selector: #selector(themeDidChange))
    }

    private func setupGestures() {
        #if !APPCLIP
        let panGesture = UIPanGestureRecognizer(target: self, action: #selector(panGestureRecognizerHandler(_:)))
        panGesture.cancelsTouchesInView = false
        view.addGestureRecognizer(panGesture)
        #endif
    }

    @objc private func themeDidChange() {
        updateColors()
        tabsView.themeDidChange()
        nowPlayingItem.themeDidChange()
        #if !APPCLIP
        chaptersItem.themeDidChange()
        showNotesItem.themeDidChange()
        transcriptsItem?.themeDidChange()
        overlayChaptersItem?.themeDidChange()
        #endif
    }

    @objc private func playbackFinished() {
        if PlaybackManager.shared.currentEpisode() == nil {
            closeNowPlaying()
        }
    }

    func closeNowPlaying() {
        #if APPCLIP
        //TODO: Show install banner
        #else
        appDelegate()?.miniPlayer()?.closeFullScreenPlayer()
        #endif
    }

    private func setupPlayer() {
        nowPlayingItem.willBeAddedToPlayer()
        mainScrollView.addSubview(nowPlayingItem.view)
        addChild(nowPlayingItem)

        let finalConstraint = nowPlayingItem.view.trailingAnchor.constraint(equalTo: mainScrollView.trailingAnchor)
        NSLayoutConstraint.activate([
            nowPlayingItem.view.leadingAnchor.constraint(equalTo: mainScrollView.leadingAnchor),
            nowPlayingItem.view.topAnchor.constraint(equalTo: mainScrollView.topAnchor),
            nowPlayingItem.view.bottomAnchor.constraint(equalTo: mainScrollView.bottomAnchor),
            nowPlayingItem.view.widthAnchor.constraint(equalTo: mainScrollView.widthAnchor),
            nowPlayingItem.view.heightAnchor.constraint(equalTo: mainScrollView.heightAnchor),
            finalConstraint
        ])
        finalScrollViewConstraint = finalConstraint

        tabsView.tabs = [.nowPlaying]
    }

    private func adjustHeaderConstraintIfNeeded() {
        guard let window = view.window else { return }

        let requiredHeight = (transcriptHeaderHidden ? 0 : 50) + UIUtil.statusBarHeight(in: window)

        if headerHeightConstraint.constant != requiredHeight {
            headerHeightConstraint.constant = requiredHeight
        }
    }

    func setTranscriptHeaderHidden(_ hidden: Bool) {
        transcriptHeaderHidden = hidden
        headerView.alpha = hidden ? 0 : 1
        headerView.isUserInteractionEnabled = !hidden
        view.setNeedsLayout()
    }

    func adjustPlayerNoSlidingRegion() {
        if tabsView.currentTab == 0 {
            let sliderRegion = mainScrollView.convert(nowPlayingItem.timeSlider.frame, from: nowPlayingItem.timeSlider.superview)
            // the slider has a large region for the popup that you get when interacting with it, which we don't need to block off (hence the 30pt top offset), and since fingers are imprecise we go 20pt lower too
            let adjustedRegion = sliderRegion.inset(by: UIEdgeInsets(top: 30, left: -10, bottom: -20, right: -10))
            mainScrollView.regionsToCancelIn = adjustedRegion
        } else {
            mainScrollView.regionsToCancelIn = nil
        }
    }

    override var preferredStatusBarStyle: UIStatusBarStyle {
        .lightContent
    }

    // MARK: - App Backgrounding

    @objc func handleAppWillBecomeActive() {
        didSwitchToTab(index: tabsView.currentTab)
    }

    // MARK: - Hide/Show tabs

    func scrollView(isEnabled: Bool) {
        mainScrollView.isScrollEnabled = isEnabled
        view.layoutIfNeeded()
    }

    // MARK: - Transcripts

    #if !APPCLIP
    func showTranscript() {
        hideChaptersOverlay()
        updateTranscriptContainerLayout()

        let transcriptsItem = transcriptsItem ?? makeTranscriptViewController()
        self.transcriptsItem = transcriptsItem

        addChild(transcriptsItem)
        transcriptContainerView.addSubview(transcriptsItem.view)
        transcriptsItem.view.anchorToAllSidesOf(view: transcriptContainerView)
        transcriptsItem.didMove(toParent: self)
        transcriptsItem.willBeAddedToPlayer()
        transcriptsItem.themeDidChange()
        transcriptsItem.showGeneratedTranscriptsPremiumOverlay = { [weak self] in
            UIView.animate(withDuration: 0.25) {
                self?.showGeneratedTranscriptsPremiumOverlay()
            }
        }
    }

    private func showGeneratedTranscriptsPremiumOverlay() {
        generatedTranscriptsPremiumOverlay.didAppear()
        addChild(generatedTranscriptsPremiumOverlay)
        view.addSubview(generatedTranscriptsPremiumOverlay.view)
        generatedTranscriptsPremiumOverlay.view.anchorToAllSidesOf(view: view)
        generatedTranscriptsPremiumOverlay.didMove(toParent: self)
    }

    private func dismissGeneratedTranscriptsPremiumOverlay(dismissTranscript: Bool) {
        UIView.animate(withDuration: 0.25) { [weak self] in
            self?.generatedTranscriptsPremiumOverlay.didDisappear()
            self?.generatedTranscriptsPremiumOverlay.willMove(toParent: nil)
            self?.generatedTranscriptsPremiumOverlay.removeFromParent()
            self?.generatedTranscriptsPremiumOverlay.view.removeFromSuperview()
        } completion: { [weak self] _ in
            if dismissTranscript {
                self?.dismissTranscript()
            }
        }
    }

    func hideTranscript() {
        guard let transcriptsItem else { return }
        transcriptsItem.willBeRemovedFromPlayer()
        transcriptsItem.willMove(toParent: nil)
        transcriptsItem.removeFromParent()
        transcriptsItem.view.removeFromSuperview()
        transcriptsItem.didDisappear()
        self.transcriptsItem = nil
    }

    func showChaptersOverlay() {
        hideTranscript()
        updateTranscriptContainerLayout()

        let overlayChaptersItem = overlayChaptersItem ?? makeOverlayChaptersViewController()
        self.overlayChaptersItem = overlayChaptersItem

        addChild(overlayChaptersItem)
        transcriptContainerView.addSubview(overlayChaptersItem.view)
        overlayChaptersItem.view.anchorToAllSidesOf(view: transcriptContainerView)
        overlayChaptersItem.didMove(toParent: self)
        overlayChaptersItem.willBeAddedToPlayer()
        overlayChaptersItem.themeDidChange()
        overlayChaptersItem.scrollToCurrentlyPlayingChapter(animated: false)
    }

    func hideChaptersOverlay() {
        guard let overlayChaptersItem else { return }
        overlayChaptersItem.willBeRemovedFromPlayer()
        overlayChaptersItem.willMove(toParent: nil)
        overlayChaptersItem.removeFromParent()
        overlayChaptersItem.view.removeFromSuperview()
        self.overlayChaptersItem = nil
    }

    private func configureTranscriptContainerView() {
        let transcriptConstraints = view.constraints.filter { constraint in
            (constraint.firstItem as? UIView) === transcriptContainerView ||
            (constraint.secondItem as? UIView) === transcriptContainerView
        }
        NSLayoutConstraint.deactivate(transcriptConstraints)

        transcriptLeadingConstraint = transcriptContainerView.leadingAnchor.constraint(equalTo: view.leadingAnchor)
        transcriptTopConstraint = transcriptContainerView.topAnchor.constraint(equalTo: view.topAnchor)
        transcriptWidthConstraint = transcriptContainerView.widthAnchor.constraint(equalToConstant: 0)
        transcriptHeightConstraint = transcriptContainerView.heightAnchor.constraint(equalToConstant: 0)

        NSLayoutConstraint.activate([
            transcriptLeadingConstraint,
            transcriptTopConstraint,
            transcriptWidthConstraint,
            transcriptHeightConstraint
        ].compactMap { $0 })

        transcriptContainerView.backgroundColor = PlayerColorHelper.playerBackgroundColor01()
        transcriptContainerView.layer.cornerRadius = 8
        transcriptContainerView.layer.masksToBounds = true
        transcriptContainerView.layer.cornerCurve = .continuous
        updateTranscriptContainerLayout()
    }

    private func updateTranscriptContainerLayout() {
        guard let mediaSourceView = nowPlayingItem.floatingVideoView?.isHidden == false
            ? nowPlayingItem.floatingVideoView
            : nowPlayingItem.episodeImage,
              let titleInfoView = nowPlayingItem.episodeInfoView?.superview else {
            return
        }
        let mediaFrame = view.convert(mediaSourceView.bounds, from: mediaSourceView)
        let titleInfoFrame = view.convert(titleInfoView.bounds, from: titleInfoView)
        let infoIsHidden = nowPlayingItem.episodeInfoView?.isHidden == true && nowPlayingItem.chapterInfoView?.isHidden == true
        let titleInfoEdge = infoIsHidden ? titleInfoFrame.maxY : titleInfoFrame.minY - 6
        let transcriptBottom = max(mediaFrame.maxY, titleInfoEdge)
        let horizontalInset: CGFloat = 10

        transcriptLeadingConstraint?.constant = horizontalInset
        transcriptTopConstraint?.constant = mediaFrame.minY
        transcriptWidthConstraint?.constant = view.bounds.width - (horizontalInset * 2)
        transcriptHeightConstraint?.constant = transcriptBottom - mediaFrame.minY
    }
    #endif
}

private extension PlayerContainerViewController {
    @discardableResult
    func scroll(to tab: PlayerTabs) -> Bool {
        guard let index = tabsView.tabs.firstIndex(of: tab) else {
            return false
        }

        scroll(to: index)

        return true
    }

    func scroll(to index: Int) {
        if tabsView.currentTab != index {
            tabsView.currentTab = index
        }

        let offset = CGFloat(index) * mainScrollView.frame.width

        UIView.animate(withDuration: Constants.Animation.playerTabSwitch) {
            self.mainScrollView.setContentOffset(.init(x: offset, y: 0), animated: false)
        }
    }
}

extension PlayerContainerViewController: AnalyticsSourceProvider {
    var analyticsSource: AnalyticsSource {
        .player
    }
}
