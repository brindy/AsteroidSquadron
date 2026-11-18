import Accelerate
import AVFoundation
import Foundation

enum SoundtrackProfile: String, CaseIterable, Sendable {
    case `default`, calm, intense, trailerCue

    var title: String {
        switch self {
        case .default: return "Default"
        case .calm: return "Calm"
        case .intense: return "Intense"
        case .trailerCue: return "Trailer Cue"
        }
    }
}

struct SoundtrackCue: Equatable, Sendable {
    enum Kind: String, Sendable {
        case accent, impact, drop, phrase
    }

    let time: TimeInterval
    let strength: Float
    let kind: Kind
}

struct SoundtrackAnalysis: Sendable {
    let duration: TimeInterval
    let cues: [SoundtrackCue]
    let waveform: [Float]

    init(duration: TimeInterval, cues: [SoundtrackCue], waveform: [Float] = []) {
        self.duration = duration
        self.cues = cues
        self.waveform = waveform
    }

    static func analyze(url: URL, isCancelled: () -> Bool = { false }) throws -> SoundtrackAnalysis {
        try analyze(url: url, profiles: [.default], isCancelled: isCancelled)[.default]!
    }

    static func analyzeProfiles(url: URL, isCancelled: () -> Bool = { false }) throws -> [SoundtrackProfile: SoundtrackAnalysis] {
        try analyze(url: url, profiles: SoundtrackProfile.allCases, isCancelled: isCancelled)
    }

