import Foundation

class PlayLogViewController: ThemedHostingController<PlayLogView> {
    init() {
        let model = PlayLogViewModel()
        let screen = PlayLogView(model: model)
        super.init(rootView: screen)
    }

    @MainActor required dynamic init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
    }
}
