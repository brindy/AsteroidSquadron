import SceneKit
import simd

final class SpinOut {
    let origin: V3
    let velocity: V3
    let axis: V3
    let orientation: simd_quatf
    let duration: Float
    let fatal: Bool
    var age: Float = 0
    var recoveryPosition: V3?
    var recoveryOrientation: simd_quatf?
    init(origin: V3, velocity: V3, axis: V3, orientation: simd_quatf, duration: Float, fatal: Bool) {
        self.origin = origin; self.velocity = velocity; self.axis = axis; self.orientation = orientation
        self.duration = duration; self.fatal = fatal
    }
}

extension Dogfight {
    func tryAsteroidStrike(_ f: Fighter, dt: Float) {
        guard f.collisionCooldown<=0, time>f.entryTime+17, dt>0 else { return }
        guard let rock = rocks.first(where:{simd_distance(f.position,$0.position)<$0.radius+11}) else { return }
        guard rng.next()<dt*0.7 else { return }
        let normal = unit(f.position-rock.position)
        f.position = rock.position+normal*(rock.radius+6)
        let speed = max(22,simd_distance(path(f,time+0.1),path(f,time))/0.1)
        var velocity = f.forward*min(65,speed)
        let incoming = simd_dot(velocity,normal)
        if incoming<0 { velocity -= normal*incoming*1.7 }
        velocity += normal*10
        f.spin = SpinOut(origin:f.position,velocity:velocity,axis:unit(rng.vector(1)),orientation:f.node.simdOrientation,duration:rng.range(2.0,3.3),fatal:rng.next()<0.43)
        f.node.simdPosition = f.position; f.collisionCooldown = rng.range(40,80)
        f.hitPoints = max(1,f.hitPoints-1)
        burst(at:rock.position+normal*rock.radius,count:16,big:false,velocity:velocity*0.2)
        spinOuts += 1
        if let index = fighters.firstIndex(where:{$0 === f}) { director.requestSpin(index,in:self) }
    }
    func updateSpinOut(_ f: Fighter, dt: Float) {
        guard let spin = f.spin else { return }
        spin.age += dt
        if spin.age<spin.duration {
            f.position = spin.origin+spin.velocity*spin.age
            f.forward = unit(spin.velocity)
            f.node.simdPosition = f.position
            f.node.simdOrientation = simd_quatf(angle:spin.age*3.6,axis:spin.axis)*spin.orientation
            if spin.age>0.3 && rocks.contains(where:{simd_distance(f.position,$0.position)<$0.radius+3}) {
                asteroidLosses += 1; destroy(f)
            }
        } else if spin.fatal {
            asteroidLosses += 1; destroy(f)
        } else {
            if spin.recoveryPosition == nil {
                spin.recoveryPosition = f.position; spin.recoveryOrientation = f.node.simdOrientation
            }
            let age = spin.age-spin.duration, t = min(1,age/2.2), ease = t*t*(3-2*t)
            let destination = path(f,time)
            f.position = clearFlight(mix(spin.recoveryPosition!+spin.velocity*age,destination,ease))
            f.forward = unit(path(f,time+0.08)-destination)
            let level = SCNNode()
            level.look(at:SCNVector3(f.forward),up:SCNVector3(0,1,0),localFront:SCNVector3(0,0,-1))
            f.node.simdOrientation = simd_slerp(spin.recoveryOrientation!,level.simdOrientation,ease)
            f.node.simdPosition = f.position
            if t>=1 { f.spin = nil; recoveries += 1 }
        }
    }
}

extension SIMD4 where Scalar == Float {
    var xyz: SIMD3<Float> { SIMD3(x,y,z) }
}
