import Kingfisher
import PocketCastsDataModel
import SwiftUI

struct NowPlayingContainerView: View {
    @StateObject private var viewModel = NowPlayingViewModel()
    @State private var selection = 2
    @State private var presentedView: WatchInterfaceType? = nil
    @State private var optionSelected: Bool = false

    var body: some View {
        Group {
            if let episode = viewModel.episode {
                ZStack {
                    NowPlayingArtworkBackground(episode: episode)
                        .ignoresSafeArea()

                    TabView(selection: $selection) {
                        NowPlayingOptions(viewModel: viewModel, presentView: $presentedView, optionSelected: $optionSelected)
                            .tag(1)
                            .animation(.none, value: selection)
                        NowPlayingControls(viewModel: viewModel, presentView: $presentedView)
                            .tag(2)
                            .animation(.none, value: selection)
                    }
                    .animation(.easeInOut, value: selection)
                }
            } else {
                NowPlayingEmptyView()
            }
        }
        .navigationTitle(L10n.nowPlayingShortTitle.prefixSourceUnicode)
        .navigationDestination(item: $presentedView) { type in
            destination(for: type)
        }
        .restorable(.nowPlaying)
        .onChange(of: optionSelected) {
            withAnimation {
                selection = 2
            }
        }
    }

    // MARK: Navigation

    @ViewBuilder
    private func destination(for type: WatchInterfaceType) -> some View {
        switch type {
        case .effects:
            EffectsView()
        case .upnext:
            UpNextView()
        case .sleepTimer:
            SleepTimerView()
        case .episodeDetails:
            if let episode = viewModel.episode {
                EpisodeView(viewModel: EpisodeDetailsViewModel(episode: episode, playlist: nil), listTitle: L10n.nowPlaying)
            }
        default:
            EmptyView()
        }
    }
}

private struct NowPlayingArtworkBackground: View {
    let episode: BaseEpisode

    var body: some View {
        ZStack {
            Color.black

            KFImage
                .url(episode.largeImageUrl)
                .targetCache(WatchImageHelper.shared.mainCache)
                .placeholder { _ in
                    Color.black
                }
                .resizable()
                .scaledToFill()
                .scaleEffect(1.2)
                .blur(radius: 20)
                .saturation(1.15)
                .clipped()
                .overlay(Color.black.opacity(0.55))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct NowPlayingContainerView_Previews: PreviewProvider {
    static var previews: some View {
        ForEach(PreviewDevice.previewDevices) {
            NowPlayingContainerView()
                .previewDevice($0)
        }
    }
}
