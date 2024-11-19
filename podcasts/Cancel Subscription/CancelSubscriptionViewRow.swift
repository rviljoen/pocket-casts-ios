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
            return "Get your next month free"
        case .newPlan:
            return "Looking for a different plan?"
        case .help:
            return "Need help with Pocket Casts?"
        }
    }

    var subtitle: String {
        switch self {
        case .promotion(let price):
            return "Save \(price) with your next month on us."
        case .newPlan:
            return "Find the plan that’s right for you."
        case .help:
            return "Struggling with any features or having issues."
        }
    }
}

struct CancelSubscriptionViewRow: View {
    let option: CancelSubscriptionOption
    let price: String?

    @EnvironmentObject var theme: Theme

    init(option: CancelSubscriptionOption, price: String? = nil) {
        self.option = option
        self.price = price
    }

    var separator: some View {
        Rectangle()
            .frame(height: 1)
            .foregroundStyle(.clear)
            .background(theme.primaryUi05)
    }

    var body: some View {
        ZStack {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top, spacing: 0) {
                    Rectangle()
                        .frame(width: 24, height: 24)
                        .padding(.leading, 18.0)
                        .padding(.trailing, 12.0)

                    VStack(alignment: .leading, spacing: 0) {
                        Text(option.title)
                            .font(size: 15.0, style: .body, weight: .medium)
                            .foregroundStyle(theme.primaryText01)
                            .padding(.bottom, 4.0)

                        Text(option.subtitle)
                            .font(size: 12.0, style: .body, weight: .semibold)
                            .foregroundStyle(theme.secondaryText02)

                        if case .promotion = option {
                            Button(action: test) {
                                Text("Claim offer")
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
                HStack {
                    Spacer()
                    Rectangle()
                        .background(.red)
                        .frame(width: 24, height: 24)
                        .padding(.trailing, 20.0)
                }
            }
        }
    }

    func test() {

    }
}

struct CancelSubscriptionViewRow_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: 0) {
            CancelSubscriptionViewRow(option: .promotion(price: "$3.99"))
                .environmentObject(Theme.sharedTheme)
            CancelSubscriptionViewRow(option: .newPlan)
                .environmentObject(Theme.sharedTheme)
            CancelSubscriptionViewRow(option: .help)
                .environmentObject(Theme.sharedTheme)
        }
    }
}
