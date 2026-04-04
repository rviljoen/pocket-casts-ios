import Combine
import Foundation
import PocketCastsUtils

/// Drives the on-device transcript UI. Loads transcript data for a given episode,
/// and keeps `currentWordIndex` / `currentParagraphIndex` in sync with the player.
@MainActor
final class OnDeviceTranscriptViewModel: ObservableObject {

    @Published private(set) var state: OnDeviceTranscriptionState = .idle
    @Published private(set) var paragraphs: [OnDeviceTranscriptParagraph] = []
    @Published private(set) var words: [OnDeviceTranscriptWord] = []
    @Published private(set) var rawResults: [OnDeviceRawTranscriptionResult] = []
    @Published private(set) var progress: Double = 0
    @Published private(set) var progressLabel: String = ""
    @Published private(set) var currentWordIndex: Int? = nil
    @Published private(set) var currentParagraphIndex: Int? = nil

    private let playbackManager: TranscriptPlaybackManaging
    private var syncTimer: AnyCancellable?
    private var transcriptionTask: Task<Void, Never>?

    init(playbackManager: TranscriptPlaybackManaging) {
        self.playbackManager = playbackManager
    }

    deinit {
        transcriptionTask?.cancel()
    }

    // MARK: - Load

    func load(episodeFileURL: URL) {
        guard #available(iOS 26.0, *) else {
            state = .unavailable
            return
        }

        transcriptionTask?.cancel()
        transcriptionTask = Task {
            await runTranscription(fileURL: episodeFileURL)
        }
    }

    func cancel() {
        transcriptionTask?.cancel()
        transcriptionTask = nil
        stopSync()
    }

    // MARK: - Sync

    func startSync() {
        guard syncTimer == nil else { return }
        syncTimer = Timer.publish(every: 0.1, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.updateSyncPosition()
            }
    }

    func stopSync() {
        syncTimer?.cancel()
        syncTimer = nil
    }

    // MARK: - Paragraph seek

    func seek(to paragraph: OnDeviceTranscriptParagraph) {
        PlaybackManager.shared.seekTo(time: paragraph.startTime)
    }

    // MARK: - Private

    @available(iOS 26.0, *)
    private func runTranscription(fileURL: URL) async {
        let service = OnDeviceTranscriptService()

        do {
            state = .preparingAssets
            let payload = try await service.transcribe(fileURL: fileURL) { [weak self] fraction, label in
                guard let self else { return }
                self.progress = fraction
                self.progressLabel = label
                if fraction > 0 && fraction < 1 {
                    self.state = fraction < 0.5 ? .preparingAssets : .transcribing
                }
            }

            guard !Task.isCancelled else { return }

            words = payload.words
            paragraphs = payload.paragraphs
            rawResults = payload.rawResults
            state = .completed
            startSync()
        } catch {
            guard !Task.isCancelled else { return }
            state = .error(error.localizedDescription)
        }
    }

    private func updateSyncPosition() {
        let time = playbackManager.currentTime()
        guard time >= 0, !words.isEmpty else {
            currentWordIndex = nil
            currentParagraphIndex = nil
            return
        }

        if #available(iOS 26.0, *) {
            currentWordIndex = OnDeviceTranscriptFormatter.currentWordIndex(in: words, at: time)
        }

        if let wordIndex = currentWordIndex {
            let wordID = words[wordIndex].id
            currentParagraphIndex = paragraphs.firstIndex { $0.words.contains { $0.id == wordID } }
        } else {
            currentParagraphIndex = nil
        }
    }
}
