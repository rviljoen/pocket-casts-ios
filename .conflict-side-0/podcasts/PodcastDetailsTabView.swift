import SwiftUI
import Combine
import PocketCastsUtils

/// Displays a fake set of tabs that allows the user to open the bookmarks view from the podcast list
struct PodcastDetailsTabView: View {
    @EnvironmentObject var theme: Theme
    @State private var selectedTab: Tab = .episodes

    weak var delegate: PodcastActionsDelegate?

    enum Tab {
        case episodes
        case bookmarks
        case youMightLike

        init(from viewMode: PodcastViewController.ViewMode) {
            switch viewMode {
            case .episodes:
                self = .episodes
            case .bookmarks:
                self = .bookmarks
            case .youMightLike:
                self = .youMightLike
            }
        }
    }

    var body: some View {
        Group {
            if FeatureFlag.recommendations.enabled {
                ScrollView(.horizontal, showsIndicators: false) { tabs }
            } else {
                tabs
            }
        }
        .onReceive(delegate?.currentViewModePublisher ?? Just(.episodes).eraseToAnyPublisher()) { viewMode in
            selectedTab = Tab(from: viewMode)
        }
    }

    @ViewBuilder var tabs: some View {
        HStack(spacing: 12) {
            Text(L10n.episodes)
                .buttonize {
                    selectedTab = .episodes
                    delegate?.showEpisodes()
                } customize: { config in
                    config.label
                        .fixedSize()
                        .applyCapsuleStyle(theme: theme, highlighted: selectedTab == .episodes)
                        .applyButtonEffect(isPressed: config.isPressed)
                }

            Text(L10n.bookmarks)
                .buttonize {
                    selectedTab = .bookmarks
                    delegate?.showBookmarks()
                } customize: { config in
                    config.label
                        .fixedSize()
                        .applyCapsuleStyle(theme: theme, highlighted: selectedTab == .bookmarks)
                        .applyButtonEffect(isPressed: config.isPressed)
                }

            Text(L10n.youMightLike)
                .buttonize {
                    selectedTab = .youMightLike
                    delegate?.showYouMightLike()
                } customize: { config in
                    config.label
                        .fixedSize()
                        .applyCapsuleStyle(theme: theme, highlighted: selectedTab == .youMightLike)
                        .applyButtonEffect(isPressed: config.isPressed)
                }

            Spacer()
        }
        .font(.subheadline.weight(.medium))
    }
}

// MARK: - View Extension

private extension View {
    func applyCapsuleStyle(theme: Theme, highlighted: Bool = false) -> some View {
        self
            .contentShape(Capsule())
            .padding(.vertical, 8)
            .padding(.horizontal, 14)
            .foregroundColor(highlighted ? theme.primaryUi01 : theme.primaryText02)
            .background(
                Capsule()
                    .fill(highlighted ? theme.primaryText01 : .clear)
            )
            .overlay(
                Capsule()
                    .stroke(theme.primaryText02.opacity(highlighted ? 0 : 0.25), lineWidth: 1)
            )
            .animation(.linear(duration: 0.1), value: highlighted)
    }
}

// MARK: - Previews

struct PodcastDetailsTabView_Previews: PreviewProvider {
    static var previews: some View {
        PodcastDetailsTabView()
            .setupDefaultEnvironment()
    }
}
