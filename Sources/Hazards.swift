import SceneKit
import simd

final class SpinOut {
    enum Cause { case asteroid, ship }
    let cause: Cause
    let origin: V3
    var velocity: V3
    let axis: V3
    let orientation: simd_quatf
    let duration: Float
    let fatal: Bool
    var age: Float = 0
    var recoveryOrientation: simd_quatf?
    init(origin: V3, velocity: V3, axis: V3, orientation: simd_quatf, duration: Float, fatal: Bool, cause: Cause = .asteroid) {
        self.cause = cause
        self.origin = origin; self.velocity = velocity; self.axis = axis; self.orientation = orientation
        self.duration = duration; self.fatal = fatal
    }
}

extension Dogfight {
    func tryAsteroidStrike(_ f: Fighter, from old: V3, dt: Float) {
        guard dt>0 else { return }
        var first: (Rock,Float)?
        for rock in rocks {
            if let t = sphereImpact(from:old,to:f.position,center:rock.position,radius:rock.radius+f.faction.collisionRadius), t<(first?.1 ?? 2) { first = (rock,t) }
        }
        guard let (rock,t) = first else { return }
        let contact = mix(old,f.position,t), normal = unit(contact-rock.position)
        f.position = contact+normal*0.02
        let speed = simd_length(f.velocity), incoming = simd_dot(f.velocity,normal)
        let incidence = max(0,-incoming/max(1,speed))
        var outgoing = f.velocity
        if incoming<0 { outgoing -= normal*incoming*1.6 }
        outgoing += normal*3
        f.velocity = outgoing
        f.spin = SpinOut(origin:f.position,velocity:outgoing,axis:unit(rng.vector(1)),orientation:f.node.simdOrientation,duration:rng.range(2.0,3.3),fatal:rng.next()<(incidence>0.75 && speed>70 ? 0.9 : 0.3+incidence*0.25))
        f.node.simdPosition = f.position; f.collisionCooldown = 0.3
        f.hitPoints = max(1,f.hitPoints-1)
        burst(at:rock.position+normal*rock.radius,count:16,big:false,velocity:outgoing*0.2)
        spinOuts += 1
        if let index = fighters.firstIndex(where:{$0 === f}) { director.requestSpin(index,in:self) }
    }
    func updateSpinOut(_ f: Fighter, dt: Float, positions: [V3], velocities: [V3], active: [Bool]) {
        guard let spin = f.spin else { return }
        spin.age += dt
        let old = f.position
        if spin.age<spin.duration {
            f.velocity = spin.velocity; f.position += f.velocity*dt; f.forward = unit(f.velocity)
            f.node.simdPosition = f.position
            f.node.simdOrientation = simd_quatf(angle:spin.age*3.6,axis:spin.axis)*spin.orientation
        } else if spin.fatal {
            asteroidLosses += 1; destroy(f); return
        } else {
            if spin.recoveryOrientation == nil { spin.recoveryOrientation = f.node.simdOrientation }
            let t = min(1,(spin.age-spin.duration)/2.2), ease = t*t*(3-2*t)
            updateFlight(f,dt:dt,positions:positions,velocities:velocities,active:active)
            f.node.simdOrientation = simd_slerp(spin.recoveryOrientation!,f.node.simdOrientation,ease)
            if t>=1 { f.spin = nil; recoveries += 1 }
        }
        if spin.age>0.15 {
            for rock in rocks {
                if let t = sphereImpact(from:old,to:f.position,center:rock.position,radius:rock.radius+f.faction.collisionRadius*0.5) {
                    f.position = mix(old,f.position,t); f.node.simdPosition = f.position
                    asteroidLosses += 1; destroy(f); break
                }
            }
        }
    }

}

extension SIMD4 where Scalar == Float {
    var xyz: SIMD3<Float> { SIMD3(x,y,z) }
}
