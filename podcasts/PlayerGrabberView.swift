import UIKit

/// The handle at the top of the full-screen player: above the tabs, or above Now Playing when
/// the large screen player shows the tabs next to it. Tapping it closes the player. It's not a
/// `UIControl`, so the player's dismiss pan can still start on it.
final class PlayerGrabberView: UIView {
    /// The size of the visible handle, the system grabber's size.
    static let handleSize = CGSize(width: 36, height: 5)

    var onTap: (() -> Void)?

    private let handle = UIView()

    override init(frame: CGRect) {
        super.init(frame: frame)

        translatesAutoresizingMaskIntoConstraints = false
        handle.translatesAutoresizingMaskIntoConstraints = false
        handle.isUserInteractionEnabled = false
        handle.layer.cornerRadius = Self.handleSize.height / 2
        addSubview(handle)

        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: 88),
            heightAnchor.constraint(equalToConstant: 44),
            handle.centerXAnchor.constraint(equalTo: centerXAnchor),
            handle.centerYAnchor.constraint(equalTo: centerYAnchor),
            handle.widthAnchor.constraint(equalToConstant: Self.handleSize.width),
            handle.heightAnchor.constraint(equalToConstant: Self.handleSize.height)
        ])

        isAccessibilityElement = true
        accessibilityTraits = .button
        addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(handleTap)))

        updateColors()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func updateColors() {
        handle.backgroundColor = ThemeColor.playerContrast03()
    }

    override func accessibilityActivate() -> Bool {
        onTap?()
        return true
    }

    @objc private func handleTap() {
        onTap?()
    }
}
