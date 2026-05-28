import SwiftUI

struct NowPlayingOptions: View {
    @StateObject var viewModel: NowPlayingViewModel
    @Binding var presentView: WatchInterfaceType?
    @Binding var optionSelected: Bool

    var body: some View {
        GeometryReader { geo in
            VStack(spacing: 8) {
                HStack(spacing: 8) {
                    NowPlayingOption(iconName: "markasplayed", label: L10n.markPlayed) {
                        viewModel.markPlayed()
                        optionSelected.toggle()
                    }
                    .frame(maxWidth: geo.size.width / 2)

                    NowPlayingOption(systemIconName: "archivebox", label: L10n.archive) {
                        viewModel.archive()
                        optionSelected.toggle()
                    }
                    .frame(maxWidth: geo.size.width / 2)
                }
                .frame(maxHeight: geo.size.height / 2)

                HStack(spacing: 8) {
                    NowPlayingOption(iconName: "episodedetails", label: L10n.watchEpisodeDetails) {
                        presentView = .episodeDetails
                    }
                    .frame(maxWidth: geo.size.width / 2)

                    NowPlayingOption(systemIconName: "moon.zzz.fill", label: L10n.sleepTimer, highlighted: viewModel.sleepTimerActive) {
                        presentView = .sleepTimer
                    }
                    .frame(maxWidth: geo.size.width / 2)
                }
                .frame(maxHeight: geo.size.height / 2)
            }
            .padding(8)
            .frame(maxHeight: .infinity, alignment: .center)
        }
    }
}

private struct NowPlayingOption: View {
    var iconName: String? = nil
    var systemIconName: String? = nil
    let label: String
    var highlighted: Bool = false
    var action: () -> Void

    var body: some View {
        Button {
            action()
        } label: {
            Group {
                if let systemIconName {
                    Image(systemName: systemIconName)
                        .resizable()
                        .aspectRatio(1, contentMode: .fit)
                        .frame(minHeight: 24, maxHeight: 36)
                } else if let iconName {
                    Image(iconName)
                        .resizable()
                        .aspectRatio(1, contentMode: .fit)
                        .frame(minHeight: 24, maxHeight: 36)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(5)
            .watchGlass(
                in: RoundedRectangle(cornerRadius: 20, style: .continuous),
                interactive: highlighted,
                tint: highlighted ? Color.accentColor.opacity(0.4) : nil,
                fallback: highlighted ? Color.selectedBackground : Color.background
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
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
