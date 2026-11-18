import Accelerate
import AVFoundation
import Foundation

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
        let cues = try editCues(in: features, step: spectrum.step, duration: duration, isCancelled: isCancelled)
        return SoundtrackAnalysis(duration: duration, cues: cues, waveform: envelope.waveform)
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

    private static func editCues(in frames: [SoundtrackFrame], step: TimeInterval, duration: TimeInterval,
                                 isCancelled: () -> Bool) throws -> [SoundtrackCue] {
        guard frames.count >= 7 else { return [] }
        let loudness = frames.map(\.level)
        let low = frames.map(\.bass)
        let flux = frames.map(\.flux)
        let attack = frames.map(\.attack)
        // A relative signal floor admits a softly mastered recording and ignores
        // tiny changes during silence, fades, and persistent low-level noise.
        let reference = max(quantile(loudness, 0.88), loudness.max()! - 18)
        guard reference > -91 else { return [] }
        let audibleFloor = max(-91, reference - 45)
        let onset = zip(flux, attack).map { $0 + 0.026 * min(18, $1) }
        let activity = max(0.026, quantile(onset, 0.95))
        let onsetContext = AudioWindow(onset)
        let levelContext = AudioWindow(loudness.map { max(audibleFloor, $0) })
        let lowContext = AudioWindow(low.map { max(audibleFloor - 8, $0) })
        let context = max(4, Int(0.8 / step))
        let guardFrames = max(2, Int(0.065 / step))
        let before = max(3, Int(0.55 / step))
        let after = max(3, Int(0.70 / step))
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
            let previousBass = lowContext.mean(i - before, i - guardFrames)
            let bassRise = lowContext.mean(i + guardFrames, i + after) - previousBass
            let baseline = onsetContext.mean(i - context, i + context + 1)
            let deviation = onsetContext.deviation(i - context, i + context + 1, around: baseline)
            let surprise = (onset[i] - baseline) / max(0.018, deviation * 0.58, activity * 0.14)
            let isOnset = onset[i] >= max(0.035, activity * 0.25, baseline * 1.4) && surprise >= 1.45

            if isOnset && frame.level > audibleFloor && isPeak(onset, at: i, radius: localPeak) {
                // A drum's initial tick can be high-pitched before its low end arrives.
                // Rank the whole attack but keep the timing on its earliest peak.
                let span = i..<min(frames.count, i + attackWindow)
                let peakLevel = loudness[span].max() ?? frame.level
                let peakBass = low[span].max() ?? frame.bass
                let punch = max(0, peakLevel - past)
                let bassPunch = max(0, peakBass - previousBass)
                let relativeOnset = onset[i] / activity
                let strength = 0.12 + 0.34 * surprise / (surprise + 2.8)
                    + 0.27 * relativeOnset / (relativeOnset + 0.8)
                    + 0.18 * punch / (punch + 6) + 0.09 * bassPunch / (bassPunch + 8)
                let strongBass = peakBass > max(reference - 19, peakLevel - 11) && bassPunch >= 6
                let newBody = levelContext.mean(i + guardFrames, i + max(guardFrames + 2, after / 4))
                let structuralRise = i > before && i + after < frames.count && rise >= 6
                    && nextTail >= max(past + 4, newBody - 9) && next > reference - 19
                    && (bassRise >= 5 || rise >= 9)
                if structuralRise {
                    candidates.append(SoundtrackCue(time: frame.time, strength: min(1, strength + 0.18), kind: .drop))
                } else if strength >= 0.57 && (strongBass || (past > reference - 24 && punch >= 7 && relativeOnset >= 1.25)) {
                    candidates.append(SoundtrackCue(time: frame.time, strength: min(1, strength + 0.10), kind: .impact))
                } else {
                    candidates.append(SoundtrackCue(time: frame.time, strength: strength, kind: .accent))
                }
            }

            // A sudden sustained break can mark a phrase boundary even when it
            // adds no transient. Slow level drift and individual decays do not qualify.
            if i > before && i + after < frames.count && rise < -8 && nextTail < past - 6
                && past > reference - 16 && loudness[i - 3] - loudness[i + 3] > 6
                && isPeak(levelContext.fall, at: i, radius: localPeak) {
                candidates.append(SoundtrackCue(time: frame.time, strength: min(0.83, 0.48 + (-rise - 8) * 0.017), kind: .phrase))
            }
        }
        try checkCancellation(isCancelled)

        // Keep the strongest point in each neighbourhood. Dense drumming can
        // provide useful timing without producing a cue for every strike.
        let spacing: TimeInterval = 1.05
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
