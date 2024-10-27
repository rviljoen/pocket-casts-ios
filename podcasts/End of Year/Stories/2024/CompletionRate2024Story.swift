import SwiftUI
import PocketCastsServer
import PocketCastsDataModel

struct CompletionRate2024Story: ShareableStory {
    let plusOnly = true

    let subscriptionTier: SubscriptionTier

    let startedAndCompleted: EpisodesStartedAndCompleted

    private let backgroundColor = Color(hex: "#E0EFAD")

    var body: some View {
        GeometryReader { totalGeo in
            VStack {
                Spacer()
                GeometryReader { geometry in
                    HStack(alignment: .bottom, spacing: -80) {
                        VStack(spacing: 4) {
                            ForEach(0..<Int(geometry.size.height / 5), id: \.self) { _ in
                                Rectangle()
                                    .frame(height: 1)
                            }
                        }
                        .frame(width: geometry.size.width / 2, height: geometry.size.height)
                        .offset(y: 2) // Offset to ensure bottoms match
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
                .frame(height: 400)//totalGeo.size.width * 0.5)
                footerView()
                    .padding(.top, 24)
                Spacer()
            }
        }
        .background(backgroundColor)
    }

    private var formattedPercentage: String {
        startedAndCompleted.percentage.formatted(.percent.precision(.fractionLength(0)))
    }

    @ViewBuilder func footerView() -> some View {
        VStack(alignment: .leading, spacing: 16) {
            SubscriptionBadge2024(subscriptionTier: subscriptionTier)
            Text("You completion rate this year was \(formattedPercentage)%")
                .font(.system(size: 31, weight: .bold))
            Text("From the \(startedAndCompleted.started) episodes you started you listened fully to a total of \(startedAndCompleted.completed)")
                .font(.system(size: 15, weight: .light))
        }
        .padding(.horizontal, 24)
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
