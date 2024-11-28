import SwiftUI

struct CancelSubscriptionPlansView: View {
    @EnvironmentObject var theme: Theme

    @ObservedObject var viewModel: CancelSubscriptionViewModel

    init(viewModel: CancelSubscriptionViewModel) {
        self.viewModel = viewModel
    }

    var body: some View {
        VStack(spacing: 0) {
            switch viewModel.currentProductAvailability {
            case .loading:
                ProgressView()
                    .foregroundStyle(theme.primaryUi01)
            default:
                Text(viewModel.currentPricingProduct?.id ?? "No product")
            }
        }
        .onAppear {
            Task {
                await viewModel.loadCurrentProduct()
            }
        }
    }
}

#Preview {
    CancelSubscriptionPlansView(viewModel: CancelSubscriptionViewModel(navigationController: UINavigationController()))
        .environmentObject(Theme.sharedTheme)
}
