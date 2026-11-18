import SceneKit
import simd

struct SectorDeparture {
    static let wipeDuration: Float = 1.16
    static let revealDuration: Float = 1.12
    static let establishingDuration: Float = 3.35

    let side: Int
    let leader: Int
    let started: Float
    let origin: V3
    let heading: V3
    let across: V3
    var wipeStart: Float?

    func destination(for fighter: Fighter) -> V3 {
        let along = simd_dot(fighter.position-origin,heading)
        let column = Float(fighter.pair/2)-1
        let row: Float = fighter.trailing ? 1 : -1
        return origin+heading*(max(980,along+430)-row*35)+across*(column*59)+V3(0,row*27,0)
    }

    func wipeCoverage(at time: Float) -> Float {
        wipeStart.map { min(1,max(0,(time-$0)/Self.wipeDuration)) } ?? 0
    }
}

extension Dogfight {
    var showingSector: Bool { time<sectorEstablishingUntil }

    // A victory retires the winning pilots from the sector without logging a loss.
    @discardableResult func scheduleSectorDeparture(for winner: Int) -> Bool {
        guard let threshold = sectorWaveLimit, encountersCompleted>=threshold, sideCount(winner)>0 else { return false }
        let indices = fighters.indices.filter { fighters[$0].side == winner && fighters[$0].active }
        let live = indices.map { fighters[$0] }
        let count = Float(live.count)
        let center = live.reduce(V3.zero) { $0+$1.position }/count
        let direction = live.reduce(V3.zero) { $0+$1.velocity }
        let tangent = unit(simd_cross(landmarkPosition,V3(0,1,0)))
        let sign: Float = simd_dot(tangent,direction)<0 ? -1 : 1
        let heading = unit(tangent*sign+V3(0,0.24,0))
        let across = unit(simd_cross(heading,V3(0,1,0)))
        let leader = indices.max { simd_dot(fighters[$0].velocity,heading)<simd_dot(fighters[$1].velocity,heading) }!
        sectorDeparture = SectorDeparture(side:winner,leader:leader,started:time,origin:center,heading:heading,across:across)
        for fighter in live {
            fighter.breakUntil = -1
            fighter.pivotUntil = -100
            fighter.victoryWaypoint = nil
            fighter.attackTarget = nil
        }
        cut = true
        cameraChanged?()
        return true
    }

    func updateSectorDeparture() {
        guard var flight = sectorDeparture, flight.wipeStart == nil, time-flight.started>=5.8 else { return }
        let survivors = fighters.filter { $0.side == flight.side && $0.active }
        let ready = survivors.allSatisfy { fighter in
            let forwardTravel = simd_dot(fighter.position-flight.origin,flight.heading)
            return forwardTravel>500 && simd_dot(unit(fighter.velocity),flight.heading)>0.83
        }
        if ready || time-flight.started>=11.5 {
            flight.wipeStart = time
            sectorDeparture = flight
        }
    }

    func followingSector(backdrop: (kind: SectorLandmark,waves: Int)) -> Dogfight {
        let untilAtlantis = nextAtlantisEncounter.map { max(1,$0-encountersCompleted) }
        let nextSeed = seed &+ 0x9E37_79B9_7F4A_7C15
        var roster = Random(state:nextSeed ^ 0x464C_4545_5453)
        var factions = Faction.allCases.filter { !sideFactions.contains($0) }
        let first = factions.remove(at:roster.index(factions.count))
        let next = Dogfight(seed:nextSeed,initialFactions:[first,factions[roster.index(factions.count)]],
                            firstAtlantisEncounter:nil,landmark:backdrop.kind,
                            sectorWaveLimit:backdrop.waves,sectorEstablishingUntil:SectorDeparture.establishingDuration,
                            soundtrackTiming:automatic ? soundtrackTiming : nil)
        next.aceKillRecord = aceKillRecord
        next.acesEmerged = acesEmerged
        next.longestEncounterStreak = longestEncounterStreak
        next.nextAtlantisEncounter = untilAtlantis
        next.manualAtlantisSiegeQueued = manualAtlantisSiegeQueued
        next.atlantisRandom = atlantisRandom
        next.automatic = automatic
        next.cameraIndex = cameraIndex
        next.viewportAspect = viewportAspect
        next.cut = true
        next.updateCamera(0)
        return next
    }
}
