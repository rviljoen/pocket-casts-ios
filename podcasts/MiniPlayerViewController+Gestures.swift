import Foundation
import PocketCastsDataModel
import PocketCastsUtils

extension MiniPlayerViewController: UIGestureRecognizerDelegate {
    private static let minMoveAmount = 80 as CGFloat

    func addGestureRecognizers() {
        longPressRecognizer = UILongPressGestureRecognizer(target: self, action: #selector(miniPlayerLongPressed(_:)))
        longPressRecognizer.delegate = self
        view.addGestureRecognizer(longPressRecognizer)

        panUpRecognizer = UIPanGestureRecognizer(target: self, action: #selector(handlePullingUpGesture(_:)))
        panUpRecognizer.delegate = self
        view.addGestureRecognizer(panUpRecognizer)

        let miniPlayerTap = UITapGestureRecognizer(target: self, action: #selector(miniPlayerTapped))
        miniPlayerTap.require(toFail: panUpRecognizer)
        miniPlayerTap.require(toFail: longPressRecognizer)
        view.addGestureRecognizer(miniPlayerTap)
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        true
    }

    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        if gestureRecognizer != panUpRecognizer { return true }

        if playerOpenState == .animating { return false } // don't allow dragging until the player has finished an existing animation

        let velocity = panUpRecognizer.velocity(in: view)

        // Only recognize upward swipes (negative y velocity)
        return velocity.y < 0 && abs(velocity.y) > abs(velocity.x)
    }

    @objc private func handlePullingUpGesture(_ recognizer: UIPanGestureRecognizer) {
        // Open the full screen player as soon as the upward swipe is recognized,
        // rather than waiting for the gesture to end. This makes the transition
        // feel immediate and responsive.
        if recognizer.state == .began {
            openFullScreenPlayer()
        }
    }

    @objc private func miniPlayerLongPressed(_ recognizer: UIGestureRecognizer) {
        if recognizer.state == UIGestureRecognizer.State.began {
            showLongPressMenu(recognizer.location(in: view.superview))
        }
    }

    private func showLongPressMenu(_ touchPoint: CGPoint) {
        Analytics.track(.miniPlayerLongPressMenuShown)

        let alertController = UIAlertController(title: nil, message: nil, preferredStyle: .actionSheet)

        let markAsPlayedAction = UIAlertAction(title: L10n.markPlayedShort, style: .default) { _ in
            Analytics.track(.miniPlayerLongPressMenuOptionTapped, properties: ["option": "mark_played"])
            if let episode = PlaybackManager.shared.currentEpisode() {
                AnalyticsEpisodeHelper.shared.currentSource = self.analyticsSource
                EpisodeManager.markAsPlayed(episode: episode, fireNotification: true)
            }
        }
        alertController.addAction(markAsPlayedAction)

        let archiveAction = UIAlertAction(title: L10n.archive, style: .default) { _ in
            if let episode = PlaybackManager.shared.currentEpisode() {
                AnalyticsEpisodeHelper.shared.currentSource = self.analyticsSource
                EpisodeManager.archiveEpisode(episode: episode as! Episode, fireNotification: true)
            }
        }
        alertController.addAction(archiveAction)

        let closeAction = UIAlertAction(title: L10n.miniPlayerClose, style: .destructive) { _ in
            Analytics.track(.miniPlayerLongPressMenuOptionTapped, properties: ["option": "close_and_clear_up_next"])

            FileLog.shared.addMessage("Close and Clear Up Next pressed from the mini player")
            self.removeAllCustomObservers()

            self.hideMiniPlayer(true)
            PlaybackManager.shared.endPlayback()

            self.addUINotificationObservers()
        }
        alertController.addAction(closeAction)

        let cancelAction = UIAlertAction(title: L10n.cancel, style: .cancel) { _ in
            Analytics.track(.miniPlayerLongPressMenuDismissed)
        }
        alertController.addAction(cancelAction)

        alertController.popoverPresentationController?.sourceView = view
        alertController.popoverPresentationController?.sourceRect = CGRect(origin: touchPoint, size: .zero)

        present(alertController, animated: true)
    }

    @objc private func miniPlayerTapped() {
        openFullScreenPlayer()
    }
}
