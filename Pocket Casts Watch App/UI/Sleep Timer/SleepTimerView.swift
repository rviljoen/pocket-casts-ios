import PocketCastsDataModel
import SwiftUI

struct SleepTimerView: View {
    var episode: BaseEpisode? = nil
    @StateObject var viewModel = SleepTimerViewModel()

    private let columns = [GridItem(.flexible()), GridItem(.flexible())]

    private let presets: [TimeInterval] = [15.minutes, 30.minutes]

    var body: some View {
        ScrollView {
            VStack(spacing: WatchConstants.spacing) {
                if viewModel.isActive {
                    Text(viewModel.statusText)
                        .font(.dynamic(size: 13))
                        .multilineTextAlignment(.center)
                        .foregroundColor(.primary)

                    // Adjusting only applies to a running countdown, not to end of episode
                    if !viewModel.isEndOfEpisode {
                        LazyVGrid(columns: columns, spacing: WatchConstants.spacing) {
                            PresetCircle(label: "−5") {
                                viewModel.decreaseSleepTimer()
                            }
                            PresetCircle(label: "+5") {
                                viewModel.extendSleepTimer()
                            }
                        }
                    }

                    CapsuleButton(title: L10n.sleepTimerCancel, color: .red) {
                        viewModel.cancelSleepTimer()
                    }
                } else {
                    Text(L10n.sleepTimerSelectDuration)
                        .font(.dynamic(size: 13))
                        .multilineTextAlignment(.center)
                        .foregroundColor(.primary)

                    LazyVGrid(columns: columns, spacing: WatchConstants.spacing) {
                        ForEach(presets, id: \.self) { duration in
                            PresetCircle(label: "\(Int(duration / 60))") {
                                viewModel.setSleepTimer(duration: duration)
                            }
                        }
                    }

                    CapsuleButton(title: L10n.sleepTimerEndOfEpisode) {
                        viewModel.setSleepTimerEndOfEpisode()
                    }
                }
            }
            .padding(.top, 36)
        }
        .nowPlayingBackground(episode)
        .navigationTitle(L10n.sleepTimer)
    }
}

// MARK: - Preset Circle

private struct PresetCircle: View {
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 0) {
                Text(label)
                    .font(.system(size: 30, weight: .bold).monospacedDigit())
                    .foregroundColor(.white)
                Text(L10n.sleepTimerWatchMinutesUnit)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.white.opacity(0.7))
            }
            .frame(width: 64, height: 64)
            .overlay(Circle().strokeBorder(Color.white.opacity(0.3), lineWidth: 2))
            .watchGlass(in: Circle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Capsule Button

private struct CapsuleButton: View {
    let title: String
    var color: Color? = nil
    let action: () -> Void

    var body: some View {
        Button(title, action: action)
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .foregroundColor(color)
            .watchGlass(in: Capsule())
            .overlay(Capsule().strokeBorder(Color.white.opacity(0.3), lineWidth: 2))
            .padding(.horizontal, 8)
    }
}

// MARK: - Preview

struct SleepTimerView_Previews: PreviewProvider {
    static var previews: some View {
        ForEach(PreviewDevice.previewDevices) {
            SleepTimerView()
                .previewDevice($0)
        }
    }
}
