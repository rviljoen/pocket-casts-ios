import Kingfisher
import PocketCastsDataModel
import SwiftUI
import WatchKit

private let watchScreenBounds = WKInterfaceDevice.current().screenBounds

struct NowPlayingContainerView: View {
    @StateObject private var viewModel = NowPlayingViewModel()
    @State private var selection = 2
    @State private var presentedView: WatchInterfaceType? = nil
    @State private var optionSelected: Bool = false

    var body: some View {
        Group {
            if let episode = viewModel.episode {
                ZStack {
                    navigationHelpers

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
                .frame(minWidth: watchScreenBounds.width,
                       minHeight: watchScreenBounds.height)
                .background(NowPlayingArtworkBackground(episode: episode).ignoresSafeArea())
            } else {
                NowPlayingEmptyView()
            }
        }
        .navigationTitle(L10n.nowPlayingShortTitle.prefixSourceUnicode)
        .restorable(.nowPlaying)
        .onChange(of: optionSelected) {
            withAnimation {
                selection = 2
            }
        }
    }

    // MARK: Navigation

    /// Hidden Navigation items to allow nested screens the ability to push new views outside of the paged TabView
    var navigationHelpers: some View {
        Group {
            NavigationLink(destination: EffectsView(), tag: .effects, selection: $presentedView) {
                EmptyView()
            }.hidden()

            NavigationLink(destination: UpNextView(), tag: .upnext, selection: $presentedView) {
                EmptyView()
            }.hidden()

            NavigationLink(destination: SleepTimerView(), tag: .sleepTimer, selection: $presentedView) {
                EmptyView()
            }.hidden()

            if let episode = viewModel.episode {
                NavigationLink(destination: EpisodeView(viewModel: EpisodeDetailsViewModel(episode: episode, playlist: nil), listTitle: L10n.nowPlaying), tag: .episodeDetails, selection: $presentedView) {
                    EmptyView()
                }.hidden()
            }
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
