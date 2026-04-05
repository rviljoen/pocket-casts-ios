import PocketCastsDataModel
import PocketCastsServer
import PocketCastsUtils
import UIKit
import SwiftUI

class ProfileViewController: PCViewController, UITableViewDataSource, UITableViewDelegate {
    fileprivate enum StatValueType { case listened, saved }

    // var refreshControl: PCRefreshControl? - Removed: pull to refresh disabled for profile page

    @IBOutlet var footerView: UIView!
    @IBOutlet var alertIcon: UIImageView!
    @IBOutlet var lastRefreshTime: ThemeableLabel! {
        didSet {
            lastRefreshTime.style = .primaryText02
            lastRefreshTime.font = UIFont.font(with: .subheadline, maxSizeCategory: .accessibilityMedium)
            lastRefreshTime.adjustsFontForContentSizeCategory = true
        }
    }
    @IBOutlet var refreshButtonContainer: UIView!

    private var refreshButtonTitle: String = L10n.refreshNow {
        didSet {
            updateRefreshButton()
        }
    }

    private var isRefreshAnimating: Bool = false {
        didSet {
            updateRefreshButton()
        }
    }

    private var refreshButtonHostingController: UIHostingController<AnyView>?

    private func setupRefreshButton() {
        updateRefreshButton()
        if let hostingController = refreshButtonHostingController {
            hostingController.sizingOptions = .intrinsicContentSize
            addChild(hostingController)
            refreshButtonContainer.addSubview(hostingController.view)
            hostingController.view.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                hostingController.view.topAnchor.constraint(equalTo: refreshButtonContainer.topAnchor),
                hostingController.view.bottomAnchor.constraint(equalTo: refreshButtonContainer.bottomAnchor),
                hostingController.view.centerXAnchor.constraint(equalTo: refreshButtonContainer.centerXAnchor),
                hostingController.view.leadingAnchor.constraint(greaterThanOrEqualTo: refreshButtonContainer.leadingAnchor),
                hostingController.view.trailingAnchor.constraint(lessThanOrEqualTo: refreshButtonContainer.trailingAnchor)
            ])
            hostingController.didMove(toParent: self)
        }
    }

    private func updateRefreshButton() {
        let refreshButton = ProfileRefreshButton(
            title: refreshButtonTitle,
            isAnimating: isRefreshAnimating,
            action: { [weak self] in
                self?.refreshTapped()
            }
        ).setupDefaultEnvironment()

        if let hostingController = refreshButtonHostingController {
            hostingController.rootView = AnyView(refreshButton)
        } else {
            let hostingController = UIHostingController(rootView: AnyView(refreshButton))
            hostingController.view.backgroundColor = .clear
            self.refreshButtonHostingController = hostingController
        }
    }

    @IBOutlet var plusInfoView: PlusLockedInfoView! {
        didSet {
            plusInfoView.isHidden = Settings.plusInfoDismissedOnProfile() || SubscriptionHelper.hasActiveSubscription()
            plusInfoView.delegate = self
        }
    }

    var promoCode: String? {
        didSet {
            showPromotionViewController(promoCode: promoCode)
        }
    }

    var promoRedeemedMessage: String?
    private let settingsCellId = "SettingsCell"
    private let endOfYearPromptCell = "EndOfYearPromptCell"

    enum TableRow { case informationalBanner, kidsProfile, referralsClaim, allStats, downloaded, transcriptionQueue, onDeviceTranscripts, starred, listeningHistory, help, uploadedFiles, endOfYearPrompt, bookmarks, playLogs }

    lazy private var informationalBannerCoordinator: InformationalBannerViewCoordinator = {
        let viewModel = InformationalBannerViewModel(bannerType: .profile)
        return InformationalBannerViewCoordinator(viewModel: viewModel)
    }()

    @IBOutlet var profileTable: UITableView! {
        didSet {
            profileTable.register(UINib(nibName: "TopLevelSettingsCell", bundle: nil), forCellReuseIdentifier: settingsCellId)
            profileTable.register(EndOfYearPromptCell.self, forCellReuseIdentifier: endOfYearPromptCell)
            profileTable.register(KidsProfileBannerTableCell.self, forCellReuseIdentifier: KidsProfileBannerTableCell.identifier)
            profileTable.register(ReferralsClaimBannerTableCell.self, forCellReuseIdentifier: ReferralsClaimBannerTableCell.identifier)
            profileTable.register(InformationalProfileBannerCell.self, forCellReuseIdentifier: InformationalProfileBannerCell.identifier)

            // Set transparent background for liquid glass effect
            if let themeableTable = profileTable as? ThemeableTable {
                themeableTable.themeStyle = .primaryUi02
            }
        }
    }

    // MARK: - Profile Header
    private lazy var headerViewModel: ProfileHeaderViewModel = {
        let viewModel = ProfileHeaderViewModel(navigationController: navigationController)

        // Listen for view size changes and update the header view cell if needed
        viewModel.viewContentSizeChanged = { [weak self] in
            self?.profileTable.reloadData()
        }

        return viewModel
    }()

    private lazy var headerView: UIView = {
        let headerView = ProfileHeaderView(viewModel: headerViewModel)

        let view = headerView.themedUIView
        view.backgroundColor = .clear

        return view
    }()

    // MARK: - View Events

    override func viewDidLoad() {
        // Create a custom button to avoid constraint conflicts
        let settingsButton = UIButton(type: .system)
        settingsButton.setImage(UIImage(named: "profile-settings"), for: .normal)
        settingsButton.addTarget(self, action: #selector(settingsTapped), for: .touchUpInside)
        settingsButton.accessibilityLabel = L10n.accessibilityProfileSettings
        settingsButton.accessibilityIdentifier = "Settings"
        settingsButton.frame = CGRect(x: 0, y: 0, width: 24, height: 24)
        customRightBtn = UIBarButtonItem(customView: settingsButton)

        super.viewDidLoad()
        navigationItem.title = L10n.profile


        profileTable.tableFooterView = footerView

        setupRefreshButton()
        updateDisplayedData()
        updateRefreshFooterColors()
        updateFooterFrame()
        // setupRefreshControl() - Removed: pull to refresh disabled for profile page
        insetAdjuster.setupInsetAdjustmentsForMiniPlayer(scrollView: profileTable)

        // Set transparent background for liquid glass effect
        view.backgroundColor = ThemeColor.primaryUi02()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        updateDisplayedData()

        Analytics.track(.profileShown)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        // refreshControl?.parentViewControllerDidAppear() - Removed: pull to refresh disabled

        addCustomObserver(ServerNotifications.podcastsRefreshed, selector: #selector(refreshComplete))
        addCustomObserver(Constants.Notifications.podcastAdded, selector: #selector(handleDataChangedNotification))
        addCustomObserver(Constants.Notifications.podcastDeleted, selector: #selector(handleDataChangedNotification))
        addCustomObserver(ServerNotifications.podcastRefreshFailed, selector: #selector(refreshComplete))
        addCustomObserver(ServerNotifications.podcastRefreshThrottled, selector: #selector(refreshComplete))
        addCustomObserver(ServerNotifications.syncCompleted, selector: #selector(refreshComplete))
        addCustomObserver(ServerNotifications.syncFailed, selector: #selector(refreshComplete))
        addCustomObserver(ServerNotifications.subscriptionStatusChanged, selector: #selector(handleDataChangedNotification))
        addCustomObserver(.userLoginDidChange, selector: #selector(handleDataChangedNotification))
        addCustomObserver(.serverUserWillBeSignedOut, selector: #selector(handleDataChangedNotification))
        addCustomObserver(.whatsNewDismissed, selector: #selector(whatsNewDismissed))
        addCustomObserver(EndOfYear.eoyEligibilityDidChange, selector: #selector(handleDataChangedNotification))
        addCustomObserver(ServerNotifications.iapProductsUpdated, selector: #selector(refreshReferrals))
        addCustomObserver(.referralURLChanged, selector: #selector(refreshReferrals))

        addCustomObserver(Constants.Notifications.tappedOnSelectedTab, selector: #selector(checkForScrollTap(_:)))
        if promoRedeemedMessage != nil {
            updateDisplayedData()
            showPromotionRedeemedAcknowledgement()
            promoRedeemedMessage = nil
        }

        if EndOfYear.isEligible {
            NotificationCenter.postOnMainThread(notification: Constants.Notifications.profileSeen)
        }

        whatsNewDismissed()

        if FeatureFlag.cancelSubscriptionSurvey.enabled,
           SyncManager.isUserLoggedIn(),
           SubscriptionHelper.hasCancelledSubscription,
           !Settings.subscriptionCancelledSurveyShown {
            let controller = CancelSubscriptionSurveyViewModel.make()
            present(controller, animated: true)
        } else {
            showReferralsHintIfNeeded()
        }
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        removeAllCustomObservers()
        // refreshControl?.parentViewControllerDidDisappear() - Removed: pull to refresh disabled
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        hideReferralsHint(dontShowAgain: false)
    }

    override func handleThemeChanged() {
        super.handleThemeChanged()
        updateRefreshFooterColors()

        // Set transparent background for liquid glass effect
        view.backgroundColor = ThemeColor.primaryUi02()
    }

    private func updateRefreshFooterColors() {
        alertIcon.tintColor = ThemeColor.primaryIcon02()
    }

    // MARK: - Actions

    @objc private func checkForScrollTap(_ notification: Notification) {
        if let index = notification.object as? Int, index == tabBarItem.tag, profileTable.contentOffset.y > 0 {
            profileTable.setContentOffset(CGPoint(x: 0, y: 0), animated: true)
        }
    }

    @objc private func settingsTapped() {
        Analytics.track(.profileSettingsButtonTapped)

        let settingsController = SettingsViewController()
        navigationController?.pushViewController(settingsController, animated: true)
    }

    private func showAccountController() {
        let accountVC = AccountViewController()
        navigationController?.pushViewController(accountVC, animated: true)
    }

    private func refreshTapped() {
        Analytics.track(.profileRefreshButtonTapped)

        isRefreshAnimating = true
        lastRefreshTime.text = L10n.refreshing
        RefreshManager.shared.refreshPodcasts()
    }

    // MARK: - Data Updates

    @objc private func refreshComplete() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }

            // self.refreshControl?.endRefreshing(true) - Removed: pull to refresh disabled
            self.isRefreshAnimating = false
            self.updateLastRefreshDetails()
        }
    }

    @objc private func handleDataChangedNotification() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }

            self.updateDisplayedData()
        }
    }

    private func updateDisplayedData() {
        // Update the new header's data
        headerViewModel.update()

        updateLastRefreshDetails()
        plusInfoView.isHidden = Settings.plusInfoDismissedOnProfile() || SubscriptionHelper.hasActiveSubscription()
        updateFooterFrame()
        refreshTableData()
    }

    private func updateLastRefreshDetails() {
        if ReferralsCoordinator.shared.areReferralsAvailableToSend {
            navigationItem.leftBarButtonItem = referralsButton
        } else {
            navigationItem.leftBarButtonItem = nil
        }

        if !ServerSettings.lastRefreshSucceeded() || !ServerSettings.lastSyncSucceeded() {
            lastRefreshTime.text = !ServerSettings.lastRefreshSucceeded() ? L10n.refreshFailed : L10n.syncFailed
            refreshButtonTitle = L10n.tryAgain
            alertIcon.isHidden = false
        } else if let lastUpdateTime = ServerSettings.lastRefreshEndTime() {
            refreshButtonTitle = L10n.refreshNow
            if abs(lastUpdateTime.timeIntervalSinceNow) > 2.days {
                lastRefreshTime.text = L10n.profileLastAppRefresh(TimeFormatter.shared.appleStyleElapsedString(date: lastUpdateTime))
                alertIcon.isHidden = false
            } else {
                lastRefreshTime.text = L10n.refreshPreviousRun(TimeFormatter.shared.appleStyleElapsedString(date: lastUpdateTime))
                alertIcon.isHidden = true
            }
        } else {
            refreshButtonTitle = L10n.refreshNow
            lastRefreshTime.text = L10n.refreshPreviousRun(L10n.timeFormatNever)
            alertIcon.isHidden = false
        }
    }

    // MARK: - UITableView

    func numberOfSections(in tableView: UITableView) -> Int {
        tableData.count
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        tableData[section].count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let row = tableData[indexPath.section][indexPath.row]

        guard row != .endOfYearPrompt else {
            return tableView.dequeueReusableCell(withIdentifier: endOfYearPromptCell, for: indexPath) as! EndOfYearPromptCell
        }

        if row == .informationalBanner {
            let cell = tableView.dequeueReusableCell(withIdentifier: InformationalProfileBannerCell.identifier, for: indexPath) as! InformationalProfileBannerCell
            cell.onCloseBannerTap = { [weak self] cell in
                if let cell, let indexPath = tableView.indexPath(for: cell) {
                    self?.tableData[indexPath.section].remove(at: indexPath.row)
                    tableView.deleteRows(at: [indexPath], with: .fade)
                }
            }
            return cell
        }

        if row == .kidsProfile {
            let cell = tableView.dequeueReusableCell(withIdentifier: KidsProfileBannerTableCell.identifier, for: indexPath) as! KidsProfileBannerTableCell
            cell.onCloseButtonTap = { [weak self] cell in
                if let cell, let indexPath = tableView.indexPath(for: cell) {
                    self?.tableData[indexPath.section].remove(at: indexPath.row)
                    tableView.deleteRows(at: [indexPath], with: .fade)
                }
            }
            cell.onRequestEarlyAccessTap = { [weak self] _ in
                let viewModel = KidsProfileSheetViewModel()
                let hostViewController = KidsProfileSheetHost(viewModel: viewModel)
                self?.present(hostViewController, animated: true)
            }
            return cell
        }

        if row == .referralsClaim {
            let cell = tableView.dequeueReusableCell(withIdentifier: ReferralsClaimBannerTableCell.identifier, for: indexPath) as! ReferralsClaimBannerTableCell
            return cell
        }

        let cell = tableView.dequeueReusableCell(withIdentifier: settingsCellId, for: indexPath) as! TopLevelSettingsCell

        cell.settingsImage.tintColor = ThemeColor.primaryIcon01()
        cell.settingsLabel.setLetterSpacing(-0.01)
        cell.separatorInset = .zero

        switch row {
        case .informationalBanner:
            return InformationalProfileBannerCell()
        case .kidsProfile:
            return KidsProfileBannerTableCell()
        case .referralsClaim:
            return ReferralsClaimBannerTableCell()
        case .allStats:
            cell.settingsImage.image = UIImage(named: "profile-stats")
            cell.settingsLabel.text = L10n.settingsStats
        case .downloaded:
            cell.settingsImage.image = UIImage(named: "profile-download")
            cell.settingsLabel.text = L10n.downloads
        case .transcriptionQueue:
            cell.settingsImage.image = UIImage(systemName: "captions.bubble")
            cell.settingsLabel.text = L10n.transcriptionQueue
        case .onDeviceTranscripts:
            cell.settingsImage.image = UIImage(systemName: "text.page")
            cell.settingsLabel.text = L10n.onDeviceTranscripts
        case .uploadedFiles:
            cell.settingsImage.image = UIImage(named: "profile_files")
            cell.settingsLabel.text = L10n.files
        case .starred:
            cell.settingsImage.image = UIImage(named: "profile-star")
            cell.settingsLabel.text = L10n.statusStarred
        case .listeningHistory:
            cell.settingsImage.image = UIImage(named: "profile-history")
            cell.settingsLabel.text = L10n.listeningHistory
        case .help:
            cell.settingsImage.image = UIImage(named: "profile-help")
            cell.settingsLabel.text = L10n.settingsHelp
        case .endOfYearPrompt:
            return EndOfYearPromptCell()
        case .bookmarks:
            cell.settingsImage.image = UIImage(named: "bookmarks-profile")
            cell.settingsLabel.text = L10n.bookmarks
        case .playLogs:
            cell.settingsImage.image = UIImage(systemName: "list.bullet.rectangle")
            cell.settingsLabel.text = "Play Log"
        }

        return cell
    }

    func tableView(_ tableView: UITableView, shouldHighlightRowAt indexPath: IndexPath) -> Bool {
        let row = tableData[indexPath.section][indexPath.row]
        return row != .kidsProfile && row != .informationalBanner
    }

    func tableView(_ tableView: UITableView, willDisplay cell: UITableViewCell, forRowAt indexPath: IndexPath) {
        let row = tableData[indexPath.section][indexPath.row]
        if row == .kidsProfile {
            Analytics.track(.kidsProfileBannerSeen)
        }
        if row == .referralsClaim {
            Analytics.track(.referralPassBannerShown)
        }
        if row == .endOfYearPrompt {
            Analytics.track(.endOfYearProfileCardShown, properties: ["current_year": EndOfYear.currentYear.literalValue])
        }
    }

    func tableView(_ tableView: UITableView, estimatedHeightForRowAt indexPath: IndexPath) -> CGFloat {
        let row = tableData[indexPath.section][indexPath.row]
        switch row {
        case .informationalBanner:
            return 160
        default:
            return 70
        }
    }

    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        return UITableView.automaticDimension
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)

        let row = tableData[indexPath.section][indexPath.row]
        navigateToRow(row)
    }

    func navigateToRow(_ row: TableRow) {
        switch row {
        case .kidsProfile, .informationalBanner:
            break
        case .referralsClaim:
            dismiss(animated: true)
            ReferralsCoordinator.shared.startClaimFlow(from: self) { [weak self] in
                self?.profileTable.reloadData()
            }
        case .allStats:
            let statsViewController = StatsViewController()
            navigationController?.pushViewController(statsViewController, animated: true)
        case .downloaded:
            let downloadController = DownloadsViewController()
            navigationController?.pushViewController(downloadController, animated: true)
        case .transcriptionQueue:
            if #available(iOS 26.0, *) {
                let queueController = OnDeviceTranscriptQueueViewController()
                navigationController?.pushViewController(queueController, animated: true)
            }
        case .onDeviceTranscripts:
            if #available(iOS 26.0, *) {
                let transcriptsController = OnDeviceTranscriptLibraryViewController { [weak navigationController] item in
                    let detailController = OnDeviceTranscriptReaderViewController(
                        episodeUUID: item.episodeUUID,
                        title: item.title
                    )
                    navigationController?.pushViewController(detailController, animated: true)
                }
                navigationController?.pushViewController(transcriptsController, animated: true)
            }
        case .uploadedFiles:
            let uploadedController = UploadedViewController()
            navigationController?.pushViewController(uploadedController, animated: true)
        case .starred:
            let starredController = StarredViewController()
            navigationController?.pushViewController(starredController, animated: true)
        case .listeningHistory:
            let historyController = ListeningHistoryViewController()
            navigationController?.pushViewController(historyController, animated: true)
        case .help:
            dismiss(animated: true)
            let navController = SJUIUtils.navController(for: OnlineSupportController())
            present(navController, animated: true, completion: nil)
        case .endOfYearPrompt:
            dismiss(animated: true)
            Analytics.track(.endOfYearProfileCardTapped, properties: ["current_year": EndOfYear.currentYear.literalValue])
            if let endOfYear = (tabBarController as? MainTabBarController)?.endOfYear {
                endOfYear.showStories(in: self, from: .profile)
            } else {
                //Show warning that playback is not available
                let alert = UIAlertController(title: L10n.playbackNotAvailable, message: L10n.pleaseTryAgainLater, preferredStyle: .alert)
                present(alert, animated: true)
            }
        case .bookmarks:
            let bookmarksController = BookmarksProfileListController()
            navigationController?.pushViewController(bookmarksController, animated: true)
        case .playLogs:
            let playLogController = PlayLogViewController()
            navigationController?.pushViewController(playLogController, animated: true)
        }
    }

    func tableView(_ tableView: UITableView, heightForFooterInSection section: Int) -> CGFloat {
        18
    }

    func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
        headerView
    }

    func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat {
        return headerViewModel.contentSize?.height ?? UITableView.automaticDimension
    }

    private var tableData: [[ProfileViewController.TableRow]] = []

    private func refreshTableData() {
        var data: [[ProfileViewController.TableRow]]
        var primaryRows: [ProfileViewController.TableRow] = [.allStats, .downloaded]
        if #available(iOS 26.0, *) {
            primaryRows.append(.transcriptionQueue)
            primaryRows.append(.onDeviceTranscripts)
        }
        primaryRows.append(contentsOf: [.uploadedFiles, .starred, .bookmarks, .listeningHistory, .playLogs, .help])
        data = [primaryRows]

        if EndOfYear.isEndOfYearActive, EndOfYear.isEligible {
            data[0].insert(.endOfYearPrompt, at: 0)
        }

        if FeatureFlag.kidsProfile.enabled && !Settings.shouldHideBanner {
            data[0].insert(.kidsProfile, at: 0)
        }

        if ReferralsCoordinator.shared.isReferralAvailableToClaim {
            data[0].insert(.referralsClaim, at: 0)
        }

        if informationalBannerCoordinator.shouldShowBanner() {
            data[0].insert(.informationalBanner, at: 0)
        }

        tableData = data
        profileTable.reloadData()
    }

    private func updateFooterFrame() {
        footerView.setNeedsLayout()
        footerView.layoutIfNeeded()

        let targetSize = CGSize(width: profileTable.bounds.width, height: UIView.layoutFittingCompressedSize.height)
        let height = footerView.systemLayoutSizeFitting(targetSize, withHorizontalFittingPriority: .required, verticalFittingPriority: .fittingSizeLevel).height

        footerView.frame = CGRect(x: footerView.frame.minX, y: footerView.frame.minY, width: footerView.frame.width, height: height)
        profileTable.tableFooterView = footerView
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)

        if traitCollection.preferredContentSizeCategory != previousTraitCollection?.preferredContentSizeCategory {
            updateFooterFrame()
        }
    }

    // MARK: - What's New Autoplay flow

    @objc private func whatsNewDismissed() {
        showGeneralSettingsIfNeeded()
        showHeadphoneControlsFromWhatsNew()
    }

    private func showGeneralSettingsIfNeeded() {
        if AnnouncementFlow.current == .autoPlay {
            let generalSettingsViewController = GeneralSettingsViewController()
            navigationController?.pushViewController(generalSettingsViewController, animated: true)
        }
    }

    // Pushes to the headphone controls if shown from the what's new
    private func showHeadphoneControlsFromWhatsNew() {
        guard AnnouncementFlow.current == .bookmarksProfile else { return }

        let controller = HeadphoneSettingsViewController()
        navigationController?.pushViewController(controller, animated: true)
        AnnouncementFlow.current = .none
    }

    // MARK: - Referrals
    @objc func refreshReferrals() {
        showReferralsHintIfNeeded()
        updateDisplayedData()
    }

    private lazy var referralsButton: UIBarButtonItem = {
        let button = UIBarButtonItem(image: UIImage(named: ReferralsConstants.giftIcon), style: .plain, target: self, action: #selector(referralsTapped))
        return button
    }()

    @objc private func referralsTapped() {
        guard let referralsOfferInfo = ReferralsCoordinator.shared.referralsOfferInfo else {
            return
        }
        hideReferralsHint(dontShowAgain: true)
        let viewModel = ReferralSendPassModel(offerInfo: referralsOfferInfo,
                                              onShareGuestPassTap: { [weak self] in
            self?.dismiss(animated: true)
        }, onCloseTap: { [weak self] in
            self?.dismiss(animated: true)
        })
        let vc = ReferralSendPassVC(viewModel: viewModel)
        present(vc, animated: true)
    }

    private enum ReferralsConstants {
        static let giftIcon = "gift"
        static let giftSize = CGFloat(24)
        static let giftBadgeSize = CGFloat(16)
        static let defaultTipSize = CGSizeMake(300, 50)
    }

    private var referralsTipVC: UIViewController?

    private func showReferralsHintIfNeeded() {
        guard ReferralsCoordinator.shared.areReferralsAvailableToSend,
              Settings.shouldShowReferralsTip,
              let vc = makeReferralsHint()
        else {
            return
        }

        Analytics.track(.referralTooltipShow)
        present(vc, animated: true, completion: nil)
        self.referralsTipVC = vc
    }

    private func hideReferralsHint(dontShowAgain: Bool) {
        if dontShowAgain {
            Settings.shouldShowReferralsTip = false
        }
        self.referralsTipVC?.dismiss(animated: true)
    }

    private func makeReferralsHint() -> UIViewController? {
        guard let referralOfferInfo = ReferralsCoordinator.shared.referralsOfferInfo else {
            return nil
        }
        let vc = UIHostingController(rootView: AnyView (EmptyView()) )
        let tipView = TipView(title: L10n.referralsTipMessage(referralOfferInfo.localizedOfferDurationNoun.lowercased()),
                              message: nil,
                              sizeChanged: { size in
            vc.preferredContentSize = size
        }, onTap: { [weak self] in
            Analytics.track(.referralTooltipTapped)
            self?.hideReferralsHint(dontShowAgain: true)
        }).setupDefaultEnvironment()
        vc.rootView = AnyView(tipView)
        vc.view.backgroundColor = .clear
        vc.view.clipsToBounds = false
        vc.modalPresentationStyle = .popover
        vc.preferredContentSize = ReferralsConstants.defaultTipSize
        if let popoverPresentationController = vc.popoverPresentationController {
            popoverPresentationController.delegate = self
            popoverPresentationController.permittedArrowDirections = .up
            popoverPresentationController.sourceItem = referralsButton
            popoverPresentationController.backgroundColor = ThemeColor.primaryUi01()
            popoverPresentationController.passthroughViews = [NavigationManager.sharedManager.miniPlayer?.view, navigationController?.navigationBar, tabBarController?.tabBar, view].compactMap({$0})
        }
        return vc
    }

}

extension ProfileViewController: UIPopoverPresentationControllerDelegate {
    func adaptivePresentationStyle(for controller: UIPresentationController) -> UIModalPresentationStyle {
        // Return no adaptive presentation style, use default presentation behaviour
        return .none
    }
}
// MARK: - PlusLockedInfoDelegate

extension ProfileViewController: PlusLockedInfoDelegate {
    func closeInfoTapped() {
        Settings.setPlusInfoDismissedOnProfile(true)
        plusInfoView.isHidden = true
        updateFooterFrame()
    }

    var displayingViewController: UIViewController {
        self
    }

    var displaySource: PlusUpgradeViewSource {
        .profile
    }
}

// MARK: - Refresh Control

// MARK: - Pull to Refresh (Disabled)
// Pull to refresh functionality has been removed from the profile page
// The setupRefreshControl method and scroll delegate methods have been commented out

@available(iOS 26.0, *)
private struct OnDeviceTranscriptQueueScreen: View {
    @ObservedObject private var queueStore = OnDeviceTranscriptQueueStore.shared
    @EnvironmentObject private var theme: Theme

    var body: some View {
        Group {
            if queueStore.queueState.activeItem == nil, queueStore.queueState.queuedItems.isEmpty {
                emptyState
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        if let activeItem = queueStore.queueState.activeItem {
                            section(title: "Transcribing now") {
                                queueCard(for: activeItem, showsProgress: true)
                            }
                        }

                        if !queueStore.queueState.queuedItems.isEmpty {
                            section(title: "Queued episodes") {
                                VStack(spacing: 12) {
                                    ForEach(queueStore.queueState.queuedItems) { item in
                                        queueCard(for: item, showsProgress: false)
                                    }
                                }
                            }
                        }
                    }
                    .padding(16)
                }
            }
        }
        .background(theme.primaryUi02)
        .navigationTitle(L10n.transcriptionQueue)
        .navigationBarTitleDisplayMode(.inline)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Text(L10n.transcriptionQueue)
                .font(.headline)
                .foregroundStyle(theme.primaryText01)

            Text("Downloaded episodes will appear here while they wait to be transcribed.")
                .font(.subheadline)
                .foregroundStyle(theme.primaryText02)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
    }

    private func section<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(theme.primaryText02)
            content()
        }
    }

    private func queueCard(for item: OnDeviceTranscriptQueueStore.QueueItem, showsProgress: Bool) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(item.title)
                .font(.body.weight(.semibold))
                .foregroundStyle(theme.primaryText01)
                .fixedSize(horizontal: false, vertical: true)

            if showsProgress {
                ProgressView(value: item.progress)
                    .tint(theme.primaryText01)

                if !item.progressLabel.isEmpty {
                    Text(item.progressLabel)
                        .font(.footnote)
                        .foregroundStyle(theme.primaryText02)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(theme.primaryUi01)
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }
}

