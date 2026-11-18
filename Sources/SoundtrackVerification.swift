import AVFoundation
import Foundation
import simd

private func requireSoundtrack(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else { print("FAIL: \(message)"); exit(1) }
}

private func writeSoundtrackFixture(named name: String, duration: Double, into directory: URL,
                                    sample: (Double, Int) -> Double) throws -> URL {
    let rate = 24_000.0
    let frames = AVAudioFrameCount((duration * rate).rounded())
    let format = AVAudioFormat(standardFormatWithSampleRate: rate, channels: 1)!
    let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames)!
    buffer.frameLength = frames
    let samples = buffer.floatChannelData![0]
    for frame in 0..<Int(frames) {
        samples[frame] = Float(sample(Double(frame) / rate, frame))
    }
    let url = directory.appendingPathComponent(name).appendingPathExtension("wav")
    let file = try AVAudioFile(forWriting: url, settings: format.settings)
    try file.write(from: buffer)
    return url
}

private func verifySoundtrackAnalysis(in directory: URL) throws {
    let duration = 18.0
    let pianoAttacks = [1.2, 4.1, 7.4, 11.2, 15.5]
    func piano(_ time: Double) -> Double {
        pianoAttacks.enumerated().reduce(0) { mix, note in
            let age = time - note.element
            guard age >= 0 && age <= 1.65 else { return mix }
            let frequency = [220.0, 293.7, 261.6, 196.0, 246.9][note.offset]
            let fundamental = 2 * Double.pi * frequency * age
            let attack = min(1, age / 0.009)
            let decayingTone = sin(fundamental) * exp(-3.2 * age)
            let harmonics = (0.45 * sin(2 * fundamental) + 0.19 * sin(3 * fundamental)) * exp(-13 * age)
            return mix + 0.031 * attack * (decayingTone + harmonics)
        }
    }
    let quietFile = try writeSoundtrackFixture(named: "Quiet Piano", duration: duration, into: directory) { time, _ in piano(time) }
    let amplifiedFile = try writeSoundtrackFixture(named: "Amplified Piano", duration: duration, into: directory) { time, _ in 8 * piano(time) }
    let quiet = try SoundtrackAnalysis.analyze(url: quietFile)
    let amplified = try SoundtrackAnalysis.analyze(url: amplifiedFile)
    func nearby(_ seconds: Double, in analysis: SoundtrackAnalysis, tolerance: Double = 0.14) -> Bool {
        analysis.cues.contains { abs($0.time - seconds) <= tolerance }
    }
    requireSoundtrack(pianoAttacks.filter { nearby($0, in: quiet) }.count >= 4,
                      "Quiet piano attacks were missed or noticeably late: \(quiet.cues.map(\.time))")
    requireSoundtrack(pianoAttacks.filter { nearby($0, in: quiet) && nearby($0, in: amplified) }.count >= 4,
                      "The same soft and amplified tracks produced different edit timing")

    // A thick guitar bed and constant short attacks should still yield room to hold a shot.
    let denseAccents = [2.4, 5.6, 8.8, 12.0, 15.2]
    let denseFile = try writeSoundtrackFixture(named: "Dense Percussion", duration: duration, into: directory) { time, frame in
        let age = time.truncatingRemainder(dividingBy: 0.20)
        let guitar = tanh(sin(time * 2 * .pi * 84) * 3 + sin(time * 2 * .pi * 126) * 2)
        let noise = Double((UInt64(frame) &* 2_654_435_761) & 0xFFFF) / 32_768 - 1
        let drum = exp(-age * 56) * (0.13 * noise + 0.20 * sin(age * 2 * .pi * 68))
        let accented = denseAccents.reduce(0.0) { mix, start in
            let offset = time - start
            guard offset >= 0 && offset < 0.30 else { return mix }
            let snare = noise * exp(-offset * 33)
            let kick = sin(offset * 2 * .pi * 52) * exp(-offset * 21)
            return mix + 0.32 * snare + 0.43 * kick
        }
        return 0.20 * guitar + drum + accented
    }
    let dense = try SoundtrackAnalysis.analyze(url: denseFile)
    requireSoundtrack(denseAccents.filter { nearby($0, in: dense) }.count >= 3,
                      "Dense music hid its main accents: \(dense.cues.map(\.time))")
    requireSoundtrack(dense.cues.count <= 23 && zip(dense.cues, dense.cues.dropFirst()).allSatisfy { $1.time - $0.time >= 0.77 },
                      "Sustained percussion generated too many neighboring edits")

    let dropTime = 7.75
    let impactTime = 12.0
    let trailerFile = try writeSoundtrackFixture(named: "Trailer Rise and Drop", duration: duration, into: directory) { time, frame in
        let noise = Double((UInt64(frame) &* 2_654_435_761) & 0xFFFF) / 32_768 - 1
        let bed = sin(time * 2 * .pi * 165) + 0.45 * sin(time * 2 * .pi * 249)
        let build = min(1, max(0, (time - 2.0) / 5.0))
        if time < dropTime - 0.65 { return (0.033 + 0.071 * build) * bed + 0.024 * build * noise }
        if time < dropTime { return 0 }
        if time < impactTime {
            let age = time - dropTime
            let thump = 0.63 * sin(age * 2 * .pi * 58) * exp(-age * 7) + 0.14 * noise * exp(-age * 28)
            return 0.14 * bed + thump
        }
        let age = time - impactTime
        let thump = (0.65 * sin(age * 2 * .pi * 53) + 0.16 * noise) * exp(-age * 10)
        return 0.14 * bed + thump
    }
    let trailer = try SoundtrackAnalysis.analyze(url: trailerFile)
    requireSoundtrack(trailer.cues.contains { abs($0.time - dropTime) < 0.16 && $0.kind == .drop },
                      "The trailer build and re-entry did not produce a timed drop: \(trailer.cues)")
    requireSoundtrack(trailer.cues.contains { abs($0.time - impactTime) < 0.16 && $0.kind == .impact },
                      "Bass impact did not produce a timed impact: \(trailer.cues)")

    let silenceFile = try writeSoundtrackFixture(named: "Silence", duration: 2, into: directory) { _, _ in 0 }
    let silence = try SoundtrackAnalysis.analyze(url: silenceFile)
    requireSoundtrack(silence.cues.isEmpty, "Silence generated soundtrack cues")
    for result in [quiet, amplified, dense, trailer] {
        requireSoundtrack(abs(result.duration - duration) < 0.02, "The soundtrack duration changed during analysis")
        requireSoundtrack(result.cues.allSatisfy {
            (0..<duration).contains($0.time) && (0...1).contains($0.strength)
        }, "Out-of-range soundtrack cue")
        requireSoundtrack(zip(result.cues, result.cues.dropFirst()).allSatisfy { $0.time < $1.time },
                          "Soundtrack cues were out of order or duplicated")
    }
    var cancelled = false
    var cancellationChecks = 0
    do {
        _ = try SoundtrackAnalysis.analyze(url: denseFile) {
            cancellationChecks += 1
            return cancellationChecks >= 3
        }
    } catch {
        cancelled = true
    }
    requireSoundtrack(cancelled, "Replacing a track could not interrupt in-progress audio analysis")
    print("PASS: quiet piano, gain changes, dense music, trailer drops and impacts, silence, and analysis cancellation.")
}

