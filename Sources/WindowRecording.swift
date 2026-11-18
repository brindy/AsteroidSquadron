import AVFoundation
import CoreGraphics
import ScreenCaptureKit

enum RecordingError: LocalizedError {
    case permissionDenied, windowUnavailable, encodingUnavailable, noVideo, encoderFailed

    var errorDescription: String? {
        switch self {
        case .permissionDenied:
            return "macOS hasn’t granted screen recording access to this copy of Asteroid Squadron."
        case .windowUnavailable: return "Open the flight window before starting a recording."
        case .encodingUnavailable: return "This Mac couldn’t encode video at this window size. Try a smaller size."
        case .noVideo: return "No video frames were captured. Let the recording run for a moment before stopping."
        case .encoderFailed: return "The video encoder couldn’t finish the recording."
        }
    }
}

final class WindowRecording {
    private struct Capture {
        let stream: SCStream
        let output: RecordingOutput
    }

    private var capture: Capture?
    private var starting = false
    private var startupInterruption: Error?
    var onInterruption: ((Error) -> Void)?

    @MainActor func start(windowID: Int, size: CGSize, fps: Int) async throws {
        guard capture == nil, !starting else { return }
        guard let windowID = CGWindowID(exactly: windowID), windowID > 0 else {
            throw RecordingError.windowUnavailable
        }
        // 4:2:0 video needs an even number of pixels on both axes.
        let width = max(2, Int(size.width.rounded(.down)) & ~1)
        let height = max(2, Int(size.height.rounded(.down)) & ~1)
        let frameInterval = CMTime(value: 1, timescale: fps == 60 ? 60 : 30)
        starting = true
        defer { starting = false; startupInterruption = nil }

        let shareable: SCShareableContent
        do {
            if #available(macOS 14.4, *) {
                // Own-window capture is available without enumerating other apps
                // or requesting broad Screen Recording access on newer macOS.
                shareable = try await SCShareableContent.currentProcess
            } else {
                guard CGPreflightScreenCaptureAccess() || CGRequestScreenCaptureAccess() else {
                    throw RecordingError.permissionDenied
                }
                shareable = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true)
            }
        } catch let error as SCStreamError where error.code == .userDeclined {
            throw RecordingError.permissionDenied
        }
        let ownPID = ProcessInfo.processInfo.processIdentifier
        guard let window = shareable.windows.first(where: {
            $0.windowID == windowID && $0.owningApplication?.processID == ownPID
        }) else { throw RecordingError.windowUnavailable }

        // A window filter captures video from this window and audio from its owning app.
        let filter = SCContentFilter(desktopIndependentWindow: window)
        let configuration = SCStreamConfiguration()
        configuration.width = width
        configuration.height = height
        configuration.minimumFrameInterval = frameInterval
        configuration.pixelFormat = kCVPixelFormatType_32BGRA
        configuration.queueDepth = 5
        configuration.scalesToFit = true
        configuration.showsCursor = false
        configuration.capturesAudio = true
        configuration.excludesCurrentProcessAudio = false
        configuration.sampleRate = 48_000
        configuration.channelCount = 2
        if #available(macOS 14, *) {
            configuration.ignoreShadowsSingleWindow = true
            configuration.ignoreGlobalClipSingleWindow = true
        }

        let output = try RecordingOutput(width: width, height: height, frameInterval: frameInterval) { [weak self] output, error in
            DispatchQueue.main.async { [weak self, weak output] in
                guard let self, let output, self.capture?.output === output else { return }
                if self.starting { self.startupInterruption = error }
                else { self.onInterruption?(error) }
            }
        }
        let stream = SCStream(filter: filter, configuration: configuration, delegate: output)
        do {
            try stream.addStreamOutput(output, type: .screen, sampleHandlerQueue: output.queue)
            try stream.addStreamOutput(output, type: .audio, sampleHandlerQueue: output.queue)
            capture = Capture(stream: stream, output: output)
            try await stream.startCapture()
            if let startupInterruption { throw startupInterruption }
        } catch {
            capture = nil
            // This also covers interruptions after the stream started but before setup returned.
            try? await stream.stopCapture()
            await output.discard()
            if (error as? SCStreamError)?.code == .userDeclined { throw RecordingError.permissionDenied }
            throw error
        }
    }

    // If macOS stops the stream itself, finalise what was recorded before it stopped.
    @MainActor func stop() async throws -> URL {
        guard let capture, !starting else { throw RecordingError.noVideo }
        self.capture = nil
        let end = CMClockGetTime(CMClockGetHostTimeClock())
        try? await capture.stream.stopCapture()
        return try await capture.output.finish(at: end)
    }
}

private final class RecordingOutput: NSObject, SCStreamOutput, SCStreamDelegate, @unchecked Sendable {
    let queue = DispatchQueue(label: "dev.brindy.asteroid-squadron.recording")
    private let onInterruption: (RecordingOutput, Error) -> Void

    private let writer: AVAssetWriter
    private let video: AVAssetWriterInput
    private let audio: AVAssetWriterInput
    private let frameInterval: CMTime

    // All sample processing and finalisation takes place on `queue`.
    private var acceptingSamples = true
    private var startTime: CMTime?
    private var lastVideo: CMSampleBuffer?
    private var lastAudioTime = CMTime.invalid
    private var interruptionTime: CMTime?
    private var encodingError: Error?

