import SwiftUI

struct UpNextAnnouncementView: View {
    let dismissAction: () -> Void

    @EnvironmentObject var theme: Theme

    var body: some View {
        VStack(alignment: .center, spacing: 0) {
            Image("up-next-shuffle-sheet")
                .frame(width: 36, height: 36)
                .padding(.bottom, 17)
                .foregroundStyle(theme.primaryIcon01)
            Text(L10n.upNextShuffleAnnouncementTitle)
                .multilineTextAlignment(.center)
                .font(size: 22, style: .body, weight: .bold)
                .foregroundStyle(theme.primaryText01)
                .padding(.bottom, 10)
                .padding(.horizontal, 41)
            Text(L10n.upNextShuffleAnnouncementText)
                .multilineTextAlignment(.center)
                .font(size: 14, style: .body, weight: .regular)
                .foregroundStyle(theme.primaryText01)
                .padding(.horizontal, 41)
                .padding(.bottom, 35)
            Button(action: dismissAction) {
                Text(L10n.upNextShuffleAnnouncementButton)
            }
            .buttonStyle(
                BasicButtonStyle(textColor: theme.primaryInteractive02,
                                 backgroundColor: theme.primaryInteractive01)
            )
            .frame(height: 56)
            .padding(.horizontal, 29)
        }
        .background(theme.primaryUi01)
    }
}

struct UpNextAnnouncementView__Previews: PreviewProvider {
    static var previews: some View {
        UpNextAnnouncementView() {}
            .setupDefaultEnvironment()
            .previewLayout(.fixed(width: 393, height: 290))
    }
}
