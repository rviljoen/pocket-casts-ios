import Foundation
import PocketCastsDataModel
import SwiftUI
import UIKit

extension PodcastViewController: SwipeHandler {
    // MARK: - Swipe Actions

    func episodeSwipeActionsConfiguration(for edge: HorizontalEdge, at indexPath: IndexPath) -> UISwipeActionsConfiguration? {
        guard !isMultiSelectEnabled, indexPath.section == PodcastViewController.allEpisodesSection, let episode = episodeAtIndexPath(indexPath) else { return nil }

        let tableView = tableView()
        switch edge {
        case .leading:
            return SwipeActionsHelper.createLeftActionsForEpisode(episode, tableView: tableView, indexPath: indexPath, swipeHandler: self).swipeActions()
        case .trailing:
            return SwipeActionsHelper.createRightActionsForEpisode(episode, tableView: tableView, indexPath: indexPath, swipeHandler: self).swipeActions()
        }
    }

    // MARK: - SwipeActionsHandler

    var swipeSource: String {
        "podcast_details"
    }

    var swipeSourceType: SwipeSourceType {
        .podcast
    }

    func archivingRemovesFromList() -> Bool {
        !(podcast?.showArchived ?? false)
    }

    func tableView(_ tableView: UITableView, willBeginEditingRowAt indexPath: IndexPath) {
        isSwipingRow = true
        swipedIndexPath = indexPath
    }

    func tableView(_ tableView: UITableView, didEndEditingRowAt indexPath: IndexPath?) {
        isSwipingRow = false
        swipedIndexPath = nil
        guard needsEpisodeReloadAfterSwipe else { return }

        needsEpisodeReloadAfterSwipe = false
        refreshEpisodes()
    }

    func actionPerformed(willBeRemoved: Bool) {
        // Remove the row right away, as UIKit expects for a destructive swipe action. The full reload
        // (archived count, placeholders) waits for the swipe to end.
        if willBeRemoved, archivingRemovesFromList(), let swipedIndexPath {
            removeEpisodeRow(at: swipedIndexPath)
        }
        refreshEpisodes()
    }

    private func removeEpisodeRow(at indexPath: IndexPath) {
        guard indexPath.section == PodcastViewController.allEpisodesSection,
              episodeInfo.indices.contains(indexPath.section),
              episodeInfo[indexPath.section].elements.indices.contains(indexPath.row) else { return }

        episodeInfo[indexPath.section].elements.remove(at: indexPath.row)
        tableView().deleteRows(at: [indexPath], with: .automatic)
    }

    func deleteRequested(uuid: String) {} // we don't support this one

    func share(episode: Episode, at indexPath: IndexPath) {
        SharingHelper.shared.shareLinkTo(episode: episode, fromController: self, fromTableView: tableView(), at: indexPath)
    }

    func addToManualPlaylist(episode: Episode, at: IndexPath) {
        NavigationManager.shared.navigateTo(
            NavigationManager.manualPlaylistsChooserKey,
            data: [
                NavigationManager.manualPlaylistsChooserEpisodeKey: episode
            ]
        )
    }

    func removeFromManualPlaylist(episode: PocketCastsDataModel.Episode, at: IndexPath) { }
}
