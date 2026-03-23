import UIKit

class MiniPlayerShadowView: UIView {

    enum Constants {
        static let shadowRadius = CGFloat(8)        // Reduced from 15 for softer glass shadow
        static let shadowOffset = CGSize(width: 0, height: -2)  // Reduced from -4 for subtlety
        static let shadowOpacity = Float(0.15)      // Reduced from 1.0 for glass effect
        static let shadowCornerRadius = CGFloat(16) // Match tab bar roundedness
    }

    var shadowRadius: CGFloat = Constants.shadowRadius {
        didSet {
            updateView()
        }
    }

    var shadowOffset = Constants.shadowOffset {
        didSet {
            updateView()
        }
    }

    var shadowOpacity: Float = Constants.shadowOpacity {
        didSet {
            updateView()
        }
    }

    var shadowCornerRadius: CGFloat = Constants.shadowCornerRadius {
        didSet {
            updateView()
        }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)

        setup()
    }

    required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)

        setup()
    }

    override func layoutSubviews() {
        super.layoutSubviews()

        // Use capsule shape for shadow path
        let capsuleRadius = bounds.height / 2
        layer.shadowPath = UIBezierPath(roundedRect: bounds, cornerRadius: capsuleRadius).cgPath
    }

    private func setup() {
        clipsToBounds = false

        updateView()
    }

    private func updateView() {
        if shadowOpacity == 0 { return }
        backgroundColor = .clear

        // Use capsule radius for the shadow layer
        let capsuleRadius = bounds.height > 0 ? bounds.height / 2 : shadowCornerRadius
        layer.cornerRadius = capsuleRadius

        layer.shadowRadius = shadowRadius
        layer.shadowOffset = shadowOffset
        layer.shadowOpacity = shadowOpacity
        layer.shadowColor = UIColor.black.withAlphaComponent(0.1).cgColor
        layer.shouldRasterize = true
        layer.rasterizationScale = UIScreen.main.scale
    }
}
