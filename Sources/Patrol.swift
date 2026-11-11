import simd

extension Dogfight {
    // Long, fixed legs alternate between the belt's interior and its outer edge.
    // Plan against rock clearance, then let the normal flight controller fly the route.
    func patrolDestination(for fighter: Fighter) -> V3 {
        if let first = fighter.patrolRoute.first,
           simd_distance_squared(first,fighter.position)<65*65 {
            fighter.patrolRoute.removeFirst()
        }
        if fighter.patrolRoute.isEmpty {
            fighter.patrolRoute = planPatrol(for:fighter)
        }
        return fighter.patrolRoute.first ?? fighter.position+fighter.forward*300
    }

    private func planPatrol(for fighter: Fighter) -> [V3] {
        var route: [V3] = []
        var origin = fighter.position
        var forward = fighter.forward
        let direction: Float = fighter.pair%2 == 0 ? 1 : -1
        for leg in 0..<8 {
            let local = arenaRotation.inverse.act(origin)
            let angle = atan2(local.x,local.z)
            // Fighters leaving a siege may initially face away from the belt.
            // Outside the field they have room for a full turn onto the route.
            let outsideBelt = simd_length_squared(local)>1000*1000
            let preferredRadius: Float = (leg+fighter.side)%2 == 0 ? 650 : 225
            var best: V3?
            var bestScore: Float = -.infinity
            for attempt in 0..<44 {
                let a = angle+direction*rng.range(0.6,1.65)
                let radius = attempt<30 ? preferredRadius+rng.range(-90,115) : rng.range(180,920)
                let candidate = arenaRotation.act(V3(sin(a)*radius,rng.range(-170,170),cos(a)*radius))
                let offset = candidate-origin
                let distance = simd_length(offset)
                guard distance>220 else { continue }
                let heading = offset/distance
                let alignment = simd_dot(heading,forward)
                guard outsideBelt || alignment > -0.8 else { continue }
                let clearance = fighter.faction.collisionRadius+25
                let blocked = rocks.contains { rock in
                    let separation = origin-rock.position
                    let keepOut = rock.radius+clearance
                    if simd_length_squared(separation)<keepOut*keepOut,
                       simd_dot(separation,heading)>0 {
                        return false
                    }
                    return sphereImpact(from:origin,to:candidate,center:rock.position,radius:keepOut) != nil
                }
                if blocked { continue }
                let score = alignment*200 + min(650,distance)*0.12 - abs(radius-preferredRadius)*0.3
                if score>bestScore { bestScore = score; best = candidate }
            }
            guard let best else { break }
            route.append(best)
            forward = unit(best-origin)
            origin = best
        }
        return route
    }
}
