import AVFoundation
import Foundation
import PocketCastsDataModel
import PocketCastsUtils
import SoundAnalysis
import Speech
import UIKit

/// On-device transcripts of the episode file the listener actually has.
///
/// The server-generated transcript is made from a reference copy of the audio, which doesn't
/// contain dynamically inserted ads. When the listener's file has them, every time after the
/// first inserted ad is off, and the ads themselves are invisible. A transcript of the
/// listener's own file fixes both: its times are on the playback timeline, and its text
/// includes the inserted ads.
///
/// Transcripts are made with `SpeechTranscriber` (iOS 26) from a downloaded file, and cached
/// per file, since a new download can carry different ads.
enum LocalTranscripts {
    /// The server transcript is treated as out of sync when it ends this much earlier (or
    /// later) than the audio. An outro of music or silence explains a small difference; an
    /// inserted ad is usually 30 seconds or more.
    static let durationMismatchThreshold: TimeInterval = 45

    static var isSupported: Bool {
        if #available(iOS 26.0, *) {
            return SpeechTranscriber.isAvailable
        }
        return false
    }

    /// Whether `serverTranscript` covers a noticeably different length of audio than the
    /// listener's file, which is what inserted ads cause.
    static func isOutOfSync(serverTranscript: TranscriptModel, audioDuration: TimeInterval) -> Bool {
        guard audioDuration > 0, let transcriptEnd = serverTranscript.cues.map(\.endTime).max() else {
            return false
        }
        let difference = audioDuration - transcriptEnd
        FileLog.shared.addMessage("LocalTranscripts [debug]: server transcript ends at \(Int(transcriptEnd))s, audio is \(Int(audioDuration))s (difference \(Int(difference))s)")
        return abs(difference) > durationMismatchThreshold
    }

    /// The complete local file for `episode`, or nil while it's only streaming. Transcribing
    /// needs the whole file.
    static func localAudioURL(for episode: BaseEpisode) -> URL? {
        if episode.downloaded(pathFinder: DownloadManager.shared) {
            return URL(fileURLWithPath: episode.pathToDownloadedFile(pathFinder: DownloadManager.shared))
        }
        if let episode = episode as? Episode, episode.streamDownloaded(pathFinder: DownloadManager.shared) {
            let path = DownloadManager.shared.streamingBufferPath(for: episode)
            if FileManager.default.fileExists(atPath: path) {
                return URL(fileURLWithPath: path)
            }
        }
        return nil
    }

    /// A chapter start to show as a heading in a transcript.
    struct ChapterBreak: Equatable, Sendable {
        let time: TimeInterval
        let title: String
    }

    /// The cached transcript of `episode`'s current local file, if one has been made, with a
    /// heading at each of `chapterBreaks`.
    static func cachedTranscript(for episode: BaseEpisode, chapterBreaks: [ChapterBreak] = []) -> TranscriptModel? {
        guard let audioURL = localAudioURL(for: episode),
              let cached = LocalTranscriptCache.load(episodeUUID: episode.uuid, audioURL: audioURL) else {
            return nil
        }
        var model = makeModel(from: cached.segments, chapterBreaks: chapterBreaks)
        model?.music = (cached.music ?? []).map { TranscriptMusic(range: $0.start...$0.end, confidence: $0.confidence, isBed: $0.isBed ?? false) }
        return model
    }

    /// Whether `episode`'s cached transcript has no music detection yet, or one from an older
    /// version of it.
    static func cachedTranscriptNeedsMusic(for episode: BaseEpisode) -> Bool {
        guard let audioURL = localAudioURL(for: episode),
              let cached = LocalTranscriptCache.load(episodeUUID: episode.uuid, audioURL: audioURL) else {
            return false
        }
        return cached.needsMusic
    }

    /// Which transcript to use in place of a server-generated one.
    enum Source {
        /// The server transcript matches the audio, or there's no way to replace it (or, for
        /// `onDeviceSource`, to make one).
        case server
        /// An on-device transcript of the listener's file.
        case local(TranscriptModel)
        /// The server transcript doesn't match the audio, and an on-device transcript is
        /// being made. Until it's ready, the server transcript is all there is.
        case transcribing
    }

    /// Picks the transcript to use instead of `serverTranscript` (a generated transcript, or
    /// a podcast's timed one, which is also cued against audio without inserted ads).
    /// When it doesn't match the audio and there's no cached on-device transcript yet, queues
    /// one, and calls `completion` once it's done with whether it succeeded. Progress is
    /// reported with `stateChangedNotification`.
    ///
    /// - Parameter urgent: Whether the episode is wanted now (it's playing, or its transcript
    ///   is open), which puts it at the front of the queue. Prefetching passes false.
    static func source(replacing serverTranscript: TranscriptModel,
                       for episode: BaseEpisode,
                       audioDuration: TimeInterval,
                       chapterBreaks: [ChapterBreak] = [],
                       urgent: Bool = true,
                       completion: (@Sendable (Bool) -> Void)? = nil) -> Source {
        let audioDuration = audioDuration > 0 ? audioDuration : episode.duration
        guard isOutOfSync(serverTranscript: serverTranscript, audioDuration: audioDuration) else {
            return .server
        }
        return onDeviceSource(for: episode, chapterBreaks: chapterBreaks, urgent: urgent, completion: completion)
    }

    /// The on-device transcript of `episode`'s file when one is cached, or else queues one
    /// like `source(replacing:)`. `.server` means one can't be made: on-device transcription
    /// isn't available, or the episode isn't downloaded.
    ///
    /// Called directly for an episode with no transcript at all, where there's nothing to
    /// compare the file with. Then only when it's wanted now (it's playing, or its transcript
    /// is open), never ahead of time: the server may still generate a transcript, which would
    /// make this one unnecessary.
    static func onDeviceSource(for episode: BaseEpisode,
                               chapterBreaks: [ChapterBreak] = [],
                               urgent: Bool = true,
                               completion: (@Sendable (Bool) -> Void)? = nil) -> Source {
        if let localTranscript = cachedTranscript(for: episode, chapterBreaks: chapterBreaks) {
            // A transcript cached before music detection is used as it is, and gets its music
            // detected in the background, calling `completion` once it has.
            if cachedTranscriptNeedsMusic(for: episode) {
                FileLog.shared.addMessage("LocalTranscripts [debug]: cached transcript of \(episode.uuid) has no current music detection, running it")
                transcribeInBackground(episode, urgent: urgent, completion: completion ?? { _ in })
            }
            return .local(localTranscript)
        }
        guard transcribeInBackground(episode, urgent: urgent, completion: completion ?? { _ in }) else {
            return .server
        }
        return .transcribing
    }

    // MARK: Progress

    /// Posted on the main queue when a transcription starts, progresses or ends. `userInfo`
    /// holds the episode's UUID under `episodeUUIDKey`, and once it ends, whether it
    /// succeeded under `succeededKey`.
    static let stateChangedNotification = Notification.Name("LocalTranscriptsStateChanged")
    static let episodeUUIDKey = "episodeUUID"
    static let succeededKey = "succeeded"

    /// How far through `episodeUUID`'s file the transcription is, from 0 to 1, or nil when it
    /// isn't being transcribed.
    static func progress(for episodeUUID: String) -> Double? {
        LocalTranscriptProgress.shared.fraction(for: episodeUUID)
    }

    /// Whether `episode` has a finished on-device transcript of its current file. Cheap enough
    /// for list rows: it answers from an index kept in memory, and says false until that's
    /// loaded (see `loadIndex`), which posts `stateChangedNotification` without an episode.
    static func hasTranscript(for episode: BaseEpisode) -> Bool {
        guard let cachedIdentity = LocalTranscriptIndex.shared.identity(for: episode.uuid),
              let audioURL = localAudioURL(for: episode) else {
            return false
        }
        return LocalTranscriptCache.identity(of: audioURL) == cachedIdentity
    }

    /// Loads the index `hasTranscript` answers from, in the background.
    static func loadIndex() {
        LocalTranscriptIndex.shared.loadInBackground()
    }

    /// Whether `episodeUUID` is waiting its turn to be transcribed.
    static func isQueued(_ episodeUUID: String) -> Bool {
        LocalTranscriptProgress.shared.isQueued(episodeUUID)
    }

    /// Queues `episode`'s local file for transcription unless it's already queued, then calls
    /// `completion` with whether a transcript was cached. Returns false, without calling
    /// `completion`, when on-device transcription or a local file isn't available.
    ///
    /// Transcriptions run one at a time, in the order queued, except that an `urgent` one
    /// goes to the front.
    @discardableResult
    static func transcribeInBackground(_ episode: BaseEpisode, urgent: Bool = true, completion: @escaping @Sendable (Bool) -> Void) -> Bool {
        guard #available(iOS 26.0, *), SpeechTranscriber.isAvailable else {
            FileLog.shared.addMessage("LocalTranscripts [debug]: on-device transcription isn't available")
            return false
        }
        guard let audioURL = localAudioURL(for: episode) else {
            FileLog.shared.addMessage("LocalTranscripts [debug]: \(episode.uuid) isn't downloaded, can't transcribe it")
            return false
        }
        let episodeUUID = episode.uuid
        Task.detached(priority: .utility) {
            let succeeded = await LocalTranscriber.shared.transcribe(episodeUUID: episodeUUID, audioURL: audioURL, urgent: urgent)
            completion(succeeded)
        }
        return true
    }

    /// A pause at least this long starts a new paragraph.
    private static let paragraphPause: TimeInterval = 1.5
    /// A paragraph this long ends at the next sentence end.
    private static let paragraphTargetDuration: TimeInterval = 30
    /// A paragraph this long ends at the next segment, sentence end or not.
    private static let paragraphMaxDuration: TimeInterval = 90

    /// Builds a transcript model whose cues are the transcriber's segments, so it can be used
    /// anywhere a parsed server transcript is. The transcriber gives no paragraphs, so they're
    /// made from pauses and length, and each chapter in `chapterBreaks` starts with its title
    /// as a heading. Headings are marked like speaker names, so they're styled as headings
    /// and left out of bookmark passages.
    fileprivate static func makeModel(from segments: [LocalTranscriptCache.Segment], chapterBreaks: [ChapterBreak] = []) -> TranscriptModel? {
        let text = NSMutableAttributedString()
        var cues: [TranscriptCue] = []
        var pendingBreaks = chapterBreaks.sorted { $0.time < $1.time }[...]
        var paragraphStart: TimeInterval?
        var previous: LocalTranscriptCache.Segment?

        for segment in segments {
            // The chapters that have started by this segment: only the last gets a heading,
            // the others had no text of their own.
            var heading: ChapterBreak?
            while let next = pendingBreaks.first, next.time <= segment.start + 0.5 {
                heading = next
                pendingBreaks.removeFirst()
            }

            if let heading {
                text.append(NSAttributedString(string: text.length > 0 ? "\n\n" : ""))
                text.append(NSAttributedString(string: heading.title, attributes: [.transcriptSpeaker: heading.title, .transcriptChapter: heading.title]))
                text.append(NSAttributedString(string: "\n"))
                paragraphStart = segment.start
            } else if let previous, let start = paragraphStart {
                let pause = segment.start - previous.end
                let length = previous.end - start
                let endsSentence = previous.text.last.map { ".?!".contains($0) } ?? false
                if pause >= paragraphPause || length >= paragraphMaxDuration || (endsSentence && length >= paragraphTargetDuration) {
                    text.append(NSAttributedString(string: "\n"))
                    paragraphStart = segment.start
                } else {
                    text.append(NSAttributedString(string: " "))
                }
            } else {
                paragraphStart = segment.start
            }

            let piece = NSAttributedString(string: segment.text)
            cues.append(TranscriptCue(startTime: segment.start, endTime: segment.end, characterRange: NSRange(location: text.length, length: piece.length)))
            text.append(piece)
            previous = segment
        }
        guard !cues.isEmpty else { return nil }
        return TranscriptModel(attributedText: text, cues: cues, type: TranscriptFormat.vtt.rawValue, hasJavascript: false)
    }
}

