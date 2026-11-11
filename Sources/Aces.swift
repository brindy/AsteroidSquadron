import AppKit
import SceneKit
import simd

// A single gold, camera-facing star. The world-up offset follows the hull
// without spinning around it when the pilot banks or tumbles.
final class AceBadge {
    let node = SCNNode()
    private var hoverHeight: Float = 5
    var visible: Bool { node.parent != nil }

    init() {
        node.name = "pilot.ace"
        node.constraints = [SCNBillboardConstraint()]
    }

    func attach(to fighter: Fighter) {
        guard let model = fighter.node.childNodes.first else { return }
        if node.geometry == nil {
            let star = NSBezierPath()
            for i in 0..<10 {
                let angle = CGFloat(i)*CGFloat.pi/5+CGFloat.pi/2
                let radius: CGFloat = i%2 == 0 ? 2.4 : 1.02
                let point = NSPoint(x:cos(angle)*radius,y:sin(angle)*radius)
                if i == 0 { star.move(to:point) } else { star.line(to:point) }
            }
            star.close()
            let shape = SCNShape(path:star,extrusionDepth:0.08)
            let gold = material(color(1,0.76,0.28))
            gold.lightingModel = .constant
            gold.isDoubleSided = true
            shape.materials = [gold]
            node.geometry = shape
        }
        hoverHeight = max(4,Float(model.boundingBox.max.y)+4)
        model.addChildNode(node)
        updatePose(fighter)
    }

    func updatePose(_ fighter: Fighter) {
        guard visible else { return }
        node.simdPosition = fighter.node.simdOrientation.inverse.act(V3(0,hoverHeight,0))
        node.isHidden = !fighter.active
    }

    func reset() {
        node.removeFromParentNode()
    }
}

extension Dogfight {
    var aceHUDStatus: String {
        if let acePilot {
            let pilot = fighters[acePilot.index]
            if pilot.active && pilot.generation == acePilot.generation {
                return "★  CURRENT ACE   ·   KILLS \(pilot.enemyKills)   ·   ENCOUNTERS SURVIVED \(pilot.encountersSurvived)"
            }
        }
        let vacant = "CURRENT ACE  VACANT   ·   KILLS —"
        return aceKillRecord>0 ? vacant+"   ·   RECORD TO BEAT \(aceKillRecord)" : vacant
    }

    func updateAce() {
        let previous = acePilot
        var incumbent: Int?
        if let previous {
            let pilot = fighters[previous.index]
            if pilot.active && pilot.generation == previous.generation {
                incumbent = previous.index
                aceKillRecord = max(aceKillRecord,pilot.enemyKills)
            }
        }

        var selected = incumbent
        var bestKills = aceKillRecord
        for i in fighters.indices where fighters[i].aceEligible && fighters[i].enemyKills>bestKills {
            selected = i
            bestKills = fighters[i].enemyKills
        }
        aceKillRecord = bestKills

        let next = selected.map { (index:$0,generation:fighters[$0].generation) }
        guard previous?.index != next?.index || previous?.generation != next?.generation else { return }
        if let previous {
            fighters[previous.index].isAce = false
            fighters[previous.index].aceBadge.reset()
        }
        acePilot = next
        if let next {
            let winner = fighters[next.index]
            winner.isAce = true
            winner.aceBadge.attach(to:winner)
            acePromotions += 1
            if honouredAceGenerations[next.index] != next.generation {
                acesEmerged += 1
                honouredAceGenerations[next.index] = next.generation
            }
        }
    }

    func creditWeaponKill(from shot: Laser, victim: Fighter) {
        guard let index = shot.sourceIndex, fighters.indices.contains(index), shot.generations.indices.contains(index) else { return }
        let shooter = fighters[index]
        guard shooter.side == shot.sourceSide, shooter.side != victim.side,
              shooter.generation == shot.generations[index] else { return }
        // A shot belongs to the pilot who fired it, not a replacement occupying
        // the same slot. Destruction refreshes the title after this increment.
        shooter.enemyKills += 1
    }

    func creditEncounter(surviving side: Int) {
        creditEncounter(survivingSides:[side])
    }

    func creditEncounter(survivingSides sides: [Int], replenish: Bool = true) {
        let survivors = fighters.filter { sides.contains($0.side) && $0.active }
        guard !survivors.isEmpty else { return }
        encountersCompleted += 1
        for f in survivors {
            f.encountersSurvived += 1
            longestEncounterStreak = max(longestEncounterStreak,f.encountersSurvived)
        }
        for side in sides where survivors.contains(where:{$0.side == side}) {
            squadronEncounters[side] += 1
            if replenish { refillVeteranSquadron(side:side) }
        }
        updateAce()
    }

    func refillVeteranSquadron(side: Int) {
        guard squadronEncounters[side]>=2, sideCount(side)>0, !pendingSides.contains(side) else { return }
        let losses = fighters.filter { $0.side == side && !$0.isSiegeReserve && $0.state == .destroyed }
        guard !losses.isEmpty else { return }
        for f in losses { f.replaceFaction(sideFactions[side]) }
        deployReinforcements(side:side,topUp:true)
    }
}
