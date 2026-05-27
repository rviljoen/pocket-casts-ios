import SwiftUI

struct NowPlayingOptions: View {
    @StateObject var viewModel: NowPlayingViewModel
    @Binding var presentView: WatchInterfaceType?
    @Binding var optionSelected: Bool

    var body: some View {
        GeometryReader { geo in
            VStack(spacing: 5) {
                HStack {
                    NowPlayingOption(iconName: "markasplayed", title: L10n.markPlayedShort) {
                        viewModel.markPlayed()
                        optionSelected.toggle()
                    }
                    .frame(maxWidth: geo.size.width / 2)

                    NowPlayingOption(systemIconName: "archivebox", title: L10n.archive) {
                        viewModel.archive()
                        optionSelected.toggle()
                    }
                    .frame(maxWidth: geo.size.width / 2)
                }
                .frame(maxHeight: geo.size.height / 2)

                HStack {
                    NowPlayingOption(iconName: "episodedetails", title: L10n.watchEpisodeDetails) {
                        presentView = .episodeDetails
                    }
                    .frame(maxWidth: geo.size.width / 2)

                    NowPlayingOption(systemIconName: "moon.zzz.fill", title: viewModel.sleepTimerButtonTitle, highlighted: viewModel.sleepTimerActive) {
                        presentView = .sleepTimer
                    }
                    .frame(maxWidth: geo.size.width / 2)
                }
                .frame(maxHeight: geo.size.height / 2)
            }
            .frame(maxHeight: .infinity, alignment: .center)
        }
    }
}

private struct NowPlayingOption: View {
    var iconName: String? = nil
    var systemIconName: String? = nil
    var title: String
    var highlighted: Bool = false
    var action: () -> Void

    var body: some View {
        Button {
            action()
        } label: {
            VStack(alignment: .center, spacing: 5) {
                if let systemIconName {
                    Image(systemName: systemIconName)
                        .resizable()
                        .aspectRatio(1, contentMode: .fit)
                        .frame(minHeight: 20, maxHeight: 30)
                } else if let iconName {
                    Image(iconName)
                        .resizable()
                        .aspectRatio(1, contentMode: .fit)
                        .frame(minHeight: 20, maxHeight: 30)
                }

                Text(title)
                    .layoutPriority(1)
                    .multilineTextAlignment(.center)
                    .font(.dynamic(size: 13))
                    .minimumScaleFactor(0.7)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(5)
            .background(highlighted ? Color.selectedBackground : Color.background)
            .clipShape(RoundedRectangle(cornerRadius: 20))
        }
        .buttonStyle(.plain)
        .frame(maxHeight: .infinity)
    }
}

struct NowPlayingOptions_Previews: PreviewProvider {
    static var previews: some View {
        ForEach(PreviewDevice.previewDevices) {
            NowPlayingOptions(viewModel: NowPlayingViewModel(), presentView: .constant(nil), optionSelected: .constant(false))
                .previewDevice($0)
        }
    }
}
