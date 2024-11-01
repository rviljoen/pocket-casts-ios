import Foundation
import PocketCastsDataModel
import PocketCastsUtils
import SwiftProtobuf

class RetrieveRatingsTask: ApiBaseTask {
    var completion: (([UserPodcastRating]?) -> Void)?

    var success: Bool = false

    private var convertedRatings = [UserPodcastRating]()

    private lazy var addRatingGroup: DispatchGroup = {
        let dispatchGroup = DispatchGroup()

        return dispatchGroup
    }()

    override func apiTokenAcquired(token: String) {
        let url = ServerConstants.Urls.api() + "user/podcast_rating/list"

        do {
            let (response, httpStatus) = getToServer(url: url, token: token)

            guard let responseData = response, httpStatus?.statusCode == ServerConstants.HttpConstants.ok else {
                completion?(nil)

                return
            }

            do {
                let serverRatings = try Api_PodcastRatingsResponse(serializedData: responseData).podcastRatings
                if serverRatings.count == 0 {
                    completion?(convertedRatings)

                    return
                }

                convertedRatings = serverRatings.map { rating in
                    UserPodcastRating(podcastRating: rating.podcastRating, podcastUuid: rating.podcastUuid, modifiedAt: rating.modifiedAt.date)
                }

                //TODO: Do comparison?

                DataManager.sharedManager.ratings.ratings = convertedRatings

                success = true

                completion?(convertedRatings)
            } catch {
                FileLog.shared.addMessage("Decoding ratings failed \(error.localizedDescription)")
                completion?(nil)
            }
        } catch {
            FileLog.shared.addMessage("retrieve ratings failed \(error.localizedDescription)")
            completion?(nil)
        }
    }

//    private func processRating(_ protoRating: Api_PodcastRating) {
//        // take the easy case first, do we have this episode locally?
//        if convertLocalEpisode(protoEpisode: protoEpisode) {
//            addRatingGroup.leave()
//
//            return
//        }
//
//        // we don't have the episode, see if we have the podcast
//        if let podcast = DataManager.sharedManager.findPodcast(uuid: protoEpisode.podcastUuid, includeUnsubscribed: true) {
//            // we do, so try and refresh it
//            ServerPodcastManager.shared.updatePodcastIfRequired(podcast: podcast) { [weak self] updated in
//                if updated {
//                    // the podcast was updated, try to convert the episode
//                    self?.convertLocalEpisode(protoEpisode: protoEpisode)
//                }
//
//                self?.addRatingGroup.leave()
//            }
//        } else {
//            // we don't, so try and add it
//            ServerPodcastManager.shared.addFromUuid(podcastUuid: protoEpisode.podcastUuid, subscribe: false) { [weak self] _ in
//                // this will convert the episode if we now have it, if we don't not much we can do
//                self?.convertLocalEpisode(protoEpisode: protoEpisode)
//                self?.addRatingGroup.leave()
//            }
//        }
//    }
//
//    @discardableResult
//    private func convertLocalEpisode(protoEpisode: Api_StarredEpisode) -> Bool {
//        guard let episode = DataManager.sharedManager.findEpisode(uuid: protoEpisode.uuid) else { return false }
//
//        // star this episode in case it's not locally
//        if !episode.keepEpisode || episode.starredModified != protoEpisode.starredModified {
//            DataManager.sharedManager.saveEpisode(starred: true, starredModified: protoEpisode.starredModified, episode: episode, updateSyncFlag: false)
//        }
//
//        convertedEpisodes.append(episode)
//
//        return true
//    }
}
