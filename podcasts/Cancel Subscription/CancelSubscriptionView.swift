import SwiftUI

struct CancelSubscriptionView: View {
    @EnvironmentObject var theme: Theme

    let viewModel: CancelSubscriptionViewModel

    init(viewModel: CancelSubscriptionViewModel) {
        self.viewModel = viewModel
    }

    var body: some View {
        Text("Cancel Subscription")
            .background(color(for: .primaryUi01).ignoresSafeArea())
    }

    private func color(for style: ThemeStyle) -> Color {
        AppTheme.color(for: style, theme: theme)
    }
}

#Preview {
    CancelSubscriptionView(viewModel: CancelSubscriptionViewModel(navigationController: UINavigationController()))
        .environmentObject(Theme.sharedTheme)
}
