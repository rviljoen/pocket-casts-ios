import SwiftUI
import PocketCastsDataModel
import PocketCastsUtils

struct TopSpotStory2024: ShareableStory {
    let topPodcast: TopPodcast

    let backgroundColor = Color(hex: "#EDB0F3")

    @State private var rotation: Double = 360

    var body: some View {
        ZStack {
            GeometryReader { proxy in
                ZStack(alignment: .top) {
                    PodcastImage(uuid: topPodcast.podcast.uuid, size: .page, aspectRatio: nil, contentMode: .fill)
                        .frame(height: 600)
                        .frame(maxWidth: proxy.size.width)
                        .mask {
                            let maskInset = CGSize(width: 60, height: 60)
                            InwardSidesRectangle(inwardAngle: .degrees(5))
                                .frame(width: proxy.size.width + maskInset.width, height: proxy.size.width + maskInset.height)
                                .rotationEffect(.degrees(rotation))
                                .animation(.linear(duration: 30).repeatForever(autoreverses: false), value: rotation)
                                .onAppear {
                                    rotation = 0
                                }
                        }
                        .padding(.top, 40)

                    VStack {
                        Spacer() // Force footer to bottom
                        let timeString = topPodcast.totalPlayedTime.storyTimeDescriptionForSharing
                        let numberPlayed = topPodcast.numberOfPlayedEpisodes
                        let title = topPodcast.podcast.title ?? "unknown"
                        StoryFooter2024(title: "This was your top podcast in 2024",
                                        description: "You listened to \(numberPlayed) episodes for a total of \(timeString) of \"\(title)\"")
                        .padding(.bottom, 20)
                        .zIndex(1) // Keep footer on top
                    }

                    Image("playback-sticker-top-spot")
                        .position(x: 18, y: 90, for: CGSize(width: 213, height: 101), in: proxy.frame(in: .local))
                }
            }
        }
        .ignoresSafeArea()
        .background(backgroundColor)
        .enableProportionalValueScaling()
    }

    // Hide old share button
    func hideShareButton() -> Bool {
        true
    }

    func sharingAssets() -> [Any] {
        [
            StoryShareableProvider.new(AnyView(self)),
            StoryShareableText(L10n.eoyStoryTopPodcastShareText("%1$@"), podcast: topPodcast.podcast)
        ]
    }
}


fileprivate struct InwardSidesRectangle: Shape {
    let inwardAngle: Angle

    func path(in rect: CGRect) -> Path {
        var path = Path()

        // Calculate the inward distance for each side
        let horizontalInset = rect.height * 0.5 * tan(inwardAngle.radians)
        let verticalInset = rect.width * 0.5 * tan(inwardAngle.radians)

        // Start from top-left corner
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))

        // Top edge - goes from corner to middle point and back to other corner
        path.addLine(to: CGPoint(x: rect.midX, y: rect.minY + horizontalInset))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))

        // Right edge
        path.addLine(to: CGPoint(x: rect.maxX - verticalInset, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))

        // Bottom edge
        path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY - horizontalInset))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))

        // Left edge
        path.addLine(to: CGPoint(x: rect.minX + verticalInset, y: rect.midY))

        path.closeSubpath()

        return path
    }
}
