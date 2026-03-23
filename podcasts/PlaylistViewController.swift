import DifferenceKit
import PocketCastsDataModel
import PocketCastsServer
import PocketCastsUtils
import UIKit

class PlaylistViewController: PCViewController, TitleButtonDelegate {
    var filter: EpisodeFilter
    var isNewFilter = false


    private lazy var operationQueue: OperationQueue = {
        let queue = OperationQueue()
        queue.maxConcurrentOperationCount = 1

        return queue
    }()

    var episodes = [ListEpisode]()

    @IBOutlet var tableView: UITableView! {
        didSet {
            registerCells()
            registerLongPress()
            tableView.allowsMultipleSelectionDuringEditing = true
        }
    }

    @IBOutlet var filterCollectionView: FilterChipCollectionView!

    @IBOutlet var noEpisodesScrollView: UIScrollView! {
        didSet {
            noEpisodesScrollView.backgroundColor = AppTheme.colorForStyle(.primaryUi04)
        }
    }

    @IBOutlet var noEpisodesView: ThemeableView! {
        didSet {
            noEpisodesView.style = .primaryUi02
        }
    }

    @IBOutlet var noEpisodesTitle: ThemeableLabel! {
        didSet {
            noEpisodesTitle.text = FeatureFlag.playlistsRebranding.enabled ?  L10n.episodeFilterNoEpisodesTitle.sentenceCased : L10n.episodeFilterNoEpisodesTitle
        }
    }

    @IBOutlet var noEpisodesDescription: ThemeableLabel! {
        didSet {
            noEpisodesDescription.text = L10n.episodeFilterNoEpisodesMsg
            noEpisodesDescription.style = .primaryText02
        }
    }

    @IBOutlet var noEpisodesIcon: ThemeableImageView! {
        didSet {
            noEpisodesIcon.imageNameFunc = AppTheme.emptyFilterImageName
        }
    }

    init(filter: EpisodeFilter) {
        self.filter = filter

        super.init(nibName: "PlaylistViewController", bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @IBOutlet var themeDividerTopAnchor: NSLayoutConstraint!
    @IBOutlet var themeDividerTop: UIView!

    private var titleView: TitleViewWithCollapseButton!
    private var isChipHidden = true
    private var shouldShowChipsAfterMulitSelect = false

    var isMultiSelectEnabled = false {
        didSet {
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }

                self.setupNavBar()
                self.tableView.beginUpdates()
                self.tableView.setEditing(self.isMultiSelectEnabled, animated: true)
                self.insetAdjuster.isMultiSelectEnabled = isMultiSelectEnabled
                self.tableView.endUpdates()

                if self.isMultiSelectEnabled {
                    Analytics.track(.filterMultiSelectEntered)
                    self.multiSelectFooter.setSelectedCount(count: self.selectedEpisodes.count)
                    self.multiSelectFooterBottomConstraint.constant = PlaybackManager.shared.currentEpisode() == nil ? 16 : Constants.Values.miniPlayerOffset + 16
                    self.shouldShowChipsAfterMulitSelect = !self.isChipHidden
                    if !self.isChipHidden {
                        self.hideFilterChips()
                    }
                    if let selectedIndexPath = self.longPressMultiSelectIndexPath {
                        self.tableView.selectIndexPath(selectedIndexPath)
                        self.longPressMultiSelectIndexPath = nil
                    }
                } else {
                    Analytics.track(.filterMultiSelectExited)
                    if self.shouldShowChipsAfterMulitSelect {
                        self.showFilterChips()
                    }
                    self.multiSelectFooter.isHidden = true
                    self.selectedEpisodes.removeAll()
                }
            }
        }
    }

    var multiSelectGestureInProgress = false
    var longPressMultiSelectIndexPath: IndexPath?
    var multiSelectActionInProgress = false
    @IBOutlet var multiSelectFooter: MultiSelectFooterView! {
        didSet {
            multiSelectFooter.delegate = self
        }
    }

    @IBOutlet var multiSelectFooterBottomConstraint: NSLayoutConstraint!
    var selectedEpisodes = [ListEpisode]() {
        didSet {
            multiSelectFooter.setSelectedCount(count: selectedEpisodes.count)
            updateSelectAllBtn()
        }
    }