    private static func analyze(url: URL, profiles: [SoundtrackProfile], isCancelled: () -> Bool) throws -> [SoundtrackProfile: SoundtrackAnalysis] {
        try checkCancellation(isCancelled)
        let file = try AVAudioFile(forReading: url, commonFormat: .pcmFormatFloat32, interleaved: false)
        let format = file.processingFormat
        guard format.sampleRate.isFinite, format.sampleRate > 0, format.channelCount > 0,
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 32_768) else {
            throw AnalysisError.invalidAudio
        }
        let spectrum = try SoundtrackSpectrum(sampleRate: format.sampleRate, channels: Int(format.channelCount))
        var features: [SoundtrackFrame] = []
        let frameCount = file.length
        var envelope = SoundtrackEnvelope(frameCount: frameCount, channels: min(Int(format.channelCount), 8))
        while AVAudioFramePosition(spectrum.sampleCount) < frameCount {
            try checkCancellation(isCancelled)
            try file.read(into: buffer)
            if buffer.frameLength == 0 { break }
            guard let channels = buffer.floatChannelData else { throw AnalysisError.invalidAudio }
            envelope.append(channels, count: Int(buffer.frameLength))
            spectrum.append(channels, count: Int(buffer.frameLength), to: &features)
            if buffer.frameLength < buffer.frameCapacity { break }
        }
        guard spectrum.sampleCount > 0 else { throw AnalysisError.emptyAudio }
        let duration = Double(spectrum.sampleCount) / format.sampleRate
        let waveform = envelope.waveform
        let signal = CueSignal(frames: features)
        var result: [SoundtrackProfile: SoundtrackAnalysis] = [:]
        for profile in profiles {
            try checkCancellation(isCancelled)
            let cues = try signal.map {
                try editCues(in: $0, profile: profile, step: spectrum.step, duration: duration, isCancelled: isCancelled)
            } ?? []
            result[profile] = SoundtrackAnalysis(duration: duration, cues: cues, waveform: waveform)
        }
        return result
    }

    private static func checkCancellation(_ isCancelled: () -> Bool) throws {
        if isCancelled() { throw CancellationError() }
    }

    private enum AnalysisError: LocalizedError {
        case invalidAudio, emptyAudio

        var errorDescription: String? {
            switch self {
            case .invalidAudio: return "The soundtrack could not be decoded as audio."
            case .emptyAudio: return "This file contains no playable audio."
            }
        }
    }

    // Shared by every profile. Decode the file and measure each audio frame once.
    private struct CueSignal {
        let frames: [SoundtrackFrame]
        let loudness: [Float]
        let bass: [Float]
        let onset: [Float]
        let onsetContext: AudioWindow
        let levelContext: AudioWindow
        let bassContext: AudioWindow
        let reference: Float
        let audibleFloor: Float
        let activity: Float

        init?(frames: [SoundtrackFrame]) {
            guard frames.count >= 7 else { return nil }
            let loudness = frames.map(\.level)
            // Admit soft recordings while ignoring minute changes in fades and silence.
            let reference = max(quantile(loudness, 0.88), loudness.max()! - 18)
            guard reference > -91 else { return nil }
            let bass = frames.map(\.bass)
            let onset = frames.map { $0.flux + 0.026 * min(18, $0.attack) }
            let audibleFloor = max(-91, reference - 45)
            self.frames = frames
            self.loudness = loudness
            self.bass = bass
            self.onset = onset
            self.reference = reference
            self.audibleFloor = audibleFloor
            activity = max(0.026, quantile(onset, 0.95))
            onsetContext = AudioWindow(onset)
            levelContext = AudioWindow(loudness.map { max(audibleFloor, $0) })
            bassContext = AudioWindow(bass.map { max(audibleFloor - 8, $0) })
        }
    }

    private static func editCues(in signal: CueSignal, profile: SoundtrackProfile, step: TimeInterval, duration: TimeInterval,
                                 isCancelled: () -> Bool) throws -> [SoundtrackCue] {
        let tuning = profile.cueTuning
        let frames = signal.frames
        let loudness = signal.loudness
        let onset = signal.onset
        let reference = signal.reference
        let levelContext = signal.levelContext
        let context = max(4, Int(tuning.context / step))
        let guardFrames = max(2, Int(0.065 / step))
        let before = max(3, Int(tuning.before / step))
        let after = max(3, Int(tuning.after / step))
        let localPeak = max(1, Int(0.030 / step))
        let attackWindow = max(2, Int(0.068 / step))
        var candidates: [SoundtrackCue] = []

        for i in 3..<(frames.count - 3) {
            if i.isMultiple(of: 4_096) { try checkCancellation(isCancelled) }
            let frame = frames[i]
            guard frame.time >= 0.10, frame.time < duration - 0.05 else { continue }
            let past = levelContext.mean(i - before, i - guardFrames)
            let next = levelContext.mean(i + guardFrames, i + after)
            let nextTail = levelContext.mean(i + after / 2, i + after)
            let rise = next - past
            let previousBass = signal.bassContext.mean(i - before, i - guardFrames)
            let bassRise = signal.bassContext.mean(i + guardFrames, i + after) - previousBass
            let baseline = signal.onsetContext.mean(i - context, i + context + 1)
            let deviation = signal.onsetContext.deviation(i - context, i + context + 1, around: baseline)
            let activity = signal.activity
            let surprise = (onset[i] - baseline) / max(tuning.noiseFloor, deviation * 0.58, activity * tuning.activityFloor)
            let isOnset = onset[i] >= max(tuning.onsetFloor, activity * tuning.relativeOnset, baseline * tuning.localOnset)
                && surprise >= tuning.surpriseFloor
            let hasContext = i > before && i + after < frames.count

            if isOnset && frame.level > signal.audibleFloor && isPeak(onset, at: i, radius: localPeak) {
                // A drum's initial tick can be high-pitched before its low end arrives.
                // Rank the whole attack but keep the timing on its earliest peak.
                let span = i..<min(frames.count, i + attackWindow)
                let peakLevel = loudness[span].max() ?? frame.level
                let peakBass = signal.bass[span].max() ?? frame.bass
                let punch = max(0, peakLevel - past)
                let bassPunch = max(0, peakBass - previousBass)
                let relativeOnset = onset[i] / activity
                let strength = 0.12 + 0.34 * surprise / (surprise + 2.8)
                    + 0.27 * relativeOnset / (relativeOnset + 0.8)
                    + 0.18 * punch / (punch + 6) + 0.09 * bassPunch / (bassPunch + 8)
                let strongBass = peakBass > max(reference - 19, peakLevel - 11) && bassPunch >= 6
                let newBody = levelContext.mean(i + guardFrames, i + max(guardFrames + 2, after / 4))
                let structuralRise = hasContext && rise >= 6
                    && nextTail >= max(past + 4, newBody - 9) && next > reference - 19
                    && (bassRise >= 5 || rise >= 9)
                var kind: SoundtrackCue.Kind?
                switch profile {
                case .default:
                    if structuralRise { kind = .drop }
                    else if strength >= 0.57 && (strongBass || (past > reference - 24 && punch >= 7 && relativeOnset >= 1.25)) {
                        kind = .impact
                    } else { kind = .accent }
                case .calm:
                    // A voiced note can change the spectrum without moving the volume much.
                    // Leave those notes as accents so they keep the longer camera hold.
                    let immediatePast = levelContext.mean(i - attackWindow, i - 1)
                    let immediateFuture = levelContext.mean(i + guardFrames, i + guardFrames + attackWindow)
                    let tonalChange = onset[i] > baseline * 2.4 && immediateFuture >= immediatePast - 2
                    if punch >= 1.3 || tonalChange { kind = .accent }
                case .intense:
                    // In compressed mixes the bass can change sections with little gain change.
                    let heavierSection = hasContext && rise >= 2 && bassRise >= 6
                        && nextTail > past + 2 && next > reference - 12
                    if structuralRise || heavierSection { kind = .drop }
                    else if strength >= 0.62 && strongBass && relativeOnset >= 1 { kind = .impact }
                    else if relativeOnset >= 1.1 || punch >= 6 { kind = .accent }
                case .trailerCue:
                    // Favor big re-entries and singular stingers over notes in a build.
                    let reentry = hasContext && rise >= 8 && nextTail >= past + 6 && next > reference - 15
                    let bassLift = bassRise > 5 && peakBass > peakLevel - 15
                    let sustainedLift = rise >= 11 && nextTail > newBody - 5 && nextTail > reference - 15
                    if reentry && (bassLift || sustainedLift) { kind = .drop }
                    else if strength >= 0.60 && peakLevel > reference - 10
                        && ((strongBass && bassPunch >= 9) || (past > reference - 26 && punch >= 10 && relativeOnset >= 1.6)) {
                        kind = .impact
                    }
                }
                if let kind {
                    let bonus: Float = kind == .drop ? 0.18 : (kind == .impact ? 0.10 : 0)
                    candidates.append(SoundtrackCue(time: frame.time, strength: min(1, strength + bonus), kind: kind))
                }
            }

            // A sudden sustained break can mark a phrase boundary even when it
            // adds no transient. Slow level drift and individual decays do not qualify.
            let fall = tuning.phraseFall
            if hasContext && rise < -fall && nextTail < past - (fall - 2)
                && past > reference - tuning.phraseFloor && loudness[i - 3] - loudness[i + 3] > fall - 2
                && isPeak(levelContext.fall, at: i, radius: localPeak) {
                if profile == .calm {
                    // Don't treat the tail of a single fading note as the end of a phrase.
                    let earlier = levelContext.mean(i - before, i - before / 2)
                    let recent = levelContext.mean(i - before / 2, i - guardFrames)
                    if earlier - recent > 3.5 { continue }
                }
                candidates.append(SoundtrackCue(time: frame.time, strength: min(0.83, 0.48 + (-rise - fall) * 0.017), kind: .phrase))
            }
        }
        try checkCancellation(isCancelled)

        // Keep the strongest point in each neighbourhood. Dense drumming can
        // provide useful timing without producing a cue for every strike.
        let spacing = tuning.spacing
        var selected: [Int: SoundtrackCue] = [:]
        for candidate in candidates.sorted(by: cuePriority) {
            let bucket = Int(candidate.time / spacing)
            let hasNeighbour = (bucket - 1...bucket + 1).contains { key in
                selected[key].map { abs($0.time - candidate.time) < spacing } ?? false
            }
            if !hasNeighbour { selected[bucket] = candidate }
        }
        return selected.values.sorted { $0.time < $1.time }
    }

    private static func cuePriority(_ lhs: SoundtrackCue, _ rhs: SoundtrackCue) -> Bool {
        func rank(_ cue: SoundtrackCue) -> Float {
            switch cue.kind {
            case .drop: return cue.strength + 0.22
            case .impact: return cue.strength + 0.06
            case .phrase: return cue.strength + 0.10
            case .accent: return cue.strength
            }
        }
        let left = rank(lhs), right = rank(rhs)
        return left == right ? lhs.time < rhs.time : left > right
    }

    private static func isPeak(_ values: [Float], at index: Int, radius: Int) -> Bool {
        let start = max(0, index - radius)
        let end = min(values.count - 1, index + radius)
        let value = values[index]
        return (start..<index).allSatisfy { values[$0] < value }
            && ((index + 1)...end).allSatisfy { values[$0] <= value }
    }

    private static func quantile(_ values: [Float], _ percentile: Double) -> Float {
        let sorted = values.sorted()
        return sorted[Int(Double(sorted.count - 1) * percentile)]
    }
}

