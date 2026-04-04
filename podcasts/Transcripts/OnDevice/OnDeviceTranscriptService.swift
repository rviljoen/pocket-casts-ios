import AVFAudio
import CoreMedia
import Foundation
import Speech

/// Handles asset preparation, the SpeechAnalyzer pipeline, caching, and
/// progress reporting. All public methods are async and safe to call from any context.
@available(iOS 26.0, *)
actor OnDeviceTranscriptService {

    private let cache = OnDeviceTranscriptCache()

    // MARK: - Public API

    /// Transcribes the audio file at `fileURL`, using a cached result if available.
    /// Progress is reported via the `onProgress` closure on the main actor.
    func transcribe(
        fileURL: URL,
        onProgress: @MainActor @escaping (Double, String) -> Void
    ) async throws -> OnDeviceTranscriptPayload {
        let audioHash = try cache.audioHash(for: fileURL)

        if let cached = try cache.loadTranscript(forHash: audioHash) {
            await onProgress(1.0, "Loaded from cache")
            return payloadFromCache(cached)
        }

        let locale = await resolvedLocale()
        let transcriber = SpeechTranscriber(
            locale: locale,
            transcriptionOptions: [],
            reportingOptions: [],
            attributeOptions: [.audioTimeRange]
        )

        try await prepareAssets(for: transcriber, onProgress: onProgress)

        await onProgress(0, "Analyzing audio…")

        let audioFile = try AVAudioFile(forReading: fileURL)
        let audioDuration = duration(of: audioFile)

        let analyzer = SpeechAnalyzer(
            modules: [transcriber],
            options: .init(priority: .userInitiated, modelRetention: .whileInUse)
        )

        try await prepareAnalyzer(analyzer, format: audioFile.processingFormat, onProgress: onProgress)

        var words: [OnDeviceTranscriptWord] = []
        var rawResults: [OnDeviceRawTranscriptionResult] = []

        async let resultsTask: Void = collectResults(
            from: transcriber,
            audioDuration: audioDuration,
            words: &words,
            rawResults: &rawResults,
            onProgress: onProgress
        )

        if let lastSample = try await analyzer.analyzeSequence(from: audioFile) {
            try await analyzer.finalizeAndFinish(through: lastSample)
        } else {
            await analyzer.cancelAndFinishNow()
        }

        try await resultsTask

        guard !words.isEmpty else {
            throw OnDeviceTranscriptionError.emptyTranscript
        }

        let paragraphs = OnDeviceTranscriptFormatter.paragraphs(from: words)
        let payload = OnDeviceTranscriptPayload(
            audioHash: audioHash,
            words: words,
            paragraphs: paragraphs,
            rawResults: rawResults
        )

        try saveToCache(payload)
        await onProgress(1.0, "Transcription complete")
        return payload
    }

    /// Returns true if on-device transcription is supported on this device.
    static var isSupported: Bool {
        SpeechTranscriber.isAvailable
    }

    // MARK: - Private

    private func resolvedLocale() async -> Locale {
        if let locale = await SpeechTranscriber.supportedLocale(equivalentTo: .current) {
            return locale
        }
        let english = Locale(identifier: "en-US")
        if let locale = await SpeechTranscriber.supportedLocale(equivalentTo: english) {
            return locale
        }
        return await SpeechTranscriber.supportedLocales.first ?? english
    }

    private func prepareAssets(
        for transcriber: SpeechTranscriber,
        onProgress: @MainActor @escaping (Double, String) -> Void
    ) async throws {
        guard SpeechTranscriber.isAvailable else {
            throw OnDeviceTranscriptionError.unavailable
        }

        await onProgress(0, "Preparing speech models…")

        let modules: [any SpeechModule] = [transcriber]
        let status = await AssetInventory.status(forModules: modules)

        switch status {
        case .installed:
            return
        case .supported, .downloading:
            if let request = try await AssetInventory.assetInstallationRequest(supporting: modules) {
                try await request.downloadAndInstall()
            }
            guard await AssetInventory.status(forModules: modules) == .installed else {
                throw OnDeviceTranscriptionError.assetsNotInstalled
            }
        case .unsupported:
            throw OnDeviceTranscriptionError.unsupportedLocale(transcriber.selectedLocales.first)
        @unknown default:
            throw OnDeviceTranscriptionError.unknownAssetStatus
        }
    }

    private func prepareAnalyzer(
        _ analyzer: SpeechAnalyzer,
        format: AVAudioFormat,
        onProgress: @MainActor @escaping (Double, String) -> Void
    ) async throws {
        try await analyzer.prepareToAnalyze(in: format) { progress in
            let fraction = max(0, min(progress.fractionCompleted, 1))
            Task { @MainActor in
                onProgress(fraction * 0.5, fraction < 1 ? "Preparing speech models…" : "Starting transcription…")
            }
        }
    }

    private func collectResults(
        from transcriber: SpeechTranscriber,
        audioDuration: TimeInterval?,
        words: inout [OnDeviceTranscriptWord],
        rawResults: inout [OnDeviceRawTranscriptionResult],
        onProgress: @MainActor @escaping (Double, String) -> Void
    ) async throws {
        var collectedWords: [OnDeviceTranscriptWord] = []
        var collectedRaw: [OnDeviceRawTranscriptionResult] = []
        var nextWordID = 0
        var nextRawID = 0

        for try await result in transcriber.results {
            guard result.isFinal else { continue }

            collectedRaw.append(OnDeviceRawTranscriptionResult(
                id: nextRawID,
                text: String(result.text.characters),
                rangeDescription: formatRange(result.range),
                finalizationDescription: formatTime(CMTimeGetSeconds(result.resultsFinalizationTime))
            ))
            nextRawID += 1

            let newWords = OnDeviceTranscriptFormatter.words(
                from: result.text,
                fallbackRange: result.range,
                startingAt: nextWordID
            )
            collectedWords.append(contentsOf: newWords)
            nextWordID += newWords.count

            if let audioDuration, audioDuration > 0 {
                let end = CMTimeGetSeconds(result.range.start) + CMTimeGetSeconds(result.range.duration)
                let fraction = 0.5 + max(0, min(end / audioDuration, 1)) * 0.5
                await onProgress(fraction, "Transcribing audio…")
            }
        }

        words = collectedWords
        rawResults = collectedRaw
    }

    private func saveToCache(_ payload: OnDeviceTranscriptPayload) throws {
        let cached = CachedOnDeviceTranscript(
            audioHash: payload.audioHash,
            words: payload.words.map {
                CachedOnDeviceTranscriptWord(
                    text: $0.text,
                    displayText: $0.displayText,
                    startTime: $0.startTime,
                    duration: $0.duration
                )
            },
            rawResults: payload.rawResults.map {
                CachedOnDeviceRawResult(
                    text: $0.text,
                    rangeDescription: $0.rangeDescription,
                    finalizationDescription: $0.finalizationDescription
                )
            }
        )
        try cache.saveTranscript(cached)
    }

    private func payloadFromCache(_ cached: CachedOnDeviceTranscript) -> OnDeviceTranscriptPayload {
        let words: [OnDeviceTranscriptWord] = cached.words.enumerated().map { index, w in
            OnDeviceTranscriptWord(id: index, text: w.text, displayText: w.displayText,
                                   startTime: w.startTime, duration: w.duration)
        }
        let rawResults: [OnDeviceRawTranscriptionResult] = cached.rawResults.enumerated().map { index, r in
            OnDeviceRawTranscriptionResult(id: index, text: r.text,
                                           rangeDescription: r.rangeDescription,
                                           finalizationDescription: r.finalizationDescription)
        }
        return OnDeviceTranscriptPayload(
            audioHash: cached.audioHash,
            words: words,
            paragraphs: OnDeviceTranscriptFormatter.paragraphs(from: words),
            rawResults: rawResults
        )
    }

    private func duration(of audioFile: AVAudioFile) -> TimeInterval? {
        let rate = audioFile.processingFormat.sampleRate
        guard rate > 0 else { return nil }
        return Double(audioFile.length) / rate
    }

    private func formatRange(_ range: CMTimeRange) -> String {
        let start = CMTimeGetSeconds(range.start)
        let end = start + CMTimeGetSeconds(range.duration)
        return "\(formatTime(start)) – \(formatTime(end))"
    }

    private func formatTime(_ time: TimeInterval) -> String {
        let t = max(0, Int(time))
        let h = t / 3600
        let m = (t % 3600) / 60
        let s = t % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }
}

// MARK: - Errors

@available(iOS 26.0, *)
enum OnDeviceTranscriptionError: LocalizedError {
    case unavailable
    case unsupportedLocale(Locale?)
    case assetsNotInstalled
    case emptyTranscript
    case unknownAssetStatus

    var errorDescription: String? {
        switch self {
        case .unavailable:
            return "On-device transcription is not available on this device."
        case .unsupportedLocale(let locale):
            if let id = locale?.identifier {
                return "No speech assets available for \(id)."
            }
            return "No speech assets available for the current locale."
        case .assetsNotInstalled:
            return "The required speech assets could not be installed."
        case .emptyTranscript:
            return "Transcription completed but returned no timed words."
        case .unknownAssetStatus:
            return "Could not determine speech asset status."
        }
    }
}
