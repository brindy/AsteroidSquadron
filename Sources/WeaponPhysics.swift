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
        switch self { case .rebel: return 6.7; case .empire: return 5.5; case .colonial: return 7; case .cylon: return 8.7; case .earth: return 7.3; case .shadow: return 8; case .tauri: return 7; case .goauld: return 8; case .wraith: return 8.1 }
    }
    var hitVolumes: [(V3,Float)] {
        switch self {
        case .rebel: return [(V3(0,0,-1),1.2),(V3(0,0,-4),0.65),(V3(-3,1,0.4),1.1),(V3(3,1,0.4),1.1),(V3(-3,-1,0.4),1.1),(V3(3,-1,0.4),1.1)]
        case .empire: return [(.zero,1.3),(V3(-3.1,0,0),2.6),(V3(3.1,0,0),2.6)]
        case .colonial: return [(V3(0,0,-1),1.25),(V3(0,0,-4.5),0.6),(V3(-2.6,-0.3,1.5),1),(V3(2.6,-0.3,1.5),1)]
        case .cylon: return [(V3(0,0,-0.7),1.3),(V3(-3,0,-1),1.2),(V3(3,0,-1),1.2),(V3(-5,0,-3.4),0.8),(V3(5,0,-3.4),0.8)]
        case .earth: return [(.zero,1.4),(V3(-4.5,-3.2,0.9),1.2),(V3(-4.5,3.2,0.9),1.2),(V3(4.5,-3.2,0.9),1.2),(V3(4.5,3.2,0.9),1.2)]
        case .tauri: return [(V3(0,0,-2),1.15),(V3(0,0,-4.7),0.6),(V3(0,0,2),1.6),(V3(-3.4,0,2),1.0),(V3(3.4,0,2),1.0)]
        case .goauld: return [(V3(0,0,-1.8),1.22),(V3(0,0,1.5),1.3),(V3(-3.1,0,1),1.15),(V3(3.1,0,1),1.15),(V3(-5.5,-0.35,-0.6),0.85),(V3(5.5,-0.35,-0.6),0.85)]
        case .wraith: return [(V3(0,0,0.3),1.5),(V3(0,0,-2.75),0.8),(V3(0,0,-5.2),0.44),(V3(-2.7,-0.2,2.7),0.85),(V3(2.7,-0.2,2.7),0.85)]
        case .shadow: return [(V3(0,0,0.4),1.7),(V3(-4,0,0),1.2),(V3(4,0,0),1.2),(V3(-3,0,-3),0.7),(V3(3,0,-3),0.7)]
        }
    }
}

extension Dogfight {
    @discardableResult func fire(from index: Int, to targetIndex: Int) -> Bool {
        let f = fighters[index], target = fighters[targetIndex]
        guard !fleetTruce, f.active, f.spin == nil, time>=f.breakUntil, target.active, f.side != target.side else { return false }
        let barrels = f.firingMuzzles
        let aligned = barrels.contains { muzzle in
            let matrix = muzzle.simdWorldTransform, origin = matrix.columns.3.xyz, forward = unit(-matrix.columns.2.xyz)
            let lead = interceptPoint(from:origin,velocity:f.velocity,target:target.position,targetVelocity:target.velocity,speed:f.faction.projectileSpeed)
            let cone: Float = f.burstShotsLeft>0 ? 0.9848 : 0.9945 // 10° continuing / 6° opening burst.
            return simd_dot(unit(lead-origin),forward)>cone && simd_distance(origin,lead)<700
        }
        guard aligned else { return false }
        launchVolley(from:index,targetsAtlantis:false)
        return true
    }

    func fireAtAtlantis(from index: Int, city: Atlantis) -> Bool {
        let fighter = fighters[index]
        guard city.intact, fighter.active, fighter.spin == nil, fighter.atlantisEgress == nil,
              city.distanceToSurface(from:fighter.position)<=Atlantis.attackRange else { return false }
        let aligned = fighter.firingMuzzles.contains { muzzle in
            let transform = muzzle.simdWorldTransform
            let origin = transform.columns.3.xyz
            let aim = unit(-transform.columns.2.xyz)
            return city.impact(from:origin,to:origin+aim*(Atlantis.attackRange+25)) != nil
        }
        guard aligned else { return false }
        launchVolley(from:index,targetsAtlantis:true)
        director.requestAtlantisAttack(index,in:self)
        return true
    }

    private func launchVolley(from index: Int, targetsAtlantis: Bool) {
        let f = fighters[index]
        let barrels = f.firingMuzzles
        let generations = fighters.map(\.generation)
        for muzzle in barrels {
            let transform = muzzle.simdWorldTransform
            let origin = transform.columns.3.xyz, forward = unit(-transform.columns.2.xyz)
            let length: Float = (f.faction.usesBlinkFTL || f.faction.usesJumpWindow) ? 1.3 : 4.2
            let bolt = SCNNode(); bolt.simdPosition = origin
            bolt.addChildNode(box(V3(0.1,0.1,length),projectileMaterials[f.faction]!,V3(0,0,-length/2)))
            bolt.simdOrientation = simd_quatf(from:V3(0,0,-1),to:forward)
            scene.rootNode.addChildNode(bolt)
            lasers.append(Laser(node:bolt,position:origin,velocity:forward*f.faction.projectileSpeed+f.velocity,life:1.8,sourceSide:f.side,generations:generations,launchOrigin:origin,launchForward:forward,inheritedVelocity:f.velocity,length:length,sourceIndex:index,targetsAtlantis:targetsAtlantis))
        }
        shots += barrels.count; f.gunCycle += 1
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
            for (j,f) in fighters.enumerated() where !fleetTruce && !lasers[i].targetsAtlantis && f.active && f.side != lasers[i].sourceSide && lasers[i].generations.indices.contains(j) && f.generation == lasers[i].generations[j] {
                for (center,radius) in f.faction.hitVolumes {
                    let world = f.node.simdConvertPosition(center,to:nil)
                    if let hit = sphereImpact(from:from,to:to,center:world,radius:radius), hit<fraction { fraction = hit; victim = f }
                }
            }
            for rock in rocks {
                if let hit = sphereImpact(from:from,to:to,center:rock.position,radius:rock.radius), hit<fraction { fraction = hit; victim = nil }
            }
            var cityHit: Atlantis?
            if lasers[i].targetsAtlantis, let city = atlantis, city.intact,
               let hit = city.impact(from:from,to:to), hit<fraction {
                fraction = hit
                cityHit = city
            }
            if fraction<=1 {
                let impact = mix(from,to,fraction)
                if let city = cityHit {
                    if city.shieldPoints==0 { burst(at:impact,count:6,big:false,scale:3) }
                    hitAtlantis(city,at:impact,damage:lasers[i].atlantisDamage)
                } else {
                    burst(at:impact,count:4,big:false)
                }
                if let victim {
                    weaponHits += 1
                    victim.hitPoints -= 1
                    if victim.hitPoints<=0 {
                        creditWeaponKill(from:lasers[i],victim:victim)
                        destroy(victim)
                    }
                }
            }
            if fraction<=1 || lasers[i].life<=0 { lasers[i].node.removeFromParentNode(); lasers.remove(at:i) }
        }
    }
}
