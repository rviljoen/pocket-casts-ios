import Foundation
import PocketCastsDataModel

@MainActor
final class OnDeviceTranscriptQueueStore: ObservableObject {
    static let shared = OnDeviceTranscriptQueueStore()

    struct QueueItem: Identifiable, Equatable {
        let episodeUUID: String
        let title: String
        let state: OnDeviceTranscriptionState
        let progress: Double
        let progressLabel: String

        var id: String { episodeUUID }
    }

    struct TranscriptLibraryItem: Identifiable, Equatable {
        let episodeUUID: String
        let title: String
        let podcastTitle: String?
        let publishedDate: Date?

        var id: String { episodeUUID }
    }

    struct QueueState: Equatable {
        let activeItem: QueueItem?
        let queuedItems: [QueueItem]
    }

    struct Snapshot {
        let state: OnDeviceTranscriptionState
        let progress: Double
        let progressLabel: String
        let paragraphs: [OnDeviceTranscriptParagraph]
    }

    @Published private var snapshots: [String: Snapshot] = [:]
    @Published private(set) var queueState = QueueState(activeItem: nil, queuedItems: [])
    @Published private(set) var transcriptLibrary: [TranscriptLibraryItem] = []

    func snapshot(for episodeUUID: String) -> Snapshot? {
        snapshots[episodeUUID]
    }

    func update(
        episodeUUID: String,
        state: OnDeviceTranscriptionState,
        progress: Double,
        progressLabel: String,
        paragraphs: [OnDeviceTranscriptParagraph]
    ) {
        snapshots[episodeUUID] = Snapshot(
            state: state,
            progress: progress,
            progressLabel: progressLabel,
            paragraphs: paragraphs
        )
    }

    func remove(episodeUUID: String) {
        snapshots.removeValue(forKey: episodeUUID)
    }

    func updateQueue(activeItem: QueueItem?, queuedItems: [QueueItem]) {
        queueState = QueueState(activeItem: activeItem, queuedItems: queuedItems)
    }

    func updateTranscriptLibrary(_ items: [TranscriptLibraryItem]) {
        transcriptLibrary = items
    }
}

