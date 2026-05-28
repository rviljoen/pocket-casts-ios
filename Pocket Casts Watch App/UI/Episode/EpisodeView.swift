import Kingfisher
import PocketCastsDataModel
import SwiftUI

struct EpisodeView: View {
    @Environment(\.presentationMode) var presentationMode
    @StateObject var viewModel: EpisodeDetailsViewModel
    let listTitle: String

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 12) {
                    artwork
                    Spacer()
                    playPauseButton
                    Spacer()
                }
                episodeDetails
                Divider()
                episodeActions
                    .buttonStyle(.plain)
            }
            .padding(.horizontal, 12)
            .padding(.top, 36)
        }
        .nowPlayingBackground(viewModel.episode)
        .navigationTitle(listTitle)
        .actionSheet(item: $viewModel.actionRequiresConfirmation) { action in
            ActionSheet(title: Text(action.confirmationTitle),
                        message: Text(action.confirmationMessage),
                        buttons: [
                            .cancel(),
                            .destructive(Text(action.confirmationButtonTitle), action: {
                                WKInterfaceDevice.current().play(.click)
                                viewModel.handleEpisodeAction(action, wasConfirmed: true, dismiss: dismissView)
                            })
                        ])
        }
    }

    private var artwork: some View {
        CachedImage(url: viewModel.episode.largeImageUrl)
            .frame(width: 64, height: 64)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var episodeDetails: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(viewModel.episode.title ?? "")
                .font(.dynamic(size: 15, weight: .medium))

            Text(viewModel.episode.subTitle())
                .foregroundColor(viewModel.episode.subTitleColor)
                .font(.dynamic(size: 12, weight: .medium))
            Text(viewModel.episode.displayDate + " • "  + viewModel.episode.displayableInfo())
                .foregroundColor(.subheadlineText)
                .font(.dynamic(size: 12, weight: .medium))
        }
    }

    private var playPauseButton: some View {
        Button {
            WKInterfaceDevice.current().play(.click)
            viewModel.playPauseTapped()
        } label: {
            Image(viewModel.isPlaying ? "episodepause" : "episodeplay", bundle: Bundle.watchAssets)
        }
        .accessibilityLabel(viewModel.isPlaying ? L10n.pause : L10n.play)
        .buttonStyle(.plain)
        .watchGlass(in: Circle(), interactive: true, fallback: nil)
    }

    private var episodeActions: some View {
        Group {
            ForEach(viewModel.actions) { action in
                Button(action: {
                    WKInterfaceDevice.current().play(.success)
                    viewModel.handleEpisodeAction(action, dismiss: dismissView)
                }) {
                    Group {
                        switch action {
                        case .pauseDownload:
                            DownloadProgressEpisodeActionView(downloadProgress: $viewModel.downloadProgress)
                        case .playNext, .playLast:
                            UpNextEpisodeActionView(isCurrentlyPlaying: $viewModel.isCurrentlyPlaying, episodeAction: action)
                        default:
                            EpisodeActionView(iconName: action.iconName, title: action.title)
                        }
                    }
                    .episodeActionCapsule()
                }
            }

            if viewModel.supportsPodcastNavigation, let podcast = viewModel.parentPodcast {
                NavigationLink(destination: PodcastEpisodeListView(viewModel: .init(podcast: podcast))) {
                    EpisodeActionView(iconName: "episode_goto", title: L10n.goToPodcast)
                        .episodeActionCapsule()
                }
            }
        }
    }

    private func dismissView() {
        presentationMode.wrappedValue.dismiss()
    }
}

private extension View {
    func episodeActionCapsule() -> some View {
        frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 14)
            .padding(.horizontal, 12)
            .watchGlass(in: Capsule(), interactive: true)
    }
}

struct EpisodeView_Previews: PreviewProvider {
    static let testEpisode: Episode = {
        let episode = Episode()
        episode.title = "An Episode Title That Wraps Onto Multiple Lines"
        episode.episodeDescription = "A sample episode description that is long enough to wrap so the layout can be checked."
        return episode
    }()

    static let testViewModel = EpisodeDetailsViewModel(episode: testEpisode, playlist: nil)
    static var previews: some View {
        ForEach(PreviewDevice.previewDevices, id: \.rawValue) { device in
            EpisodeView(viewModel: testViewModel, listTitle: "Test")
                .previewDevice(device)
        }
    }
}
