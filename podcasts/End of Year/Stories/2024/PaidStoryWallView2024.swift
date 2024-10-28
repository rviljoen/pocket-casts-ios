import SwiftUI
import PocketCastsServer
import PocketCastsUtils

struct PaidStoryWallView2024: View {
    @StateObject private var model = PlusPricingInfoModel()

    let subscriptionTier: SubscriptionTier

    private let words = [
        "Wait",
        "Attendez",
        "Espera",
        "Aspettare",
        "Agarda"
    ].map { $0.uppercased() }

    private let separator = Image("playback-24-union")

    private let backgroundColor = Color(hex: "#EFECAD")
    private let foregroundColor = Color(hex: "#F9BC48")

    var body: some View {
        GeometryReader { geometry in
            VStack {
                Spacer()
                ZStack {
                    VStack(spacing: -20) {
                        MarqueeTextView(words: words, separator: separator, direction: .leading)
                        MarqueeTextView(words: words, separator: separator, direction: .trailing)
                    }
                    .minimumScaleFactor(0.9)
                    .foregroundStyle(foregroundColor)
                    .rotationEffect(.degrees(-15))
                    .frame(width: geometry.size.width + 200, height: geometry.size.width - 50)
                    .offset(x: -50)
                }
                .frame(width: geometry.size.width, height: geometry.size.width)

                VStack(alignment: .leading, spacing: 16) {
                    SubscriptionBadge2024(subscriptionTier: .plus)
                    Text(L10n.playback2024PlusUpsellTitle)
                        .font(.system(size: 31, weight: .bold))
                    Text(L10n.playback2024PlusUpsellDescription)
                        .font(.system(size: 15, weight: .light))
                    Button(L10n.playback2024PlusUpsellButtonTitle) {
                        guard let storiesViewController = FeatureFlag.newPlayerTransition.enabled ? SceneHelper.rootViewController() : SceneHelper.rootViewController()?.presentedViewController else {
                            return
                        }

                        NavigationManager.sharedManager.showUpsellView(from: storiesViewController, source: .endOfYear, flow: SyncManager.isUserLoggedIn() ? .endOfYearUpsell : .endOfYear)
                    }
                    .buttonStyle(BasicButtonStyle(textColor: .black, backgroundColor: Color.clear, borderColor: .black))
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 6)
            }
        }
        .background(backgroundColor)
        .allowsHitTesting(false)
        .onAppear {
            Analytics.track(.endOfYearUpsellShown)
        }
    }
}

#Preview {
    PaidStoryWallView()
}
