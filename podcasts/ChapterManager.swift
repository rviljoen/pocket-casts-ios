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
    /// Topics listed in the show notes without timestamps, placed on the generated
    /// transcript's timeline by the LLM.
    case llmTranscriptAligned
    /// Topics listed in the show notes without timestamps, placed by the LLM on an
    /// on-device transcript of the listener's own file, made because the generated
    /// transcript didn't match it (dynamic ads).
    case llmLocalTranscriptAligned
    case unknown

    /// Whether start times are on the generated transcript's reference timeline, which
    /// dynamic ads shift, so seeking should resolve the real position by fingerprinting.
    var usesReferenceTimeline: Bool {
        self == .generated || self == .llmTranscriptAligned
    }

    /// Whether the chapters came from the LLM reading the show notes.
    var isFromShowNotes: Bool {
        self == .llmShowNotes || isFromShowNotesTopics
    }

    /// Whether the chapters are show notes topics the LLM placed on a transcript, rather
    /// than timestamps written in the show notes.
    var isFromShowNotesTopics: Bool {
        self == .llmTranscriptAligned || self == .llmLocalTranscriptAligned
    }

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
        case .llmTranscriptAligned:
            "llm_transcript_aligned"
        case .llmLocalTranscriptAligned:
            "llm_local_transcript_aligned"
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

    var currentChapters = Chapters()

    var chaptersOrigin: ChapterOrigin = .unknown

    var chaptersFromShowNotes: Bool {
        chaptersOrigin.isFromShowNotes
    }

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

    #if !os(watchOS) && !os(tvOS) && !APPCLIP
    /// The visible chapters as headings for an on-device transcript, which is on the playback
    /// timeline. Empty when the chapters are on a reference timeline instead, since their
    /// times wouldn't line up with the transcript's.
    func chapterBreaksOnPlaybackTimeline() -> [LocalTranscripts.ChapterBreak] {
        guard !chaptersOrigin.usesReferenceTimeline else { return [] }
        return visibleChapters
            .filter { !$0.title.isEmpty }
            .map { LocalTranscripts.ChapterBreak(time: $0.startTime.seconds, title: $0.title) }
    }
    #endif

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
            } else if let llmChapters = await loadLLMChaptersLogged(for: episode, duration: duration, generatedChapters: generatedChapters), !llmChapters.chapters.isEmpty {
                // The creator's own show notes text takes priority over server-generated
                // chapters, since it's a first-party source rather than an inference.
                chapters = llmChapters.chapters
                chaptersOrigin = llmChapters.origin
                FileLog.shared.addMessage("ChapterManager: using LLM chapters from show notes (\(llmChapters.origin.analyticsDescription))")
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

    private typealias LLMChapters = (chapters: [ChapterInfo], origin: ChapterOrigin)

    /// Wraps `loadLLMChapters` so every way it can come back empty (no show notes,
    /// a thrown error, or a zero-chapter extraction) leaves a trace in the log —
    /// otherwise falling back to server-generated chapters looks identical to a bug.
    private func loadLLMChaptersLogged(for episode: BaseEpisode, duration: TimeInterval, generatedChapters: [GeneratedChapter]?) async -> LLMChapters? {
        #if !os(watchOS) && !os(tvOS) && !APPCLIP
        do {
            let chapters = try await loadLLMChapters(for: episode, duration: duration, generatedChapters: generatedChapters)
            if chapters == nil {
                FileLog.shared.addMessage("ChapterManager: no LLM chapters for \(episode.uuid)")
            }
            return chapters
        } catch {
            FileLog.shared.addMessage("ChapterManager: LLM chapter extraction threw - \(error.localizedDescription)")
            return nil
        }
        #else
        // LLM extraction is only compiled into the main app.
        return nil
        #endif
    }

    #if !os(watchOS) && !os(tvOS) && !APPCLIP
    /// Timestamped chapters from the show notes when there are any. Otherwise, when the
    /// show notes list the episode's topics and the server generated chapters for it, the
    /// topics placed on the generated transcript, which replace the generated chapters.
    private func loadLLMChapters(for episode: BaseEpisode, duration: TimeInterval, generatedChapters: [GeneratedChapter]?) async throws -> LLMChapters? {
        let podcastUuid = episode.parentIdentifier()
        let showNotes = try await showInfoCoordinator.loadShowNotes(podcastUuid: podcastUuid, episodeUuid: episode.uuid)
        guard !showNotes.isEmpty, showNotes != CacheServerHandler.noShowNotesMessage else {
            FileLog.shared.addMessage("ChapterManager: no usable show notes for \(episode.uuid)")
            return nil
        }

        let extraction = await LLMChapterService.shared.extractChapters(
            episodeUUID: episode.uuid,
            showNotes: showNotes,
            episodeTitle: episode.title,
            duration: duration
        )
        if !extraction.chapters.isEmpty {
            if let realigned = await realignShowNotesChapters(extraction.chapters, for: episode, duration: duration) {
                return realigned
            }
            return (extraction.chapters, .llmShowNotes)
        }

        // Only replace generated chapters: their existence means the server has a transcript
        // on the same reference timeline, and that AI chapters weren't turned off.
        guard extraction.topics.count >= LLMChapterService.minimumTopicCount,
              let generatedChapters, !generatedChapters.isEmpty else {
            FileLog.shared.addMessage("ChapterManager: show notes have no timestamps and \(extraction.topics.count) topics, generated chapters: \(generatedChapters?.count ?? 0)")
            return nil
        }

        guard let transcriptText = try await showInfoCoordinator.loadGeneratedTranscriptText(podcastUuid: podcastUuid, episodeUuid: episode.uuid),
              let serverTranscript = TranscriptModel.makeModel(from: transcriptText, format: .vtt),
              !serverTranscript.cues.isEmpty else {
            FileLog.shared.addMessage("ChapterManager: no generated transcript to align \(extraction.topics.count) show notes topics against")
            return nil
        }

        let (transcript, origin) = transcriptForAlignment(serverTranscript: serverTranscript, episode: episode, duration: duration)
        let aligned = await LLMChapterService.shared.alignTopics(
            episodeUUID: episode.uuid,
            topics: extraction.topics,
            transcript: transcript,
            transcriptSource: origin == .llmLocalTranscriptAligned ? "on-device" : "server-generated",
            episodeTitle: episode.title,
            duration: duration
        )
        return aligned.isEmpty ? nil : (aligned, origin)
    }

    /// Show notes timestamps are for the episode without dynamically inserted ads. When the
    /// listener's file has them (the generated transcript is a different length from it),
    /// every timestamp after an inserted ad is early, and the ads aren't chapters. Then the
    /// chapters are placed again on an on-device transcript of the file, by title with the
    /// timestamps as hints, which also finds the ads.
    ///
    /// Returns nil to keep the show notes timestamps: when the file matches the generated
    /// transcript, when there's no generated transcript to compare with, or while the
    /// on-device transcript is being made (the chapters reload once it's ready).
    private func realignShowNotesChapters(_ chapters: [ChapterInfo], for episode: BaseEpisode, duration: TimeInterval) async -> LLMChapters? {
        guard chapters.count >= LLMChapterService.minimumTopicCount else { return nil }

        guard let transcriptText = try? await showInfoCoordinator.loadGeneratedTranscriptText(podcastUuid: episode.parentIdentifier(), episodeUuid: episode.uuid),
              let serverTranscript = TranscriptModel.makeModel(from: transcriptText, format: .vtt),
              !serverTranscript.cues.isEmpty else {
            FileLog.shared.addMessage("ChapterManager [debug]: no generated transcript to check \(episode.uuid)'s show notes timestamps for inserted ads")
            return nil
        }

        let (transcript, origin) = transcriptForAlignment(serverTranscript: serverTranscript, episode: episode, duration: duration)
        guard origin == .llmLocalTranscriptAligned else { return nil }

        FileLog.shared.addMessage("ChapterManager [debug]: placing \(chapters.count) show notes chapters on the on-device transcript of \(episode.uuid)")
        let aligned = await LLMChapterService.shared.alignTopics(
            episodeUUID: episode.uuid,
            topics: chapters.map(\.title),
            topicHints: chapters.map(\.startTime.seconds),
            transcript: transcript,
            transcriptSource: "on-device",
            episodeTitle: episode.title,
            duration: duration
        )
        return aligned.isEmpty ? nil : (aligned, .llmLocalTranscriptAligned)
    }

    /// The transcript to place show notes topics on. The generated transcript is made from a
    /// reference copy of the audio without dynamically inserted ads; when the listener's file
    /// is a different length, it has them, and the generated transcript's times drift from
    /// it. Then an on-device transcript of the file is used instead, once one exists: until
    /// then the generated one is used, and a transcription starts in the background that
    /// reloads the chapters when it finishes.
    private func transcriptForAlignment(serverTranscript: TranscriptModel, episode: BaseEpisode, duration: TimeInterval) -> (TranscriptModel, ChapterOrigin) {
        let audioDuration = duration > 0 ? duration : episode.duration
        let source = LocalTranscripts.source(replacing: serverTranscript, for: episode, audioDuration: audioDuration) { [weak self] succeeded in
            guard succeeded else { return }
            DispatchQueue.main.async {
                // Reload only if the listener is still on this episode.
                guard let self, self.lastEpisodeUuid == episode.uuid else { return }
                FileLog.shared.addMessage("ChapterManager [debug]: on-device transcript ready, reloading chapters for \(episode.uuid)")
                self.parseChapters(episode: episode, duration: audioDuration)
            }
        }

        switch source {
        case .server:
            return (serverTranscript, .llmTranscriptAligned)
        case .local(let localTranscript):
            FileLog.shared.addMessage("ChapterManager [debug]: generated transcript doesn't match the audio, using the on-device transcript for \(episode.uuid)")
            return (localTranscript, .llmLocalTranscriptAligned)
        case .transcribing:
            FileLog.shared.addMessage("ChapterManager [debug]: generated transcript doesn't match the audio, transcribing \(episode.uuid) on device")
            return (serverTranscript, .llmTranscriptAligned)
        }
    }
    #endif

    private func loadChapters(for episode: BaseEpisode, duration: TimeInterval) async -> [ChapterInfo] {
        if episode.downloaded(pathFinder: DownloadManager.shared) {
            return await chapterParser.parseLocalFile(episode.pathToDownloadedFile(pathFinder: DownloadManager.shared), episodeDuration: duration)
        } else if let url = EpisodeManager.url(for: episode) {
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
        chaptersOrigin = .unknown
        currentChapters = Chapters()

        NotificationCenter.postOnMainThread(notification: Constants.Notifications.podcastChaptersDidUpdate)
    }

    func chaptersForTime(_ time: TimeInterval) -> Chapters {
        Chapters(chapters: chapters.filter { $0.startTime.seconds <= time && ($0.startTime.seconds + $0.duration) > time })
    }

    /// How much of the episode after `time` falls in deselected chapters, which playback skips.
    func deselectedDuration(after time: TimeInterval) -> TimeInterval {
        #if APPCLIP
        // The App Clip treats every chapter as unplayable, so it has nothing to subtract.
        return 0
        #else
        let ranges = visibleChapters
            .filter { !$0.isPlayable() }
            .map { (start: max(time, $0.startTime.seconds), end: $0.startTime.seconds + $0.duration) }
            .filter { $0.end > $0.start }
            .sorted { $0.start < $1.start }

        // Chapters can overlap, so count time shared by deselected chapters once.
        var total: TimeInterval = 0
        var coveredUntil = time
        for range in ranges where range.end > max(range.start, coveredUntil) {
            total += range.end - max(range.start, coveredUntil)
            coveredUntil = range.end
        }

        return total
        #endif
    }

    var chaptersAnalyticsProperties: [String: Any] {
        return ["origin": chaptersOrigin.analyticsDescription]
    }

    private func handleChaptersLoaded(_ chapters: [ChapterInfo], for episode: BaseEpisode) {
        self.chapters = chapters

        // Auto-deselect chapters containing any of the configured filter keywords (case insensitive)
        let keywords = Settings.chapterFilterKeywords()
        let previouslyDeselected = episode.deselectedChapters

        for chapter in self.chapters where keywords.contains(where: { chapter.title.localizedCaseInsensitiveContains($0) }) {
            episode.deselect(chapterIndex: chapter.index)
        }

        // Only save when the filter actually deselected something new, otherwise every
        // chapter load would bump the modified date and trigger another sync write.
        if episode.deselectedChapters != previouslyDeselected {
            episode.deselectedChaptersModified = TimeFormatter.currentUTCTimeInMillis()
            DataManager.shared.save(episode: episode)
        }

        episode.deselectedChapters?
            .split(separator: ",")
            .compactMap { Int($0) }
            .forEach { self.chapters[safe: $0]?.shouldPlay = false }

        updateCurrentChapter(time: PlaybackManager.shared.currentTime)

        NotificationCenter.postOnMainThread(notification: Constants.Notifications.podcastChaptersDidUpdate)
    }
}
