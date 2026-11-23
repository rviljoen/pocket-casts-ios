import PocketCastsDataModel
import PocketCastsUtils
import UIKit

class LLMChapterSettingsViewController: PCTableViewController, UITextFieldDelegate, PodcastSelectionDelegate {
    private enum Section: Int, CaseIterable {
        case apiKey
        case model
        case connection
        case transcription
    }

    private enum Row {
        case apiKeyField
        case modelField
        case testConnection
        case excludedPodcasts
    }

    private let tableStructure: [[Row]] = [
        [.apiKeyField],
        [.modelField],
        [.testConnection],
        [.excludedPodcasts]
    ]

    private let textFieldCellId = "TextFieldCellId"
    private let buttonCellId = "ButtonCell"
    private let disclosureCellId = "DisclosureCell"

    private weak var apiKeyTextField: UITextField?
    private weak var modelTextField: UITextField?

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "LLM Chapters"
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: textFieldCellId)
        tableView.register(UINib(nibName: "ButtonCell", bundle: nil), forCellReuseIdentifier: buttonCellId)
        tableView.register(UINib(nibName: "DisclosureCell", bundle: nil), forCellReuseIdentifier: disclosureCellId)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        // The excluded count changes in the podcast chooser.
        tableView.reloadData()
    }

    // MARK: - Table View

    func numberOfSections(in tableView: UITableView) -> Int {
        tableStructure.count
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        tableStructure[section].count
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let row = tableStructure[indexPath.section][indexPath.row]
        switch row {
        case .apiKeyField:
            let cell = tableView.dequeueReusableCell(withIdentifier: textFieldCellId, for: indexPath)
            let textField = textField(in: cell)
            textField.isSecureTextEntry = true
            textField.text = Settings.llmChapterAPIKey
            textField.placeholder = "sk-ant-…"
            textField.rightView = makeRevealButton()
            textField.rightViewMode = .always
            apiKeyTextField = textField
            return cell

        case .modelField:
            let cell = tableView.dequeueReusableCell(withIdentifier: textFieldCellId, for: indexPath)
            let textField = textField(in: cell)
            textField.isSecureTextEntry = false
            textField.rightView = nil
            textField.text = Settings.llmChapterModel
            textField.placeholder = Settings.defaultLLMChapterModel
            modelTextField = textField
            return cell

        case .testConnection:
            let cell = tableView.dequeueReusableCell(withIdentifier: buttonCellId, for: indexPath) as! ButtonCell
            cell.buttonTitle.text = "Test Extraction"
            cell.buttonTitle.textColor = ThemeColor.support01()
            return cell

        case .excludedPodcasts:
            let cell = tableView.dequeueReusableCell(withIdentifier: disclosureCellId, for: indexPath) as! DisclosureCell
            cell.cellLabel.text = "Excluded Podcasts"
            let count = excludedSubscribedPodcastUUIDs().count
            cell.cellSecondaryLabel.text = count == 0 ? "None" : "\(count)"
            return cell
        }
    }

    /// The subscribed podcasts that are excluded from on-device transcription.
    private func excludedSubscribedPodcastUUIDs() -> [String] {
        let excluded = Settings.localTranscriptionExcludedPodcasts
        return DataManager.shared.allPodcasts(includeUnsubscribed: false).map(\.uuid).filter { excluded.contains($0) }
    }

    private func textField(in cell: UITableViewCell) -> UITextField {
        cell.selectionStyle = .none

        if let existing = cell.contentView.subviews.first(where: { $0 is UITextField }) as? UITextField {
            return existing
        }

        let textField = UITextField()
        textField.translatesAutoresizingMaskIntoConstraints = false
        textField.autocapitalizationType = .none
        textField.autocorrectionType = .no
        textField.returnKeyType = .done
        textField.delegate = self
        cell.contentView.addSubview(textField)
        NSLayoutConstraint.activate([
            textField.leadingAnchor.constraint(equalTo: cell.contentView.leadingAnchor, constant: 16),
            textField.trailingAnchor.constraint(equalTo: cell.contentView.trailingAnchor, constant: -16),
            textField.topAnchor.constraint(equalTo: cell.contentView.topAnchor, constant: 12),
            textField.bottomAnchor.constraint(equalTo: cell.contentView.bottomAnchor, constant: -12),
        ])
        return textField
    }

    private func makeRevealButton() -> UIButton {
        let button = UIButton(type: .system)
        button.setImage(UIImage(systemName: "eye"), for: .normal)
        button.accessibilityLabel = "Show API key"
        button.addTarget(self, action: #selector(toggleAPIKeyVisibility(_:)), for: .touchUpInside)
        return button
    }

    @objc private func toggleAPIKeyVisibility(_ sender: UIButton) {
        guard let textField = apiKeyTextField else { return }

        textField.isSecureTextEntry.toggle()
        let isHidden = textField.isSecureTextEntry
        sender.setImage(UIImage(systemName: isHidden ? "eye" : "eye.slash"), for: .normal)
        sender.accessibilityLabel = isHidden ? "Show API key" : "Hide API key"
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let row = tableStructure[indexPath.section][indexPath.row]
        switch row {
        case .testConnection:
            testConnection()
        case .excludedPodcasts:
            showExcludedPodcastsChooser()
        case .apiKeyField, .modelField:
            break
        }
    }

    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        switch Section(rawValue: section) {
        case .apiKey: return "Anthropic API Key"
        case .model: return "Model"
        case .transcription: return "On-Device Transcription"
        case .connection, .none: return nil
        }
    }

    func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        switch Section(rawValue: section) {
        case .apiKey: return "Stored in the Keychain on this device. Chapters will be extracted from show notes when no embedded chapters are found. Clear the field to remove the key."
        case .model: return "The Claude model used for extraction. The model must support structured outputs."
        case .transcription: return "Episodes of excluded podcasts are never transcribed on this device, and transcripts already made of them are ignored, so they get no chapters made from one. Use it for podcasts in a language the transcriber doesn't support, or with very long episodes."
        case .connection, .none: return nil
        }
    }

    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        UITableView.automaticDimension
    }

    // MARK: - Excluded Podcasts

    private func showExcludedPodcastsChooser() {
        let chooser = PodcastChooserViewController()
        chooser.delegate = self
        chooser.allowSelectAll = false
        chooser.selectedUuids = excludedSubscribedPodcastUUIDs()
        navigationController?.pushViewController(chooser, animated: true)
    }

    func bulkSelectionChange(selected: Bool) {
        let all = DataManager.shared.allPodcasts(includeUnsubscribed: false).map(\.uuid)
        LocalTranscripts.setExcluded(selected, podcastUUIDs: all)
    }

    func podcastSelected(podcast: String) {
        LocalTranscripts.setExcluded(true, podcastUUIDs: [podcast])
    }

    func podcastUnselected(podcast: String) {
        LocalTranscripts.setExcluded(false, podcastUUIDs: [podcast])
    }

    func didChangePodcasts(numberSelected: Int) {}

    // MARK: - UITextFieldDelegate

    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        textField.resignFirstResponder()
        return true
    }

    func textFieldDidEndEditing(_ textField: UITextField) {
        let newValue = textField.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if textField === apiKeyTextField {
            Settings.llmChapterAPIKey = newValue.isEmpty ? nil : newValue
        } else if textField === modelTextField {
            Settings.llmChapterModel = newValue.isEmpty ? Settings.defaultLLMChapterModel : newValue
        }
    }

    // MARK: - Test Connection

    private func testConnection() {
        apiKeyTextField?.resignFirstResponder()
        modelTextField?.resignFirstResponder()

        guard Settings.llmChapterAPIKey != nil else {
            showResult(success: false, message: "Enter an API key first.")
            return
        }
        let model = Settings.llmChapterModel

        let alert = UIAlertController(title: "Extracting Sample Chapters…", message: nil, preferredStyle: .alert)
        present(alert, animated: true)

        Task {
            do {
                let chapters = try await LLMChapterService.shared.testExtraction(
                    showNotes: Self.sampleShowNotes,
                    episodeTitle: Self.sampleEpisodeTitle,
                    duration: Self.sampleDuration
                )
                let lines = chapters.map { chapter in
                    "\(TimeFormatter.shared.playTimeFormat(time: chapter.startTime.seconds))  \(chapter.title)"
                }
                let message = lines.isEmpty ? "\(model) found no chapters." : "\(model) found:\n\n" + lines.joined(separator: "\n")
                await MainActor.run {
                    alert.dismiss(animated: true) {
                        self.showResult(success: !chapters.isEmpty, message: message)
                    }
                }
            } catch {
                await MainActor.run {
                    alert.dismiss(animated: true) {
                        self.showResult(success: false, message: error.localizedDescription)
                    }
                }
            }
        }
    }

    // Starts after 00:00 so the result should include a prepended Intro, and has a sponsor
    // link without a timestamp and a chapter past the episode's end that should both be dropped.
    private static let sampleEpisodeTitle = "Episode 42: Sample Episode"
    private static let sampleDuration: TimeInterval = 3600
    private static let sampleShowNotes = """
    <p>This week we talk about sourdough and space.</p>
    <p>Sponsored by <a href="https://example.com/sponsor">Example Co</a>.</p>
    <ul>
    <li>02:15 Welcome and news</li>
    <li>14:40 <a href="https://example.com/sourdough">Sourdough deep dive</a></li>
    <li>38:05 Listener questions</li>
    <li>1:15:00 Bonus outtakes</li>
    </ul>
    """

    private func showResult(success: Bool, message: String) {
        let alert = UIAlertController(
            title: success ? "Extraction Works" : "Extraction Failed",
            message: message,
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }
}