    init(width: Int, height: Int, frameInterval: CMTime,
         onInterruption: @escaping (RecordingOutput, Error) -> Void) throws {
        let file = FileManager.default.temporaryDirectory
            .appendingPathComponent("Asteroid Squadron \(UUID().uuidString).mp4")
        writer = try AVAssetWriter(outputURL: file, fileType: .mp4)
        writer.shouldOptimizeForNetworkUse = true
        self.frameInterval = frameInterval
        self.onInterruption = onInterruption

        let pixels = width * height
        let codec: AVVideoCodecType = width > 4096 || height > 4096 || pixels > 4096 * 2304 ? .hevc : .h264
        let bitrate = min(80_000_000, max(1_500_000, pixels * Int(frameInterval.timescale) / 8))
        let videoSettings: [String: Any] = [
            AVVideoCodecKey: codec,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: bitrate,
                AVVideoExpectedSourceFrameRateKey: frameInterval.timescale,
                AVVideoMaxKeyFrameIntervalDurationKey: 2
            ]
        ]
        let audioSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: 48_000,
            AVNumberOfChannelsKey: 2,
            AVEncoderBitRateKey: 192_000
        ]
        guard writer.canApply(outputSettings: videoSettings, forMediaType: .video),
              writer.canApply(outputSettings: audioSettings, forMediaType: .audio) else {
            throw RecordingError.encodingUnavailable
        }
        video = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        audio = AVAssetWriterInput(mediaType: .audio, outputSettings: audioSettings)
        super.init()
        for input in [video, audio] {
            guard writer.canAdd(input) else { throw RecordingError.encodingUnavailable }
            input.expectsMediaDataInRealTime = true
            writer.add(input)
        }
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sample: CMSampleBuffer, of type: SCStreamOutputType) {
        guard acceptingSamples, sample.isValid, sample.presentationTimeStamp.isNumeric else { return }
        switch type {
        case .screen:
            guard let attachments = CMSampleBufferGetSampleAttachmentsArray(sample, createIfNecessary: false)
                    as? [[SCStreamFrameInfo: Any]],
                  let status = attachments.first?[.status] as? Int,
                  status == SCFrameStatus.complete.rawValue else { return }
            appendVideo(sample)
        case .audio:
            appendAudio(sample)
        default:
            break
        }
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        let when = CMClockGetTime(CMClockGetHostTimeClock())
        queue.async {
            guard self.acceptingSamples, self.interruptionTime == nil else { return }
            self.interruptionTime = when
            self.onInterruption(self, error)
        }
    }

    private func appendVideo(_ sample: CMSampleBuffer) {
        let time = sample.presentationTimeStamp
        if startTime == nil {
            guard writer.startWriting() else { failEncoding(); return }
            writer.startSession(atSourceTime: time)
            startTime = time
        }
        guard video.isReadyForMoreMediaData,
              lastVideo.map({ $0.presentationTimeStamp < time }) ?? true else { return }
        if video.append(sample) { lastVideo = sample }
        else { failEncoding() }
    }

    private func appendAudio(_ sample: CMSampleBuffer) {
        let time = sample.presentationTimeStamp
        guard let startTime, time >= startTime, lastVideo != nil, audio.isReadyForMoreMediaData,
              !lastAudioTime.isNumeric || time > lastAudioTime else { return }
        if audio.append(sample) { lastAudioTime = time }
        else { failEncoding() }
    }

    private func failEncoding() {
        let error = writer.error ?? RecordingError.encoderFailed
        encodingError = error
        acceptingSamples = false
        onInterruption(self, error)
    }

    func finish(at time: CMTime) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                self.acceptingSamples = false
                guard self.writer.status == .writing, let lastVideo = self.lastVideo else {
                    let error = self.encodingError ?? self.writer.error ?? RecordingError.noVideo
                    self.discardOnQueue()
                    continuation.resume(throwing: error)
                    return
                }
                let end = max(lastVideo.presentationTimeStamp + self.frameInterval,
                              min(self.interruptionTime ?? time, time))
                self.extendLastFrame(lastVideo, to: end)
                self.lastVideo = nil
                self.video.markAsFinished()
                self.audio.markAsFinished()
                self.writer.endSession(atSourceTime: end)
                self.writer.finishWriting {
                    if self.writer.status == .completed {
                        continuation.resume(returning: self.writer.outputURL)
                    } else {
                        try? FileManager.default.removeItem(at: self.writer.outputURL)
                        continuation.resume(throwing: self.writer.error ?? RecordingError.encoderFailed)
                    }
                }
            }
        }
    }

    // ScreenCaptureKit stops delivering complete frames when the window is static.
    private func extendLastFrame(_ lastVideo: CMSampleBuffer, to end: CMTime) {
        let time = end - frameInterval
        guard time > lastVideo.presentationTimeStamp, video.isReadyForMoreMediaData else { return }
        var timing = CMSampleTimingInfo(duration: frameInterval, presentationTimeStamp: time, decodeTimeStamp: .invalid)
        var copy: CMSampleBuffer?
        let result = CMSampleBufferCreateCopyWithNewTiming(allocator: kCFAllocatorDefault,
            sampleBuffer: lastVideo, sampleTimingEntryCount: 1, sampleTimingArray: &timing, sampleBufferOut: &copy)
        if result == noErr, let copy { _ = video.append(copy) }
    }

    func discard() async {
        await withCheckedContinuation { continuation in
            queue.async {
                self.discardOnQueue()
                continuation.resume()
            }
        }
    }

    private func discardOnQueue() {
        acceptingSamples = false
        lastVideo = nil
        if writer.status == .writing { writer.cancelWriting() }
        try? FileManager.default.removeItem(at: writer.outputURL)
    }
}
