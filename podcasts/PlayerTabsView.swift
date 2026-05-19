import PocketCastsUtils
import UIKit

protocol PlayerTabDelegate: AnyObject {
    func didSwitchToTab(index: Int)
}

enum PlayerTabs: Int {
    case nowPlaying
    case showNotes
    case chapters
    case bookmarks

    var description: String {
        switch self {
        case .nowPlaying:
            return L10n.nowPlaying
        case .showNotes:
            return L10n.playerShowNotesTitle
        case .chapters:
            return L10n.chapters
        case .bookmarks:
            return L10n.bookmarks
        }
    }
}

class PlayerTabsView: UIScrollView {
    var tabs: [PlayerTabs] = [.nowPlaying] {
        didSet {
            updateTabs()
        }
    }

    var currentTab = 0 {
        didSet {
            animateTabChange(fromIndex: oldValue, toIndex: currentTab)

            guard oldValue != currentTab, let tab = tabs[safe: currentTab] else {
                return
            }

            trackTabChanged(tab: tab)

            switch tab {
            case .nowPlaying:
                break
            case .showNotes:
                AnalyticsHelper.playerShowNotesOpened()
            case .chapters:
                AnalyticsHelper.chaptersOpened()
                trackChaptersShown()
            case .bookmarks:
                break
            }
        }
    }

    weak var tabDelegate: PlayerTabDelegate?

    private lazy var tabsStackView: UIStackView = {
        let stackView = UIStackView()
        stackView.axis = .horizontal
        stackView.distribution = .fillProportionally
        stackView.alignment = .fill

        stackView.spacing = TabConstants.spacing

        return stackView
    }()

    func setup() {
        showsVerticalScrollIndicator = false
        showsHorizontalScrollIndicator = false
        clipsToBounds = true

        // Keep the tabs left-to-right in every language so their order stays in
        // sync with the paged player content, which is also forced LTR. See #1952.
        semanticContentAttribute = .forceLeftToRight
        tabsStackView.semanticContentAttribute = .forceLeftToRight

        updateTabs()

        addSubview(tabsStackView)
        tabsStackView.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            tabsStackView.leadingAnchor.constraint(equalTo: contentLayoutGuide.leadingAnchor),
            tabsStackView.trailingAnchor.constraint(equalTo: contentLayoutGuide.trailingAnchor),
            tabsStackView.bottomAnchor.constraint(equalTo: contentLayoutGuide.bottomAnchor),
            tabsStackView.topAnchor.constraint(equalTo: contentLayoutGuide.topAnchor),
            tabsStackView.heightAnchor.constraint(equalTo: frameLayoutGuide.heightAnchor)
        ])
    }

    func themeDidChange() {
        updateTabs()
    }

    var lastLayedOutWidth: CGFloat = 0
    override func layoutSubviews() {
        super.layoutSubviews()

        let currentWidth = bounds.width
        if lastLayedOutWidth == currentWidth { return }

        lastLayedOutWidth = currentWidth
        updateTabs()
    }

    private func updateTabs() {
        tabsStackView.removeAllSubviews()

        for (index, tab) in tabs.enumerated() {
            let button = PlayerTabButton(title: tab.description)
            button.isSelected = index == currentTab
            button.tag = index
            button.isPointerInteractionEnabled = true
            button.addTarget(self, action: #selector(buttonTapped(_:)), for: .touchUpInside)
            tabsStackView.addArrangedSubview(button)
        }

        // Add an empty view to make sure the sizes are calculated correctly when there is a longer first item
        let empty = UIView()
        empty.isUserInteractionEnabled = false
        tabsStackView.addArrangedSubview(UIView())

        layoutIfNeeded()
    }

    @objc private func buttonTapped(_ sender: UIButton) {
        currentTab = sender.tag
        tabDelegate?.didSwitchToTab(index: currentTab)
    }

    private func animateTabChange(fromIndex: Int, toIndex: Int) {
        let animationDuration = Constants.Animation.playerTabSwitch

        // text color animation
        if let fromTab = tabsStackView.arrangedSubviews[safe: fromIndex] as? UIButton {
            UIView.transition(with: fromTab, duration: animationDuration, options: .transitionCrossDissolve, animations: {
                fromTab.isSelected = false
            })
        }

        if let toTab = tabsStackView.arrangedSubviews[safe: toIndex] as? UIButton {
            UIView.transition(with: toTab, duration: animationDuration, options: .transitionCrossDissolve, animations: {
                toTab.isSelected = true

                self.scrollRectToVisible(toTab.frame, animated: false)
            })
        }
    }
}


private enum TabConstants {
    static let titleFont = UIFont.systemFont(ofSize: 15, weight: .semibold)
    static let spacing: CGFloat = 0

    static let lineHeight: CGFloat = 2
    static let lineOffset: CGFloat = 8

    static let fadeSize: CGFloat = 50
}

// MARK: - Private: Analytics

private extension PlayerTabsView {
    func trackTabChanged(tab: PlayerTabs) {
        let tabName: String
        switch tab {
        case .nowPlaying:
            tabName = "now_playing"
        case .showNotes:
            tabName = "show_notes"
        case .chapters:
            tabName = "chapters"
        case .bookmarks:
            tabName = "bookmarks"
        }

        Analytics.track(.playerTabSelected, properties: ["tab": tabName])
    }

    /// Emitted when the user switches to the Chapters tab and the episode has
    /// chapters, matching Android's `chapters_shown` (fired from its player
    /// pager with the same guard against empty chapter lists).
    private func trackChaptersShown() {
        guard PlaybackManager.shared.chapterCount() > 0 else { return }

        Analytics.track(.chaptersShown, properties: [
            "episode_uuid": PlaybackManager.shared.currentEpisode?.uuid ?? "unknown",
            "podcast_uuid": PlaybackManager.shared.currentPodcast?.uuid ?? "unknown",
            "origin": PlaybackManager.shared.chaptersOriginAnalyticsValue,
            "source": "fullscreen_player"
        ])
    }
}

/// A button subclass that applies the tab button style
private class PlayerTabButton: UIButton {
    let title: String

    init(title: String) {
        self.title = title
        super.init(frame: .zero)

        configuration = .plain()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func updateConfiguration() {
        let background: UIColor
        let text: UIColor

        var config = UIButton.Configuration.plain()
        config.automaticallyUpdateForSelection = true

        switch state {

        case .selected, [.selected, .highlighted]:
            background = ThemeColor.playerContrast05()
            text = ThemeColor.playerContrast01()

        case .highlighted:
            background = ThemeColor.playerContrast05().withAlphaComponent(0.1)
            text = ThemeColor.playerContrast01()

        default:
            background = .clear
            text = ThemeColor.playerContrast02()
        }

        config.contentInsets = .init(top: 8, leading: 12, bottom: 8, trailing: 12)

        config.attributedTitle = {
            var attributedTitle = AttributedString(title)
            attributedTitle.font = TabConstants.titleFont
            attributedTitle.foregroundColor = text
            return attributedTitle
        }()

        config.background = {
            var config = UIBackgroundConfiguration.clear()
            config.backgroundColor = .clear
            if LiquidGlass.isEnabled {
                config.cornerRadius = bounds.height / 2
            }
            return config
        }()

        // Background isn't animatable, so we'll default to using the layer
        layer.backgroundColor = background.cgColor
        // Render the selected tab as a proper pill under Liquid Glass.
        layer.cornerRadius = LiquidGlass.isEnabled ? bounds.height / 2 : 8

        self.configuration = config
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        if LiquidGlass.isEnabled {
            layer.cornerRadius = bounds.height / 2
        }
    }
}
