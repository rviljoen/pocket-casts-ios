import UIKit

class LLMChapterServerSettingsViewController: PCTableViewController, UITextFieldDelegate {
    private enum Section: Int, CaseIterable {
        case serverURL
        case connection
    }

    private enum Row {
        case urlField
        case testConnection
    }

    private let tableStructure: [[Row]] = [
        [.urlField],
        [.testConnection]
    ]

    private let urlCellId = "URLCellId"
    private let buttonCellId = "ButtonCell"

    private weak var serverURLTextField: UITextField?

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "LLM Chapter Server"
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: urlCellId)
        tableView.register(UINib(nibName: "ButtonCell", bundle: nil), forCellReuseIdentifier: buttonCellId)
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
        case .urlField:
            let cell = tableView.dequeueReusableCell(withIdentifier: urlCellId, for: indexPath)
            cell.selectionStyle = .none

            let textField: UITextField
            if let existing = cell.contentView.subviews.first(where: { $0 is UITextField }) as? UITextField {
                textField = existing
            } else {
                let newField = UITextField()
                newField.translatesAutoresizingMaskIntoConstraints = false
                newField.keyboardType = .URL
                newField.autocapitalizationType = .none
                newField.autocorrectionType = .no
                newField.returnKeyType = .done
                newField.delegate = self
                cell.contentView.addSubview(newField)
                NSLayoutConstraint.activate([
                    newField.leadingAnchor.constraint(equalTo: cell.contentView.leadingAnchor, constant: 16),
                    newField.trailingAnchor.constraint(equalTo: cell.contentView.trailingAnchor, constant: -16),
                    newField.topAnchor.constraint(equalTo: cell.contentView.topAnchor),
                    newField.bottomAnchor.constraint(equalTo: cell.contentView.bottomAnchor),
                ])
                textField = newField
            }

            textField.text = Settings.llmChapterServerURL
            textField.placeholder = Settings.defaultLLMChapterServerURL
            serverURLTextField = textField
            return cell

        case .testConnection:
            let cell = tableView.dequeueReusableCell(withIdentifier: buttonCellId, for: indexPath) as! ButtonCell
            cell.buttonTitle.text = "Test Connection"
            cell.buttonTitle.textColor = ThemeColor.support01()
            return cell
        }
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let row = tableStructure[indexPath.section][indexPath.row]
        if row == .testConnection {
            testConnection()
        }
    }

    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        switch Section(rawValue: section) {
        case .serverURL: return "Server URL"
        case .connection, .none: return nil
        }
    }

    func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        switch Section(rawValue: section) {
        case .serverURL: return "The URL of the LLM chapter server running on your local network. Chapters will be extracted from show notes when no embedded chapters are found."
        case .connection, .none: return nil
        }
    }

    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        UITableView.automaticDimension
    }

    // MARK: - UITextFieldDelegate

    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        textField.resignFirstResponder()
        return true
    }

    func textFieldDidEndEditing(_ textField: UITextField) {
        let newValue = textField.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        Settings.llmChapterServerURL = newValue.isEmpty ? Settings.defaultLLMChapterServerURL : newValue
    }

    // MARK: - Test Connection

    private func testConnection() {
        serverURLTextField?.resignFirstResponder()

        let baseURL = Settings.llmChapterServerURL
        guard let url = URL(string: "\(baseURL)/health") else {
            showResult(success: false, message: "Invalid URL: \(baseURL)")
            return
        }

        let alert = UIAlertController(title: "Testing Connection…", message: nil, preferredStyle: .alert)
        present(alert, animated: true)

        Task {
            do {
                var request = URLRequest(url: url, timeoutInterval: 5)
                request.httpMethod = "GET"
                let (_, response) = try await URLSession.shared.data(for: request)
                let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
                await MainActor.run {
                    alert.dismiss(animated: true) {
                        if statusCode == 200 {
                            self.showResult(success: true, message: "Connected to \(baseURL)")
                        } else {
                            self.showResult(success: false, message: "Server returned status \(statusCode)")
                        }
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

    private func showResult(success: Bool, message: String) {
        let alert = UIAlertController(
            title: success ? "Connected" : "Connection Failed",
            message: message,
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }
}