// MARK: - Transcription

@available(iOS 26.0, *)
private actor LocalTranscriber {
    static let shared = LocalTranscriber()

    /// One episode waiting for, or getting, its transcription. Everyone who asked for it waits
    /// on `result`.
    private final class Job: @unchecked Sendable {
        let episodeUUID: String
        let audioURL: URL
        let queuedAt = Date()
        let result: Task<Bool, Never>
        private let continuation: AsyncStream<Bool>.Continuation

        init(episodeUUID: String, audioURL: URL) {
            self.episodeUUID = episodeUUID
            self.audioURL = audioURL
            let (stream, continuation) = AsyncStream<Bool>.makeStream()
            self.continuation = continuation
            result = Task {
                for await succeeded in stream {
                    return succeeded
                }
                return false
            }
        }

        func finish(succeeded: Bool) {
            continuation.yield(succeeded)
            continuation.finish()
        }
    }

    /// Transcriptions run one at a time: each is heavy, and running two would only slow both.
    private var running: Job?
    private var pending: [Job] = []

    func transcribe(episodeUUID: String, audioURL: URL, urgent: Bool) async -> Bool {
        let job: Job
        if let running, running.episodeUUID == episodeUUID {
            job = running
        } else if let index = pending.firstIndex(where: { $0.episodeUUID == episodeUUID }) {
            job = pending[index]
            if urgent, index > 0 {
                pending.remove(at: index)
                pending.insert(job, at: 0)
                FileLog.shared.addMessage("LocalTranscripts [debug]: \(episodeUUID) is wanted now, moved to the front of the queue")
            }
        } else {
            job = Job(episodeUUID: episodeUUID, audioURL: audioURL)
            if urgent {
                pending.insert(job, at: 0)
            } else {
                pending.append(job)
            }
            LocalTranscriptProgress.shared.queue(episodeUUID: episodeUUID)
            let ahead = (running == nil ? 0 : 1) + (pending.firstIndex { $0 === job } ?? 0)
            FileLog.shared.addMessage("LocalTranscripts [debug]: queued \(episodeUUID) for transcription (\(urgent ? "wanted now" : "prefetch"), \(ahead) ahead of it)")
        }
        startNextIfIdle()
        return await job.result.value
    }

    private func startNextIfIdle() {
        guard running == nil, !pending.isEmpty else { return }
        let job = pending.removeFirst()
        running = job
        LocalTranscriptProgress.shared.start(episodeUUID: job.episodeUUID)
        let waited = Date().timeIntervalSince(job.queuedAt)
        if waited >= 1 {
            FileLog.shared.addMessage("LocalTranscripts [debug]: starting \(job.episodeUUID) after \(Int(waited))s in the queue, \(pending.count) still queued")
        }
        Task {
            let succeeded = await Self.transcribeAndCache(episodeUUID: job.episodeUUID, audioURL: job.audioURL)
            await self.finished(job, succeeded: succeeded)
        }
    }

    private func finished(_ job: Job, succeeded: Bool) {
        LocalTranscriptProgress.shared.finish(episodeUUID: job.episodeUUID, succeeded: succeeded)
        job.finish(succeeded: succeeded)
        running = nil
        startNextIfIdle()
    }

    /// Share of the progress bar given to transcription when music detection follows it.
    private static let transcriptionProgressShare = 0.9

    /// Transcribes the file and detects its music, caching both. A transcript cached before
    /// music detection was added only gets its music detected.
    private static func transcribeAndCache(episodeUUID: String, audioURL: URL) async -> Bool {
        if let cached = LocalTranscriptCache.load(episodeUUID: episodeUUID, audioURL: audioURL), !cached.needsMusic {
            return true
        }
        let report: @Sendable (Double) -> Void = { fraction in
            LocalTranscriptProgress.shared.update(episodeUUID: episodeUUID, fraction: fraction)
        }

        let segments: [LocalTranscriptCache.Segment]
        let musicProgress: @Sendable (Double) -> Void
        if let cached = LocalTranscriptCache.load(episodeUUID: episodeUUID, audioURL: audioURL), cached.needsMusic {
            segments = cached.segments
            musicProgress = report
        } else {
            do {
                let started = Date()
                segments = try await run(audioURL: audioURL) { report($0 * transcriptionProgressShare) }
                guard !segments.isEmpty else {
                    FileLog.shared.addMessage("LocalTranscripts [debug]: transcription of \(episodeUUID) produced no text")
                    return false
                }
                let audioEnd = segments.last?.end ?? 0
                let state = await MainActor.run { Self.appStateDescription() }
                FileLog.shared.addMessage("LocalTranscripts [debug]: transcribed \(Int(audioEnd))s of \(episodeUUID) into \(segments.count) segments in \(Int(Date().timeIntervalSince(started)))s (app now \(state))")
            } catch {
                FileLog.shared.addMessage("LocalTranscripts [debug]: transcription of \(episodeUUID) failed - \(error.localizedDescription)")
                return false
            }
            musicProgress = { report(transcriptionProgressShare + $0 * (1 - transcriptionProgressShare)) }
        }

        // Music is an extra hint, so a failure still caches the transcript, with no music, and
        // isn't retried.
        let music: [LocalTranscriptCache.MusicRange]
        do {
            music = try await MusicDetector.detect(in: audioURL, episodeUUID: episodeUUID, onProgress: musicProgress)
        } catch {
            FileLog.shared.addMessage("LocalTranscripts [debug]: music detection of \(episodeUUID) failed - \(error.localizedDescription)")
            music = []
        }

        LocalTranscriptCache.save(LocalTranscriptCache.Entry(episodeUUID: episodeUUID, audioURL: audioURL, segments: segments, music: music))
        return true
    }

    /// Whether the app is in the foreground and audio is playing, to see from the logs how
    /// transcriptions fare while the app is in the background.
    @MainActor
    private static func appStateDescription() -> String {
        let foreground = UIApplication.shared.applicationState == .active ? "in the foreground" : "in the background"
        let playing = PlaybackManager.shared.isPlaying ? "playing" : "not playing"
        return "\(foreground), \(playing)"
    }

    private enum TranscriptionError: LocalizedError {
        case unsupportedLocale

        var errorDescription: String? {
            switch self {
            case .unsupportedLocale: "no supported transcription locale"
            }
        }
    }

    /// Transcribes the file, calling `onProgress` with how far through it the results have
    /// reached, from 0 to 1.
    private static func run(audioURL: URL, onProgress: @escaping @Sendable (Double) -> Void) async throws -> [LocalTranscriptCache.Segment] {
        // Episodes don't carry a language, so use the device's, falling back to US English.
        var supportedLocale = await SpeechTranscriber.supportedLocale(equivalentTo: .current)
        if supportedLocale == nil {
            supportedLocale = await SpeechTranscriber.supportedLocale(equivalentTo: Locale(identifier: "en-US"))
        }
        guard let locale = supportedLocale else {
            throw TranscriptionError.unsupportedLocale
        }
        FileLog.shared.addMessage("LocalTranscripts [debug]: transcribing \(audioURL.lastPathComponent) in \(locale.identifier)")

        // Final results only, with a time range on every run of text so long results can
        // be split into short timed segments.
        let transcriber = SpeechTranscriber(locale: locale, transcriptionOptions: [], reportingOptions: [], attributeOptions: [.audioTimeRange])

        // The language model is a system asset that may need downloading the first time.
        if let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
            FileLog.shared.addMessage("LocalTranscripts [debug]: downloading speech assets for \(locale.identifier)")
            try await request.downloadAndInstall()
        }

        let audioFile = try AVAudioFile(forReading: audioURL)
        let sampleRate = audioFile.processingFormat.sampleRate
        let fileDuration = sampleRate > 0 ? Double(audioFile.length) / sampleRate : 0

        // Results arrive in order while the file is analyzed, so collect them concurrently,
        // and use how far they've reached as the progress.
        let collector = Task<[LocalTranscriptCache.Segment], Error> {
            var segments: [LocalTranscriptCache.Segment] = []
            for try await result in transcriber.results {
                segments += Self.segments(from: result)
                if fileDuration > 0 {
                    onProgress(min(1, result.range.end.seconds / fileDuration))
                }
            }
            return segments
        }

        let analyzer = SpeechAnalyzer(modules: [transcriber])
        do {
            if let lastSample = try await analyzer.analyzeSequence(from: audioFile) {
                try await analyzer.finalizeAndFinish(through: lastSample)
            } else {
                await analyzer.cancelAndFinishNow()
            }
        } catch {
            await analyzer.cancelAndFinishNow()
            collector.cancel()
            throw error
        }

        return try await collector.value.sorted { $0.start < $1.start }
    }

    /// Segments longer than this are split, so chapter and ad boundaries placed on the
    /// transcript stay precise.
    private static let maxSegmentDuration: TimeInterval = 5

    /// Splits a result into segments of up to `maxSegmentDuration`, breaking early at the end
    /// of a sentence, using the time range on each run of its text. A result without
    /// per-run times becomes one segment.
    private static func segments(from result: SpeechTranscriber.Result) -> [LocalTranscriptCache.Segment] {
        var segments: [LocalTranscriptCache.Segment] = []
        var text = ""
        var start: TimeInterval?
        var end: TimeInterval = 0

        func flush() {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if let start, !trimmed.isEmpty {
                segments.append(LocalTranscriptCache.Segment(start: start, end: end, text: trimmed))
            }
            text = ""
            start = nil
        }

        for run in result.text.runs {
            let runText = String(result.text[run.range].characters)
            text += runText
            guard let range = run.audioTimeRange else { continue }

            let runStart = start ?? range.start.seconds
            start = runStart
            end = range.end.seconds
            let endsSentence = runText.trimmingCharacters(in: .whitespaces).last.map { ".?!".contains($0) } ?? false
            if endsSentence || end - runStart >= maxSegmentDuration {
                flush()
            }
        }
        flush()

        if segments.isEmpty {
            let whole = String(result.text.characters).trimmingCharacters(in: .whitespacesAndNewlines)
            if !whole.isEmpty {
                segments.append(LocalTranscriptCache.Segment(start: result.range.start.seconds, end: result.range.end.seconds, text: whole))
            }
        }
        return segments
    }
}

