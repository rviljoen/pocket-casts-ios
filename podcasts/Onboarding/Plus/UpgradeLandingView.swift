import SwiftUI
import PocketCastsServer

struct UpgradeLandingView: View {
    @EnvironmentObject var viewModel: PlusLandingViewModel

    @ObservedObject private var purchaseModel: PlusPurchaseModel

    private let tiers: [UpgradeTier] = [.plus, .patron]

    private var selectedTier: UpgradeTier {
        tiers[currentPage]
    }

    @State private var currentPage: Int = 0

    @State private var displayPrice: PlusPricingInfoModel.DisplayPrice = .yearly

    private var selectedProduct: Constants.IapProducts {
        displayPrice == .yearly ? selectedTier.plan.yearly : selectedTier.plan.monthly
    }

    /// If this device has a small screen
    private var isSmallScreen: Bool {
        UIScreen.main.bounds.height <= 667
    }

    /// If this device has a bottom safe area
    private var hasBottomSafeArea: Bool {
        !UIDevice.current.isiPad() && (SceneHelper.connectedScene()?.windows.first(where: \.isKeyWindow)?.safeAreaInsets.bottom ?? 0) > 0
    }

    init(purchaseModel: PlusPurchaseModel) {
        self.purchaseModel = purchaseModel
    }

    var body: some View {
        ZStack {
            ForEach(tiers) { tier in
                tier.background
                    .opacity(selectedTier.id == tier.id ? 1 : 0)
                    .ignoresSafeArea()
            }

            VStack(spacing: 0) {
                topBar

                ZStack {

                    ScrollViewIfNeeded {
                        VStack(spacing: 0) {

                            PlusLabel(selectedTier.header, for: .title2)
                                .transition(.opacity)
                                .id("plus_title" + selectedTier.header)
                                .minimumScaleFactor(0.5)
                                .lineLimit(2)
                                .padding(.bottom, 16)
                                .padding(.horizontal, 32)

                            UpgradeRoundedSegmentedControl(selected: $displayPrice)
                                .padding(.bottom, 24)

                            FeaturesCarousel(currentIndex: $currentPage.animation(), currentPrice: $displayPrice, tiers: tiers)

                            PageIndicatorView(numberOfItems: tiers.count, currentPage: currentPage)
                            .padding(.top, 27)

                            if isSmallScreen {
                                Spacer()
                            }
                        }
                    }

                    VStack {
                        Spacer()

                        let hasError = Binding<Bool>(
                            get: { self.purchaseModel.state == .failed },
                            set: { _ in }
                        )
                        let isLoading = (purchaseModel.state == .purchasing) || (viewModel.priceAvailability == .loading)
                        Button(action: {
                            purchaseModel.purchase(product: selectedProduct)
                        }, label: {
                            VStack {
                                Text(viewModel.purchaseTitle(for: selectedTier, frequency: $displayPrice.wrappedValue))
                                Text(viewModel.purchaseSubtitle(for: selectedTier, frequency: $displayPrice.wrappedValue))
                                    .font(style: .subheadline)
                            }
                            .transition(.opacity)
                            .id("plus_price" + selectedTier.title)
                        })
                        .buttonStyle(PlusOpaqueButtonStyle(isLoading: isLoading, plan: selectedTier.plan))
                        .padding(.horizontal, 20)
                        .padding(.bottom, hasBottomSafeArea ? 0 : 16)
                        .alert(isPresented: hasError) {
                            Alert(
                                title: Text(L10n.plusPurchaseFailed)
                            )
                        }
                    }
                }
            }
        }
        .background(Color.plusBackgroundColor)
        .onAppear {
            // Ensure prices are loaded
            viewModel.loadPrices { }
        }
    }

    var topBar: some View {
        HStack(spacing: 0) {
            Spacer()
            Button(viewModel.source == .upsell ? L10n.eoyNotNow : L10n.plusSkip) {
                viewModel.dismissTapped()
            }
            .foregroundColor(.white)
            .font(style: .body, weight: .medium)
            .padding()
        }
    }
}