@available(iOS 26.0, *)
private final class OnDeviceTranscriptQueueViewController: PCHostingController<OnDeviceTranscriptQueueScreen> {
    init() {
        super.init(rootView: OnDeviceTranscriptQueueScreen())
        title = L10n.transcriptionQueue
    }

    @MainActor required dynamic init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

@available(iOS 26.0, *)
private struct OnDeviceTranscriptLibraryScreen: View {
    @ObservedObject private var queueStore = OnDeviceTranscriptQueueStore.shared
    @EnvironmentObject private var theme: Theme
    let onSelect: (OnDeviceTranscriptQueueStore.TranscriptLibraryItem) -> Void

    var body: some View {
        Group {
            if queueStore.transcriptLibrary.isEmpty {
                emptyState
            } else {
                List(queueStore.transcriptLibrary) { item in
                    Button {
                        onSelect(item)
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(item.title)
                                .foregroundStyle(theme.primaryText01)

                            if let subtitle = subtitle(for: item), !subtitle.isEmpty {
                                Text(subtitle)
                                    .font(.footnote)
                                    .foregroundStyle(theme.primaryText02)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    .buttonStyle(.plain)
                    .listRowBackground(theme.primaryUi02)
                    .listRowSeparatorTint(theme.primaryUi05)
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .background(theme.primaryUi04)
            }
        }
        .background(theme.primaryUi04)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Text(L10n.onDeviceTranscripts)
                .font(.headline)
                .foregroundStyle(theme.primaryText01)

            Text("Completed transcripts will appear here once they have been processed on device.")
                .font(.subheadline)
                .foregroundStyle(theme.primaryText02)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
        .background(theme.primaryUi04)
    }

    private func subtitle(for item: OnDeviceTranscriptQueueStore.TranscriptLibraryItem) -> String? {
        let dateString = item.publishedDate.map(Self.dateFormatter.string(from:))

        switch (item.podcastTitle, dateString) {
        case let (podcastTitle?, dateString?):
            return "\(podcastTitle) • \(dateString)"
        case let (podcastTitle?, nil):
            return podcastTitle
        case let (nil, dateString?):
            return dateString
        case (nil, nil):
            return nil
        }
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter
    }()
}

@available(iOS 26.0, *)
private struct OnDeviceTranscriptReaderScreen: View {
    let episodeUUID: String
    let title: String

    @ObservedObject private var queueStore = OnDeviceTranscriptQueueStore.shared
    @EnvironmentObject private var theme: Theme

    private var paragraphs: [OnDeviceTranscriptParagraph] {
        queueStore.snapshot(for: episodeUUID)?.paragraphs ?? []
    }

    var body: some View {
        Group {
            if paragraphs.isEmpty {
                VStack(spacing: 12) {
                    Text(title)
                        .font(.headline)
                        .foregroundStyle(theme.primaryText01)

                    Text("This transcript is not available in memory yet.")
                        .font(.subheadline)
                        .foregroundStyle(theme.primaryText02)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(24)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(paragraphs) { paragraph in
                            Text(paragraph.text)
                                .font(size: 17, style: .body, weight: .regular)
                                .foregroundStyle(theme.primaryText01)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.vertical, 12)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 24)
                }
            }
        }
        .background(theme.primaryUi04)
    }
}

@available(iOS 26.0, *)
private final class OnDeviceTranscriptLibraryViewController: PCHostingController<OnDeviceTranscriptLibraryScreen> {
    init(onSelect: @escaping (OnDeviceTranscriptQueueStore.TranscriptLibraryItem) -> Void) {
        super.init(rootView: OnDeviceTranscriptLibraryScreen(onSelect: onSelect))
        title = L10n.onDeviceTranscripts
    }

    @MainActor required dynamic init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

@available(iOS 26.0, *)
private final class OnDeviceTranscriptReaderViewController: PCHostingController<OnDeviceTranscriptReaderScreen> {
    init(episodeUUID: String, title: String) {
        super.init(rootView: OnDeviceTranscriptReaderScreen(episodeUUID: episodeUUID, title: title))
        self.title = title
    }

    @MainActor required dynamic init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