// MARK: - Music detection

/// Finds music in an episode file with SoundAnalysis' built-in sound classifier: jingles
/// between segments, and the music beds ads are often read over, which both mark boundaries.
@available(iOS 26.0, *)
private enum MusicDetector {
    /// Analysis window, and how much consecutive windows overlap. Shorter windows place a
    /// boundary more precisely but are noisier.
    private static let windowDuration: TimeInterval = 1.5
    private static let overlapFactor = 0.5

    /// Music comes in two kinds, told apart separately:
    ///
    /// - Jingles and stings: music in its own right, possibly with a host over it. The
    ///   confidence, averaged over `smoothingWindows`, stays at `musicConfidence` or more.
    /// - Beds: quiet music under speech, typical of ads. Speech drowns it out, so the
    ///   confidence only flickers above `bedWindowConfidence`, but much more often than in
    ///   plain talk: at least `bedDensity` of the windows around each point.
    private static let smoothingWindows = 5
    private static let musicConfidence = 0.45
    private static let musicEdgeConfidence = 0.35
    private static let musicMergeGap: TimeInterval = 5
    private static let musicMinimumDuration: TimeInterval = 2

    private static let bedWindowConfidence = 0.15
    private static let bedDensityWindows = 13
    private static let bedDensity = 0.35
    private static let bedMergeGap: TimeInterval = 12
    private static let bedMinimumDuration: TimeInterval = 8

