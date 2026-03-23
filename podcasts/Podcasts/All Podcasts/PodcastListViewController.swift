import DifferenceKit
import SwiftUI
import PocketCastsDataModel
import PocketCastsServer
import PocketCastsUtils
import UIKit
import Kingfisher
import SafariServices

class PodcastListViewController: PCViewController, UIGestureRecognizerDelegate, ShareListDelegate {
    let gridHelper = GridHelper()
    var bannerAdModel: BannerAdModel?

    /// Indicates whether the banner ad is currently animating to indicate to the collection view layout which size to use
    var isAnimatingBannerAd = false

    private var bannerTask: Task<Void, Never>? = nil

    @IBOutlet var addPodcastBtn: ThemeableButton! {
        didSet {
            addPodcastBtn.buttonTitle = L10n.podcastGridDiscoverPodcasts
            addPodcastBtn.buttonTapped = {
                Analytics.track(.podcastsListDiscoverButtonTapped)
                NavigationManager.sharedManager.navigateTo(NavigationManager.discoverPageKey, data: nil)
            }
        }
    }

    @IBOutlet var podcastsCollectionView: UICollectionView! {
        didSet {
            registerCells()

            if let layout = podcastsCollectionView.collectionViewLayout as? UICollectionViewFlowLayout {
                layout.sectionHeadersPinToVisibleBounds = false
            }
        }
    }

    var gridItems = [HomeGridListItem]()
    var gridLayout: LibraryType = Settings.libraryType()

    private var lastWillLayoutWidth: CGFloat = 0

    private var homeGridDataHelper = HomeGridDataHelper()

    private lazy var refreshQueue: OperationQueue = {
        let queue = OperationQueue()
        queue.maxConcurrentOperationCount = 1

        return queue
    }()

    var recentlyPlayedSortingTip: UIViewController?

    var searchController: PCSearchBarController!

    lazy var searchResultsController = SearchResultsViewController(source: .podcastsList, showLocalResults: true)

    var resultsControllerDelegate: SearchResultsDelegate {
        searchResultsController
    }

