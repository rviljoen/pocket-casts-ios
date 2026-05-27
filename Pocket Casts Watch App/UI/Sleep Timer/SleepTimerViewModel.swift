import Combine
import Foundation
import PocketCastsUtils
import SwiftUI

class SleepTimerViewModel: ObservableObject {
    @Published var isActive: Bool = false
    @Published var statusText: String = ""

    private var playSource = PlaySourceHelper.playSourceViewModel
    private var cancellables = Set<AnyCancellable>()

    init() {
        Publishers.Merge(
            Publishers.Notification.dataUpdated,
            Publishers.Notification.sleepTimerChanged
        )
        .receive(on: RunLoop.main)
        .sink { [unowned self] _ in
            self.refreshState()
        }
        .store(in: &cancellables)

        refreshState()
    }

    private func refreshState() {
        let remaining = playSource.sleepTimeRemaining
        let episodes = playSource.sleepEpisodeCount
        isActive = remaining >= 0 || episodes > 0

        if episodes > 0 {
            statusText = "On: \(L10n.sleepTimerEndOfEpisode)"
        } else if remaining >= 0 {
            let formatted = TimeFormatter.shared.playTimeFormat(time: remaining, showSeconds: remaining < 60)
            statusText = "On: \(formatted)"
        } else {
            statusText = ""
        }
    }

    func setSleepTimer(duration: TimeInterval) {
        playSource.setSleepTimer(duration: duration)
    }

    func setSleepTimerEndOfEpisode() {
        playSource.setSleepTimerEndOfEpisode()
    }

    func extendSleepTimer() {
        playSource.extendSleepTimer(by: 5.minutes)
    }

    func decreaseSleepTimer() {
        playSource.extendSleepTimer(by: -5.minutes)
    }

    func cancelSleepTimer() {
        playSource.cancelSleepTimer()
    }
}
