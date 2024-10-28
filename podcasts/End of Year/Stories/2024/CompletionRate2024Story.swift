import SwiftUI
import PocketCastsServer
import PocketCastsDataModel

struct CompletionRate2024Story: ShareableStory {
    @Environment(\.animated) var animated: Bool

    let plusOnly = true

    let subscriptionTier: SubscriptionTier

    let startedAndCompleted: EpisodesStartedAndCompleted

    let identifier: String = "completion_rate"

    private let backgroundColor = Color(hex: "#E0EFAD")

    @ObservedObject private var animationViewModel = PlayPauseAnimationViewModel(duration: 0.3, animation: Animation.linear(duration:))

    @State private var chartOpacity: Double = 0

    var body: some View {
        GeometryReader { geometry in
            VStack {
                Spacer()
                chartView()
                .frame(height: geometry.size.height * 0.5)
                .opacity(chartOpacity)
                .modifier(animationViewModel.animate($chartOpacity, to: 1, after: 0.2))
                footerView()
                    .padding(.top, 24)
                Spacer()
            }
        }
        .onAppear {
            if animated {
                animationViewModel.play()
            }
        }
        .background(backgroundColor)
    }

    private var formattedPercentage: String {
        startedAndCompleted.percentage.formatted(.percent.precision(.fractionLength(0)))
    }

    @ViewBuilder func chartView() -> some View {
        GeometryReader { geometry in
            HStack(alignment: .bottom, spacing: -80) {
                VStack(spacing: 4) {
                    ForEach(0..<Int(geometry.size.height / 5), id: \.self) { _ in
                        Rectangle()
                            .frame(height: 1)
                    }
                }
                .frame(width: geometry.size.width / 2, height: geometry.size.height)
                .offset(y: 3) // Offset to ensure bottoms match
                .foregroundStyle(.black)
                ZStack {
                    Rectangle()
                        .frame(width: geometry.size.width / 2, height: geometry.size.height * startedAndCompleted.percentage)
                        .foregroundStyle(.black)
                    Text(formattedPercentage)
                        .font(.custom("Humane-Medium", size: 96))
                        .foregroundStyle(backgroundColor)
                }
            }
            .padding(.horizontal, 24)
        }
    }

    @ViewBuilder func footerView() -> some View {
        VStack(alignment: .leading, spacing: 16) {
            SubscriptionBadge2024(subscriptionTier: subscriptionTier)
            Text(L10n.eoyYearCompletionRateTitle(formattedPercentage))
                .font(.system(size: 31, weight: .bold))
            Text(L10n.playback2024CompletionRateDescription(startedAndCompleted.started, startedAndCompleted.completed))
                .font(.system(size: 15, weight: .light))
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 24)
    }

    func onAppear() {
        Analytics.track(.endOfYearStoryShown, story: identifier)
    }

    func onPause() {
        animationViewModel.pause()
    }

    func onResume() {
        animationViewModel.play()
    }

    func sharingAssets() -> [Any] {
        [
            StoryShareableProvider.new(AnyView(self)),
            StoryShareableText(L10n.eoyYearCompletionRateShareText)
        ]
    }
}

struct CompletionRateStory2024_Previews: PreviewProvider {
    static var previews: some View {
        CompletionRate2024Story(subscriptionTier: .plus, startedAndCompleted: .init(started: 100, completed: 10))
            .previewDisplayName("10%")

        CompletionRate2024Story(subscriptionTier: .plus, startedAndCompleted: .init(started: 100, completed: 30))
            .previewDisplayName("30%")

        CompletionRate2024Story(subscriptionTier: .plus, startedAndCompleted: .init(started: 100, completed: 70))
            .previewDisplayName("70%")

        CompletionRate2024Story(subscriptionTier: .plus, startedAndCompleted: .init(started: 100, completed: 100))
            .previewDisplayName("100%")
    }
}