    static func detect(in audioURL: URL, episodeUUID: String, onProgress: @escaping @Sendable (Double) -> Void) async throws -> [LocalTranscriptCache.MusicRange] {
        let started = Date()
        let analyzer = try SNAudioFileAnalyzer(url: audioURL)
        let request = try SNClassifySoundRequest(classifierIdentifier: .version1)
        request.overlapFactor = overlapFactor
        let window = CMTime(seconds: windowDuration, preferredTimescale: 1000)
        switch request.windowDurationConstraint {
        case .durationRange(let range) where range.containsTime(window):
            request.windowDuration = window
        case .enumeratedDurations(let durations):
            if let closest = durations.min(by: { abs($0.seconds - windowDuration) < abs($1.seconds - windowDuration) }) {
                request.windowDuration = closest
            }
        default:
            break
        }

        let fileDuration = (try? AVAudioFile(forReading: audioURL)).map { Double($0.length) / $0.processingFormat.sampleRate } ?? 0
        let observer = MusicObserver(fileDuration: fileDuration, onProgress: onProgress)
        try analyzer.add(request, withObserver: observer)
        let completed = await withCheckedContinuation { continuation in
            analyzer.analyze { continuation.resume(returning: $0) }
        }
        if let error = observer.error {
            throw error
        }

        let ranges = stretches(from: observer.windows)
        let total = ranges.filter { $0.isBed != true }.reduce(0) { $0 + $1.end - $1.start }
        let bedTotal = ranges.filter { $0.isBed == true }.reduce(0) { $0 + $1.end - $1.start }
        FileLog.shared.addMessage("LocalTranscripts [debug]: music detection of \(episodeUUID) took \(String(format: "%.1f", Date().timeIntervalSince(started)))s for \(Int(fileDuration))s of audio (window \(String(format: "%.2f", request.windowDuration.seconds))s, completed: \(completed)): \(ranges.filter { $0.isBed != true }.count) music stretches (\(Int(total))s), \(ranges.filter { $0.isBed == true }.count) beds under speech (\(Int(bedTotal))s)")
        #if DEBUG
        logTimeline(observer.windows)
        for range in ranges {
            FileLog.shared.console("LocalTranscripts [debug] | \(range.isBed == true ? "bed  " : "music") \(Self.timestamp(range.start))-\(Self.timestamp(range.end)) (\(Int(range.end - range.start))s), confidence average \(Self.percent(range.confidence)), lowest \(Self.percent(range.minimumConfidence))")
        }
        #endif
        return ranges
    }

