import Combine
import Foundation
import PocketCastsUtils

/// Drives the on-device transcript UI and keeps `currentParagraphIndex` in sync
/// with the player.
@MainActor
final class OnDeviceTranscriptViewModel: ObservableObject {
    struct ScrollRequest: Equatable {
        let paragraphID: Int
        let token = UUID()
    }

    @Published private(set) var state: OnDeviceTranscriptionState = .idle
    @Published private(set) var paragraphs: [OnDeviceTranscriptParagraph] = []
    @Published private(set) var progress: Double = 0
    @Published private(set) var progressLabel: String = ""
    @Published private(set) var currentParagraphIndex: Int? = nil
    @Published private(set) var scrollRequest: ScrollRequest? = nil
    @Published private(set) var isOutOfSync = false
    @Published private(set) var activeQueueItem: OnDeviceTranscriptQueueStore.QueueItem?
    @Published private(set) var queuedQueueItems: [OnDeviceTranscriptQueueStore.QueueItem] = []

    private let playbackManager: TranscriptPlaybackManaging
    private let transcriptQueueStore = OnDeviceTranscriptQueueStore.shared
    private var syncTimer: AnyCancellable?
    private var queueSubscription: AnyCancellable?
    private var observedEpisodeUUID: String?
    private var lastSyncedPlaybackTime: TimeInterval?
    private var autoSyncEnabled = true
    private var autoSyncResumeTask: Task<Void, Never>?

    init(playbackManager: TranscriptPlaybackManaging) {
        self.playbackManager = playbackManager
        queueSubscription = transcriptQueueStore.objectWillChange
            .sink { [weak self] in
                self?.refreshFromQueue()
            }
    }

    // MARK: - Observe

    func observe(episodeUUID: String) {
        if observedEpisodeUUID != episodeUUID {
            observedEpisodeUUID = episodeUUID
            autoSyncEnabled = true
            isOutOfSync = false
            autoSyncResumeTask?.cancel()
            stopSync()
        }
        refreshFromQueue()
    }

    func cancel() {
        stopSync()
    }

    // MARK: - Sync

    func startSync() {
        guard syncTimer == nil else { return }
        syncTimer = Timer.publish(every: 0.1, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.updateSyncPosition()
            }
    }

    func stopSync() {
        syncTimer?.cancel()
        syncTimer = nil
    }

    // MARK: - Paragraph seek

    func seek(to paragraph: OnDeviceTranscriptParagraph) {
        PlaybackManager.shared.seekTo(time: paragraph.startTime)
    }

    func userDidStartManualScroll() {
        autoSyncResumeTask?.cancel()
        autoSyncEnabled = false
        isOutOfSync = true
    }

    func userDidStopManualScroll() {
        autoSyncResumeTask?.cancel()
        autoSyncResumeTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            await self?.resumeAutoSync()
        }
    }

    func resyncNow() {
        autoSyncResumeTask?.cancel()
        resumeAutoSync()
    }

    // MARK: - Private

    private func refreshFromQueue() {
        guard let observedEpisodeUUID else {
            applyIdleState()
            return
        }

        guard let snapshot = transcriptQueueStore.snapshot(for: observedEpisodeUUID) else {
            applyIdleState()
            return
        }

        progress = snapshot.progress
        progressLabel = snapshot.progressLabel
        state = snapshot.state
        activeQueueItem = transcriptQueueStore.queueState.activeItem
        queuedQueueItems = transcriptQueueStore.queueState.queuedItems

        if case .completed = snapshot.state {
            paragraphs = snapshot.paragraphs
            startSync()
        } else {
            paragraphs = []
            currentParagraphIndex = nil
            scrollRequest = nil
            lastSyncedPlaybackTime = nil
            autoSyncEnabled = true
            isOutOfSync = false
            autoSyncResumeTask?.cancel()
            stopSync()
        }
    }

    private func applyIdleState() {
        state = .idle
        paragraphs = []
        progress = 0
        progressLabel = ""
        currentParagraphIndex = nil
        scrollRequest = nil
        lastSyncedPlaybackTime = nil
        autoSyncEnabled = true
        isOutOfSync = false
        autoSyncResumeTask?.cancel()
        activeQueueItem = transcriptQueueStore.queueState.activeItem
        queuedQueueItems = transcriptQueueStore.queueState.queuedItems
        stopSync()
    }

    private func updateSyncPosition() {
        let time = playbackManager.currentTime()
        guard time >= 0, !paragraphs.isEmpty else {
            currentParagraphIndex = nil
            return
        }

        let newParagraphIndex = paragraphs.firstIndex { paragraph in
            time >= paragraph.startTime && time < paragraph.endTime
        } ?? paragraphs.lastIndex(where: { time >= $0.startTime })

        if autoSyncEnabled,
           let newParagraphIndex,
           newParagraphIndex != currentParagraphIndex {
            scrollRequest = ScrollRequest(paragraphID: paragraphs[newParagraphIndex].id)
        }

        currentParagraphIndex = newParagraphIndex
        lastSyncedPlaybackTime = time
    }

    private func resumeAutoSync() {
        autoSyncEnabled = true
        isOutOfSync = false
        guard let currentParagraphIndex,
              currentParagraphIndex < paragraphs.count else { return }
        scrollRequest = ScrollRequest(paragraphID: paragraphs[currentParagraphIndex].id)
    }
}
