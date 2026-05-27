import Combine
import Foundation
import PocketCastsDataModel
import PocketCastsUtils
import SwiftUI

class NowPlayingViewModel: ObservableObject {
    @Published var episode: BaseEpisode?
    @Published var isPlaying = false
    @Published var episodeName: String = L10n.loading
    @Published var progress: CGFloat = 0
    @Published var progressTitle: String = ""
    @Published var timeRemaining: String = ""
    @Published var episodeAccentColor: Color = .white
    @Published var effectsIconName: String
    @Published var upNextCount: Int
    @Published var hasChapters: Bool
    @Published var sleepTimerActive: Bool = false
    @Published var sleepTimerButtonTitle: String = ""

    private var playSource = PlaySourceHelper.playSourceViewModel
    private var cancellables = Set<AnyCancellable>()

    private var playbackChanged: AnyPublisher<BaseEpisode?, Never> {
        Publishers.Merge(
            $episode,
            Publishers.Notification.playbackChanged.map { [unowned self] _ in self.episode }.eraseToAnyPublisher()
        )
        .eraseToAnyPublisher()
    }

    private var dataUpdated: AnyPublisher<Notification, Never> {
        Publishers.Merge3(
            Publishers.Notification.dataUpdated,
            Publishers.Notification.playbackChanged,
            Publishers.Notification.podcastChaptersDidUpdate
        )
        .eraseToAnyPublisher()
    }

    init() {
        episode = playSource.nowPlayingEpisode
        effectsIconName = playSource.effectsIconName
        upNextCount = playSource.upNextCount
        hasChapters = playSource.playingEpisodeHasChapters

        let initialRemaining = playSource.sleepTimeRemaining
        let initialEpisodes = playSource.sleepEpisodeCount
        sleepTimerActive = initialRemaining >= 0 || initialEpisodes > 0
        if initialEpisodes > 0 {
            sleepTimerButtonTitle = L10n.sleepTimerEndOfEpisode
        } else if initialRemaining >= 0 {
            sleepTimerButtonTitle = TimeFormatter.shared.playTimeFormat(time: initialRemaining, showSeconds: false)
        } else {
            sleepTimerButtonTitle = L10n.sleepTimer
        }

        Publishers.Merge(
            $episode,
            Publishers.Notification.podcastChapterChanged.map { [unowned self] _ in self.episode }
        )
        .map { [unowned self] episode in
            guard
                let episode,
                let title = self.playSource.nowPlayingTitle(forEpisode: episode)
            else {
                return L10n.loading
            }
            return title
        }
        .receive(on: RunLoop.main)
        .assign(to: &$episodeName)

        Publishers.Merge(
            $episode,
            Publishers.Notification.progressUpdated.map { [unowned self] _ in self.episode }
        )
        .receive(on: RunLoop.main)
        .sink { [unowned self] episode in
            guard let episode else { return }
            self.progress = self.playSource.playbackProgress
            self.progressTitle = self.playSource.nowPlayingSubTitle(forEpisode: episode) ?? ""
            self.timeRemaining = self.playSource.nowPlayingTimeRemaining(forEpisode: episode)
        }
        .store(in: &cancellables)

        playbackChanged
            .map { [unowned self] episode in
                guard let episode else { return false }
                return self.playSource.isPlaying(forEpisode: episode)
            }
            .receive(on: RunLoop.main)
            .assign(to: &$isPlaying)

        dataUpdated
            .map { [unowned self] _ in
                self.playSource.nowPlayingEpisode
            }
            .receive(on: RunLoop.main)
            .assign(to: &$episode)

        $episode
            .map { [unowned self] episode in
                guard let episode else { return Color.white }
                return self.playSource.nowPlayingTint(forEpisode: episode)
            }
            .receive(on: RunLoop.main)
            .assign(to: &$episodeAccentColor)

        Publishers.Merge(
            dataUpdated,
            Publishers.Notification.playbackEffectsChanged
        )
        .map { [unowned self] _ in
            self.playSource.effectsIconName
        }
        .receive(on: RunLoop.main)
        .assign(to: &$effectsIconName)

        dataUpdated
            .map { [unowned self] _ in
                self.playSource.upNextCount
            }
            .receive(on: RunLoop.main)
            .assign(to: &$upNextCount)

        Publishers.Merge(
            $episode,
            Publishers.Notification.podcastChaptersDidUpdate.map { [unowned self] _ in self.episode }
        )
        .map { [unowned self] _ in
            self.playSource.playingEpisodeHasChapters
        }
        .receive(on: RunLoop.main)
        .assign(to: &$hasChapters)

        Publishers.Merge(
            dataUpdated,
            Publishers.Notification.sleepTimerChanged
        )
        .map { [unowned self] _ in
            let remaining = self.playSource.sleepTimeRemaining
            let episodes = self.playSource.sleepEpisodeCount
            return remaining >= 0 || episodes > 0
        }
        .receive(on: RunLoop.main)
        .assign(to: &$sleepTimerActive)

        Publishers.Merge(
            dataUpdated,
            Publishers.Notification.sleepTimerChanged
        )
        .map { [unowned self] _ -> String in
            let remaining = self.playSource.sleepTimeRemaining
            let episodes = self.playSource.sleepEpisodeCount
            if episodes > 0 {
                return L10n.sleepTimerEndOfEpisode
            } else if remaining >= 0 {
                return TimeFormatter.shared.playTimeFormat(time: remaining, showSeconds: false)
            }
            return L10n.sleepTimer
        }
        .receive(on: RunLoop.main)
        .assign(to: &$sleepTimerButtonTitle)
    }

    func skip(forward: Bool) {
        playSource.skip(forward: forward)
    }

    func playPauseTapped() {
        guard let episode else { return }
        playSource.playPauseTapped(withEpisode: episode, playlist: nil)
    }

    func markPlayed() {
        guard let episode else { return }
        playSource.markPlayed(episode: episode)
    }

    func archive() {
        guard let episode else { return }
        playSource.archive(episode: episode)
    }

    func changeChapter(next: Bool) {
        playSource.changeChapter(next: next)
    }
}
