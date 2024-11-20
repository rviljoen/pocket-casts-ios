import SwiftUI

enum CancelSubscriptionOption: CaseIterable, Hashable, Identifiable {
    static var allCases: [CancelSubscriptionOption] = [.promotion(price: ""), .newPlan, .help]

    case promotion(price: String)
    case newPlan
    case help

    var id: Self {
        return self
    }

    var title: String {
        switch self {
        case .promotion:
            return L10n.cancelSubscriptionPromotionTitle
        case .newPlan:
            return L10n.cancelSubscriptionNewPlanTitle
        case .help:
            return L10n.cancelSubscriptionHelpTitle
        }
    }

    var subtitle: String {
        switch self {
        case .promotion(let price):
            return L10n.cancelSubscriptionPromotionDescription(price)
        case .newPlan:
            return L10n.cancelSubscriptionNewPlanDescription
        case .help:
            return L10n.cancelSubscriptionHelpDescription
        }
    }

    var icon: String {
        switch self {
        case .promotion:
            return "heart"
        case .newPlan:
            return "skipbackward"
        case .help:
            return "help"
        }
    }
}

struct CancelSubscriptionViewRow: View {
    let option: CancelSubscriptionOption
    let viewModel: CancelSubscriptionViewModel

    @EnvironmentObject var theme: Theme

    init(option: CancelSubscriptionOption, viewModel: CancelSubscriptionViewModel) {
        self.option = option
        self.viewModel = viewModel
    }

    var separator: some View {
        Rectangle()
            .frame(height: 1)
            .foregroundStyle(.clear)
            .background(theme.primaryUi05)
    }

    var claimButton: some View {
        Button(action: viewModel.claimOffer) {
            Text(L10n.cancelSubscriptionClaimOfferButton)
                .font(size: 13.0, style: .body, weight: .medium)
                .foregroundStyle(theme.primaryInteractive02)
                .frame(height: 32.0)
                .frame(maxWidth: .infinity)
                .background(
                    RoundedRectangle(
                        cornerRadius: 8.0,
                        style: .continuous
                    )
                    .fill(theme.primaryInteractive01)
                )
        }
    }

    var icon: some View {
        Image(option.icon)
            .renderingMode(.template)
            .foregroundStyle(theme.primaryIcon01)
            .frame(width: 24, height: 24)
    }

    var chevron: some View {
        HStack {
            Spacer()
            Image("chevron-small-right")
                .renderingMode(.template)
                .foregroundStyle(theme.primaryIcon02)
                .frame(width: 24, height: 24)
        }
    }

    var body: some View {
        ZStack {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top, spacing: 0) {
                    icon
                        .padding(.leading, 18.0)
                        .padding(.trailing, 12.0)

                    VStack(alignment: .leading, spacing: 0) {
                        Text(option.title)
                            .font(size: 15.0, style: .body, weight: .medium)
                            .foregroundStyle(theme.primaryText01)
                            .padding(.bottom, 4.0)

                        Text(option.subtitle)
                            .font(size: 12.0, style: .body, weight: .semibold)
                            .foregroundStyle(theme.primaryText02)

                        if case .promotion = option {
                            claimButton
                                .padding(.top, 12.0)
                        }

                        Spacer()
                            .frame(height: 24.0)
                    }

                    Spacer()
                        .frame(width: 55.0)
                        .background(.red)
                }

                separator
                    .padding(.leading, 16.0)
            }
            .padding(.top, 24.0)

            if option == .newPlan || option == .help {
                chevron
                    .padding(.trailing, 20.0)
            }
        }
    }
}

struct CancelSubscriptionViewRow_Previews: PreviewProvider {
    static var viewModel = CancelSubscriptionViewModel(navigationController: UINavigationController())
    static var previews: some View {
        VStack(spacing: 0) {
            CancelSubscriptionViewRow(option: .promotion(price: "$3.99"), viewModel: viewModel)
                .environmentObject(Theme.sharedTheme)
            CancelSubscriptionViewRow(option: .newPlan, viewModel: viewModel)
                .environmentObject(Theme.sharedTheme)
            CancelSubscriptionViewRow(option: .help, viewModel: viewModel)
                .environmentObject(Theme.sharedTheme)
        }
    }
}