    /// Finds the music stretches and beds in the windows (see `musicConfidence` and
    /// `bedDensity`), sorted by start.
    private static func stretches(from windows: [MusicObserver.Window]) -> [LocalTranscriptCache.MusicRange] {
        let windows = windows.sorted { $0.start < $1.start }
        guard !windows.isEmpty else { return [] }
        let confidences = windows.map(\.confidence)

        // Music: where the smoothed confidence is high, with each end trimmed back to a window
        // that's confident on its own, since smoothing blurs the edges.
        let smoothed = movingAverage(confidences, width: smoothingWindows)
        let music = runs(where: { smoothed[$0] >= musicConfidence }, count: windows.count)
            .compactMap { run -> ClosedRange<Int>? in
                var lower = run.lowerBound
                var upper = run.upperBound
                while lower < upper, confidences[lower] < musicEdgeConfidence { lower += 1 }
                while upper > lower, confidences[upper] < musicEdgeConfidence { upper -= 1 }
                return lower...upper
            }
        let musicRuns = merge(music, in: windows, gap: musicMergeGap, minimumDuration: musicMinimumDuration)

        // Beds: where windows above the bed confidence are dense, outside the music, trimmed
        // to the first and last such window.
        let isMusic = Set(musicRuns.flatMap { Array($0) })
        let flickers = confidences.map { $0 >= bedWindowConfidence ? 1.0 : 0.0 }
        let density = movingAverage(flickers, width: bedDensityWindows)
        let beds = runs(where: { density[$0] >= bedDensity && !isMusic.contains($0) }, count: windows.count)
            .compactMap { run -> ClosedRange<Int>? in
                guard let lower = run.first(where: { flickers[$0] > 0 }),
                      let upper = run.last(where: { flickers[$0] > 0 }) else { return nil }
                return lower...upper
            }
        let bedRuns = merge(beds, in: windows, gap: bedMergeGap, minimumDuration: bedMinimumDuration, barrier: isMusic)

        func range(_ run: ClosedRange<Int>, isBed: Bool) -> LocalTranscriptCache.MusicRange {
            let values = confidences[run]
            return LocalTranscriptCache.MusicRange(
                start: windows[run.lowerBound].start,
                end: windows[run.upperBound].end,
                isBed: isBed,
                confidence: values.reduce(0, +) / Double(values.count),
                minimumConfidence: values.min()
            )
        }
        return (musicRuns.map { range($0, isBed: false) } + bedRuns.map { range($0, isBed: true) })
            .sorted { $0.start < $1.start }
    }

