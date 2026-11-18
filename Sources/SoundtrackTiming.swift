import Foundation

// The audio player owns the clock. A cut cue expires if rendering misses it,
// and a reserved arrival may only move forward before its ships are staged.
final class SoundtrackTiming {
    private let analysis: SoundtrackAnalysis
    private var position: TimeInterval?
    private var lastPosition: TimeInterval?
    private var cutCue: SoundtrackCue?

    init(analysis: SoundtrackAnalysis) { self.analysis = analysis }

    func observe(position: TimeInterval?) {
        self.position = position
        cutCue = nil
        guard let position else { return }
        defer { lastPosition = position }
        guard let lastPosition, position != lastPosition else { return }
        // At a loop boundary only use cues from the start of the new pass.
        let previous = position < lastPosition ? 0 : lastPosition.nextUp
        let after = max(previous,position-0.14)
        for cue in analysis.cues[firstCue(after)...] {
            if cue.time>position { break }
            if cutCue == nil || cue.strength>cutCue!.strength { cutCue = cue }
        }
    }

    func takeCutCue() -> SoundtrackCue? {
        defer { cutCue = nil }
        return cutCue
    }

    func arrivalDelay(untilReveal: TimeInterval) -> TimeInterval? {
        guard let position, analysis.duration>0, untilReveal>=0 else { return nil }
        let reveal = (position+untilReveal).truncatingRemainder(dividingBy:analysis.duration)
        let maximumDelay = min(1.8,analysis.duration)
        var best: (delay: TimeInterval, score: Double)?
        func consider(from start: TimeInterval, to end: TimeInterval, elapsed: TimeInterval) {
            for cue in analysis.cues[firstCue(start)...] {
                if cue.time>end { break }
                if (cue.kind == .accent || cue.kind == .phrase) && cue.strength<0.72 { continue }
                let delay = elapsed+cue.time-start
                let bonus = cue.kind == .drop ? 0.32 : (cue.kind == .impact ? 0.16 : 0)
                let score = Double(cue.strength)+bonus-delay*0.23
                if best == nil || score>best!.score { best = (delay,score) }
            }
        }
        consider(from:reveal,to:reveal+maximumDelay,elapsed:0)
        let toLoop = analysis.duration-reveal
        if toLoop<maximumDelay { consider(from:0,to:maximumDelay-toLoop,elapsed:toLoop) }
        return best?.delay
    }

    private func firstCue(_ time: TimeInterval) -> Int {
        var low = 0, high = analysis.cues.count
        while low<high {
            let mid = (low+high)/2
            if analysis.cues[mid].time<time { low = mid+1 } else { high = mid }
        }
        return low
    }
}

extension Faction {
    var soundtrackRevealOffset: TimeInterval {
        switch self {
        case .rebel: return 1.25
        case .earth: return 0.38
        case .shadow: return 1.4
        case .colonial,.cylon: return 0.85
        default: return 1.4*0.65
        }
    }
}
