import PocketCastsUtils
import UIKit

class StorageAndDataUseViewController: PCViewController, UITableViewDelegate, UITableViewDataSource {
    @IBOutlet var settingsTable: UITableView! {
        didSet {
            settingsTable.register(UINib(nibName: "SwitchCell", bundle: nil), forCellReuseIdentifier: switchCellId)
            settingsTable.register(UINib(nibName: "DisclosureCell", bundle: nil), forCellReuseIdentifier: disclosureCellId)
        }
    }

    private let usageSection = 0
    private let dataUseSection = 1
    private let switchCellId = "SwitchCell"
    private let disclosureCellId = "DisclosureCell"

    override func viewDidLoad() {
        super.viewDidLoad()

        title = L10n.settingsStorage
        Analytics.track(.settingsStorageShown)
        showManageDownloadsModal()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        settingsTable.reloadData()
    }

    func numberOfSections(in tableView: UITableView) -> Int {
        2
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        1
    }

    func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
        let headerFrame = CGRect(x: 0, y: 0, width: 0, height: Constants.Values.tableSectionHeaderHeight)

        if section == usageSection {
            return SettingsTableHeader(frame: headerFrame, title: L10n.settingsStorageUsage)
        }

        return SettingsTableHeader(frame: headerFrame, title: L10n.settingsStorageMobileData)
    }

    func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat {
        Constants.Values.tableSectionHeaderHeight
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        if indexPath.section == usageSection {
            let cell = tableView.dequeueReusableCell(withIdentifier: disclosureCellId, for: indexPath) as! DisclosureCell

            cell.cellLabel.text = L10n.downloadedFiles

            let fileSize = EpisodeManager.downloadSizeOfAllEpisodes()
            let sizeAsStr = SizeFormatter.shared.noDecimalFormat(bytes: Int64(fileSize))
            cell.cellSecondaryLabel.text = sizeAsStr == "" ? SizeFormatter.shared.placeholder : sizeAsStr

            return cell
        } else {
            let cell = tableView.dequeueReusableCell(withIdentifier: switchCellId, for: indexPath) as! SwitchCell

            cell.cellLabel.text = L10n.settingsStorageDataWarning
            cell.cellSwitch.isOn = !Settings.mobileDataAllowed()

            cell.cellSwitch.removeTarget(self, action: nil, for: UIControl.Event.valueChanged)
            cell.cellSwitch.addTarget(self, action: #selector(warnWhenNotOnWifiToggled(_:)), for: UIControl.Event.valueChanged)

            return cell
        }
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        if indexPath.section == usageSection {
            if indexPath.row == 0 {
                navigationController?.pushViewController(DownloadedFilesViewController(), animated: true)
            }
        }
    }

    @objc private func warnWhenNotOnWifiToggled(_ sender: UISwitch) {
        Settings.setMobileDataAllowed(!sender.isOn, userInitiated: true)
    }

    private func showManageDownloadsModal() {
        guard FeatureFlag.manageDownloadedEpisodes.enabled,
              ManageDownloadsBannerModel.shouldShowBanner
        else {
            return
        }
        Analytics.track(.freeUpSpaceModalShown, properties: ["source": "storage_and_data_usage"])
        let modalView = ManageDownloadsBannerModel(initialSize: "", onManageTap: { [weak self] in
            Analytics.track(.freeUpSpaceManageDownloadsTapped, properties: ["source": "storage_and_data_usage"])
            self?.dismiss(animated: true, completion: {
                self?.navigationController?.pushViewController(DownloadedFilesViewController(), animated: true)
            })
        }, onNotNowTap: { [weak self] in
            Analytics.track(.freeUpSpaceMaybeLaterTapped)
            self?.dismiss(animated: true)
        })
        let vc = ThemedHostingController(rootView: ManageDownloadsModalView(dataModel: modalView))
        if let sheet = vc.sheetPresentationController {
            sheet.detents = [.medium()]
            sheet.prefersGrabberVisible = true
        }
        present(vc, animated: true)
    }
}
