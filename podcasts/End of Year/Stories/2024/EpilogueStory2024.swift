import SwiftUI

struct StoryShareButton: View {
    let shareable: Bool

    var body: some View {
        EmptyView()
    }
}

struct EpilogueStory2024: StoryView {

    let marqueeTextColor = Color(hex: "#EEB1F4")
    let backgroundColor = Color(hex: "#EE661C")

    private let words = [
        "Thanks",
        "Merci",
        "Gracias",
        "Obrigado",
        "Gratki"
    ].map { $0.uppercased() }

    private let separator = Image("playback-24-heart")

    var identifier: String = "ending"

    var body: some View {
        VStack {
            Spacer()
            VStack {
                MarqueeTextView(words: words, separator: separator, direction: .leading)
                MarqueeTextView(words: words, separator: separator, direction: .trailing)
            }
            .frame(height: 350)
            .foregroundStyle(marqueeTextColor)
            Spacer()
            footerView()
        }
        .minimumScaleFactor(0.8)
        .background {
            backgroundColor
                .ignoresSafeArea()
                .allowsHitTesting(false)
        }
        .enableProportionalValueScaling()
    }

    @ViewBuilder func footerView() -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(L10n.eoy2024EpilogueTitle)
                .font(.system(size: 31, weight: .bold))
            Text(L10n.eoy2024EpilogueDescription)
                .font(.system(size: 15, weight: .light))
            Button(L10n.eoyStoryReplay) {
                StoriesController.shared.replay()
                Analytics.track(.endOfYearStoryReplayButtonTapped)
            }
            .buttonStyle(BasicButtonStyle(textColor: .black, backgroundColor: Color.clear, borderColor: .black))
            .allowsHitTesting(true)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 6)
    }

    func onAppear() {
        Analytics.track(.endOfYearStoryShown, story: identifier)
    }
}

struct MarqueeTextView: View {
    let words: [String]
    let separator: Image
    private(set) var separatorPadding: Double = 0 // Must be mutable for initializer
    let direction: HorizontalEdge

    @State private var offset = CGFloat.zero
    @State private var screenWidth: CGFloat = 0
    @State private var contentWidth: CGFloat = 0

    var body: some View {
        GeometryReader { geometry in
            let baseText = HStack(spacing: 20) {
                ForEach(0..<words.count, id: \.self) { idx in
                    Text(words[idx])
                        .font(.custom("Humane-Medium", size: 227))
                        .padding(.horizontal, -10)
                    separator
                        .padding(.horizontal, separatorPadding)
                }
            }

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 0) {
                    ForEach(0..<50000) { _ in
                        baseText
                            .padding(.horizontal, 6)
                    }
                }
                .background(
                    GeometryReader { contentGeometry in
                        Color.clear.onAppear {
                            contentWidth = contentGeometry.size.width / 4 // Divide by number of copies
                            screenWidth = geometry.size.width
                            // Start from left side for trailing direction
                            offset = direction == .trailing ? -contentWidth : 0
                        }
                    }
                )
                .offset(x: offset)
                .onAppear {
                    startScrolling()
                }
            }
            .disabled(true)
            .allowsHitTesting(false)
        }
    }

    private func startScrolling() {
        let speed: CGFloat = 0.1

        Timer.scheduledTimer(withTimeInterval: 0.002, repeats: true) { timer in
            switch direction {
            case .leading:
                offset -= speed
                if -offset >= contentWidth {
                    offset = 0
                }
            case .trailing:
                offset += speed
                if offset >= contentWidth {
                    offset = 0
                }
            }
        }
    }
}
