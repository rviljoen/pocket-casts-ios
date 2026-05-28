import PocketCastsDataModel
import SwiftUI
import WatchKit

struct EffectsView: View {
    var episode: BaseEpisode? = nil
    @StateObject var viewModel = EffectsViewModel()

    var body: some View {
        ScrollView {
            VStack(spacing: WatchConstants.spacing) {
                HStack(spacing: WatchConstants.spacing) {
                    Button(action: { viewModel.decreasePlaybackSpeed() }) {
                        Image("minus", bundle: Bundle.watchAssets)
                    }
                    .roundIcon()

                    Button(L10n.playbackSpeed(viewModel.playbackSpeed.localized()), action: { viewModel.changeSpeedInterval() })
                        .buttonStyle(.plain)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .watchGlass(
                            in: RoundedRectangle(cornerRadius: WatchConstants.cornerRadius),
                            interactive: true,
                            tint: viewModel.playbackSpeed == 1 ? nil : Color.accentColor.opacity(0.4),
                            fallback: viewModel.playbackSpeed == 1 ? Color.background : Color.selectedBackground
                        )

                    Button(action: { viewModel.increasePlaybackSpeed() }) {
                        Image("plus", bundle: Bundle.watchAssets)
                    }
                    .roundIcon()
                }
                .padding(.horizontal, 15)

                if viewModel.trimSilenceAvailable {
                    Toggle(L10n.trimSilence, isOn: $viewModel.trimSilenceEnabled)
                        .styled()
                }
                if viewModel.volumeBoostAvailable {
                    Toggle(L10n.volumeBoost, isOn: $viewModel.volumeBoostEnabled)
                        .styled()
                }
            }
            .padding(.top, 36)
        }
        .nowPlayingBackground(episode)
        .navigationTitle(L10n.watchEffects)
    }
}

// MARK: - Modifiers

private extension Toggle {
    @MainActor
    func styled() -> some View {
        padding(.vertical)
            .padding(.horizontal, 15)
            .watchGlass(in: Capsule())
    }
}

private extension Button {
    @MainActor
    func roundIcon() -> some View {
        buttonStyle(.plain)
            .clipShape(Circle())
    }
}

// MARK: - Preview

struct EffectsView_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            EffectsView()
                .previewDevice(.largeWatch)

            EffectsView()
                .previewDevice(.smallWatch)
        }
    }
}
