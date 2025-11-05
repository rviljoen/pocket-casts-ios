private var contentUnavailableKey: UInt8 = 0

extension UIViewController {
    private var pc_contentUnavailableView: UIView? {
        get { objc_getAssociatedObject(self, &contentUnavailableKey) as? UIView }
        set { objc_setAssociatedObject(self, &contentUnavailableKey, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC) }
    }

    func setContentUnavailableConfiguration(_ configuration: UIContentConfiguration?) {
        // Remove previous view if any
        pc_contentUnavailableView?.removeFromSuperview()
        pc_contentUnavailableView = nil

        guard let configuration = configuration else { return }

        let configView = configuration.makeContentView()
        configView.translatesAutoresizingMaskIntoConstraints = false
        configView.backgroundColor = AppTheme.colorForStyle(.primaryUi02)
        view.addSubview(configView)

        NSLayoutConstraint.activate([
            configView.topAnchor.constraint(equalTo: view.topAnchor),
            configView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            configView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            configView.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        ])

        pc_contentUnavailableView = configView
    }
}
