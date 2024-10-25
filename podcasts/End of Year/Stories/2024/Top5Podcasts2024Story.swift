import SwiftUI
import PocketCastsDataModel

struct Top5Podcasts2024Story: ShareableStory {
    @Environment(\.renderForSharing) var renderForSharing: Bool

    let top5Podcasts: [TopPodcast]

    private let shapeColor = Color.green

    private let backgroundColor = Color(hex: "#E0EFAD")
    private let shapeImages = ["playback-2024-shape-pentagon",
                               "playback-2024-shape-two-ovals",
                               "playback-2024-shape-wavy-circle"]

//    @ObservedObject private var animationViewModel = PlayPauseAnimationViewModel(duration: 0.8, animation: Animation.easeInOut(duration:))

    @State private var visible = false

    var body: some View {
        GeometryReader { proxy in
            VStack(alignment: .leading) {
                //            ScrollView {
                ForEach(top5Podcasts.enumerated().map({ $0 }), id: \.element.podcast.uuid) { (idx, podcast) in
                    HStack {
                        Text("#\(idx+1)")
                            .font(.system(size: 22, weight: .semibold))
                        ZStack {
                            Image(shapeImages[idx % shapeImages.count])
                                .foregroundStyle(shapeColor)
                            PodcastImage(uuid: podcast.podcast.uuid, size: .grid)
                                .frame(width: 72, height: 72)
                                .clipShape(RoundedRectangle(cornerRadius: 4))
                        }
                        .transition(.scale)
                        VStack(alignment: .leading) {
                            if let author = podcast.podcast.author {
                                Text(author)
                                    .font(.system(size: 15))
                            }
                            if let title = podcast.podcast.title {
                                Text(title)
                                    .font(.system(size: 18, weight: .medium))
                            }
                        }
                        .transition(.opacity)
                    }
                }
                Text("And you were big on these shows too!")
                    .font(.system(size: 30, weight: .bold))
                    .transition(.scale)
            }
            .padding()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .id(visible)
        .animation(.default.speed(0.5), value: visible)
        .ignoresSafeArea()
        .enableProportionalValueScaling()
        .background(backgroundColor)
    }

    func onAppear() {
        visible = true
        Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { _ in
            visible.toggle()
        }
    }

    func sharingAssets() -> [Any] {
        [
            StoryShareableProvider.new(AnyView(self)),
            StoryShareableText(L10n.eoyStoryTopPodcastsShareText("%1$@"), podcasts: top5Podcasts.map { $0.podcast })
        ]
    }
}