    var cellHeights: [IndexPath: CGFloat] = [:]

    private var loadingIndicator: ThemeLoadingIndicator! {
        didSet {
            view.addSubview(loadingIndicator)
            loadingIndicator.center = view.center
        }
    }

    private var firstTimeLoading = true

    // MARK: - View Methods

    override func viewDidLoad() {
        supportsGoogleCast = true
        super.customRightBtn = UIBarButtonItem(image: UIImage(named: "more"), style: .plain, target: self, action: #selector(moreTapped))
        super.customRightBtn?.accessibilityLabel = L10n.accessibilitySortAndOptions

        super.viewDidLoad()

        tableView.tableFooterView = UIView(frame: CGRect.zero)
        tableView.sectionFooterHeight = 0.0
        tableView.estimatedRowHeight = 80
        tableView.rowHeight = UITableView.automaticDimension

        insetAdjuster.setupInsetAdjustmentsForMiniPlayer(scrollView: tableView)

        setupRefreshControls()

        let tap = UITapGestureRecognizer(target: self, action: #selector(navTitleTapped(shortPress:)))
        navigationController?.navigationBar.addGestureRecognizer(tap)

        titleView = TitleViewWithCollapseButton()
        titleView.delegate = self
        navigationItem.titleView = titleView

        themeDividerTopAnchor.constant = isNewFilter ? 52 : 0
        titleView.arrowButton.setExpanded(isNewFilter, animated: false)

        filterCollectionView.chipActionDelegate = self
        filterCollectionView.filter = filter

        isChipHidden = !isNewFilter
        filterCollectionView.isHidden = isChipHidden
        filterCollectionView.alpha = isChipHidden ? 0 : 1

        loadingIndicator = ThemeLoadingIndicator()

        Analytics.track(.filterShown)
    }

    override func viewWillAppear(_ animated: Bool) {
        updateNavTintColor()
        super.viewWillAppear(animated)

        titleView.titleLabel.text = filter.playlistName
        titleView.isAccessibilityElement = true
        titleView.accessibilityLabel = filter.playlistName
        titleView.accessibilityIdentifier = "expandFilter"
        titleView.accessibilityTraits = [.button]

        navigationController?.setNavigationBarHidden(false, animated: true)

        reloadFilterAndRefresh()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        navigationController?.navigationBar.shadowImage = UIImage()

        addEventObservers()


        updateNavTintColor()

        AnalyticsHelper.filterOpened()
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        removeAllCustomObservers()
        navigationController?.navigationBar.shadowImage = nil
    }

    override func handleAppDidEnterBackground() {
        // we don't need to keep our UI up to date while backgrounded, so remove all the notification observers we have
        removeAllCustomObservers()
    }

    override func handleAppWillBecomeActive() {
        refreshEpisodes(animated: true)
        addEventObservers()
    }

    func setupNavBar() {
        navigationItem.titleView = isMultiSelectEnabled ? nil : titleView
        title = isMultiSelectEnabled ? filter.playlistName : nil
        supportsGoogleCast = isMultiSelectEnabled ? false : true
        super.customRightBtn = isMultiSelectEnabled ? UIBarButtonItem(title: L10n.cancel, style: .plain, target: self, action: #selector(cancelTapped)) : UIBarButtonItem(image: UIImage(named: "more"), style: .plain, target: self, action: #selector(moreTapped))
        super.customRightBtn?.accessibilityLabel = isMultiSelectEnabled ? L10n.accessibilityCancelMultiselect : L10n.accessibilitySortAndOptions

        navigationItem.leftBarButtonItem = isMultiSelectEnabled ? UIBarButtonItem(title: L10n.selectAll, style: .done, target: self, action: #selector(selectAllTapped)) : nil
        navigationItem.backBarButtonItem = isMultiSelectEnabled ? nil : UIBarButtonItem(title: "", style: .plain, target: nil, action: nil)
    }

    // MARK: - Notification Updates

    private func addEventObservers() {
        addCustomObserver(ServerNotifications.podcastsRefreshed, selector: #selector(refreshEpisodesFromNotification))
        addCustomObserver(Constants.Notifications.opmlImportCompleted, selector: #selector(refreshEpisodesFromNotification))
        addCustomObserver(Constants.Notifications.episodeDownloaded, selector: #selector(refreshEpisodesFromNotification))
        addCustomObserver(Constants.Notifications.playbackTrackChanged, selector: #selector(refreshEpisodesFromNotification))
        addCustomObserver(Constants.Notifications.playbackEnded, selector: #selector(refreshEpisodesFromNotification))
        addCustomObserver(Constants.Notifications.playbackFailed, selector: #selector(refreshEpisodesFromNotification))
        addCustomObserver(Constants.Notifications.playlistChanged, selector: #selector(refreshFilterFromNotification))
        addCustomObserver(Constants.Notifications.upNextEpisodeRemoved, selector: #selector(refreshEpisodesFromNotification))
        addCustomObserver(Constants.Notifications.upNextEpisodeAdded, selector: #selector(refreshEpisodesFromNotification))
        addCustomObserver(Constants.Notifications.upNextQueueChanged, selector: #selector(refreshEpisodesFromNotification))
        addCustomObserver(Constants.Notifications.episodePlayStatusChanged, selector: #selector(refreshEpisodesFromNotification))
        addCustomObserver(Constants.Notifications.episodeArchiveStatusChanged, selector: #selector(refreshEpisodesFromNotification))
        addCustomObserver(Constants.Notifications.episodeStarredChanged, selector: #selector(refreshEpisodesFromNotification))
        addCustomObserver(Constants.Notifications.episodeDownloadStatusChanged, selector: #selector(refreshEpisodesFromNotification))
        addCustomObserver(Constants.Notifications.manyEpisodesChanged, selector: #selector(refreshEpisodesFromNotification))
    }

    private func reloadFilterAndRefresh(animated: Bool = false) {
        if firstTimeLoading {
            loadingIndicator.startAnimating()
        }

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            if let reloadedFilter = DataManager.sharedManager.findPlaylist(uuid: filter.uuid) {
                filter = reloadedFilter
                DispatchQueue.main.async {
                    self.filterCollectionView.filter = reloadedFilter
                }
            }

            refreshEpisodes(animated: animated)
        }
    }


    @objc func moreTapped() {
        Analytics.track(.filterOptionsButtonTapped)

        let optionsPicker = OptionsPicker(title: nil)

        let MultiSelectAction = OptionAction(label: L10n.selectEpisodes, icon: "option-multiselect") { [weak self] in
            Analytics.track(.filterOptionsModalOptionTapped, properties: ["option": "select_episodes"])
            self?.isMultiSelectEnabled = true
        }
        optionsPicker.addAction(action: MultiSelectAction)

        let currentSort = PlaylistSort(rawValue: filter.sortType)?.description ?? ""
        let sortAction = OptionAction(label: L10n.sortBy, secondaryLabel: currentSort, icon: "podcastlist_sort") {
            Analytics.track(.filterOptionsModalOptionTapped, properties: ["option": "sort_by"])
            self.showSortByPicker()
        }
        let editAction = OptionAction(label: L10n.filterOptions, icon: "profile-settings") {
            Analytics.track(.filterOptionsModalOptionTapped, properties: ["option": "filter_options"])
            self.filterOptionsTapped()
        }

        let playAllAction = OptionAction(label: L10n.playAll, icon: "filter_play") { [weak self] in
            guard let self = self else { return }

            Analytics.track(.filterOptionsModalOptionTapped, properties: ["option": "play_all"])
            let playableEpisodeCount = min(ServerSettings.autoAddToUpNextLimit(), self.episodes.count)
            OptionsPickerHelper.playAllWarning(episodeCount: playableEpisodeCount, confirmAction: {
                PlaybackManager.shared.play(playlist: self.filter)
            })
        }

        let downloadAllAction = OptionAction(label: L10n.downloadAll, icon: "filter_downloaded") { [weak self] in
            guard let self = self else { return }
            Analytics.track(.filterOptionsModalOptionTapped, properties: ["option": "download_all"])

            let downloadableCount = self.downloadableCount(listEpisodes: self.episodes)
            let downloadLimitExceeded = downloadableCount > Constants.Limits.maxBulkDownloads
            let actualDownloadCount = downloadLimitExceeded ? Constants.Limits.maxBulkDownloads : downloadableCount
            if actualDownloadCount == 0 { return }
            let downloadText = L10n.downloadCountPrompt(actualDownloadCount)
            let downloadAction = OptionAction(label: downloadText, icon: nil) { [weak self] in
                self?.downloadAll()
            }

            let confirmPicker = OptionsPicker(title: nil)
            var warningMessage = downloadLimitExceeded ? L10n.bulkDownloadMax : ""

            if NetworkUtils.shared.isConnectedToUnexpensiveConnection() {
                confirmPicker.addDescriptiveActions(title: L10n.downloadAll, message: warningMessage, icon: "filter_downloaded", actions: [downloadAction])
            } else {
                downloadAction.destructive = true

                let queueAction = OptionAction(label: L10n.queueForLater, icon: nil) {
                    self.queueAll()
                }

                if !Settings.mobileDataAllowed() {
                    warningMessage = L10n.downloadDataWarningWithSettingsLink("pktc://settings/storage-and-data") + "\n" + warningMessage
                }

                confirmPicker.addAttributedDescriptiveActions(title: L10n.notOnWifi, message: warningMessage, icon: "option-alert", actions: [downloadAction, queueAction])
            }
            confirmPicker.show(statusBarStyle: AppTheme.defaultStatusBarStyle())
        }

        optionsPicker.addAction(action: sortAction)
        optionsPicker.addAction(action: playAllAction)
        optionsPicker.addAction(action: downloadAllAction)
        optionsPicker.addAction(action: editAction)

        optionsPicker.show(statusBarStyle: AppTheme.defaultStatusBarStyle())
    }

    func showSortByPicker() {
        let optionsPicker = OptionsPicker(title: L10n.sortBy.localizedUppercase)

        addSortAction(to: optionsPicker, sortOrder: .newestToOldest)
        addSortAction(to: optionsPicker, sortOrder: .oldestToNewest)
        addSortAction(to: optionsPicker, sortOrder: .shortestToLongest)
        addSortAction(to: optionsPicker, sortOrder: .longestToShortest)

        optionsPicker.show(statusBarStyle: AppTheme.defaultStatusBarStyle())
    }

    private func addSortAction(to optionPicker: OptionsPicker, sortOrder: PlaylistSort) {
        let action = OptionAction(label: sortOrder.description, selected: filter.sortType == sortOrder.rawValue) {
            Analytics.track(.filterSortByChanged, properties: ["sort_order": sortOrder])
            self.filter.sortType = sortOrder.rawValue
            self.saveFilter()
        }
        optionPicker.addAction(action: action)
    }

    @objc func filterOptionsTapped() {
        let filterEditController = FilterEditOptionsViewController()
        filterEditController.filterToEdit = filter
        navigationController?.pushViewController(filterEditController, animated: true)
    }

    func saveFilter() {
        filter.syncStatus = SyncStatus.notSynced.rawValue
        DataManager.sharedManager.save(playlist: filter)
        NotificationCenter.postOnMainThread(notification: Constants.Notifications.playlistChanged, object: filter)
    }

    override func handleThemeChanged() {
        tableView.reloadData()
        filterCollectionView.reloadData()
        updateNavTintColor()
        noEpisodesScrollView.backgroundColor = AppTheme.colorForStyle(.primaryUi04)
        noEpisodesIcon.tintColor = ThemeColor.primaryIcon02()
    }

    private func updateNavTintColor() {
        let filterColor = filter.playlistColor()
        let titleColor = ThemeColor.filterText01(filterColor: filterColor)
        let iconColor = ThemeColor.filterIcon01(filterColor: filterColor)
        let backgroundColor = ThemeColor.filterUi01(filterColor: filterColor)
        // Use transparent navigation bar for modern glass effect
        changeNavTint(titleColor: titleColor, iconsColor: iconColor, backgroundColor: .clear)
        titleView.setTintColor(newColor: iconColor)
        themeDividerTop.backgroundColor = ThemeColor.filterUi04(filterColor: filterColor)

    }

    func arrowTapped() {
        toggleFilterChipHideShow()
    }

    @objc func navTitleTapped(shortPress: UITapGestureRecognizer) {
        guard !isMultiSelectEnabled else { return }

        toggleFilterChipHideShow()
    }

    private func toggleFilterChipHideShow() {
        if !isChipHidden {
            hideFilterChips()
        } else {
            showFilterChips()
        }
    }

    func hideFilterChips() {
        isChipHidden = true
        titleView.arrowButton.setExpanded(false)
        themeDividerTopAnchor.constant = 0
        UIView.animate(withDuration: Constants.Animation.defaultAnimationTime, delay: 0, options: .curveEaseInOut, animations: {
            self.filterCollectionView.alpha = 0
            self.view.layoutIfNeeded()
        }, completion: { _ in
            self.filterCollectionView.isHidden = true
            self.titleView.accessibilityHint = L10n.accessibilityShowFilterDetails
        })
    }

    func showFilterChips() {
        isChipHidden = false
        titleView.arrowButton.setExpanded(true)
        filterCollectionView.isHidden = false
        themeDividerTopAnchor.constant = 52
        UIView.animate(withDuration: Constants.Animation.defaultAnimationTime, delay: 0, options: .curveEaseInOut, animations: {
            self.filterCollectionView.alpha = 1
            self.view.layoutIfNeeded()
        }, completion: { _ in
            self.titleView.accessibilityHint = L10n.accessibilityHideFilterDetails
        })
    }

    // MARK: - Refresh

    @objc private func refreshFilterFromNotification() {
        updateNavTintColor()
        reloadFilterAndRefresh(animated: true)
    }

    @objc private func refreshEpisodesFromNotification() {
        refreshEpisodes(animated: true)
    }

    func refreshEpisodes(animated: Bool) {
        let refreshOperation = PlaylistRefreshOperation(playlist: filter) { [weak self] newData in
            guard let strongSelf = self else { return }

            strongSelf.firstTimeLoading = false
            strongSelf.loadingIndicator.stopAnimating()

            strongSelf.tableView.isHidden = (newData.count == 0)
            if animated {
                let oldData = strongSelf.episodes
                let changeSet = StagedChangeset(source: oldData, target: newData)
                strongSelf.tableView.reload(using: changeSet, with: .none, setData: { data in
                    strongSelf.episodes = data
                })
            } else {
                strongSelf.episodes = newData
                strongSelf.tableView.reloadData()
            }
            strongSelf.refreshMultiSelectEpisodes()
        }

        operationQueue.addOperation(refreshOperation)
    }

    // MARK: - Long press helpers

    func archiveAll(startingAt: Episode) {
        DispatchQueue.global().async { [weak self] in
            guard let self = self else { return }

            if self.episodes.count == 0 { return }

            var haveFoundFirst = false
            for listEpisode in self.episodes {
                if !haveFoundFirst, listEpisode.episode.uuid != startingAt.uuid { continue }

                haveFoundFirst = true
                if listEpisode.episode.archived { continue }

                EpisodeManager.archiveEpisode(episode: listEpisode.episode, fireNotification: false)
            }

            self.refreshEpisodes(animated: true)
        }
    }

    func downloadAll() {
        DispatchQueue.global().async { [weak self] in
            guard let self = self else { return }

            if self.episodes.count == 0 { return }

            self.downloadItems(allEpisodes: self.episodes)
        }
    }

    func queueAll() {
        DispatchQueue.global().async { [weak self] in
            guard let self = self else { return }

            if self.episodes.count == 0 { return }
            self.queueItems(allEpisodes: self.episodes)
        }
    }

    func queueItems(allEpisodes: [ListEpisode]) {
        var queuedEpisodes = 0
        for listEpisode in allEpisodes {
            if listEpisode.episode.downloading() || listEpisode.episode.downloaded(pathFinder: DownloadManager.shared) || listEpisode.episode.queued() {
                continue
            }

            DownloadManager.shared.queueForLaterDownload(episodeUuid: listEpisode.episode.uuid, fireNotification: true, autoDownloadStatus: .notSpecified)

            queuedEpisodes += 1
            if queuedEpisodes == Constants.Limits.maxBulkDownloads {
                return
            }
        }
    }

    func downloadItems(allEpisodes: [ListEpisode]) {
        var queuedEpisodes = 0
        for listEpisode in allEpisodes {
            if listEpisode.episode.downloading() || listEpisode.episode.downloaded(pathFinder: DownloadManager.shared) || listEpisode.episode.queued() {
                continue
            }

            DownloadManager.shared.addToQueue(episodeUuid: listEpisode.episode.uuid, fireNotification: true, autoDownloadStatus: .notSpecified)
            queuedEpisodes += 1
            if queuedEpisodes == Constants.Limits.maxBulkDownloads {
                return
            }
        }
    }

    func downloadableCount(listEpisodes: [ListEpisode]) -> Int {
        if listEpisodes.count == 0 { return 0 }
        var count = 0

        for listEpisode in listEpisodes {
            if !listEpisode.episode.downloaded(pathFinder: DownloadManager.shared), !listEpisode.episode.downloading(), !listEpisode.episode.queued() {
                count += 1
            }
        }
        return count
    }
}

// MARK: - Refresh Control

extension PlaylistViewController {
    private func setupRefreshControls() {
        setupTableRefreshControl()
        setupNoEpisodesRefreshControl()
        
        // Add notification observers to end refresh when complete
        addCustomObserver(ServerNotifications.podcastsRefreshed, selector: #selector(endRefreshControl))
        addCustomObserver(ServerNotifications.podcastRefreshFailed, selector: #selector(endRefreshControl))
        addCustomObserver(ServerNotifications.syncCompleted, selector: #selector(endRefreshControl))
        addCustomObserver(ServerNotifications.syncFailed, selector: #selector(endRefreshControl))
    }
    
    private func setupTableRefreshControl() {
        let refreshControl = UIRefreshControl()
        refreshControl.tintColor = .clear // Hide default spinner
        refreshControl.addTarget(self, action: #selector(tableRefreshData(_:)), for: .valueChanged)
        
        // Add custom animation views
        setupCustomRefreshAnimation(in: refreshControl)
        
        tableView.refreshControl = refreshControl
    }
    
    private func setupNoEpisodesRefreshControl() {
        let refreshControl = UIRefreshControl()
        refreshControl.tintColor = .clear // Hide default spinner
        refreshControl.addTarget(self, action: #selector(noEpisodesRefreshData(_:)), for: .valueChanged)
        
        // Add custom animation views
        setupCustomRefreshAnimation(in: refreshControl)
        
        noEpisodesScrollView.refreshControl = refreshControl
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
    
    @objc private func tableRefreshData(_ sender: UIRefreshControl) {
        // Update label and start animation
        if let label = sender.viewWithTag(100) as? UILabel {
            label.text = L10n.refreshControlFetchingEpisodes
        }
        startCustomAnimation(in: sender)
        
        RefreshManager.shared.refreshPodcasts()
    }
    
    @objc private func noEpisodesRefreshData(_ sender: UIRefreshControl) {
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
            // End refresh for table view
            if let tableRefreshControl = self?.tableView.refreshControl {
                self?.endSpecificRefreshControl(tableRefreshControl)
            }
            
            // End refresh for no episodes scroll view
            if let noEpisodesRefreshControl = self?.noEpisodesScrollView.refreshControl {
                self?.endSpecificRefreshControl(noEpisodesRefreshControl)
            }
        }
    }
    
    private func endSpecificRefreshControl(_ refreshControl: UIRefreshControl) {
        // Update label
        if let label = refreshControl.viewWithTag(100) as? UILabel {
            label.text = L10n.refreshControlRefreshComplete
        }
        
        // Stop animation and end refreshing after a brief delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
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

// MARK: - Analytics

extension PlaylistViewController: AnalyticsSourceProvider {
    var analyticsSource: AnalyticsSource {
        .filters
    }
}
