import SceneKit
import simd

// Segment/sphere time of impact, including a projectile that starts inside its volume.
func sphereImpact(from a: V3, to b: V3, center: V3, radius: Float) -> Float? {
    let offset = a-center, delta = b-a, c = simd_dot(offset,offset)-radius*radius
    if c<=0 { return 0 }
    let length = simd_dot(delta,delta)
    guard length>0.000001 else { return nil }
    let projection = simd_dot(offset,delta), disc = projection*projection-length*c
    guard disc>=0 else { return nil }
    let t = (-projection-sqrt(disc))/length
    return t>=0 && t<=1 ? t : nil
}

func interceptPoint(from origin: V3, velocity: V3, target: V3, targetVelocity: V3, speed: Float) -> V3 {
    let p = target-origin, v = targetVelocity-velocity
    let a = simd_dot(v,v)-speed*speed, b = 2*simd_dot(p,v), c = simd_dot(p,p)
    var t = sqrt(c)/speed
    let disc = b*b-4*a*c
    if abs(a)>0.0001 && disc>=0 {
        let x = (-b-sqrt(disc))/(2*a), y = (-b+sqrt(disc))/(2*a)
        let positive = [x,y].filter{$0>0}
        if let first = positive.min() { t = first }
    }
    return target+v*min(2,t)
}

extension Faction {
    var collisionRadius: Float {
        switch self { case .rebel: return 6.7; case .empire: return 5.5; case .colonial: return 7; case .cylon: return 8.7 }
    }
    var hitVolumes: [(V3,Float)] {
        switch self {
        case .rebel: return [(V3(0,0,-1),1.2),(V3(0,0,-4),0.65),(V3(-3,1,0.4),1.1),(V3(3,1,0.4),1.1),(V3(-3,-1,0.4),1.1),(V3(3,-1,0.4),1.1)]
        case .empire: return [(.zero,1.3),(V3(-3.1,0,0),2.6),(V3(3.1,0,0),2.6)]
        case .colonial: return [(V3(0,0,-1),1.25),(V3(0,0,-4.5),0.6),(V3(-2.6,-0.3,1.5),1),(V3(2.6,-0.3,1.5),1)]
        case .cylon: return [(V3(0,0,-0.7),1.3),(V3(-3,0,-1),1.2),(V3(3,0,-1),1.2),(V3(-5,0,-3.4),0.8),(V3(5,0,-3.4),0.8)]
        }
    }
}

extension Dogfight {
    @discardableResult func fire(from index: Int, to targetIndex: Int) -> Bool {
        let f = fighters[index], target = fighters[targetIndex]
        guard f.active, f.spin == nil, target.active, f.side != target.side else { return false }
        let barrels = f.firingMuzzles
        let aligned = barrels.contains { muzzle in
            let matrix = muzzle.simdWorldTransform, origin = matrix.columns.3.xyz, forward = unit(-matrix.columns.2.xyz)
            let lead = interceptPoint(from:origin,velocity:f.velocity,target:target.position,targetVelocity:target.velocity,speed:f.faction.projectileSpeed)
            let cone: Float = f.burstShotsLeft>0 ? 0.9848 : 0.9945 // 10° continuing / 6° opening burst.
            return simd_dot(unit(lead-origin),forward)>cone && simd_distance(origin,lead)<700
        }
        guard aligned else { return false }
        let generations = fighters.map(\.generation)
        for muzzle in barrels {
            let transform = muzzle.simdWorldTransform
            let origin = transform.columns.3.xyz, forward = unit(-transform.columns.2.xyz)
            let length: Float = f.faction.usesBlinkFTL ? 1.3 : 4.2
            let bolt = SCNNode(); bolt.simdPosition = origin
            bolt.addChildNode(box(V3(0.1,0.1,length),projectileMaterials[f.faction]!,V3(0,0,-length/2)))
            bolt.simdOrientation = simd_quatf(from:V3(0,0,-1),to:forward)
            scene.rootNode.addChildNode(bolt)
            lasers.append(Laser(node:bolt,position:origin,velocity:forward*f.faction.projectileSpeed+f.velocity,life:1.8,sourceSide:f.side,generations:generations,launchOrigin:origin,launchForward:forward,inheritedVelocity:f.velocity,length:length))
        }
        shots += barrels.count; f.gunCycle += 1
        return true
    }
    func updateLasers(_ dt: Float) {
        for i in lasers.indices.reversed() {
            lasers[i].life -= dt
            let forward = unit(lasers[i].velocity)
            let from = lasers[i].position+forward*lasers[i].length
            lasers[i].position += lasers[i].velocity*dt
            let to = lasers[i].position+forward*lasers[i].length
            lasers[i].node.simdPosition = lasers[i].position
            var fraction: Float = 2
            var victim: Fighter?
            for (j,f) in fighters.enumerated() where f.active && f.side != lasers[i].sourceSide && f.generation == lasers[i].generations[j] {
                for (center,radius) in f.faction.hitVolumes {
                    let world = f.node.simdConvertPosition(center,to:nil)
                    if let hit = sphereImpact(from:from,to:to,center:world,radius:radius), hit<fraction { fraction = hit; victim = f }
                }
            }
            for rock in rocks {
                if let hit = sphereImpact(from:from,to:to,center:rock.position,radius:rock.radius), hit<fraction { fraction = hit; victim = nil }
            }
            if fraction<=1 {
                let impact = mix(from,to,fraction)
                burst(at:impact,count:4,big:false)
                if let victim {
                    weaponHits += 1
                    victim.hitPoints -= 1
                    if victim.hitPoints<=0 { destroy(victim) }
                }
            }
            if fraction<=1 || lasers[i].life<=0 { lasers[i].node.removeFromParentNode(); lasers.remove(at:i) }
        }
    }
}