    /// Each value averaged with its neighbours, `width` values in all.
    private static func movingAverage(_ values: [Double], width: Int) -> [Double] {
        let half = width / 2
        return values.indices.map { index in
            let neighbours = values[max(0, index - half)...min(values.count - 1, index + half)]
            return neighbours.reduce(0, +) / Double(neighbours.count)
        }
    }

    /// The runs of consecutive indices where `isIncluded` holds.
    private static func runs(where isIncluded: (Int) -> Bool, count: Int) -> [ClosedRange<Int>] {
        var runs: [ClosedRange<Int>] = []
        var start: Int?
        for index in 0..<count {
            if isIncluded(index) {
                start = start ?? index
            } else if let runStart = start {
                runs.append(runStart...(index - 1))
                start = nil
            }
        }
        if let start {
            runs.append(start...(count - 1))
        }
        return runs
    }

    /// Joins runs less than `gap` apart, unless a window in `barrier` is between them, then
    /// drops runs shorter than `minimumDuration`.
    private static func merge(_ runs: [ClosedRange<Int>], in windows: [MusicObserver.Window], gap: TimeInterval, minimumDuration: TimeInterval, barrier: Set<Int> = []) -> [ClosedRange<Int>] {
        var merged: [ClosedRange<Int>] = []
        for run in runs {
            if let last = merged.last,
               windows[run.lowerBound].start - windows[last.upperBound].end <= gap,
               !(last.upperBound..<run.lowerBound).contains(where: { barrier.contains($0) }) {
                merged[merged.count - 1] = last.lowerBound...run.upperBound
            } else {
                merged.append(run)
            }
        }
        return merged.filter { windows[$0.upperBound].end - windows[$0.lowerBound].start >= minimumDuration }
    }

    /// Seconds of audio per timeline line in the debug output.
    private static let timelineLineDuration: TimeInterval = 15

