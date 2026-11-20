import Foundation
import PocketCastsDataModel
import PocketCastsServer
import PocketCastsUtils

/// Tracks each episode's server transcripts, for the episode rows: the podcast's own (from its
/// feed) once one has been downloaded, and the Pocket Casts generated one: whether the server
/// has made one, and whether it's being downloaded or already is.
///
/// Answers from memory, so rows can ask while scrolling. Downloaded podcast transcripts are
/// remembered across launches. Whether a generated transcript was downloaded in an earlier
/// launch is checked in the background the first time a row asks. Observers of
/// `LocalTranscripts.stateChangedNotification` hear about every change.
final class ServerTranscriptStatus: NSObject {
    static let shared = ServerTranscriptStatus()

    enum State: Equatable {
        /// The podcast's own transcript has been downloaded. The transcript view shows it
        /// instead of a generated one. `isTimed` is false for HTML or plain text.
        case podcast(isTimed: Bool)
        /// The server hasn't made one (yet).
        case notGenerated
        /// The server has one, which hasn't been downloaded, or is downloading now.
        case available
        /// Downloaded and cached on this device.
        case downloaded
    }

    private let lock = NSLock()
    private var loading: Set<String> = []
    private var downloaded: Set<String> = []
    /// Episodes whose cache has been checked, or is being checked.
    private var checked: Set<String> = []
    /// Episodes whose podcast transcript has been downloaded, and whether it has timings.
    private var podcastTranscripts: [String: Bool] = [:]
    private var isStarted = false

    private static let podcastTranscriptsKey = "ServerTranscriptStatusPodcastTranscripts"

    func start() {
        lock.lock()
        defer { lock.unlock() }
        guard !isStarted else { return }
        isStarted = true
        podcastTranscripts = UserDefaults.standard.dictionary(forKey: Self.podcastTranscriptsKey) as? [String: Bool] ?? [:]
        NotificationCenter.default.addObserver(self, selector: #selector(loadStateChanged(_:)), name: TranscriptsDataRetriever.loadStateChangedNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(transcriptLoaded(_:)), name: TranscriptManager.transcriptLoadedNotification, object: nil)
    }

    /// The episode's server transcript state: a downloaded podcast transcript first, since
    /// that's the one shown, then the generated one. Nil when there's nothing to show: it isn't
    /// a podcast episode, or there's no podcast transcript and generated transcripts are off
    /// or the server hasn't said.
    func state(for episode: BaseEpisode) -> State? {
        guard let episode = episode as? Episode else { return nil }

        lock.lock()
        let podcastTranscriptIsTimed = podcastTranscripts[episode.uuid]
        lock.unlock()
        if let podcastTranscriptIsTimed { return .podcast(isTimed: podcastTranscriptIsTimed) }

        guard FeatureFlag.generatedTranscripts.enabled else { return nil }

        lock.lock()
        let isDownloaded = downloaded.contains(episode.uuid)
        let needsCheck = !isDownloaded && episode.hasGeneratedTranscript == true && checked.insert(episode.uuid).inserted
        lock.unlock()

        if isDownloaded { return .downloaded }
        if needsCheck { checkCache(for: episode) }

        switch episode.hasGeneratedTranscript {
        case true?: return .available
        case false?: return .notGenerated
        case nil: return nil
        }
    }

    /// Whether the episode's generated transcript is downloading right now.
    func isLoading(_ episodeUUID: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return loading.contains(episodeUUID)
    }

    private func checkCache(for episode: Episode) {
        guard let url = Self.url(podcastUuid: episode.podcastUuid, episodeUuid: episode.uuid) else { return }
        let episodeUUID = episode.uuid
        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard TranscriptsDataRetriever.hasCachedTranscript(url: url) else { return }
            self?.update(episodeUUID) { $0.downloaded.insert(episodeUUID) }
        }
    }

    @objc private func transcriptLoaded(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let episodeUUID = userInfo[TranscriptManager.episodeUUIDKey] as? String,
              userInfo[TranscriptManager.isGeneratedKey] as? Bool == false,
              let isTimed = userInfo[TranscriptManager.isTimedKey] as? Bool else {
            return
        }

        lock.lock()
        let changed = podcastTranscripts[episodeUUID] != isTimed
        if changed {
            podcastTranscripts[episodeUUID] = isTimed
            UserDefaults.standard.set(podcastTranscripts, forKey: Self.podcastTranscriptsKey)
        }
        lock.unlock()

        if changed {
            NotificationCenter.postOnMainThread(notification: LocalTranscripts.stateChangedNotification, userInfo: [LocalTranscripts.episodeUUIDKey: episodeUUID])
        }
    }

    @objc private func loadStateChanged(_ notification: Notification) {
        guard let url = notification.userInfo?[TranscriptsDataRetriever.urlKey] as? URL,
              let episodeUUID = Self.episodeUUID(from: url) else {
            return
        }
        let loaded = notification.userInfo?[TranscriptsDataRetriever.loadedKey] as? Bool
        update(episodeUUID) { status in
            if let loaded {
                status.loading.remove(episodeUUID)
                if loaded {
                    status.downloaded.insert(episodeUUID)
                } else {
                    status.downloaded.remove(episodeUUID)
                }
            } else {
                status.loading.insert(episodeUUID)
            }
        }
    }

    private func update(_ episodeUUID: String, _ change: (ServerTranscriptStatus) -> Void) {
        lock.lock()
        change(self)
        lock.unlock()
        NotificationCenter.postOnMainThread(notification: LocalTranscripts.stateChangedNotification, userInfo: [LocalTranscripts.episodeUUIDKey: episodeUUID])
    }

    // MARK: - Generated transcript URLs

    static func url(podcastUuid: String, episodeUuid: String) -> URL? {
        URL(string: "\(ServerConstants.Urls.generatedTranscripts)\(podcastUuid)/\(episodeUuid).\(TranscriptFormat.vtt.fileExtension)")
    }

    /// The episode a generated transcript URL is for, or nil for any other transcript.
    private static func episodeUUID(from url: URL) -> String? {
        guard url.absoluteString.hasPrefix(ServerConstants.Urls.generatedTranscripts) else { return nil }
        return url.deletingPathExtension().lastPathComponent
    }
}
