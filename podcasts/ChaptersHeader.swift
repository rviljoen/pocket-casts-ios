import UIKit

class ChaptersHeader: UIView {
    weak var delegate: ChaptersHeaderDelegate?

    private lazy var container: UIStackView = {
        let container = UIStackView()
        container.layoutMargins = .init(top: 0, left: 12, bottom: 0, right: 12)
        container.isLayoutMarginsRelativeArrangement = true
        container.axis = .horizontal
        container.backgroundColor = .black
        return container
    }()

    private lazy var chaptersLabel: UILabel = {
        let label = UILabel()
        label.textColor = .white
        label.font = .preferredFont(forTextStyle: .footnote)
        return label
    }()

    private lazy var toggleButton: UIButton = {
        let button = UIButton(configuration: .plain())
        button.setTitle(L10n.skipChapters, for: .normal)
        button.setTitleColor(.white, for: .normal)
        button.addTarget(self, action: #selector(toggleChapterSelection), for: .touchUpInside)
        button.setImage(lockIcon, for: .normal)
        button.semanticContentAttribute = UIApplication.shared.userInterfaceLayoutDirection == .rightToLeft ? .forceLeftToRight : .forceRightToLeft
        button.configuration?.imagePadding = 8
        button.configuration?.titleTextAttributesTransformer =
           UIConfigurationTextAttributesTransformer { incoming in
             var outgoing = incoming
             outgoing.font = .preferredFont(forTextStyle: .footnote)
             return outgoing
         }
        button.heightAnchor.constraint(equalToConstant: 44).isActive = true
        return button
    }()

    private var lockIcon: UIImage? {
        PaidFeature.deselectChapters.isUnlocked ? nil : (PaidFeature.deselectChapters.tier == .patron ? UIImage(named: "patron-heart") : UIImage(named: "plusGold"))
    }

    // MARK: - Config
    override init(frame: CGRect) {
        super.init(frame: frame)

        configure()
        updateChapterLabel()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)

        configure()
    }

    func update() {
        updateChapterLabel()
        updateButtonLabel()
    }

    private func configure() {
        container.addArrangedSubview(chaptersLabel)
        container.addArrangedSubview(toggleButton)
        addSubview(container)
        container.anchorToAllSidesOf(view: self)
    }

    @objc private func toggleChapterSelection() {
        delegate?.toggleTapped()
    }

    private func updateChapterLabel() {
        let chapterCount = PlaybackManager.shared.chapterCount(onlyPlayable: true)
        let hiddenChapterCount = PlaybackManager.shared.chapterCount(onlyPlayable: false) - chapterCount
        var label = chapterCount > 1 ? L10n.numberOfChapters(chapterCount) : L10n.singleChapter
        if hiddenChapterCount > 0 {
            label += " • \(L10n.numberOfHiddenChapters(hiddenChapterCount))"
        }
        chaptersLabel.text = label
    }

    func updateButtonLabel() {
        let buttonTitle = toggleButton.title(for: .normal) == L10n.skipChapters ? L10n.done : L10n.skipChapters
        toggleButton.setTitle(buttonTitle, for: .normal)
    }
}

protocol ChaptersHeaderDelegate: AnyObject {
    func toggleTapped()
}