private struct CueTuning {
    let spacing: TimeInterval
    let context: TimeInterval
    let before: TimeInterval
    let after: TimeInterval
    let onsetFloor: Float
    let relativeOnset: Float
    let localOnset: Float
    let surpriseFloor: Float
    let noiseFloor: Float
    let activityFloor: Float
    let phraseFall: Float
    let phraseFloor: Float
}

private extension SoundtrackProfile {
    var cueTuning: CueTuning {
        switch self {
        case .default:
            return CueTuning(spacing: 1.05, context: 0.8, before: 0.55, after: 0.7,
                             onsetFloor: 0.035, relativeOnset: 0.25, localOnset: 1.4, surpriseFloor: 1.45,
                             noiseFloor: 0.018, activityFloor: 0.14, phraseFall: 8, phraseFloor: 16)
        case .calm:
            return CueTuning(spacing: 1.4, context: 1.15, before: 0.65, after: 0.7,
                             onsetFloor: 0.021, relativeOnset: 0.13, localOnset: 1.25, surpriseFloor: 1.15,
                             noiseFloor: 0.012, activityFloor: 0.09, phraseFall: 6, phraseFloor: 24)
        case .intense:
            return CueTuning(spacing: 1.75, context: 1.45, before: 0.75, after: 0.9,
                             onsetFloor: 0.052, relativeOnset: 0.62, localOnset: 1.7, surpriseFloor: 1.9,
                             noiseFloor: 0.022, activityFloor: 0.18, phraseFall: 9, phraseFloor: 16)
        case .trailerCue:
            return CueTuning(spacing: 2.15, context: 1.2, before: 0.8, after: 0.84,
                             onsetFloor: 0.042, relativeOnset: 0.37, localOnset: 1.45, surpriseFloor: 1.55,
                             noiseFloor: 0.018, activityFloor: 0.14, phraseFall: 12, phraseFloor: 17)
        }
    }
}