/// Serializes on-device transcript generation across the app and exposes
/// per-episode state for UI consumers through `OnDeviceTranscriptQueueStore`.
actor OnDeviceTranscriptQueue {
    static let shared = OnDeviceTranscriptQueue()

    private let cache = OnDeviceTranscriptCache()

    private struct Entry {
        let episodeUUID: String
        var title: String
        var podcastTitle: String?
        var publishedDate: Date?
        var fileURL: URL
        var state: OnDeviceTranscriptionState
        var progress: Double
        var progressLabel: String
        var payload: OnDeviceTranscriptPayload?
    }

    private var entries: [String: Entry] = [:]
    private var queuedEpisodeUUIDs: [String] = []
    private var activeEpisodeUUID: String?
    private var workerTask: Task<Void, Never>?
    private var observers: [NSObjectProtocol] = []
    private var started = false

    func start() {
        guard !started else { return }
        started = true

        observeNotifications()
        bootstrapDownloadedEpisodes()
    }

    func enqueueDownloadedEpisode(_ episode: Episode) async {
        guard episode.downloaded(pathFinder: DownloadManager.shared) else {
            await removeEpisode(episode.uuid)
            return
        }

        let fileURL = URL(fileURLWithPath: episode.pathToDownloadedFile(pathFinder: DownloadManager.shared))
        let title = episode.title ?? "Untitled episode"
        let podcastTitle = episode.parentPodcast()?.title
        let publishedDate = episode.publishedDate
        let cachedPayload: OnDeviceTranscriptPayload?
        if #available(iOS 26.0, *) {
            cachedPayload = loadCachedPayloadIfAvailable(for: fileURL)
        } else {
            cachedPayload = nil
        }

        if let existing = entries[episode.uuid] {
            var updated = existing
            updated.title = title
            updated.podcastTitle = podcastTitle
            updated.publishedDate = publishedDate
            updated.fileURL = fileURL

            if let cachedPayload {
                updated.state = .completed
                updated.progress = 1
                updated.progressLabel = "Loaded from cache"
                updated.payload = cachedPayload
                entries[episode.uuid] = updated
                queuedEpisodeUUIDs.removeAll { $0 == episode.uuid }
                if activeEpisodeUUID == episode.uuid {
                    activeEpisodeUUID = nil
                }
                await publish(updated)
                await publishQueueState()
                await publishTranscriptLibrary()
                return
            }

            switch existing.state {
            case .completed:
                entries[episode.uuid] = updated
                await publishQueueState()
                await publishTranscriptLibrary()
                return
            case .preparingAssets, .transcribing:
                entries[episode.uuid] = updated
            case .idle, .queued, .unavailable, .error:
                updated.state = .queued
                updated.progress = 0
                updated.progressLabel = "Queued for transcription…"
                updated.payload = nil
                entries[episode.uuid] = updated
                await publish(updated)
            }
        } else {
            let entry = Entry(
                episodeUUID: episode.uuid,
                title: title,
                podcastTitle: podcastTitle,
                publishedDate: publishedDate,
                fileURL: fileURL,
                state: cachedPayload == nil ? .queued : .completed,
                progress: cachedPayload == nil ? 0 : 1,
                progressLabel: cachedPayload == nil ? "Queued for transcription…" : "Loaded from cache",
                payload: cachedPayload
            )
            entries[episode.uuid] = entry
            await publish(entry)
        }

        if cachedPayload == nil, activeEpisodeUUID != episode.uuid, !queuedEpisodeUUIDs.contains(episode.uuid) {
            queuedEpisodeUUIDs.append(episode.uuid)
        }

        await publishQueueState()
        await publishTranscriptLibrary()
        startWorkerIfNeeded()
    }

    func prioritizeEpisode(_ episode: Episode) async {
        await enqueueDownloadedEpisode(episode)

        guard activeEpisodeUUID != episode.uuid else { return }
        guard let entry = entries[episode.uuid] else { return }

        if case .completed = entry.state {
            queuedEpisodeUUIDs.removeAll { $0 == episode.uuid }
            await publishQueueState()
            return
        }

        queuedEpisodeUUIDs.removeAll { $0 == episode.uuid }
        queuedEpisodeUUIDs.insert(episode.uuid, at: 0)
        await publishQueueState()
    }

    // MARK: - Setup

    private func observeNotifications() {
        let center = NotificationCenter.default

        observers.append(
            center.addObserver(forName: Constants.Notifications.episodeDownloadStatusChanged, object: nil, queue: .main) { notification in
                guard let episodeUUID = notification.object as? String,
                      let episode = DataManager.sharedManager.findEpisode(uuid: episodeUUID) else {
                    return
                }

                Task {
                    await OnDeviceTranscriptQueue.shared.enqueueDownloadedEpisode(episode)
                }
            }
        )

        observers.append(
            center.addObserver(forName: Constants.Notifications.episodeDownloaded, object: nil, queue: .main) { notification in
                guard let episodeUUID = notification.object as? String,
                      let episode = DataManager.sharedManager.findEpisode(uuid: episodeUUID) else {
                    return
                }

                Task {
                    await OnDeviceTranscriptQueue.shared.enqueueDownloadedEpisode(episode)
                }
            }
        )

        observers.append(
            center.addObserver(forName: Constants.Notifications.playbackTrackChanged, object: nil, queue: .main) { _ in
                guard let episode = PlaybackManager.shared.currentEpisode() as? Episode else {
                    return
                }

                Task {
                    await OnDeviceTranscriptQueue.shared.prioritizeEpisode(episode)
                }
            }
        )
    }

    private func bootstrapDownloadedEpisodes() {
        let query = "episodeStatus = \(DownloadStatus.downloaded.rawValue) ORDER BY lastDownloadAttemptDate DESC"
        let downloadedEpisodes = DataManager.sharedManager.findEpisodesWhere(customWhere: query, arguments: nil)

        Task {
            for episode in downloadedEpisodes {
                await enqueueDownloadedEpisode(episode)
            }

            if let currentEpisode = PlaybackManager.shared.currentEpisode() as? Episode {
                await prioritizeEpisode(currentEpisode)
            }
        }
    }

    // MARK: - Worker

    private func startWorkerIfNeeded() {
        guard workerTask == nil else { return }

        workerTask = Task { [weak self] in
            guard let self else { return }
            await self.processQueue()
        }
    }

    private func processQueue() async {
        while !Task.isCancelled {
            guard let entry = nextQueuedEntry() else {
                workerTask = nil
                return
            }

            await transcribe(entry)
        }

        workerTask = nil
    }

    private func nextQueuedEntry() -> Entry? {
        guard let nextEpisodeUUID = queuedEpisodeUUIDs.first,
              let entry = entries[nextEpisodeUUID] else {
            return nil
        }

        queuedEpisodeUUIDs.removeFirst()
        activeEpisodeUUID = nextEpisodeUUID
        return entry
    }

    private func transcribe(_ entry: Entry) async {
        guard #available(iOS 26.0, *) else {
            activeEpisodeUUID = nil
            await updateState(.unavailable, for: entry.episodeUUID, progress: 0, label: "")
            return
        }

        let service = OnDeviceTranscriptService()
        await updateState(.preparingAssets, for: entry.episodeUUID, progress: 0, label: "Preparing speech models…")

        do {
            let payload = try await service.transcribe(fileURL: entry.fileURL) { fraction, label in
                Task {
                    let state: OnDeviceTranscriptionState = fraction <= 0.5 ? .preparingAssets : .transcribing
                    await self.updateState(state, for: entry.episodeUUID, progress: fraction, label: label)
                }
            }

            activeEpisodeUUID = nil
            if var completedEntry = entries[entry.episodeUUID] {
                completedEntry.payload = payload
                entries[entry.episodeUUID] = completedEntry
                await publish(completedEntry, overridingState: .completed, progress: 1, label: "Transcription complete")
                await publishQueueState()
                await publishTranscriptLibrary()
            }
        } catch {
            activeEpisodeUUID = nil
            await updateState(.error(error.localizedDescription), for: entry.episodeUUID, progress: 0, label: "")
        }
    }

    private func updateState(_ state: OnDeviceTranscriptionState, for episodeUUID: String, progress: Double, label: String) async {
        guard var entry = entries[episodeUUID] else { return }
        entry.state = state
        entry.progress = progress
        entry.progressLabel = label
        entries[episodeUUID] = entry
        await publish(entry)
        await publishQueueState()
    }

    private func removeEpisode(_ episodeUUID: String) async {
        queuedEpisodeUUIDs.removeAll { $0 == episodeUUID }
        if activeEpisodeUUID == episodeUUID {
            activeEpisodeUUID = nil
        }
        entries.removeValue(forKey: episodeUUID)
        await MainActor.run {
            OnDeviceTranscriptQueueStore.shared.remove(episodeUUID: episodeUUID)
        }
        await publishQueueState()
        await publishTranscriptLibrary()
    }

    private func publish(
        _ entry: Entry,
        overridingState: OnDeviceTranscriptionState? = nil,
        progress: Double? = nil,
        label: String? = nil
    ) async {
        await MainActor.run {
            OnDeviceTranscriptQueueStore.shared.update(
                episodeUUID: entry.episodeUUID,
                state: overridingState ?? entry.state,
                progress: progress ?? entry.progress,
                progressLabel: label ?? entry.progressLabel,
                paragraphs: entry.payload?.paragraphs ?? []
            )
        }
    }

    private func publishQueueState() async {
        let activeItem = activeEpisodeUUID.flatMap { episodeUUID in
            entries[episodeUUID].map(queueItem(from:))
        }
        let queuedItems = queuedEpisodeUUIDs.compactMap { episodeUUID in
            entries[episodeUUID].map(queueItem(from:))
        }

        await MainActor.run {
            OnDeviceTranscriptQueueStore.shared.updateQueue(activeItem: activeItem, queuedItems: queuedItems)
        }
    }

    private func publishTranscriptLibrary() async {
        let items = entries.values
            .filter { entry in
                if case .completed = entry.state {
                    return entry.payload != nil
                }
                return false
            }
            .sorted { lhs, rhs in
                switch (lhs.publishedDate, rhs.publishedDate) {
                case let (lhsDate?, rhsDate?):
                    if lhsDate != rhsDate {
                        return lhsDate > rhsDate
                    }
                case (.some, nil):
                    return true
                case (nil, .some):
                    return false
                case (nil, nil):
                    break
                }

                return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
            }
            .map(transcriptLibraryItem(from:))

        await MainActor.run {
            OnDeviceTranscriptQueueStore.shared.updateTranscriptLibrary(items)
        }
    }

    private func queueItem(from entry: Entry) -> OnDeviceTranscriptQueueStore.QueueItem {
        OnDeviceTranscriptQueueStore.QueueItem(
            episodeUUID: entry.episodeUUID,
            title: entry.title,
            state: entry.state,
            progress: entry.progress,
            progressLabel: entry.progressLabel
        )
    }

    private func transcriptLibraryItem(from entry: Entry) -> OnDeviceTranscriptQueueStore.TranscriptLibraryItem {
        OnDeviceTranscriptQueueStore.TranscriptLibraryItem(
            episodeUUID: entry.episodeUUID,
            title: entry.title,
            podcastTitle: entry.podcastTitle,
            publishedDate: entry.publishedDate
        )
    }

    @available(iOS 26.0, *)
    private func loadCachedPayloadIfAvailable(for fileURL: URL) -> OnDeviceTranscriptPayload? {
        guard let audioHash = try? cache.audioHash(for: fileURL),
              let cached = try? cache.loadTranscript(forHash: audioHash) else {
            return nil
        }

        let words: [OnDeviceTranscriptWord] = cached.words.enumerated().map { index, word in
            OnDeviceTranscriptWord(
                id: index,
                text: word.text,
                displayText: word.displayText,
                startTime: word.startTime,
                duration: word.duration
            )
        }

        let rawResults: [OnDeviceRawTranscriptionResult] = cached.rawResults.enumerated().map { index, result in
            OnDeviceRawTranscriptionResult(
                id: index,
                text: result.text,
                rangeDescription: result.rangeDescription,
                finalizationDescription: result.finalizationDescription
            )
        }

        return OnDeviceTranscriptPayload(
            audioHash: cached.audioHash,
            words: words,
            paragraphs: OnDeviceTranscriptFormatter.paragraphs(from: words),
            rawResults: rawResults
        )
    }
}
