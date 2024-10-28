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

    private let backgroundColor = Color(hex: "#EFECAD")

    var body: some View {
        VStack {
            GeometryReader { geometry in
                PodcastCoverContainer(geometry: geometry) {
                    VStack(spacing: -20) {
                        HStack(spacing: 16) {
                            Group {
                                let shadow = true
                                podcastCover(0, shadow: shadow)
                                podcastCover(1, shadow: shadow)
                                podcastCover(2, shadow: shadow)
                                podcastCover(3, shadow: shadow)
                                podcastCover(0, shadow: shadow)
                                podcastCover(1, shadow: shadow)
                                podcastCover(2, shadow: shadow)
                                podcastCover(3, shadow: shadow)
                            }
                            .frame(width: geometry.size.width * 0.4, height: geometry.size.width * 0.4)
                        }
                        .offset(x: topRowXOffset)
                        .modifier(animationViewModel.animate($topRowXOffset, to: -300))

                        HStack(spacing: 16) {
                            Group {
                                let shadow = false
                                podcastCover(4, shadow: shadow)
                                podcastCover(5, shadow: shadow)
                                podcastCover(6, shadow: shadow)
                                podcastCover(7, shadow: shadow)
                                podcastCover(4, shadow: shadow)
                                podcastCover(5, shadow: shadow)
                                podcastCover(6, shadow: shadow)
                                podcastCover(7, shadow: shadow)
                            }
                            .frame(width: geometry.size.width * 0.4, height: geometry.size.width * 0.4)
                        }
                        .padding(.leading, geometry.size.width * 0.35)
                        .offset(x: bottomRowXOffset)
                        .modifier(animationViewModel.animate($bottomRowXOffset, to: 300))
                    }
                    .rotationEffect(Angle(degrees: -15))
                    .padding(.top, geometry.size.height * 0.1)
                }
                .onAppear {
                    if animated {
                        animationViewModel.play()
                    }
                }
            }
            footerView()
        }
        .background(backgroundColor)
    }

    @ViewBuilder func footerView() -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("You listened to \(listenedNumbers.numberOfPodcasts) different shows and \(listenedNumbers.numberOfEpisodes) episodes in total")
                .font(.system(size: 31, weight: .bold))
            Text("But there was one show you kept coming back to...")
                .font(.system(size: 15, weight: .light))
        }
        .padding(.horizontal, 24)
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
}
