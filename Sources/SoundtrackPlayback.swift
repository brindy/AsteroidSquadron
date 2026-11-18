import AppKit
import AVFoundation
import UniformTypeIdentifiers

// Keep a user-selected security scope alive while either decoder is reading it.
private final class SoundtrackFile {
    let url: URL
    private let hasSecurityScope: Bool

    init(url: URL) {
        self.url = url
        hasSecurityScope = url.startAccessingSecurityScopedResource()
    }

    deinit {
        if hasSecurityScope { url.stopAccessingSecurityScopedResource() }
    }
}

// The app owns this controller on the main thread. Only file preparation runs
// on the worker queue, before the new player is handed over to the controller.
final class SoundtrackPlayback: NSObject, AVAudioPlayerDelegate {
    struct Track {
        let id = UUID()
        let url: URL
        let analysis: SoundtrackAnalysis
        let duration: TimeInterval
    }

    private struct PreparedTrack {
        let info: Track
        let source: SoundtrackFile
        let player: AVAudioPlayer
    }

    private enum PlaybackError: LocalizedError {
        case invalidAudio, cannotPlay

        var errorDescription: String? {
            switch self {
            case .invalidAudio: return "Choose a local audio file with a playable track."
            case .cannotPlay: return "The soundtrack could not be played."
            }
        }
    }

    private let worker: OperationQueue = {
        let queue = OperationQueue()
        queue.name = "dev.brindy.asteroid-squadron.soundtrack"
        queue.qualityOfService = .userInitiated
        queue.maxConcurrentOperationCount = 1
        return queue
    }()
    private var pendingLoad: Operation?
    private var prepared: PreparedTrack?
    private var wantsPlayback = false

    private(set) var loadingURL: URL?
    var onChange: (() -> Void)?
    var onError: ((URL, Error) -> Void)?

    var track: Track? { prepared?.info }
    var isPlaying: Bool { prepared?.player.isPlaying ?? false }
    var position: TimeInterval? { prepared?.player.currentTime }

    deinit { worker.cancelAllOperations() }

    static func openPanel() -> NSOpenPanel {
        let panel = NSOpenPanel()
        panel.title = "Choose a Soundtrack"
        panel.prompt = "Choose"
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.audio]
        return panel
    }

    func load(url: URL) {
        pendingLoad?.cancel()
        let operation = BlockOperation()
        pendingLoad = operation
        loadingURL = url
        onChange?()

        operation.addExecutionBlock { [weak self, weak operation] in
            guard let operation, !operation.isCancelled else { return }
            let result = Result {
                guard url.isFileURL else { throw PlaybackError.invalidAudio }
                let source = SoundtrackFile(url: url)
                let player = try AVAudioPlayer(contentsOf: source.url)
                guard player.duration.isFinite, player.duration > 0 else { throw PlaybackError.invalidAudio }
                player.numberOfLoops = -1
                player.volume = 0.65
                let analysis = try SoundtrackAnalysis.analyze(url: source.url, isCancelled: { operation.isCancelled })
                let info = Track(url: source.url, analysis: analysis, duration: player.duration)
                return PreparedTrack(info: info, source: source, player: player)
            }
            guard !operation.isCancelled else { return }
            DispatchQueue.main.async { [weak self, weak operation] in
                guard let self, let operation, self.pendingLoad === operation, !operation.isCancelled else { return }
                self.finishLoading(result, url: url)
            }
        }
        worker.addOperation(operation)
    }

    func clear() {
        guard pendingLoad != nil || prepared != nil else { return }
        pendingLoad?.cancel()
        pendingLoad = nil
        loadingURL = nil
        discardPlayer()
        onChange?()
    }

    func setPlaying(_ playing: Bool) {
        wantsPlayback = playing
        guard let player = prepared?.player, player.isPlaying != playing else { return }
        if playing {
            if !player.play() { reportPlaybackFailure(player, error: PlaybackError.cannotPlay) }
        } else {
            player.pause()
        }
    }

    private func finishLoading(_ result: Result<PreparedTrack, Error>, url: URL) {
        pendingLoad = nil
        loadingURL = nil
        switch result {
        case .success(let next):
            next.player.delegate = self
            let previous = prepared?.player
            if wantsPlayback {
                previous?.pause()
                guard next.player.play() else {
                    next.player.delegate = nil
                    _ = previous?.play()
                    onChange?()
                    onError?(url, PlaybackError.cannotPlay)
                    return
                }
            }
            discardPlayer()
            prepared = next
            onChange?()
        case .failure(let error):
            onChange?()
            onError?(url, error)
        }
    }

    private func discardPlayer() {
        prepared?.player.delegate = nil
        prepared?.player.stop()
        prepared = nil
    }

    private func reportPlaybackFailure(_ player: AVAudioPlayer, error: Error) {
        guard let prepared, prepared.player === player else { return }
        let url = prepared.info.url
        discardPlayer()
        onChange?()
        onError?(url, error)
    }

    func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        DispatchQueue.main.async { [weak self, weak player] in
            guard let player else { return }
            self?.reportPlaybackFailure(player, error: error ?? PlaybackError.cannotPlay)
        }
    }
}
