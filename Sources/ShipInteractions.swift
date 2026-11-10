import SceneKit
import simd

struct ShipContact: Hashable {
    let first: Int
    let second: Int
    let firstGeneration: Int
    let secondGeneration: Int
}

extension Dogfight {
    // Both pilots use the same snapshot and choose opposite sides of a passing plane.
    // This also breaks the symmetry of a perfectly head-on approach.
    func shipAvoidance(_ f: Fighter, positions: [V3], velocities: [V3], active: [Bool], speed: inout Float) -> V3 {
        guard let index = fighters.firstIndex(where:{$0 === f}) else { return .zero }
        let travel = f.faction == .earth ? unit(f.velocity) : f.forward
        var steering = V3.zero
        for j in fighters.indices where j != index && active[j] {
            let other = fighters[j]
            let friendly = f.side == other.side
            let horizon: Float = friendly ? 3.5 : 2.25
            let offset = positions[index]-positions[j], relative = velocities[index]-velocities[j]
            let distance = simd_length(offset)
            let spacing = f.faction.collisionRadius+other.faction.collisionRadius+(friendly ? 14 : 10)
            let relativeSquared = simd_length_squared(relative)
            let closestTime = relativeSquared>0.01 ? max(0,min(horizon,-simd_dot(offset,relative)/relativeSquared)) : 0
            guard distance<spacing*1.5+sqrt(relativeSquared)*horizon else { continue }
            let closest = offset+relative*closestTime, miss = simd_length(closest)
            if miss<spacing && (closestTime>0 || distance<spacing*1.5) {
                var lateral = closest-travel*simd_dot(closest,travel)
                if simd_length_squared(lateral)<0.25 {
                    let commonVelocity = index<j ? relative : -relative
                    let axis = abs(unit(commonVelocity).y)<0.85 ? V3(0,1,0) : V3(1,0,0)
                    lateral = unit(simd_cross(commonVelocity,axis))*(index<j ? 1 : -1)
                    if relativeSquared<0.01 { lateral = V3(index<j ? 1 : -1,0,0) }
                }
                let urgency = 1-closestTime/horizon
                steering += unit(lateral)*(0.8+urgency*4)*(1-miss/spacing)
                // Brake when gaining on a ship ahead; never accelerate into its tail.
                if simd_dot(unit(-offset),travel)>0.35 && closestTime<1.8 {
                    speed = min(speed,max(f.cruiseSpeed*(friendly ? 0.65 : 0.85),simd_length(f.velocity)-35))
                }
            }
            if distance<spacing*1.5 {
                steering += unit(offset)*max(0,1-distance/(spacing*1.5))*3
            }
        }
        return bounded(steering,length:6)
    }

    func resolveShipCollisions(from starts: [V3], wasActive: [Bool], dt: Float) {
        guard dt>0 else { return }
        var contacts = Set<ShipContact>()
        for i in fighters.indices where fighters[i].active {
            for j in fighters.indices where j>i && fighters[j].active {
                let a = fighters[i], b = fighters[j]
                guard a.active else { break }
                let radius = a.faction.collisionRadius+b.faction.collisionRadius
                let key = ShipContact(first:i,second:j,firstGeneration:a.generation,secondGeneration:b.generation)
                let startA = wasActive[i] ? starts[i] : a.position
                let startB = wasActive[j] ? starts[j] : b.position
                let offset = a.position-b.position
                // Relative swept spheres catch crossings even if the endpoints do not overlap.
                guard let t = sphereImpact(from:startA-startB,to:offset,center:.zero,radius:radius) else {
                    if shipContacts.contains(key) && simd_length(offset)<radius+1 { contacts.insert(key) }
                    continue
                }
                contacts.insert(key)
                let contactA = mix(startA,a.position,t), contactB = mix(startB,b.position,t)
                let separation = contactA-contactB
                let normal = simd_length_squared(separation)>0.0001 ? unit(separation) : unit(-(a.velocity-b.velocity)+V3(0.001,0,0))
                let relative = a.velocity-b.velocity, closing = simd_dot(relative,normal)
                // Equal-mass inelastic impact: conserve total momentum, dissipate energy.
                let impulse = max(0,-closing)*0.625
                a.velocity += normal*impulse; b.velocity -= normal*impulse
                let remaining = dt*(1-t)
                a.position = contactA+a.velocity*remaining; b.position = contactB+b.velocity*remaining
                separate(a,b,normal:normal,radius:radius)
                if !shipContacts.contains(key) {
                    shipCollisions += 1
                    let tangent = simd_length(relative-normal*closing)
                    let severity = max(0,-closing)+min(30,tangent*0.15)
                    let damage = max(1,Int(ceil(max(0,severity-8)/18)))
                    let impact = contactA-normal*a.faction.collisionRadius
                    burst(at:impact,count:12,big:false,velocity:(a.velocity+b.velocity)*0.5)
                    for f in [a,b] {
                        f.hitPoints -= damage
                        if f.hitPoints<=0 { shipCollisionLosses += 1; destroy(f) }
                        else {
                            if let spin = f.spin { spin.velocity = f.velocity }
                            else {
                                f.spin = SpinOut(origin:f.position,velocity:f.velocity,axis:unit(rng.vector(1)),orientation:f.node.simdOrientation,duration:0.7,fatal:false,cause:.ship)
                            }
                            f.node.simdPosition = f.position
                        }
                    }
                    if a.active { director.requestSpin(i,in:self) }
                    else if b.active { director.requestSpin(j,in:self) }
                }
                for f in [a,b] where f.active { f.spin?.velocity = f.velocity; f.node.simdPosition = f.position }
            }
        }
        // A pile-up can push a third hull: solve all remaining penetrations without
        // charging damage again every physics tick for one sustained contact.
        for _ in 0..<8 {
            for i in fighters.indices where fighters[i].active {
                for j in fighters.indices where j>i && fighters[j].active {
                    let a = fighters[i], b = fighters[j], delta = a.position-b.position
                    let radius = a.faction.collisionRadius+b.faction.collisionRadius
                    if simd_length_squared(delta)<radius*radius {
                        separate(a,b,normal:unit(delta),radius:radius)
                    }
                }
            }
        }
        shipContacts = contacts
    }

    private func separate(_ a: Fighter, _ b: Fighter, normal: V3, radius: Float) {
        let penetration = radius+0.02-simd_distance(a.position,b.position)
        if penetration>0 {
            a.position += normal*penetration*0.5; b.position -= normal*penetration*0.5
        }
        a.node.simdPosition = a.position; b.node.simdPosition = b.position
    }
}
