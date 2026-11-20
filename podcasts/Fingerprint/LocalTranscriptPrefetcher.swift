import AVFoundation
import Foundation
import PocketCastsDataModel
import PocketCastsUtils

/// Gets episodes ready before they're played: as soon as one finishes downloading, checks
/// whether its file has dynamically inserted ads (the podcast's own timed transcript, or else
/// the generated one, is a different length from it), and if so queues an on-device
/// transcript, then places the show notes chapters on it, so both are cached by the time the
/// episode plays. When the podcast's transcript matches, the chapters are placed on that.
///
/// An episode with no transcript at all (neither the podcast's nor a generated one) isn't
/// transcribed on download, since the server may still generate one. It's transcribed on
/// device when it starts playing, if there's still none by then.
///
/// Work only happens while the app runs, which includes the background while audio plays.
/// An episode whose transcription is cut short is picked up again when it plays.
final class LocalTranscriptPrefetcher: NSObject {
    static let shared = LocalTranscriptPrefetcher()

    private var isStarted = false
    /// The episode last checked when playback started, so resuming it doesn't check again.
    private var lastPlayedEpisodeUUID: String?

    func start() {
        guard !isStarted, LocalTranscripts.isSupported else { return }
        isStarted = true
        LocalTranscripts.loadIndex()
        NotificationCenter.default.addObserver(self, selector: #selector(episodeDownloaded(_:)), name: Constants.Notifications.episodeDownloaded, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(playbackStarted), name: Constants.Notifications.playbackStarted, object: nil)
    }

    @objc private func playbackStarted() {
        // Posted on the main queue.
        guard let episode = PlaybackManager.shared.currentEpisode,
              episode.uuid != lastPlayedEpisodeUUID else {
            return
        }
        lastPlayedEpisodeUUID = episode.uuid
        let episodeUUID = episode.uuid
        Task.detached(priority: .utility) {
            await Self.transcribeIfNoTranscript(episodeUUID: episodeUUID)
        }
    }

    /// Starts an on-device transcript of the episode that started playing, when it has no
    /// transcript at all. One with a transcript is handled where it's used: the player's
    /// chapters and the transcript view compare it with the file.
    private static func transcribeIfNoTranscript(episodeUUID: String) async {
        guard let episode = DataManager.shared.findBaseEpisode(uuid: episodeUUID),
              LocalTranscripts.localAudioURL(for: episode) != nil,
              LocalTranscripts.cachedTranscript(for: episode) == nil else {
            return
        }
        let transcriptManager = TranscriptManager(episodeUUID: episodeUUID, podcastUUID: episode.parentIdentifier())
        guard (try? await transcriptManager.loadTranscript()) == nil else { return }

        if case .transcribing = LocalTranscripts.onDeviceSource(for: episode) {
            log("\(episodeUUID) started playing with no transcript, transcribing it on device")
        }
    }

    @objc private func episodeDownloaded(_ notification: Notification) {
        guard let episodeUUID = notification.object as? String else { return }
        Task.detached(priority: .utility) {
            await Self.prepare(episodeUUID: episodeUUID)
        }
    }

    private static func prepare(episodeUUID: String) async {
        // Only podcast episodes have a generated transcript to compare with.
        guard let episode = DataManager.shared.findEpisode(uuid: episodeUUID),
              let audioURL = LocalTranscripts.localAudioURL(for: episode) else {
            return
        }

        // The file's own length, which includes any inserted ads; the feed's doesn't.
        guard let duration = try? await AVURLAsset(url: audioURL).load(.duration).seconds,
              duration.isFinite, duration > 0 else {
            log("couldn't read the length of \(episodeUUID)'s file")
            return
        }

        // A new episode may not have a generated transcript yet; then the check happens when
        // it plays.
        guard let reference = await ChapterManager.loadAlignmentReference(for: episode) else {
            log("no timed transcript for \(episodeUUID) yet, leaving it until it plays")
            return
        }
        let referenceName = reference.kind == .podcast ? "the podcast's transcript" : "its generated transcript"

        let needsMusic = LocalTranscripts.cachedTranscriptNeedsMusic(for: episode)
        let source = LocalTranscripts.source(replacing: reference.transcript, for: episode, audioDuration: duration, urgent: false) { succeeded in
            guard succeeded else { return }
            Task.detached(priority: .utility) {
                await precomputeChapters(episodeUUID: episodeUUID, duration: duration)
            }
        }

        switch source {
        case .server:
            log("\(episodeUUID) matches \(referenceName), no on-device transcript needed")
            // Topics placed on the podcast's transcript need no on-device one.
            if reference.kind == .podcast {
                await precomputeChapters(episodeUUID: episodeUUID, duration: duration)
            }
        case .transcribing:
            log("\(episodeUUID) has inserted ads, queued for on-device transcription")
        case .local:
            // When its music still needs detecting, that's queued and the chapters follow it.
            if !needsMusic {
                log("\(episodeUUID) already has an on-device transcript")
                await precomputeChapters(episodeUUID: episodeUUID, duration: duration)
            }
        }
    }

    /// Runs the chapter pipeline for the episode on a chapter manager of its own, which makes
    /// and caches the AI requests without touching what's playing.
    private static func precomputeChapters(episodeUUID: String, duration: TimeInterval) async {
        guard let episode = DataManager.shared.findEpisode(uuid: episodeUUID) else { return }
        log("precomputing chapters for \(episodeUUID)")
        await ChapterManager().precomputeLLMChapters(for: episode, duration: duration)
    }

    private static func log(_ message: String) {
        FileLog.shared.addMessage("LocalTranscriptPrefetcher [debug]: \(message)")
    }
}
