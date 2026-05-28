import SwiftUI

/// A single-line text view that scrolls horizontally when its content is too
/// wide to fit. Mirrors the pause-then-scroll behaviour of MiniPlayerScrollingTitleView
/// on iOS: the text pauses (trailing-edge fade only), then scrolls with both
/// edges faded, then the leading fade closes as the gap enters so the reset
/// looks seamless. Animation is suppressed when reduce-motion is on.
struct MarqueeText: View {
    let text: String
    let font: Font

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var containerWidth: CGFloat = 0
    @State private var textWidth: CGFloat = 0
    @State private var offset: CGFloat = 0
    @State private var leadingFadeLocation: CGFloat = 0

    private let scrollSpeed: CGFloat = 30
    private let pauseDuration: TimeInterval = 5.0
    private let gap: CGFloat = 28
    private let fadeFraction: CGFloat = 0.08
    private let maskTransitionDuration: TimeInterval = 0.35

    private var needsScrolling: Bool {
        textWidth > containerWidth + 0.5 && !reduceMotion
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                HStack(spacing: 0) {
                    textContent
                    if needsScrolling {
                        Spacer().frame(width: gap)
                        textContent
                    }
                }
                .offset(x: offset)
            }
            .frame(width: proxy.size.width, alignment: .leading)
            .clipped()
            .mask(maskView)
            .onAppear { containerWidth = proxy.size.width }
        }
        .background(
            textContent
                .fixedSize()
                .hidden()
                .background(GeometryReader { geo in
                    Color.clear.preference(key: TextWidthKey.self, value: geo.size.width)
                })
        )
        .onPreferenceChange(TextWidthKey.self) { width in
            guard width > 0 else { return }
            textWidth = width
        }
        .task(id: MarqueeTaskID(needsScrolling: needsScrolling, textWidth: textWidth)) {
            offset = 0
            leadingFadeLocation = 0
            guard needsScrolling else { return }

            let cycleDistance = textWidth + gap
            let scrollDuration = Double(cycleDistance / scrollSpeed)
            let preGapDuration = Double(textWidth / scrollSpeed)
            let gapDuration = Double(gap / scrollSpeed)

            while !Task.isCancelled {
                // Pause with only trailing-edge fade visible
                try? await Task.sleep(nanoseconds: UInt64(pauseDuration * 1_000_000_000))
                guard !Task.isCancelled else { break }

                // Kick off horizontal scroll
                withAnimation(.linear(duration: scrollDuration)) {
                    offset = -cycleDistance
                }
                // Open leading fade as text starts moving
                withAnimation(.easeInOut(duration: maskTransitionDuration)) {
                    leadingFadeLocation = fadeFraction
                }

                // Wait until the gap is about to enter the leading edge
                try? await Task.sleep(nanoseconds: UInt64(preGapDuration * 1_000_000_000))
                guard !Task.isCancelled else { break }

                // Close leading fade before the gap crosses the edge
                let fadeOutDuration = min(maskTransitionDuration, gapDuration)
                withAnimation(.easeInOut(duration: fadeOutDuration)) {
                    leadingFadeLocation = 0
                }

                // Wait for the remainder of the scroll before resetting
                let remaining = scrollDuration - preGapDuration + 0.05
                try? await Task.sleep(nanoseconds: UInt64(remaining * 1_000_000_000))
                guard !Task.isCancelled else { break }

                offset = 0
            }

            offset = 0
            leadingFadeLocation = 0
        }
    }

    private var textContent: some View {
        Text(text)
            .font(font)
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
    }

    @ViewBuilder
    private var maskView: some View {
        if needsScrolling {
            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0),
                    .init(color: .black, location: leadingFadeLocation),
                    .init(color: .black, location: 1 - fadeFraction),
                    .init(color: .clear, location: 1),
                ],
                startPoint: .leading,
                endPoint: .trailing
            )
        } else {
            Color.black
        }
    }
}

private struct TextWidthKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

private struct MarqueeTaskID: Equatable {
    let needsScrolling: Bool
    let textWidth: CGFloat
}