private struct SoundtrackEnvelope {
    private struct Bin {
        var peak: Float = 0
        var energy: Double = 0
        var frames = 0
    }

    private let frameCount: AVAudioFramePosition
    private let channels: Int
    private var bins: [Bin]
    private var index = 0
    private var processed: AVAudioFramePosition = 0
    private var end: AVAudioFramePosition = 0

    init(frameCount: AVAudioFramePosition, channels: Int) {
        self.frameCount = frameCount
        self.channels = channels
        bins = Array(repeating: Bin(), count: Int(max(0, min(frameCount, 192))))
        end = boundary(after: 0)
    }

    mutating func append(_ input: UnsafePointer<UnsafeMutablePointer<Float>>, count: Int) {
        var offset = 0
        while offset < count {
            let length = index < bins.count - 1 ? min(count - offset, Int(end - processed)) : count - offset
            for channel in 0..<channels {
                let samples = input[channel].advanced(by: offset)
                var peak: Float = 0, energy: Float = 0
                vDSP_maxmgv(samples, 1, &peak, vDSP_Length(length))
                vDSP_svesq(samples, 1, &energy, vDSP_Length(length))
                if peak.isFinite { bins[index].peak = max(bins[index].peak, min(8, peak)) }
                if energy.isFinite { bins[index].energy += min(64 * Double(length), Double(energy)) }
            }
            bins[index].frames += length
            processed += AVAudioFramePosition(length)
            offset += length
            if processed >= end, index < bins.count - 1 {
                index += 1
                end = boundary(after: index)
            }
        }
    }