// MARK: - Feature Carousel

private struct FeaturesCarousel: View {
    let currentIndex: Binding<Int>

    let currentPrice: Binding<PlusPricingInfoModel.DisplayPrice>

    let tiers: [UpgradeTier]

    @State var calculatedCardHeight: CGFloat?

    var body: some View {
        // Store the calculated card heights
        var cardHeights: [CGFloat] = []

        HorizontalCarousel(currentIndex: currentIndex, items: tiers) {
            UpgradeCard(tier: $0, currentPrice: currentPrice)
                .overlay(
                    // Calculate the height of the card after it's been laid out
                    GeometryReader { proxy in
                        Action {
                            // Add the calculated height to the array
                            cardHeights.append(proxy.size.height)

                            // Determine the max height only once we've calculated all the heights
                            if cardHeights.count == tiers.count {
                                calculatedCardHeight = cardHeights.max()

                                // Reset the card heights so any view changes won't use old data
                                cardHeights = []
                            }
                        }
                    }
                )
        }
        .carouselPeekAmount(.constant(Constants.peekAmount))
        .carouselItemSpacing(Constants.spacing)
        .frame(height: calculatedCardHeight)
        .padding(.leading, 30)
    }

    private enum Constants {
        static let peekAmount: Double = 20
        static let spacing: Double = 30
    }
}

// MARK: - Available plans

struct UpgradeTier: Identifiable {
    let tier: Tier
    let iconName: String
    let title: String
    let plan: Constants.Plan
    let header: String
    let description: String
    let buttonLabel: String
    let buttonForegroundColor: Color
    let features: [TierFeature]
    let background: RadialGradient

    var id: String {
        tier.rawValue
    }

    enum Tier: String {
        case plus, patron
    }

    struct TierFeature: Hashable {
        let iconName: String
        let title: String
    }
}

extension UpgradeTier {
    static var plus: UpgradeTier {
        UpgradeTier(tier: .plus, iconName: "plusGold", title: "Plus", plan: .plus, header: L10n.plusMarketingTitle, description: L10n.accountDetailsPlusTitle, buttonLabel: L10n.plusSubscribeTo, buttonForegroundColor: Color.plusButtonFilledTextColor, features: [
            TierFeature(iconName: "plus-feature-desktop", title: L10n.plusMarketingDesktopAppsTitle),
            TierFeature(iconName: "plus-feature-folders", title: L10n.folders),
            TierFeature(iconName: "plus-feature-cloud", title: L10n.plusCloudStorageLimitFormat(10)),
            TierFeature(iconName: "plus-feature-watch", title: L10n.plusMarketingWatchPlaybackTitle),
            TierFeature(iconName: "plus-feature-extra", title: L10n.plusFeatureThemesIcons),
            TierFeature(iconName: "plus-feature-love", title: L10n.plusFeatureGratitude)
        ],
                    background: RadialGradient(colors: [Color(hex: "FFDE64").opacity(0.5), Color(hex: "121212")], center: .leading, startRadius: 0, endRadius: 500))
    }

    static var patron: UpgradeTier {
        UpgradeTier(tier: .patron, iconName: "patron-heart", title: "Patron", plan: .patron, header: L10n.patronCallout, description: L10n.patronDescription, buttonLabel: L10n.patronSubscribeTo, buttonForegroundColor: .white, features: [
            TierFeature(iconName: "patron-everything", title: L10n.patronFeatureEverythingInPlus),
            TierFeature(iconName: "patron-early-access", title: L10n.patronFeatureEarlyAccess),
            TierFeature(iconName: "plus-feature-cloud", title: L10n.plusCloudStorageLimitFormat(50)),
            TierFeature(iconName: "patron-badge", title: L10n.patronFeatureProfileBadge),
            TierFeature(iconName: "patron-icons", title: L10n.patronFeatureProfileIcons),
            TierFeature(iconName: "plus-feature-love", title: L10n.plusFeatureGratitude)

        ],
        background: RadialGradient(colors: [Color(hex: "503ACC").opacity(0.8), Color(hex: "121212")], center: .leading, startRadius: 0, endRadius: 500))
    }
}