    override func viewDidLoad() {
        customRightBtn = UIBarButtonItem(image: UIImage(named: "more"), style: .plain, target: self, action: #selector(podcastOptionsTapped(_:)))
        customRightBtn?.accessibilityLabel = L10n.accessibilityMoreActions
        super.viewDidLoad()

        updateNavigationButtons()
        title = L10n.podcastsPlural
        setupSearchBar()
        setupRefreshControl()

        let longPressGesture = UILongPressGestureRecognizer(target: self, action: #selector(handleLongPress(_:)))
        podcastsCollectionView.addGestureRecognizer(longPressGesture)
        longPressGesture.delegate = self

        adjustSettingsForGridType()
        insetAdjuster.setupInsetAdjustmentsForMiniPlayer(scrollView: podcastsCollectionView)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)


        updateInsets()
        refreshGridItems()
        addEventObservers()
        updateNavigationButtons()

        Analytics.track(.podcastsListShown, properties: [
            "sort_order": Settings.homeFolderSortOrder(),
            "badge_type": Settings.podcastBadgeType(),
            "layout": Settings.libraryType(),
            "number_of_podcasts": homeGridDataHelper.numberOfPodcasts,
            "number_of_folders": homeGridDataHelper.numberOfFolders
        ])

        showRecentlyPlayedSortingTipIfNeeded()
    }

    override func viewWillLayoutSubviews() {
        super.viewWillLayoutSubviews()

        if lastWillLayoutWidth != view.bounds.width {
            lastWillLayoutWidth = view.bounds.width
            updateFlowLayoutSize()
        }
    }

    override func handleAppWillBecomeActive() {
        refreshGridItems()
        addEventObservers()
    }

    override func handleAppDidEnterBackground() {
        removeAllCustomObservers()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        navigationController?.navigationBar.shadowImage = UIImage()
        loadBannerAd()
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        bannerTask?.cancel()
        navigationController?.navigationBar.shadowImage = nil
        removeAllCustomObservers()
    }

    private func addEventObservers() {
        addCustomObserver(ServerNotifications.podcastsRefreshed, selector: #selector(refreshGridItems))
        addCustomObserver(ServerNotifications.subscriptionStatusChanged, selector: #selector(subscriptionStatusDidChange))
        addCustomObserver(Constants.Notifications.podcastAdded, selector: #selector(refreshGridItems))
        addCustomObserver(Constants.Notifications.podcastDeleted, selector: #selector(refreshGridItems))
        addCustomObserver(Constants.Notifications.opmlImportCompleted, selector: #selector(refreshGridItems))
        addCustomObserver(ServerNotifications.syncCompleted, selector: #selector(refreshGridItems))
        addCustomObserver(Constants.Notifications.playbackTrackChanged, selector: #selector(refreshGridItems))
        addCustomObserver(Constants.Notifications.playbackEnded, selector: #selector(refreshGridItems))
        addCustomObserver(Constants.Notifications.episodeArchiveStatusChanged, selector: #selector(refreshGridItems))
        addCustomObserver(Constants.Notifications.episodePlayStatusChanged, selector: #selector(refreshGridItems))

        addCustomObserver(Constants.Notifications.folderChanged, selector: #selector(refreshGridItems))
        addCustomObserver(Constants.Notifications.folderDeleted, selector: #selector(refreshGridItems))

        addCustomObserver(Constants.Notifications.tappedOnSelectedTab, selector: #selector(checkForScrollTap(_:)))
        addCustomObserver(Constants.Notifications.searchRequested, selector: #selector(searchRequested))
    }

    @objc private func subscriptionStatusDidChange() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }

            self.updateNavigationButtons()
            self.loadBannerAd()
        }
    }

    private func loadBannerAd() {
        bannerTask?.cancel()

        if SubscriptionHelper.shouldDisplayBannerAd {
            DiscoverServerHandler.shared.blazePromotion(for: .podcastList) { [weak self] promotion, shouldAnimate in
                guard let self = self else { return }

                if shouldAnimate {
                    self.bannerTask = Task { [weak self] in
                        try? await Task.sleep(for: .seconds(2))
                        await MainActor.run {
                            self?.setupBannerAd(promotion: promotion, shouldAnimate: true)
                        }
                    }
                } else {
                    self.setupBannerAd(promotion: promotion, shouldAnimate: false)
                }
            }
        } else {
            if bannerAdModel != nil {
                bannerAdModel = nil
                UIView.animate(withDuration: 0.25, delay: 0, options: [.curveEaseOut]) {
                    self.isAnimatingBannerAd = false
                } completion: { _ in
                    self.podcastsCollectionView.performBatchUpdates({
                        self.podcastsCollectionView.collectionViewLayout.invalidateLayout()
                    })
                }
            }
        }
    }

    private func makeBadge(size: CGFloat) -> UIView {
        let badgeView = CircleView()
        badgeView.borderColor = ThemeColor.secondaryUi01()
        badgeView.centerColor = ThemeColor.primaryInteractive01()
        badgeView.backgroundColor = .clear
        badgeView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            badgeView.widthAnchor.constraint(equalToConstant: size),
            badgeView.heightAnchor.constraint(equalToConstant: size),
        ])
        return badgeView
    }

    private func makeProfileButton(email: String?) -> UIBarButtonItem {
        let avatarSize = CGFloat(32)
        let imageView = UIImageView(frame: CGRect(x: 0, y: 0, width: avatarSize, height: avatarSize))
        imageView.contentMode = .center
        let profileImage = UIImage(named: "profile-placeholder")?.withRenderingMode(.alwaysTemplate)
        imageView.image = profileImage
        if let email {
            imageView.contentMode = .scaleAspectFit
            let gravatarURL = URL(string: "https://www.gravatar.com/avatar/\(email.sha256)?d=404&s=\(256)")
            let processor = DownsamplingImageProcessor(size: imageView.bounds.size) |> RoundCornerImageProcessor(cornerRadius: 20)
            imageView.kf.setImage(with: gravatarURL, placeholder: profileImage, options: [
                .processor(processor),
                .scaleFactor(UIScreen.main.scale),
                .transition(.fade(1)),
                .cacheOriginalImage
            ])
        }

        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(profileTapped(_:)))
        imageView.addGestureRecognizer(tapGesture)
        imageView.isUserInteractionEnabled = true
        NSLayoutConstraint.activate([
            imageView.widthAnchor.constraint(equalToConstant: avatarSize),
            imageView.heightAnchor.constraint(equalToConstant: avatarSize),
        ])

        if EndOfYear.isEligible, EndOfYear.shouldShowBadge {
            let badgeSize = CGFloat(10)
            let badge = makeBadge(size: badgeSize)
            imageView.addSubview(badge)
            NSLayoutConstraint.activate([
                badge.centerXAnchor.constraint(equalTo: imageView.rightAnchor, constant: -(badgeSize / 2)),
                badge.centerYAnchor.constraint(equalTo: imageView.topAnchor, constant: +(badgeSize / 2)),
            ])
        }
        return UIBarButtonItem(customView: imageView)
    }

    private func updateNavigationButtons() {
        let folderImage = UIImage(named: "folder-create")
        let folderButton = UIBarButtonItem(image: folderImage, style: .plain, target: self, action: #selector(createFolderTapped(_:)))
        folderButton.accessibilityLabel = L10n.folderCreateNew
        navigationItem.leftBarButtonItem = folderButton
        extraRightButtons = []
    }

    @objc private func checkForScrollTap(_ notification: Notification) {
        let topOffset = -PCSearchBarController.defaultHeight - view.safeAreaInsets.top
        if let index = notification.object as? Int, index == tabBarItem.tag, podcastsCollectionView.contentOffset.y.rounded(.down) > topOffset.rounded(.down) {
            podcastsCollectionView.setContentOffset(CGPoint(x: -horizontalMargin, y: topOffset), animated: true)
        } else {
            // When double-tapping on tab bar, dismiss the search if already active
            // else give focus to the search field
            if searchController.cancelButtonShowing {
                searchController.cancelTapped(self)
            } else {
                searchController.searchTextField.becomeFirstResponder()
            }
        }
    }

    @objc private func searchRequested() {
        let topOffset = view.safeAreaInsets.top
        podcastsCollectionView.setContentOffset(CGPoint(x: 0, y: -searchController.view.bounds.height - topOffset), animated: false)
        searchController.searchTextField.becomeFirstResponder()
    }

    private var horizontalMargin: CGFloat {
        Settings.libraryType() == .list ? 0 : 16
    }

    private func updateInsets() {
        let currentInsets = podcastsCollectionView.contentInset
        podcastsCollectionView.contentInset = UIEdgeInsets(top: currentInsets.top, left: horizontalMargin, bottom: currentInsets.bottom, right: horizontalMargin)
    }

    private func adjustSettingsForGridType() {
        updateInsets()
        gridHelper.configureLayout(collectionView: podcastsCollectionView)
        if let themeableCollectionView = podcastsCollectionView as? ThemeableCollectionView {
            themeableCollectionView.style = Settings.libraryType() == .list ?  ThemeStyle.primaryUi04 : ThemeStyle.primaryUi02
        }
    }

    @objc func refreshGridItems() {
        refreshQueue.addOperation { [weak self] in
            guard let strongSelf = self else { return }

            let oldData = strongSelf.gridItems
            let sortOption: LibrarySort
            if !FeatureFlag.podcastsSortChanges.enabled, Settings.homeFolderSortOrder() == .recentlyPlayed {
                Settings.setHomeFolderSortOrder(order: .dateAddedNewestToOldest)
                sortOption = .dateAddedNewestToOldest
            } else {
                sortOption = Settings.homeFolderSortOrder()
            }
            var newData = HomeGridDataHelper.gridListItems(orderedBy: sortOption, badgeType: Settings.podcastBadgeType())

            if newData.isEmpty {
                newData = [HomeGridListItem.empty]
            }

            DispatchQueue.main.sync {
                if strongSelf.gridLayout != Settings.libraryType() {
                    strongSelf.podcastsCollectionView.reloadData()
                    strongSelf.gridLayout = Settings.libraryType()
                } else {
                    let stagedSet = StagedChangeset(source: oldData, target: newData)
                    strongSelf.podcastsCollectionView.reload(using: stagedSet, setData: { data in
                        strongSelf.gridItems = data
                    })
                }
                strongSelf.foldersCoordinator.showUpsellIfNeeded(from: strongSelf)
            }
        }
    }

    func showProfileController() {
        let profileViewController = ProfileViewController()
        self.navigationController?.pushViewController(profileViewController, animated: true)
    }

    @objc private func profileTapped(_ sender: UIBarButtonItem) {
        showProfileController()
    }

    private lazy var foldersCoordinator: FoldersCoordinator = {
        return FoldersCoordinator()
    }()

    func showSuggestedFolders() {
        foldersCoordinator.showSuggestedFolders(from: self)
    }

    @objc private func createFolderTapped(_ sender: UIBarButtonItem) {
        foldersCoordinator.startFolderCreationFlow(from: self)
    }

    @objc private func podcastOptionsTapped(_ sender: UIBarButtonItem) {
        let optionsPicker = OptionsPicker(title: nil)

        let sortOption: LibrarySort = if !FeatureFlag.podcastsSortChanges.enabled, Settings.homeFolderSortOrder() == .recentlyPlayed {
            .dateAddedNewestToOldest
        } else {
            Settings.homeFolderSortOrder()
        }
        let sortAction = OptionAction(label: L10n.sortBy, secondaryLabel: sortOption.description, icon: "podcast-sort") { [weak self] in
            self?.showSortOrderOptions()
            Analytics.track(.podcastsListModalOptionTapped, properties: ["option": "sort_by"])
        }
        optionsPicker.addAction(action: sortAction)

        let largeGridAction = OptionAction(label: L10n.podcastsLargeGrid, icon: "podcastlist_largegrid", selected: Settings.libraryType() == .threeByThree) { [weak self] in
            Settings.setLibraryType(.threeByThree)
            self?.gridTypeChanged()
            Analytics.track(.podcastsListModalOptionTapped, properties: ["option": "layout"])
            Analytics.track(.podcastsListLayoutChanged, properties: ["layout": LibraryType.threeByThree])
        }
        let smallGridAction = OptionAction(label: L10n.podcastsSmallGrid, icon: "podcastlist_smallgrid", selected: Settings.libraryType() == .fourByFour) { [weak self] in
            Settings.setLibraryType(.fourByFour)
            self?.gridTypeChanged()
            Analytics.track(.podcastsListModalOptionTapped, properties: ["option": "layout"])
            Analytics.track(.podcastsListLayoutChanged, properties: ["layout": LibraryType.fourByFour])
        }
        let listGridAction = OptionAction(label: L10n.podcastsList, icon: "podcastlist_listview", selected: Settings.libraryType() == .list) { [weak self] in
            Settings.setLibraryType(.list)
            self?.gridTypeChanged()
            Analytics.track(.podcastsListModalOptionTapped, properties: ["option": "layout"])
            Analytics.track(.podcastsListLayoutChanged, properties: ["layout": LibraryType.list])
        }
        optionsPicker.addSegmentedAction(name: L10n.podcastsLayout, icon: "podcastlist_largegrid", actions: [largeGridAction, smallGridAction, listGridAction])

        let badgeType = Settings.podcastBadgeType()
        let badgesAction = OptionAction(label: L10n.podcastsBadges, secondaryLabel: badgeType.description, icon: "badges") { [weak self] in
            self?.showBadgeOptions()
            Analytics.track(.podcastsListModalOptionTapped, properties: ["option": "badges"])
        }
        optionsPicker.addAction(action: badgesAction)

        let shareAction = OptionAction(label: L10n.podcastsShare, icon: "podcast-share") {
            let shareController = SharePodcastsViewController()
            shareController.delegate = self
            let navController = SJUIUtils.navController(for: shareController)
            self.present(navController, animated: true, completion: nil)
            Analytics.track(.podcastsListModalOptionTapped, properties: ["option": "share"])
        }
        optionsPicker.addAction(action: shareAction)

        optionsPicker.show(statusBarStyle: preferredStatusBarStyle)

        Analytics.track(.podcastsListOptionsButtonTapped)
    }

    // MARK: - ShareListDelegate

    func shareUrlAvailable(_ shareUrl: String, listName: String) {
        SharingHelper.shared.shareLinkToPodcastList(name: listName, url: shareUrl, fromController: self, barButtonItem: customRightBtn, completionHandler: nil)
    }

    @objc private func handleLongPress(_ gesture: UILongPressGestureRecognizer) {
        gridHelper.handleLongPress(gesture, from: podcastsCollectionView, isList: Settings.libraryType() == .list, containerView: view)
    }

    func itemCount() -> Int {
        gridItems.count
    }

    func podcastAt(indexPath: IndexPath) -> Podcast? {
        gridItems[safe: indexPath.row]?.podcast
    }

    func folderAt(indexPath: IndexPath) -> Folder? {
        gridItems[safe: indexPath.row]?.folder
    }

    func itemAt(indexPath: IndexPath) -> HomeGridListItem? {
        gridItems[safe: indexPath.row]
    }

    func gridTypeChanged() {
        podcastsCollectionView.reloadData()
        adjustSettingsForGridType()
    }

    private func showBadgeOptions() {
        let options = OptionsPicker(title: L10n.podcastsBadges.localizedUppercase)

        let badgeOption = Settings.podcastBadgeType()

        let badgeOffAction = OptionAction(label: BadgeType.off.description, selected: badgeOption == .off) { [weak self] in
            guard let strongSelf = self else { return }

            Settings.setPodcastBadgeType(.off)
            strongSelf.refreshGridItems()
            Analytics.track(.podcastsListBadgesChanged, properties: ["type": BadgeType.off])
        }
        options.addAction(action: badgeOffAction)

        let latestEpisodeAction = OptionAction(label: BadgeType.allUnplayed.description, selected: badgeOption == .allUnplayed) { [weak self] in
            guard let strongSelf = self else { return }

            Settings.setPodcastBadgeType(.allUnplayed)
            strongSelf.refreshGridItems()
            Analytics.track(.podcastsListBadgesChanged, properties: ["type": BadgeType.allUnplayed])
        }
        options.addAction(action: latestEpisodeAction)

        let unplayedCountAction = OptionAction(label: BadgeType.latestEpisode.description, selected: badgeOption == .latestEpisode) { [weak self] in
            guard let strongSelf = self else { return }

            Settings.setPodcastBadgeType(.latestEpisode)
            strongSelf.refreshGridItems()
            Analytics.track(.podcastsListBadgesChanged, properties: ["type": BadgeType.latestEpisode])
        }
        options.addAction(action: unplayedCountAction)

        options.show(statusBarStyle: preferredStatusBarStyle)
    }

    override func handleThemeChanged() {
        super.handleThemeChanged()
        podcastsCollectionView.reloadData()
    }

    private func setupBannerAd(promotion: BlazePromotion, shouldAnimate: Bool) {
        guard SubscriptionHelper.shouldDisplayBannerAd else {
            return
        }
        bannerAdModel = BannerAdModel(promotion: promotion) {
            UIApplication.shared.openSafariVCIfPossible(promotion.urlApple)
        }
        isAnimatingBannerAd = shouldAnimate

        if shouldAnimate {
            UIView.animate(withDuration: 0.25, delay: 0, options: [.curveEaseOut]) {
                self.isAnimatingBannerAd = false
            } completion: { _ in
                self.podcastsCollectionView.performBatchUpdates({
                    self.podcastsCollectionView.collectionViewLayout.invalidateLayout()
                })
            }
        } else {
            podcastsCollectionView.performBatchUpdates({
                podcastsCollectionView.collectionViewLayout.invalidateLayout()
            })
        }
    }
}

// MARK: - Refresh Control

extension PodcastListViewController {
    private func setupRefreshControl() {
        let refreshControl = UIRefreshControl()
        refreshControl.tintColor = .clear // Hide default spinner
        refreshControl.addTarget(self, action: #selector(refreshData(_:)), for: .valueChanged)
        
        // Add custom animation views
        setupCustomRefreshAnimation(in: refreshControl)
        
        podcastsCollectionView.refreshControl = refreshControl
        
        // Add notification observers to end refresh when complete
        addCustomObserver(ServerNotifications.podcastsRefreshed, selector: #selector(endRefreshControl))
        addCustomObserver(ServerNotifications.podcastRefreshFailed, selector: #selector(endRefreshControl))
        addCustomObserver(ServerNotifications.syncCompleted, selector: #selector(endRefreshControl))
        addCustomObserver(ServerNotifications.syncFailed, selector: #selector(endRefreshControl))
    }
    
    private func setupCustomRefreshAnimation(in refreshControl: UIRefreshControl) {
        let refreshInnerImage = UIImageView()
        let refreshOuterImage = UIImageView()
        let refreshLabel = UILabel()
        
        // Setup label
        refreshLabel.text = L10n.refreshControlPullToRefresh
        refreshLabel.textAlignment = .center
        refreshLabel.font = UIFont.systemFont(ofSize: 12, weight: .semibold)
        refreshLabel.textColor = UIColor(hex: "#B8C3C9")
        refreshLabel.tag = 100 // For finding later
        
        // Setup images
        refreshInnerImage.image = UIImage(named: "refresh_inner")?.withRenderingMode(.alwaysTemplate)
        refreshInnerImage.tintColor = UIColor(hex: "#B8C3C9")
        refreshInnerImage.tag = 101
        
        refreshOuterImage.image = UIImage(named: "refresh_outer")?.withRenderingMode(.alwaysTemplate)
        refreshOuterImage.tintColor = UIColor(hex: "#B8C3C9")
        refreshOuterImage.tag = 102
        
        // Add to refresh control
        refreshControl.addSubview(refreshLabel)
        refreshControl.addSubview(refreshInnerImage)
        refreshControl.addSubview(refreshOuterImage)
        
        // Setup constraints
        refreshLabel.translatesAutoresizingMaskIntoConstraints = false
        refreshInnerImage.translatesAutoresizingMaskIntoConstraints = false
        refreshOuterImage.translatesAutoresizingMaskIntoConstraints = false
        
        NSLayoutConstraint.activate([
            refreshLabel.centerXAnchor.constraint(equalTo: refreshControl.centerXAnchor),
            refreshLabel.topAnchor.constraint(equalTo: refreshControl.topAnchor, constant: 30),
            
            refreshInnerImage.centerXAnchor.constraint(equalTo: refreshControl.centerXAnchor),
            refreshInnerImage.topAnchor.constraint(equalTo: refreshControl.topAnchor, constant: 5),
            
            refreshOuterImage.centerXAnchor.constraint(equalTo: refreshControl.centerXAnchor),
            refreshOuterImage.topAnchor.constraint(equalTo: refreshControl.topAnchor, constant: 5)
        ])
    }
    
    @objc private func refreshData(_ sender: UIRefreshControl) {
        // Update label and start animation
        if let label = sender.viewWithTag(100) as? UILabel {
            label.text = L10n.refreshControlFetchingEpisodes
        }
        startCustomAnimation(in: sender)
        
        RefreshManager.shared.refreshPodcasts()
    }
    
    private func startCustomAnimation(in refreshControl: UIRefreshControl) {
        guard let innerImage = refreshControl.viewWithTag(101) as? UIImageView,
              let outerImage = refreshControl.viewWithTag(102) as? UIImageView else { return }
        
        let innerRotation = CABasicAnimation(keyPath: "transform.rotation.z")
        innerRotation.fromValue = 0
        innerRotation.toValue = Double.pi * 2
        innerRotation.duration = 1.0
        innerRotation.repeatCount = Float.infinity
        innerImage.layer.add(innerRotation, forKey: "innerRotation")
        
        let outerRotation = CABasicAnimation(keyPath: "transform.rotation.z")
        outerRotation.fromValue = 0
        outerRotation.toValue = Double.pi * 2
        outerRotation.duration = 1.5
        outerRotation.repeatCount = Float.infinity
        outerImage.layer.add(outerRotation, forKey: "outerRotation")
    }
    
    private func stopCustomAnimation(in refreshControl: UIRefreshControl) {
        guard let innerImage = refreshControl.viewWithTag(101) as? UIImageView,
              let outerImage = refreshControl.viewWithTag(102) as? UIImageView else { return }
        
        innerImage.layer.removeAnimation(forKey: "innerRotation")
        outerImage.layer.removeAnimation(forKey: "outerRotation")
    }
    
    @objc private func endRefreshControl() {
        DispatchQueue.main.async { [weak self] in
            guard let refreshControl = self?.podcastsCollectionView.refreshControl else { return }
            
            // Update label
            if let label = refreshControl.viewWithTag(100) as? UILabel {
                label.text = L10n.refreshControlRefreshComplete
            }
            
            // Stop animation and end refreshing after a brief delay
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                self?.stopCustomAnimation(in: refreshControl)
                refreshControl.endRefreshing()
                
                // Reset label only after refresh control is fully hidden
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    if let label = refreshControl.viewWithTag(100) as? UILabel {
                        label.text = L10n.refreshControlPullToRefresh
                    }
                }
            }
        }
    }
}


// MARK: - Podcast list

extension PodcastListViewController: AnalyticsSourceProvider {
    var analyticsSource: AnalyticsSource {
        .podcastsList
    }
}
