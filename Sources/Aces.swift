import AppKit
import SceneKit
import simd

// One camera-facing set of hand-scratched tally marks for the sole Ace.
// It lives under the model so faction replacement still leaves one model root.
final class PilotTally {
    let node = SCNNode()
    private(set) var count = 0
    private var hoverHeight: Float = 5
    init() {
        node.name = "pilot.tally"
        let billboard = SCNBillboardConstraint(); billboard.freeAxes = .all
        node.constraints = [billboard]
    }
    func setCount(_ value: Int, on fighter: Fighter) {
        guard value != count else { return }
        count = value
        node.removeFromParentNode()
        for child in node.childNodes { child.removeFromParentNode() }
        guard value>0, let model = fighter.node.childNodes.first else { return }
        hoverHeight = max(2.5,Float(model.boundingBox.max.y)+2)
        model.addChildNode(node)
        let ink = material(color(1,0.77,0.32),emission:color(0.7,0.35,0.05))
        ink.lightingModel = .constant
        let shown = min(25,value), groups = (shown+4)/5
        for i in 0..<shown {
            let group = i/5, stroke = i%5
            let origin = Float(group)*2.45-Float(groups-1)*1.225-0.7
            let a: V3, b: V3
            if stroke == 4 { a = V3(origin-0.35,-0.1,0.02); b = V3(origin+1.75,1.9,0.02) }
            else {
                let x = origin+Float(stroke)*0.46
                let tilt = Float((i*7)%5-2)*0.035
                a = V3(x,-0.08,0); b = V3(x+tilt,1.85-Float(i%3)*0.06,0)
            }
            node.addChildNode(segment(a,b,radius:0.045,mat:ink))
        }
        if value>=4 {
            let label = SCNText(string:value>25 ? "ACE  +\(value-25)" : "ACE",extrusionDepth:0)
            label.font = NSFont.monospacedSystemFont(ofSize:1,weight:.semibold); label.flatness = 0.2
            let text = SCNNode(geometry:label); label.materials = [ink]
            let bounds = label.boundingBox
            text.simdPosition = V3(-Float(bounds.max.x-bounds.min.x)*0.5,2.35,0)
            node.addChildNode(text)
        }
        updatePose(fighter)
    }
    func updatePose(_ fighter: Fighter) {
        guard count>0 else { return }
        // World-up placement avoids labels wobbling around a rolling fighter.
        node.simdPosition = fighter.node.simdOrientation.inverse.act(V3(0,hoverHeight,0))
        node.isHidden = !fighter.active
    }
    func reset() {
        count = 0; node.removeFromParentNode()
        for child in node.childNodes { child.removeFromParentNode() }
    }
}

extension Dogfight {
    // The title is global across both factions. A tied incumbent keeps it;
    // without an incumbent, roster order makes the tie deterministic.
    func updateAce() {
        let qualified = fighters.indices.filter { fighters[$0].aceEligible }
        let mostKills = qualified.map { fighters[$0].enemyKills }.max()
        let leaders = qualified.filter { fighters[$0].enemyKills == mostKills }
        var selected: Int?
        if let current = acePilot, leaders.contains(current.index), fighters[current.index].generation == current.generation {
            selected = current.index
        } else { selected = leaders.first }
        let previous = acePilot
        acePilot = selected.map { ($0,fighters[$0].generation) }
        // Remove the previous marker before attaching its successor's marker.
        for i in fighters.indices where i != selected {
            fighters[i].isAce = false
            fighters[i].tally.setCount(0,on:fighters[i])
        }
        if let selected {
            let winner = fighters[selected]
            winner.isAce = true
            // Three completed encounters plus the current encounter starts at 4.
            winner.tally.setCount(winner.encountersSurvived+1,on:winner)
        }
        if let winner = acePilot, previous?.index != winner.index || previous?.generation != winner.generation {
            acePromotions += 1
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
        let survivors = fighters.filter { $0.side == side && $0.active }
        guard !survivors.isEmpty else { return }
        squadronEncounters[side] += 1
        encountersCompleted += 1
        for f in survivors {
            f.encountersSurvived += 1
        }
        updateAce()
        if squadronEncounters[side]>=2 {
            let losses = fighters.filter { $0.side == side && $0.state == .destroyed }
            if !losses.isEmpty {
                for f in losses { f.replaceFaction(sideFactions[side]) }
                deployReinforcements(side:side,topUp:true)
            }
        }
    }
}
