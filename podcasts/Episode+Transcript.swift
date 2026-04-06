import PocketCastsDataModel

extension Episode {
    func checkTranscriptAvailability() {
        let isAvailable: Bool
        if #available(iOS 26.0, *) {
            isAvailable = downloaded(pathFinder: DownloadManager.shared) && OnDeviceTranscriptService.isSupported
        } else {
            isAvailable = false
        }

        let userInfo = [
            "episodeUuid": uuid,
            "isAvailable": isAvailable,
            "hasGeneratedTranscripts": false
        ] as [String: Any]
        NotificationCenter.postOnMainThread(notification: Constants.Notifications.episodeTranscriptAvailabilityChanged, userInfo: userInfo)
    }
}
