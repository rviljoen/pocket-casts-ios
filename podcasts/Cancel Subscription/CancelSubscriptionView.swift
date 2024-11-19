import SwiftUI

struct CancelSubscriptionView: View {
    @EnvironmentObject var theme: Theme

    @ObservedObject var viewModel: CancelSubscriptionViewModel

    init(viewModel: CancelSubscriptionViewModel) {
        self.viewModel = viewModel
    }

    var body: some View {
        VStack(spacing: 0) {
            switch viewModel.priceAvailability {
            case .available:
                ScrollView {
                    LazyVStack(spacing: 0) {
                        Text("Before you cancel, check out these offers")
                            .font(size: 28.0, style: .body, weight: .bold)
                            .foregroundStyle(theme.primaryText01)
                            .multilineTextAlignment(.center)
                            .padding(.top, 48.0)
                            .padding(.horizontal, 34.0)

                        if let price = viewModel.monthlyPrice() {
                            Text(price)
                        }
                    }
                }

                Button(action: {
                    viewModel.cancelSubscriptionTap()
                }, label: {
                    Text("Continue to Cancellation")
                        .font(size: 18.0, style: .body, weight: .bold)
                        .foregroundStyle(theme.primaryText01)
                        .multilineTextAlignment(.center)
                })
                .padding(.horizontal, 34.0)
                .padding(.top, 10.0)
                .padding(.bottom, 58.0)
            case .loading, .unknown:
                ProgressView()
            case .failed:
                Text("An error occurred. Please try again later.")
                    .font(size: 18.0, style: .body, weight: .bold)
                    .foregroundStyle(theme.primaryText01)
                    .multilineTextAlignment(.center)
            }
        }
        .background(
            color(for: .primaryUi01)
                .ignoresSafeArea()
        )
    }

    private func color(for style: ThemeStyle) -> Color {
        AppTheme.color(for: style, theme: theme)
    }
}

#Preview {
    CancelSubscriptionView(viewModel: CancelSubscriptionViewModel(navigationController: UINavigationController()))
        .environmentObject(Theme.sharedTheme)
}
