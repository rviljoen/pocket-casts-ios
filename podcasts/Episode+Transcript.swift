import Foundation
import PocketCastsDataModel
import PocketCastsUtils

extension Episode {
    func checkTranscriptAvailability() {
        Task {
            let metadata = try? await ShowInfoCoordinator.shared.loadTranscriptsMetadata(podcastUuid: parentIdentifier(), episodeUuid: uuid)
            let transcriptsAvailable = !(metadata?.transcripts.isEmpty ?? true)
            // Without one from the server, the transcript view makes one on this device.
            let canTranscribeOnDevice = !transcriptsAvailable && canBeTranscribedOnDevice
            guard metadata != nil || canTranscribeOnDevice else { return }

            let userInfo = [
                "episodeUuid": uuid,
                "isAvailable": transcriptsAvailable || canTranscribeOnDevice,
                "hasGeneratedTranscripts": metadata?.hasGeneratedTranscripts ?? false
            ]
            NotificationCenter.postOnMainThread(notification: Constants.Notifications.episodeTranscriptAvailabilityChanged, userInfo: userInfo)
        }
    }

    /// Whether the transcript view can make a transcript of this episode on the device: it's
    /// downloaded, on-device transcription is available, and its podcast isn't excluded from it.
    private var canBeTranscribedOnDevice: Bool {
        #if os(iOS) && !APPCLIP
        return LocalTranscripts.isSupported && !LocalTranscripts.isExcluded(self) && LocalTranscripts.localAudioURL(for: self) != nil
        #else
        return false
        #endif
    }
}
