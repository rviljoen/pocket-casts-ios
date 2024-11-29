import SwiftUI

struct CancelSubscriptionPlansView: View {
    @EnvironmentObject var theme: Theme

    @ObservedObject var viewModel: CancelSubscriptionViewModel

    init(viewModel: CancelSubscriptionViewModel) {
        self.viewModel = viewModel
    }

    var body: some View {
        VStack(spacing: 16.0) {
            switch viewModel.currentProductAvailability {
            case .loading:
                ProgressView()
                    .foregroundStyle(theme.primaryUi01)
            default:
                ForEach(viewModel.pricingInfo.products, id: \.id) { product in
                    CancelSubscriptionPlanRow(product: product,
                                              selected: product.identifier == viewModel.currentPricingProduct?.identifier) { selectedProduct in
                        viewModel.purchase(product: selectedProduct)
                    }
                }
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
