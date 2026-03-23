import UIKit
import PocketCastsUtils

class SettingsDetailViewController: PCViewController, UITableViewDataSource, UITableViewDelegate {

    struct SettingsOption {
        let title: String
        let value: Any
        let isSelected: Bool
    }

    private var tableView: UITableView!
    private let cellId = "SettingsDetailCell"

    var options: [SettingsOption] = []
    var onSelectionChanged: ((Any) -> Void)?

    convenience init(title: String, options: [SettingsOption], onSelectionChanged: @escaping (Any) -> Void) {
        self.init()
        self.title = title
        self.options = options
        self.onSelectionChanged = onSelectionChanged
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        setupTableView()
    }

    private func setupTableView() {
        tableView = UITableView(frame: view.bounds, style: .insetGrouped)
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.dataSource = self
        tableView.delegate = self
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: cellId)

        view.addSubview(tableView)

        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }

    // MARK: - UITableView DataSource & Delegate

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return options.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: cellId, for: indexPath)
        let option = options[indexPath.row]

        cell.textLabel?.text = option.title
        cell.accessoryType = option.isSelected ? .checkmark : .none
        cell.selectionStyle = .default

        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)

        let selectedOption = options[indexPath.row]
        onSelectionChanged?(selectedOption.value)

        navigationController?.popViewController(animated: true)
    }
}