// MARK: - Segmented Control

struct UpgradeRoundedSegmentedControl: View {
    @Binding private var selected: PlusPricingInfoModel.DisplayPrice

    init(selected: Binding<PlusPricingInfoModel.DisplayPrice>) {
        self._selected = selected
    }

    var body: some View {
        HStack(spacing: 0) {
            Button(L10n.yearly) {
                withAnimation {
                    selected = .yearly
                }
            }
            .buttonStyle(UpgradeSegmentedControlButtonStyle(isSelected: selected == .yearly))
            .padding(4)

            Button(L10n.monthly) {
                withAnimation {
                    selected = .monthly
                }
            }
            .buttonStyle(UpgradeSegmentedControlButtonStyle(isSelected: selected == .monthly))
            .padding(4)
        }
        .background(.white.opacity(0.16))
        .cornerRadius(24)
    }
}

struct UpgradeSegmentedControlButtonStyle: ButtonStyle {
    let isSelected: Bool

    init(isSelected: Bool = true) {
        self.isSelected = isSelected
    }

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(
                isSelected ? .white : configuration.isPressed ? .white.opacity(0.1) : .clear
            )
            .font(style: .subheadline, weight: .medium)
            .foregroundColor(isSelected ? .black : .white)
            .cornerRadius(100)
            .contentShape(Rectangle())
    }
}

// MARK: - Upgrade card

struct UpgradeCard: View {
    @EnvironmentObject var viewModel: PlusLandingViewModel

    let tier: UpgradeTier

    let currentPrice: Binding<PlusPricingInfoModel.DisplayPrice>

    var body: some View {
        VStack {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 4) {
                    Image(tier.iconName)
                        .padding(.leading, 8)
                    Text(tier.title)
                        .foregroundColor(.white)
                        .font(style: .subheadline, weight: .medium)
                        .padding(.trailing, 8)
                        .padding(.vertical, 2)
                }
                .background(.black)
                .cornerRadius(24)
                .padding(.bottom, 16)

                VStack(alignment: .leading, spacing: 12) {
                    ForEach(tier.features, id: \.self) { feature in
                        HStack(spacing: 16) {
                            Image(feature.iconName)
                                .renderingMode(.template)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .foregroundColor(.black)
                                .frame(width: 16, height: 16)
                            Text(feature.title)
                                .font(size: 14, style: .subheadline, weight: .medium)
                                .foregroundColor(.black)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }

                    Group {
                        termsAndConditions
                    }
                    .font(style: .footnote).fixedSize(horizontal: false, vertical: true)
                    .tint(.black)
                    .opacity(0.64)
                }
                .padding(.bottom, 0)
            }
            .padding(24)

        }
        .background(.white)
        .cornerRadius(24)
        .shadow(color: .black.opacity(0.01), radius: 10, x: 0, y: 24)
        .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 14)
        .shadow(color: .black.opacity(0.09), radius: 6, x: 0, y: 6)
        .shadow(color: .black.opacity(0.1), radius: 3, x: 0, y: 2)
        .shadow(color: .black.opacity(0.1), radius: 0, x: 0, y: 0)
    }

    @ViewBuilder
    var termsAndConditions: some View {
        let purchaseTerms = L10n.purchaseTerms("$", "$", "$", "$").components(separatedBy: "$")
        Text(purchaseTerms[safe: 0] ?? "") + Text("[\(purchaseTerms[safe: 1] ?? "")](https://support.pocketcasts.com/article/privacy-policy/)").underline() + Text(purchaseTerms[safe: 2] ?? "") + Text("[\(purchaseTerms[safe: 3] ?? "")](https://support.pocketcasts.com/article/terms-of-use/)").underline()
    }
}

struct UpgradeLandingView_Previews: PreviewProvider {
    static var previews: some View {
        UpgradeLandingView(purchaseModel: PlusPurchaseModel()).environmentObject(PlusLandingViewModel(source: .login))
    }
}
