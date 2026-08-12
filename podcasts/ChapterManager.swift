import Foundation
import PocketCastsServer
import PocketCastsDataModel
import PocketCastsUtils
import CoreMedia

enum ChapterOrigin {
    case podcastIndex
    case nativeMedia
    case generated
    case showNotes
    case llmShowNotes
    case unknown

    var analyticsDescription: String {
        switch self {
        case .generated:
            "generated"
        case .nativeMedia:
            "native_media"
        case .showNotes:
            "show_notes"
        case .llmShowNotes:
            "llm_show_notes"
        case .podcastIndex:
            "podcast_index"
        case .unknown:
            "unknown"
        }
    }
}

class ChapterManager {
    private var chapterParser = PodcastChapterParser()
    private var showInfoCoordinator: ShowInfoCoordinating
    private var chapters = [ChapterInfo]() {
        didSet {
            visibleChapters = chapters.filter { !$0.isHidden }
        }
    }
    private var visibleChapters = [ChapterInfo]()

    private var lastEpisodeUuid = ""

    var numberOfChaptersSkipped = 0
    private(set) var chaptersFromShowNotes = false

    var currentChapters = Chapters()

    var chaptersOrigin: ChapterOrigin = .unknown

    private var playableChapters: [ChapterInfo] {
        visibleChapters.filter { $0.isPlayable() }
    }

    init(
        chapterParser: PodcastChapterParser = PodcastChapterParser(),
        showInfoCoordinator: ShowInfoCoordinating = ShowInfoCoordinator.shared) {
        self.chapterParser = chapterParser
        self.showInfoCoordinator = showInfoCoordinator
    }

    func visibleChapterCount() -> Int {
        visibleChapters.count
    }

    func playableChapterCount() -> Int {
        playableChapters.count
    }

    func haveTriedToParseChaptersFor(episodeUuid: String?) -> Bool {
        lastEpisodeUuid == episodeUuid
    }

    func previousVisibleChapter() -> ChapterInfo? {
        guard let visibleChapter = currentChapters.visibleChapter else {
            return nil
        }
        let previousChapter: ChapterInfo?

        if let index = visibleChapters.firstIndex(of: visibleChapter) {
            previousChapter = visibleChapters.enumerated().filter { $0.offset < index && $0.element.isPlayable() }.map { $0.element }.last
        } else {
            previousChapter = nil
        }
        return previousChapter
    }

    func nextVisiblePlayableChapter() -> ChapterInfo? {
        guard let visibleChapter = currentChapters.visibleChapter else {
            return nil
        }
        let nextChapter: ChapterInfo?

        if let index = visibleChapters.firstIndex(of: visibleChapter) {
            nextChapter = visibleChapters.enumerated().first { $0.offset > index && $0.element.isPlayable() }.map { $0.element }
        } else {
            nextChapter = nil
        }
        return nextChapter
    }

    var lastChapter: ChapterInfo? {
        visibleChapters.last
    }

    func chapterAt(index: Int) -> ChapterInfo? {
        visibleChapters[safe: index]
    }

    func playableChapterAt(index: Int) -> ChapterInfo? {
        visibleChapters.filter({ $0.isPlayable() })[safe: index]
    }

    func index(for chapter: Chapters) -> Int? {
        guard let visibleChapter = chapter.visibleChapter else {
            return nil
        }

        return playableChapters.firstIndex(of: visibleChapter)
    }

    @discardableResult
    func updateCurrentChapter(time: TimeInterval) -> Bool {
        if chapters.isEmpty { return false }

        let chapters = chaptersForTime(time)
        let hasChanged = currentChapters != chapters

        if hasChanged {
            currentChapters = chapters
        }

        return hasChanged
    }

    func parseChapters(episode: BaseEpisode, duration: TimeInterval) {
        Task.detached { [weak self] in
            await self?.parseChapters(episode: episode, duration: duration)
        }
    }