    /// Logs every window's music confidence as a bar from ▁ (0%) to █ (100%), one console
    /// line per `timelineLineDuration`, to compare with where the music really is. Windows
    /// below `bedWindowConfidence` are drawn as · so the stretches stand out.
    private static func logTimeline(_ windows: [MusicObserver.Window]) {
        let bars: [Character] = ["▁", "▂", "▃", "▄", "▅", "▆", "▇", "█"]
        let windows = windows.sorted { $0.start < $1.start }
        FileLog.shared.console("LocalTranscripts [debug]: music confidence timeline (each bar is one window, ▁ 0% to █ 100%, · below \(percent(bedWindowConfidence)); music at \(percent(musicConfidence)) averaged over \(smoothingWindows) windows, bed at \(percent(bedDensity)) of \(bedDensityWindows) windows above \(percent(bedWindowConfidence)))")
        var lineStart: TimeInterval = 0
        var line = ""
        var peak = 0.0
        func flush() {
            guard !line.isEmpty else { return }
            FileLog.shared.console("LocalTranscripts [debug] | \(timestamp(lineStart)) \(line)  peak \(percent(peak))")
            line = ""
            peak = 0
        }
        for window in windows {
            if window.start >= lineStart + timelineLineDuration {
                flush()
                lineStart = (window.start / timelineLineDuration).rounded(.down) * timelineLineDuration
            }
            let level = min(bars.count - 1, Int(window.confidence * Double(bars.count)))
            line.append(window.confidence >= bedWindowConfidence ? bars[level] : "·")
            peak = max(peak, window.confidence)
        }
        flush()
    }

    private static func percent(_ confidence: Double?) -> String {
        confidence.map { "\(Int(($0 * 100).rounded()))%" } ?? "?"
    }

    private static func timestamp(_ seconds: TimeInterval) -> String {
        let total = Int(seconds)
        return String(format: "%d:%02d:%02d", total / 3600, (total % 3600) / 60, total % 60)
    }
}

/// Collects every analysis window with its music confidence. Called on SoundAnalysis' own queue,
/// and only read once the analysis has finished.
private final class MusicObserver: NSObject, SNResultsObserving, @unchecked Sendable {
    struct Window {
        let start: TimeInterval
        let end: TimeInterval
        /// How confident the classifier is that the window is music.
        let confidence: Double
    }

    private let fileDuration: TimeInterval
    private let onProgress: @Sendable (Double) -> Void
    private var lastReportedPercent = -1

    private(set) var windows: [Window] = []
    private(set) var error: Error?

    init(fileDuration: TimeInterval, onProgress: @escaping @Sendable (Double) -> Void) {
        self.fileDuration = fileDuration
        self.onProgress = onProgress
    }

    func request(_ request: SNRequest, didProduce result: SNResult) {
        guard let result = result as? SNClassificationResult else { return }
        let start = result.timeRange.start.seconds
        let end = start + result.timeRange.duration.seconds
        windows.append(Window(start: start, end: end, confidence: result.classification(forIdentifier: "music")?.confidence ?? 0))
        if fileDuration > 0 {
            let percent = Int(min(1, end / fileDuration) * 100)
            if percent > lastReportedPercent {
                lastReportedPercent = percent
                onProgress(Double(percent) / 100)
            }
        }
    }

    func request(_ request: SNRequest, didFailWithError error: Error) {
        self.error = error
    }
}

// MARK: - Progress

/// The transcription queue's state: what's waiting, what's running and how far it's got.
/// Readable from any thread, so the transcript view can show it without waiting on the
/// transcriber.
private final class LocalTranscriptProgress: @unchecked Sendable {
    static let shared = LocalTranscriptProgress()

    private let lock = NSLock()
    private var queued: [String] = []
    private var current: (episodeUUID: String, fraction: Double)?

    func fraction(for episodeUUID: String) -> Double? {
        lock.withLock {
            current?.episodeUUID == episodeUUID ? current?.fraction : nil
        }
    }

    func isQueued(_ episodeUUID: String) -> Bool {
        lock.withLock { queued.contains(episodeUUID) }
    }

    func queue(episodeUUID: String) {
        lock.withLock {
            if current?.episodeUUID != episodeUUID, !queued.contains(episodeUUID) {
                queued.append(episodeUUID)
            }
        }
        post(episodeUUID: episodeUUID)
    }

    func start(episodeUUID: String) {
        lock.withLock {
            queued.removeAll { $0 == episodeUUID }
            current = (episodeUUID, 0)
        }
        post(episodeUUID: episodeUUID)
    }

    /// Records progress, notifying only when it moves by at least a whole percent.
    func update(episodeUUID: String, fraction: Double) {
        let changed: Bool = lock.withLock {
            guard let current, current.episodeUUID == episodeUUID,
                  Int(fraction * 100) > Int(current.fraction * 100) else {
                return false
            }
            self.current = (episodeUUID, fraction)
            return true
        }
        if changed {
            post(episodeUUID: episodeUUID)
        }
    }

    func finish(episodeUUID: String, succeeded: Bool) {
        lock.withLock {
            queued.removeAll { $0 == episodeUUID }
            if current?.episodeUUID == episodeUUID {
                current = nil
            }
        }
        post(episodeUUID: episodeUUID, succeeded: succeeded)
    }