    var waveform: [Float] {
        let levels = bins.prefix(while: { $0.frames > 0 }).map { bin in
            let rms = Float(sqrt(bin.energy / (Double(bin.frames) * Double(channels))))
            return 0.6 * rms + 0.4 * bin.peak
        }
        let reference = max(0.00001, levels.max() ?? 0)
        return levels.map { pow($0 / reference, 0.58) }
    }

    private func boundary(after index: Int) -> AVAudioFramePosition {
        let count = AVAudioFramePosition(max(1, bins.count))
        let boundary = AVAudioFramePosition(index + 1)
        return (frameCount / count) * boundary + (frameCount % count) * boundary / count
    }
}

private struct AudioWindow {
    private let sum: [Double]
    private let squares: [Double]
    let fall: [Float]

    init(_ values: [Float]) {
        var sum = [0.0], squares = [0.0]
        sum.reserveCapacity(values.count + 1)
        squares.reserveCapacity(values.count + 1)
        for value in values {
            let x = Double(value)
            sum.append(sum[sum.count - 1] + x)
            squares.append(squares[squares.count - 1] + x * x)
        }
        self.sum = sum
        self.squares = squares
        fall = values.indices.map { values[max(0, $0 - 3)] - values[min(values.count - 1, $0 + 3)] }
    }

    func mean(_ start: Int, _ end: Int) -> Float {
        average(sum, start, end)
    }

    func deviation(_ start: Int, _ end: Int, around mean: Float) -> Float {
        sqrt(max(0, average(squares, start, end) - mean * mean))
    }

    private func average(_ values: [Double], _ start: Int, _ end: Int) -> Float {
        let first = max(0, min(values.count - 2, start))
        let last = min(values.count - 1, max(first + 1, end))
        return Float((values[last] - values[first]) / Double(last - first))
    }
}

private struct SoundtrackFrame {
    let time: TimeInterval
    let level: Float
    let bass: Float
    let flux: Float
    let attack: Float
}

private final class SoundtrackSpectrum {
    private let sampleRate: Double
    private let size: Int
    private let hop: Int
    private let fftOrder: vDSP_Length
    private let setup: FFTSetup
    private let taper: [Float]
    private let channels: Int
    private let frequencyBands: [Int]
    private let binCounts: [Int]
    private var samples: [[Float]]
    private var tapered: [Float]
    private var real: [Float]
    private var imaginary: [Float]
    private var power: [Float]
    private var priorSpectrum: [Float]
    private var cursor = 0
    private(set) var sampleCount = 0
    var step: TimeInterval { Double(hop) / sampleRate }

