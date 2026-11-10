import SceneKit
import simd

extension CinematicDirector {
    func rememberIncomingSquadron(_ ship: Carrier, in b: Dogfight) {
        handoffIncoming = ship.squadron.map { ($0,b.fighters[$0].generation) }
        handoffExisting = b.fighters.indices.filter { b.fighters[$0].active && !ship.squadron.contains($0) }.map { ($0,b.fighters[$0].generation) }
        handoffAnchor = nil
    }

    @discardableResult func startArrivalHandoff(in b: Dogfight) -> Bool {
        guard b.automatic else { return false }
        handoffAnchor = nil
        guard arrivalHandoffFrame(in:b) != nil else { return false }
        begin(.handoff,in:b)
        return true
    }

    func arrivalHandoffFrame(in b: Dogfight) -> (position: V3,look: V3,fov: Float)? {
        let incoming = handoffIncoming.filter { b.fighters[$0.index].active && b.fighters[$0.index].generation == $0.generation }.map { b.fighters[$0.index] }
        let existing = handoffExisting.filter { b.fighters[$0.index].active && b.fighters[$0.index].generation == $0.generation }.map { $0.index }
        guard !incoming.isEmpty, !existing.isEmpty else { return nil }
        let center = incoming.reduce(V3.zero) { $0+$1.position }/Float(incoming.count)
        let changed = handoffAnchor == nil || !existing.contains(handoffAnchor!)
        if changed {
            handoffAnchor = existing.min { simd_distance_squared(b.fighters[$0].position,center)<simd_distance_squared(b.fighters[$1].position,center) }
            if event == .handoff { b.cut = true }
        }
        let index = handoffAnchor!, fighter = b.fighters[index]
        b.followedIndex = index
        let direction = unit(center-fighter.position)
        // Use the stern when the pilot faces the arrivals. If it is flying away,
        // slide to the far shoulder so both the old ship and the arrivals stay ahead.
        let alignment = simd_dot(fighter.forward,direction)
        let blend = max(0,min(1,(alignment-0.93)/0.065))
        let rearDirection = unit(mix(direction,fighter.forward,blend))
        let rear = max(55,fighter.faction.collisionRadius*7)/max(0.65,simd_dot(rearDirection,direction))/min(1,b.viewportAspect)
        let right = unit(simd_cross(direction,V3(0,1,0)))
        let base = fighter.position-rearDirection*rear
        if changed {
            var best = -1
            let offsets: [(Float,Float)] = [(8,6),(-8,6),(8,8),(-8,8)]
            for (side,height) in offsets {
                let point = b.clearCamera(base+right*side+V3(0,height,0))
                let visible = incoming.filter { f in
                    !b.rocks.contains { sphereImpact(from:point,to:f.position,center:$0.position,radius:$0.radius) != nil }
                }.count
                if visible>best { best = visible; handoffSide = side; handoffHeight = height }
            }
        }
        let position = base+right*handoffSide+V3(0,handoffHeight,0)
        let radius = incoming.map { simd_distance($0.position,center)+$0.faction.collisionRadius }.max() ?? 20
        let angularSize = 2*atan2(radius,max(1,simd_distance(position,center)))*180/Float.pi
        return (position,center,max(50,min(64,angularSize*1.15)))
    }
}
