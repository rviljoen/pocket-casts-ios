import SwiftUI

struct CancelSubscriptionPlanRow: View {
    @EnvironmentObject var theme: Theme

    let product: PlusPricingInfoModel.PlusProductPricingInfo
    var selected: Bool
    let onTap: (PlusPricingInfoModel.PlusProductPricingInfo) -> Void

    var body: some View {
        ZStack {
            Rectangle()
                .foregroundStyle(.clear)
                .background(theme.primaryUi01)
                .cornerRadius(8.0)
                .frame(height: 64)
            VStack(alignment: .leading, spacing: 0) {
                Text(product.identifier.rawValue)
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: 8.0)
                .stroke(theme.primaryField03Active,
                        lineWidth: selected ? 2 : 0)
        )
        .padding(.horizontal, 20.0)
        .onTapGesture {
            onTap(product)
        }
    }
}

struct CancelSubscriptionPlanRow_Preview: PreviewProvider {
    static var previews: some View {
        VStack(spacing: 16.0) {
            CancelSubscriptionPlanRow(
                product: .init(
                    identifier: .yearly,
                    price: "",
                    rawPrice: "$39.99",
                    offer: nil),
                selected: true
            ) { _ in }
                .environmentObject(Theme.sharedTheme)
            CancelSubscriptionPlanRow(
                product: .init(
                    identifier: .monthly,
                    price: "",
                    rawPrice: "$3.99",
                    offer: nil),
                selected: false
            ) { _ in }
                .environmentObject(Theme.sharedTheme)
        }
        .background(.gray)
        .previewLayout(.fixed(width: 393, height: 250))
    }
}
