import UIKit

class ChapterFilterKeywordsViewController: PCTableViewController {
    private var keywords: [String] = []

    private enum TableRow {
        case keyword(String)
        case addKeyword
    }

    private var tableRows: [TableRow] = []

    override func viewDidLoad() {
        super.viewDidLoad()

        title = "Chapter Filter Keywords"

        customRightBtn = UIBarButtonItem(
            barButtonSystemItem: .add,
            target: self,
            action: #selector(addKeywordTapped)
        )

        loadKeywords()
    }

    override var customCellTypes: [ReusableTableCell.Type] {
        [DisclosureCell.self]
    }

    private func loadKeywords() {
        keywords = Settings.chapterFilterKeywords()
        rebuildTableRows()
        tableView.reloadData()
    }

    private func rebuildTableRows() {
        tableRows = keywords.map { .keyword($0) }
    }

    @objc private func addKeywordTapped() {
        showAddKeywordAlert()
    }

    private func showAddKeywordAlert() {
        let alert = UIAlertController(
            title: "Add Keyword",
            message: "Enter a keyword to filter from chapter titles.",
            preferredStyle: .alert
        )

        alert.addTextField { textField in
            textField.placeholder = "e.g. Sponsor, Ad"
            textField.autocapitalizationType = .words
            textField.autocorrectionType = .no
        }

        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Add", style: .default) { [weak self, weak alert] _ in
            guard let self,
                  let textField = alert?.textFields?.first,
                  let keyword = textField.text?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !keyword.isEmpty else {
                return
            }

            self.addKeyword(keyword)
        })

        present(alert, animated: true)
    }

    private func addKeyword(_ keyword: String) {
        // Check if keyword already exists
        if keywords.contains(where: { $0.localizedCaseInsensitiveCompare(keyword) == .orderedSame }) {
            let alert = UIAlertController(
                title: "Keyword Already Exists",
                message: "This keyword has already been added.",
                preferredStyle: .alert
            )
            alert.addAction(UIAlertAction(title: "OK", style: .default))
            present(alert, animated: true)
            return
        }

        keywords.append(keyword)
        Settings.setChapterFilterKeywords(keywords)
        rebuildTableRows()

        let indexPath = IndexPath(row: keywords.count - 1, section: 0)
        tableView.insertRows(at: [indexPath], with: .automatic)
    }

    private func deleteKeyword(at index: Int) {
        keywords.remove(at: index)
        Settings.setChapterFilterKeywords(keywords)
        rebuildTableRows()

        let indexPath = IndexPath(row: index, section: 0)
        tableView.deleteRows(at: [indexPath], with: .automatic)
    }

    // MARK: - Table View Data Source

    func numberOfSections(in tableView: UITableView) -> Int {
        1
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        tableRows.count
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let row = tableRows[indexPath.row]

        switch row {
        case .keyword(let keyword):
            let cell = tableView.dequeueReusableCell(DisclosureCell.self, for: indexPath)
            cell.cellLabel.text = keyword
            cell.cellSecondaryLabel.text = nil
            cell.accessoryType = .none
            return cell
        case .addKeyword:
            let cell = tableView.dequeueReusableCell(DisclosureCell.self, for: indexPath)
            cell.cellLabel.text = "Add Keyword"
            cell.cellLabel.textColor = ThemeColor.support05()
            cell.cellSecondaryLabel.text = nil
            return cell
        }
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)

        let row = tableRows[indexPath.row]
        if case .addKeyword = row {
            showAddKeywordAlert()
        }
    }

    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        54
    }

    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        keywords.isEmpty ? nil : "Keywords"
    }

    func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        "Chapters containing these keywords will be automatically deselected when loaded. Swipe left to delete a keyword."
    }

    // MARK: - Table View Editing

    func tableView(_ tableView: UITableView, canEditRowAt indexPath: IndexPath) -> Bool {
        let row = tableRows[indexPath.row]
        if case .keyword = row {
            return true
        }
        return false
    }

    func tableView(_ tableView: UITableView, commit editingStyle: UITableViewCell.EditingStyle, forRowAt indexPath: IndexPath) {
        if editingStyle == .delete {
            let row = tableRows[indexPath.row]
            if case .keyword = row {
                deleteKeyword(at: indexPath.row)
            }
        }
    }
}
