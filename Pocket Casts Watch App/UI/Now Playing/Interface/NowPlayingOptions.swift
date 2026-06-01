import SwiftUI

struct NowPlayingOptions: View {
    @StateObject var viewModel: NowPlayingViewModel
    @Binding var presentView: WatchInterfaceType?
    @Binding var optionSelected: Bool

    var body: some View {
        GeometryReader { geo in
            VStack(spacing: 8) {
                HStack(spacing: 8) {
                    NowPlayingOption(iconName: "markasplayed") {
                        viewModel.markPlayed()
                        optionSelected.toggle()
                    }
                    .frame(maxWidth: geo.size.width / 2)

                    NowPlayingOption(systemIconName: "archivebox") {
                        viewModel.archive()
                        optionSelected.toggle()
                    }
                    .frame(maxWidth: geo.size.width / 2)
                }
                .frame(maxHeight: geo.size.height / 2)

                HStack(spacing: 8) {
                    NowPlayingOption(iconName: "episodedetails") {
                        presentView = .episodeDetails
                    }
                    .frame(maxWidth: geo.size.width / 2)

                    NowPlayingOption(systemIconName: "moon.zzz.fill", highlighted: viewModel.sleepTimerActive) {
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
            .modify { view in
                if #available(watchOS 26.0, *) {
                    view.glassEffect(
                        highlighted ? .clear.tint(Color.accentColor.opacity(0.4)).interactive() : .clear,
                        in: RoundedRectangle(cornerRadius: 20, style: .continuous)
                    )
                } else {
                    view.background(highlighted ? Color.selectedBackground : Color.background)
                        .clipShape(RoundedRectangle(cornerRadius: 20))
                }
            }
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