private func verifySoundtrackTiming() {
    let cues: [SoundtrackCue] = [
        .init(time: 1.0, strength: 0.9, kind: .impact),
        .init(time: 3.5, strength: 0.95, kind: .drop),
        .init(time: 6.0, strength: 0.8, kind: .accent)
    ]
    let timing = SoundtrackTiming(analysis: SoundtrackAnalysis(duration: 12, cues: cues))
    timing.observe(position: 0.97)
    timing.observe(position: 1)
    requireSoundtrack(timing.takeCutCue()?.kind == .impact && timing.takeCutCue() == nil,
                      "The playback clock did not consume a cue exactly once")
    timing.observe(position: 1.02)
    requireSoundtrack(timing.takeCutCue() == nil, "The playback clock repeated a cue from the exact previous position")
    timing.observe(position: 4.3)
    requireSoundtrack(timing.takeCutCue() == nil, "A skipped edit was replayed late after a playback jump")
    timing.observe(position: 11.8)
    timing.observe(position: 0.02)
    requireSoundtrack(timing.takeCutCue() == nil, "The playback loop delivered an old edit point")
    timing.observe(position: 0.98)
    timing.observe(position: 1.01)
    requireSoundtrack(timing.takeCutCue()?.kind == .impact, "The playback loop failed to restart cue scheduling")

    let battle = Dogfight(seed: 1860, initialFactions: [.colonial, .empire], initialArrivals: false, firstAtlantisEncounter: nil)
    battle.rocks.removeAll()
    battle.director.nextHighlightTime = 10_000
    battle.soundtrackTiming = timing
    battle.cameraAge = 8
    battle.cut = false
    timing.observe(position: 3.47)
    timing.observe(position: 3.51)
    battle.updateCamera(1.0 / 60)
    requireSoundtrack(battle.director.soundtrackCuts == 1, "The automatic camera missed a strong musical cue in an idle shot")

    battle.automatic = false
    battle.cameraAge = 8
    battle.cut = false
    let manualCamera = battle.cameraIndex
    timing.observe(position: 5.97)
    timing.observe(position: 6.01)
    battle.updateCamera(1.0 / 60)
    requireSoundtrack(battle.director.soundtrackCuts == 1 && battle.cameraIndex == manualCamera,
                      "A soundtrack cue overrode manual camera control")
    battle.automatic = true
    battle.cut = false
    battle.updateCamera(1.0 / 60)
    requireSoundtrack(battle.director.soundtrackCuts == 1, "Returning to automatic mode replayed an ignored cue")

    let arrival = Dogfight(seed: 1861, initialFactions: [.colonial, .empire], initialArrivals: false, firstAtlantisEncounter: nil)
    arrival.rocks.removeAll()
    for fighter in arrival.fighters {
        fighter.cooldown = 10_000
        fighter.collisionCooldown = 10_000
        if fighter.side == 0 { fighter.state = .destroyed; fighter.node.isHidden = true }
    }
    let visitCues: [SoundtrackCue] = [
        .init(time: 1.35, strength: 0.97, kind: .drop),
        .init(time: 2.15, strength: 0.99, kind: .impact),
        .init(time: 5.05, strength: 0.99, kind: .impact),
        .init(time: 6.45, strength: 0.99, kind: .drop)
    ]
    let visitTiming = SoundtrackTiming(analysis: SoundtrackAnalysis(duration: 15, cues: visitCues))
    arrival.soundtrackTiming = visitTiming
    visitTiming.observe(position: 0)
    arrival.deployReinforcements(side: 0)
    requireSoundtrack(arrival.carriers.count == 1, "The soundtrack arrival fixture failed to deploy a carrier")
    let carrier = arrival.carriers[0]
    requireSoundtrack(abs(Double(carrier.start + carrier.arrivalDuration) - visitCues[0].time) < 0.02,
                      "The carrier reveal did not line up with the nearby strong cue")

    var sawArrival = false
    var sawDeparture = false
    var sawHandoff = false
    for frame in 1...400 {
        visitTiming.observe(position: Double(frame) / 60)
        arrival.cameraAge = 9
        arrival.update(dt: 1.0 / 60)
        if arrival.director.event == .carrierArrival && carrier.blinkEntered { sawArrival = true }
        if arrival.director.event == .carrierArrival && carrier.departing { sawDeparture = true }
        if arrival.director.event == .handoff { sawHandoff = true }
        requireSoundtrack(arrival.director.soundtrackCuts == 0, "A music cut interrupted the carrier visit or handoff")
    }
    requireSoundtrack(sawArrival && sawDeparture && sawHandoff, "The aligned visit lost its arrival, departure, or handoff")
    print("PASS: soundtrack cues follow playback and looping, respect manual camera control, and align and preserve the carrier sequence.")
}

func verifySoundtrack() {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("AsteroidSquadron-Soundtrack-\(UUID())", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    do {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try verifySoundtrackAnalysis(in: directory)
    } catch {
        requireSoundtrack(false, "Soundtrack verification could not read or write its audio fixtures: \(error)")
    }
    verifySoundtrackTiming()
}