    func parseChapters(episode: BaseEpisode, duration: TimeInterval) async {
        // store the last episode uuid we were asked to check chapters for, we use that below in case this method is called multiple times to not return old results
        lastEpisodeUuid = episode.uuid

        try? await parseLocalAndRemoteChapters(for: episode, duration: duration)
    }

    private func parseLocalAndRemoteChapters(for episode: BaseEpisode, duration: TimeInterval) async throws {
        // Parse chapters from the file and request external chapters
        async let fileChaptersAsync = loadChapters(for: episode, duration: duration)

        async let (podloveChaptersAsync, podcastIndexChaptersAsync, generatedChaptersAsync) = await
        showInfoCoordinator.loadChapters(podcastUuid: episode.parentIdentifier(), episodeUuid: episode.uuid)

        var chapters: [ChapterInfo]
        chaptersFromShowNotes = false
        // Clear the previous episode's origin up front: the loads below are async, and
        // until one of the branches sets a new value anything reading the origin (the
        // fingerprint seek gate, the header warning) would answer for the old episode.
        chaptersOrigin = .unknown

        do {
            let (fileChapters, podloveChapters, podcastIndexChapters, generatedChapters) = try await (fileChaptersAsync, podloveChaptersAsync, podcastIndexChaptersAsync, generatedChaptersAsync)

            // Prioritize embedded chapters, given for some shows it will take
            // into account dynamic ads
            if !fileChapters.isEmpty {
                chapters = fileChapters
                FileLog.shared.addMessage("ChapterManager: using file chapters")
                chaptersOrigin = .nativeMedia
            } else if let explicitChapters = parseExplicitChapters(podlove: podloveChapters, podcastIndex: podcastIndexChapters, duration: duration), !explicitChapters.isEmpty {
                chapters = explicitChapters
                FileLog.shared.addMessage("ChapterManager: using explicit chapters")
            } else if let llmChapters = await loadLLMChaptersLogged(for: episode, duration: duration), !llmChapters.isEmpty {
                // The creator's own show notes text takes priority over server-generated
                // chapters, since it's a first-party source rather than an inference.
                chapters = llmChapters
                chaptersFromShowNotes = true
                chaptersOrigin = .llmShowNotes
                FileLog.shared.addMessage("ChapterManager: using LLM-parsed chapters from show notes")
            } else if let generatedChapters, let parsedGeneratedChapters = parseServerGeneratedChapters(generatedChapters, duration: duration), !parsedGeneratedChapters.isEmpty {
                chapters = parsedGeneratedChapters
                FileLog.shared.addMessage("ChapterManager: using server-generated chapters")
            } else {
                chapters = []
                chaptersOrigin = .unknown
                FileLog.shared.addMessage("ChapterManager: failed. Displaying no chapters.")
            }
        } catch {
            chapters = await fileChaptersAsync
            chaptersOrigin = chapters.isEmpty ? .unknown : .nativeMedia
            FileLog.shared.addMessage("ChapterManager: using file chapters because there was an error retrieving external sources")
        }

        if lastEpisodeUuid == episode.uuid {
            handleChaptersLoaded(chapters, for: episode)
        }
    }

    /// Wraps `loadLLMChapters` so every way it can come back empty (no show notes,
    /// a thrown error, or a zero-chapter extraction) leaves a trace in the log —
    /// otherwise falling back to server-generated chapters looks identical to a bug.
    private func loadLLMChaptersLogged(for episode: BaseEpisode, duration: TimeInterval) async -> [ChapterInfo]? {
        do {
            let chapters = try await loadLLMChapters(for: episode, duration: duration)
            if chapters == nil {
                FileLog.shared.addMessage("ChapterManager: no LLM chapters (no usable show notes or empty extraction) for \(episode.uuid)")
            }
            return chapters
        } catch {
            FileLog.shared.addMessage("ChapterManager: LLM chapter extraction threw - \(error.localizedDescription)")
            return nil
        }
    }

