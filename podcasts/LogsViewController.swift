import Foundation

class LogsViewController: ThemedHostingController<LogsView> {

    init() {
        let screen = LogsView()
        super.init(rootView: screen)
    }

    @MainActor required dynamic init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        Analytics.track(.referralClaimScreenShown)

        setupUI()
    }

    private func setupUI() {
        view.backgroundColor = .clear
    }
}