    init(sampleRate: Double, channels: Int) throws {
        self.sampleRate = sampleRate
        // Roughly 45 ms windows retain bass detail, sampled every 10 ms.
        let order = Int(min(13, max(6, (log2(sampleRate * 0.045)).rounded())))
        fftOrder = vDSP_Length(order)
        size = 1 << order
        hop = max(1, min(size, Int(min(Double(size), sampleRate * 0.010).rounded())))
        guard let setup = vDSP_create_fftsetup(fftOrder, FFTRadix(kFFTRadix2)) else {
            throw CocoaError(.fileReadUnknown)
        }
        self.setup = setup
        // Mix channel power after analysis to preserve opposing stereo phases.
        self.channels = min(channels, 8)
        var window = [Float](repeating: 0, count: size)
        vDSP_hann_window(&window, vDSP_Length(size), Int32(vDSP_HANN_NORM))
        taper = window
        let bins = size / 2
        let hertzPerBin = sampleRate / Double(size)
        let limits = [180.0, 560, 1_500, 4_000, 12_000]
        frequencyBands = (0..<bins).map { bin in
            let hertz = Double(bin) * hertzPerBin
            return bin == 0 ? -1 : (limits.firstIndex(where: { hertz <= $0 }) ?? -1)
        }
        var counts = [Int](repeating: 0, count: limits.count)
        for band in frequencyBands where band >= 0 { counts[band] += 1 }
        binCounts = counts
        samples = Array(repeating: Array(repeating: 0, count: size), count: self.channels)
        tapered = window
        real = Array(repeating: 0, count: bins)
        imaginary = real
        power = real
        priorSpectrum = real
    }

    deinit { vDSP_destroy_fftsetup(setup) }

    func append(_ input: UnsafePointer<UnsafeMutablePointer<Float>>, count: Int, to frames: inout [SoundtrackFrame]) {
        for frame in 0..<count {
            for channel in 0..<channels {
                let sample = input[channel][frame]
                samples[channel][cursor] = sample.isFinite ? max(-8, min(8, sample)) : 0
            }
            cursor = (cursor + 1) & (size - 1)
            sampleCount += 1
            if sampleCount >= size, (sampleCount - size).isMultiple(of: hop) {
                frames.append(measure(frames: frames))
            }
        }
    }

    private func measure(frames: [SoundtrackFrame]) -> SoundtrackFrame {
        let bins = size / 2
        for index in 0..<bins { power[index] = 0 }
        for channel in 0..<channels {
            let signal = samples[channel]
            for index in 0..<size { tapered[index] = signal[(cursor + index) & (size - 1)] * taper[index] }
            tapered.withUnsafeBufferPointer { values in
                real.withUnsafeMutableBufferPointer { real in
                    imaginary.withUnsafeMutableBufferPointer { imaginary in
                        var split = DSPSplitComplex(realp: real.baseAddress!, imagp: imaginary.baseAddress!)
                        values.baseAddress!.withMemoryRebound(to: DSPComplex.self, capacity: bins) {
                            vDSP_ctoz($0, 2, &split, 1, vDSP_Length(bins))
                        }
                        vDSP_fft_zrip(setup, &split, 1, fftOrder, FFTDirection(FFT_FORWARD))
                    }
                }
            }
            for index in 1..<bins {
                power[index] += real[index] * real[index] + imaginary[index] * imaginary[index]
            }
        }

        let scale = 1 / (Float(size) * Float(size) * Float(channels))
        var broadband: Float = 0, bass: Float = 0
        var flux = [Float](repeating: 0, count: binCounts.count)
        for index in 1..<bins {
            let band = frequencyBands[index]
            guard band >= 0 else { continue }
            let energy = power[index] * scale
            broadband += energy
            if band == 0 { bass += energy }
            let magnitude = log1p(sqrt(energy) * 7_500)
            if !frames.isEmpty { flux[band] += max(0, magnitude - priorSpectrum[index]) }
            priorSpectrum[index] = magnitude
        }
        var novelty: Float = 0
        for band in flux.indices where binCounts[band] > 0 {
            novelty += flux[band] / sqrt(Float(binCounts[band]))
        }
        novelty /= Float(flux.count)
        let level = 10 * log10(max(1.0e-11, broadband))
        let low = 10 * log10(max(1.0e-11, bass))
        let previous = frames.dropLast(2).last
        let attack = previous.map { max(0, level - $0.level) } ?? 0
        let time = Double(sampleCount - size / 2) / sampleRate
        return SoundtrackFrame(time: time, level: level, bass: low, flux: novelty, attack: attack)
    }
}