    private func loadLLMChapters(for episode: BaseEpisode, duration: TimeInterval) async throws -> [ChapterInfo]? {
        let showNotes = try await showInfoCoordinator.loadShowNotes(podcastUuid: episode.parentIdentifier(), episodeUuid: episode.uuid)
        guard !showNotes.isEmpty, showNotes != CacheServerHandler.noShowNotesMessage else {
            return nil
        }

        let chapters = await LLMChapterService.shared.extractChapters(
            episodeUUID: episode.uuid,
            showNotes: showNotes,
            episodeTitle: episode.title,
            duration: duration
        )
        return chapters.isEmpty ? nil : chapters
    }

    private func loadChapters(for episode: BaseEpisode, duration: TimeInterval) async -> [ChapterInfo] {
        if episode.downloaded(pathFinder: DownloadManager.shared) {
            return await chapterParser.parseLocalFile(episode.pathToDownloadedFile(pathFinder: DownloadManager.shared), episodeDuration: duration)
        } else if let url = EpisodeManager.urlForEpisode(episode) {
            return await chapterParser.parseRemoteFile(url.absoluteString, episodeDuration: duration)
        }

        return []
    }

    private func parseExplicitChapters(podlove: [Episode.Metadata.EpisodeChapter]?, podcastIndex: [PodcastIndexChapter]?, duration: TimeInterval) -> [ChapterInfo]? {
        if let podcastIndex {
            chaptersOrigin = .podcastIndex
            return chapterParser.parsePodcastIndexChapters(podcastIndex, episodeDuration: duration)
        }

        if let podlove {
            chaptersOrigin = .showNotes
            return chapterParser.parsePodloveChapters(podlove, episodeDuration: duration)
        }

        return nil
    }

    private func parseServerGeneratedChapters(_ generated: [GeneratedChapter], duration: TimeInterval) -> [ChapterInfo]? {
        chaptersOrigin = .generated
        return chapterParser.parseGeneratedChapters(generated, episodeDuration: duration)
    }

    func clearChapterInfo() {
        lastEpisodeUuid = ""
        chapters.removeAll()
        chaptersFromShowNotes = false
        chaptersOrigin = .unknown
        currentChapters = Chapters()

        NotificationCenter.postOnMainThread(notification: Constants.Notifications.podcastChaptersDidUpdate)
    }

    func chaptersForTime(_ time: TimeInterval) -> Chapters {
        Chapters(chapters: chapters.filter { $0.startTime.seconds <= time && ($0.startTime.seconds + $0.duration) > time })
    }

    var chaptersAnalyticsProperties: [String: Any] {
        return ["origin": chaptersOrigin.analyticsDescription]
    }

    private func handleChaptersLoaded(_ chapters: [ChapterInfo], for episode: BaseEpisode) {
        self.chapters = chapters

        // Auto-deselect chapters containing any of the configured filter keywords (case insensitive)
        let keywords = Settings.chapterFilterKeywords()
        var hasAutoDeselected = false

        for chapter in self.chapters {
            for keyword in keywords {
                if chapter.title.localizedCaseInsensitiveContains(keyword) {
                    episode.deselect(chapterIndex: chapter.index)
                    hasAutoDeselected = true
                    break // No need to check other keywords for this chapter
                }
            }
        }

        // Save episode if we auto-deselected any chapters
        if hasAutoDeselected {
            episode.deselectedChaptersModified = TimeFormatter.currentUTCTimeInMillis()
            DataManager.sharedManager.save(episode: episode)
        }

        episode.deselectedChapters?
            .split(separator: ",")
            .compactMap { Int($0) }
            .forEach { self.chapters[safe: $0]?.shouldPlay = false }

        updateCurrentChapter(time: PlaybackManager.shared.currentTime())

        NotificationCenter.postOnMainThread(notification: Constants.Notifications.podcastChaptersDidUpdate)
    }
}