    private func post(episodeUUID: String, succeeded: Bool? = nil) {
        DispatchQueue.main.async {
            var userInfo: [String: Any] = [LocalTranscripts.episodeUUIDKey: episodeUUID]
            if let succeeded {
                userInfo[LocalTranscripts.succeededKey] = succeeded
            }
            NotificationCenter.default.post(name: LocalTranscripts.stateChangedNotification, object: nil, userInfo: userInfo)
        }
    }
}

// MARK: - Index

/// Which episodes have a cached transcript, and of which file, kept in memory so list rows
/// can show it without reading transcripts from disk.
private final class LocalTranscriptIndex: @unchecked Sendable {
    static let shared = LocalTranscriptIndex()

    private let lock = NSLock()
    private var identities: [String: String] = [:]
    private var isLoading = false

    func identity(for episodeUUID: String) -> String? {
        lock.withLock { identities[episodeUUID] }
    }

    func record(episodeUUID: String, identity: String) {
        lock.withLock { identities[episodeUUID] = identity }
    }

    func loadInBackground() {
        let shouldLoad: Bool = lock.withLock {
            guard !isLoading else { return false }
            isLoading = true
            return true
        }
        guard shouldLoad else { return }

        DispatchQueue.global(qos: .utility).async {
            let loaded = LocalTranscriptCache.allIdentities()
            self.lock.withLock {
                // Entries saved while loading are newer than what's on disk was read as.
                self.identities.merge(loaded) { current, _ in current }
            }
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: LocalTranscripts.stateChangedNotification, object: nil)
            }
        }
    }
}

// MARK: - Cache

/// Local transcripts on disk, one per episode, valid only for the exact file they were made
/// from (matched by size and modification date).
private enum LocalTranscriptCache {
    struct Segment: Codable {
        let start: TimeInterval
        let end: TimeInterval
        let text: String
    }

    struct MusicRange: Codable {
        let start: TimeInterval
        let end: TimeInterval
        /// Whether this is music in its own right or a bed under speech. Optional so entries
        /// cached before it was recorded still decode, as music.
        let isBed: Bool?
        /// The music classification confidence over the stretch: its average and its
        /// lowest window. Optional so entries cached before it was recorded still decode.
        let confidence: Double?
        let minimumConfidence: Double?
    }

    /// Bump when music detection changes, so cached music is detected again.
    static let musicVersion = 5

    struct Entry: Codable {
        let episodeUUID: String
        let audioFileIdentity: String
        let segments: [Segment]
        /// Where music was detected. Nil for entries cached before music detection was added,
        /// which get it run on their next use.
        let music: [MusicRange]?
        let musicVersion: Int?

        /// Whether music needs detecting (again): never run, or run by an older version.
        var needsMusic: Bool {
            music == nil || musicVersion != LocalTranscriptCache.musicVersion
        }

        init(episodeUUID: String, audioURL: URL, segments: [Segment], music: [MusicRange]) {
            self.episodeUUID = episodeUUID
            audioFileIdentity = LocalTranscriptCache.identity(of: audioURL) ?? ""
            self.segments = segments
            self.music = music
            musicVersion = LocalTranscriptCache.musicVersion
        }
    }

    static func load(episodeUUID: String, audioURL: URL) -> Entry? {
        guard let identity = identity(of: audioURL),
              let fileURL = try? cacheFileURL(for: episodeUUID),
              let data = try? Data(contentsOf: fileURL),
              let entry = try? JSONDecoder().decode(Entry.self, from: data),
              entry.audioFileIdentity == identity else {
            return nil
        }
        return entry
    }

    static func save(_ entry: Entry) {
        guard let fileURL = try? cacheFileURL(for: entry.episodeUUID),
              let data = try? JSONEncoder().encode(entry) else {
            return
        }
        try? data.write(to: fileURL, options: .atomic)
        LocalTranscriptIndex.shared.record(episodeUUID: entry.episodeUUID, identity: entry.audioFileIdentity)
    }

    /// The cached entries' episodes and the file each was made from, without their segments.
    static func allIdentities() -> [String: String] {
        struct Header: Decodable {
            let episodeUUID: String
            let audioFileIdentity: String
        }
        guard let directory = try? cacheFileURL(for: "x").deletingLastPathComponent(),
              let files = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) else {
            return [:]
        }
        var identities: [String: String] = [:]
        for file in files where file.pathExtension == "json" {
            guard let data = try? Data(contentsOf: file),
                  let header = try? JSONDecoder().decode(Header.self, from: data) else { continue }
            identities[header.episodeUUID] = header.audioFileIdentity
        }
        return identities
    }

    /// Size and modification date: a re-download, which may carry different ads, changes both.
    static func identity(of audioURL: URL) -> String? {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: audioURL.path),
              let size = attributes[.size] as? NSNumber,
              let modified = attributes[.modificationDate] as? Date else {
            return nil
        }
        return "\(size.int64Value)-\(Int(modified.timeIntervalSince1970))"
    }

    private static func cacheFileURL(for episodeUUID: String) throws -> URL {
        let fileManager = FileManager.default
        let directory = try fileManager.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appendingPathComponent("PocketCasts", isDirectory: true)
            .appendingPathComponent("LocalTranscripts", isDirectory: true)
        if !fileManager.fileExists(atPath: directory.path) {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        return directory.appendingPathComponent("\(episodeUUID).json")
    }
}
