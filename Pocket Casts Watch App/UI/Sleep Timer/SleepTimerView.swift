import PocketCastsDataModel
import SwiftUI

struct SleepTimerView: View {
    var episode: BaseEpisode? = nil
    @StateObject var viewModel = SleepTimerViewModel()

    private let columns = [GridItem(.flexible()), GridItem(.flexible())]

    private let presets: [(value: Int, unit: String, duration: TimeInterval)] = [
        (15, "MIN", 15.minutes),
        (30, "MIN", 30.minutes),
    ]

    var body: some View {
        ZStack {
            if let episode {
                NowPlayingArtworkBackground(episode: episode)
                    .ignoresSafeArea()
            }

            ScrollView {
                VStack(spacing: WatchConstants.spacing) {
                    if viewModel.isActive {
                        Text(viewModel.statusText)
                            .font(.dynamic(size: 13))
                            .multilineTextAlignment(.center)
                            .foregroundColor(.primary)

                        LazyVGrid(columns: columns, spacing: WatchConstants.spacing) {
                            PresetCircle(label: "−5", unit: "MIN") {
                                viewModel.decreaseSleepTimer()
                            }
                            PresetCircle(label: "+5", unit: "MIN") {
                                viewModel.extendSleepTimer()
                            }
                        }

                        Button(L10n.sleepTimerCancel) {
                            viewModel.cancelSleepTimer()
                        }
                        .buttonStyle(.plain)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .foregroundColor(.red)
                        .modify { view in
                            if #available(watchOS 26.0, *) {
                                view.glassEffect(.clear, in: .capsule)
                            } else {
                                view.background(Color.background)
                                    .clipShape(Capsule())
                            }
                        }
                        .overlay(Capsule().strokeBorder(Color.white.opacity(0.3), lineWidth: 2))
                        .padding(.horizontal, 8)
                    } else {
                        Text(L10n.sleepTimerSelectDuration)
                            .font(.dynamic(size: 13))
                            .multilineTextAlignment(.center)
                            .foregroundColor(.primary)

                        LazyVGrid(columns: columns, spacing: WatchConstants.spacing) {
                            ForEach(presets, id: \.duration) { preset in
                                PresetCircle(value: preset.value, unit: preset.unit) {
                                    viewModel.setSleepTimer(duration: preset.duration)
                                }
                            }
                        }

                        Button(L10n.sleepTimerEndOfEpisode) {
                            viewModel.setSleepTimerEndOfEpisode()
                        }
                        .buttonStyle(.plain)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .modify { view in
                            if #available(watchOS 26.0, *) {
                                view.glassEffect(.clear, in: .capsule)
                            } else {
                                view.background(Color.background)
                                    .clipShape(Capsule())
                            }
                        }
                        .overlay(Capsule().strokeBorder(Color.white.opacity(0.3), lineWidth: 2))
                        .padding(.horizontal, 8)
                    }
                }
                .padding(.top, 36)
            }
        }
        .navigationTitle(L10n.sleepTimer)
    }
}

// MARK: - Preset Circle

private struct PresetCircle: View {
    let label: String
    let unit: String
    let action: () -> Void

    init(value: Int, unit: String, action: @escaping () -> Void) {
        self.label = "\(value)"
        self.unit = unit
        self.action = action
    }

    init(label: String, unit: String, action: @escaping () -> Void) {
        self.label = label
        self.unit = unit
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            VStack(spacing: 0) {
                Text(label)
                    .font(.system(size: 30, weight: .bold).monospacedDigit())
                    .foregroundColor(.white)
                Text(unit)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.white.opacity(0.7))
            }
            .frame(width: 64, height: 64)
            .overlay(Circle().strokeBorder(Color.white.opacity(0.3), lineWidth: 2))
            .modify { view in
                if #available(watchOS 26.0, *) {
                    view.glassEffect(.clear, in: .circle)
                } else {
                    view.background(Circle().fill(Color.background))
                }
            }
        }
        .buttonStyle(.plain)
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
