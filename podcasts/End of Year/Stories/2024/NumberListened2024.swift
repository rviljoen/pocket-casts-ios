import SwiftUI
import PocketCastsDataModel

struct NumberListened2024: ShareableStory {

    @Environment(\.renderForSharing) var renderForSharing: Bool
    @Environment(\.animated) var animated: Bool

    @ObservedObject private var animationViewModel = PlayPauseAnimationViewModel(duration: EndOfYear.defaultDuration)

    let listenedNumbers: ListenedNumbers
    let podcasts: [Podcast]

    @State var topRowXOffset: Double = 0
    @State var bottomRowXOffset: Double = 0

    private let foregroundColor = Color.black
    private let backgroundColor = Color(hex: "#EFECAD")
    let identifier: String = "number_of_podcasts_and_episodes_listened"

    var body: some View {
        VStack(alignment: .leading) {
            Spacer()
            podcastMarquees()
            Spacer()
            footerView()
        }
        .foregroundStyle(foregroundColor)
        .background(backgroundColor)
    }

    @ViewBuilder func podcastMarquees() -> some View {
        GeometryReader { geometry in
            PodcastCoverContainer(geometry: geometry, alignment: .center) {
                VStack(spacing: -28) {
                    let scale = 0.48
                    podcastMarquee(size: geometry.size, shadow: false, scale: scale * 0.8, indices: [0, 1, 2, 3, 0, 1, 2, 3])
                        .offset(x: topRowXOffset)
                        .modifier(animationViewModel.animate($topRowXOffset, to: -300))
                    podcastMarquee(size: geometry.size, shadow: true, scale: scale, indices: [4, 5, 6, 7, 4, 5, 6, 7])
                        .padding(.leading, geometry.size.width * 0.35)
                        .offset(x: bottomRowXOffset)
                        .modifier(animationViewModel.animate($bottomRowXOffset, to: 300))
                }
                .rotationEffect(Angle(degrees: -15))
            }
            .onAppear {
                if animated {
                    animationViewModel.play()
                }
            }
        }
    }

    @ViewBuilder func podcastMarquee(size: CGSize, shadow: Bool, scale: Double, indices: [Int]) -> some View {
        HStack(spacing: 16) {
            Group {
                ForEach(indices, id: \.self) { index in
                    podcastCover(index, shadow: shadow)
                }
            }
            .frame(width: size.width * scale, height: size.width * scale)
        }
    }

    @ViewBuilder func footerView() -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("You listened to \(listenedNumbers.numberOfPodcasts) different shows and \(listenedNumbers.numberOfEpisodes) episodes in total")
                .font(.system(size: 31, weight: .bold))
            Text("But there was one show you kept coming back to...")
                .font(.system(size: 15, weight: .light))
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 6)
    }

    @ViewBuilder
    func podcastCover(_ index: Int, shadow: Bool) -> some View {
        let podcast = podcasts[safe: index] ?? podcasts[safe: index % 2 == 0 ? 0 : 1] ?? podcasts[0]
        PodcastImage(uuid: podcast.uuid, size: .grid)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .modify {
                if shadow {
                    $0.shadow(color: Color.black.opacity(0.2), radius: 75, x: 0, y: 2.5)
                } else {
                    $0
                }
            }
    }

    func onAppear() {
        Analytics.track(.endOfYearStoryShown, story: identifier)
    }

    func sharingAssets() -> [Any] {
        [
            StoryShareableProvider.new(AnyView(self)),
            StoryShareableText(L10n.eoyStoryListenedToNumbersShareText(listenedNumbers.numberOfPodcasts, listenedNumbers.numberOfEpisodes))
        ]
    }
}
