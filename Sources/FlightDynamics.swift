import SceneKit
import simd

func bounded(_ vector: V3, length: Float) -> V3 {
    let squared = simd_length_squared(vector)
    return squared>length*length ? vector*(length/sqrt(squared)) : vector
}
func turnToward(_ from: V3, _ to: V3, radians: Float) -> V3 {
    let q = simd_quatf(from:unit(from),to:unit(to))
    let angle = 2*acos(max(-1,min(1,abs(q.real))))
    return unit(simd_slerp(simd_quatf(angle:0,axis:V3(0,1,0)),q,min(1,radians/max(0.00001,angle))).act(unit(from)))
}

extension Fighter {
    func applyFlightPose() {
        let right = unit(simd_cross(forward,navigationUp))
        let up = unit(simd_cross(right,forward))
        let basis = simd_float3x3(columns:(right,up,-forward))
        node.simdPosition = position
        node.simdOrientation = simd_quatf(basis)*simd_quatf(angle:bank,axis:V3(0,0,1))
    }
    func historyPosition(at t: Float) -> V3 {
        guard let first = history.first else { return position }
        if t<=first.0 { return first.1 }
        for i in history.indices.dropFirst() where history[i].0>=t {
            let a = history[i-1], b = history[i]
            return mix(a.1,b.1,(t-a.0)/max(0.00001,b.0-a.0))
        }
        return position
    }
}

extension Dogfight {
    func activateFlight(_ f: Fighter, position: V3, forward: V3, speed: Float) {
        f.position = position; f.forward = unit(forward); f.velocity = f.forward*speed
        f.navigationUp = V3(0,1,0); f.bank = 0; f.motionInitialized = true
        f.history.removeAll(keepingCapacity:true); f.history.append((time,position))
        f.applyFlightPose()
    }
    func chooseTarget(for f: Fighter) -> Int? {
        let current = f.attackTarget.flatMap { fighters[$0].active && fighters[$0].side != f.side ? $0 : nil }
        if let current, time<f.targetReviewAt || f.burstShotsLeft>0 { return current }
        let choices = fighters.indices.filter { fighters[$0].active && fighters[$0].side != f.side }
        func score(_ index: Int) -> Float {
            let enemy = fighters[index]
            let lead = interceptPoint(from:f.position,velocity:f.velocity,target:enemy.position,targetVelocity:enemy.velocity,speed:f.faction.projectileSpeed)
            let alignment = simd_dot(unit(lead-f.position),f.forward)
            let distance = simd_distance(f.position,enemy.position)
            let tail = max(0,-simd_dot(unit(f.position-enemy.position),enemy.forward))
            return (alignment+1)*1.2+1.5/(1+distance/200)+tail*0.6+(index == current ? 0.4 : 0)
        }
        let target = choices.max { score($0)<score($1) }
        f.attackTarget = target
        f.targetReviewAt = time+0.85
        return target
    }
    func updateFlight(_ f: Fighter, dt: Float, positions: [V3], velocities: [V3], active: [Bool]) {
        guard dt>0 else { f.applyFlightPose(); return }
        let old = f.position, oldForward = f.forward
        let age = time-f.entryTime
        if f.entry != .none && age<f.formationHold {
            // Formation and launch corridors have a shared velocity, not a per-frame snap.
            f.velocity = f.entryForward*f.entrySpeed; f.forward = f.entryForward
            f.position += f.velocity*dt; f.applyFlightPose()
            return
        }
        let radial = simd_length(f.position)
        let boost = max(0,min(1,(radial-650)/800))
        var speed = f.cruiseSpeed+(215-f.cruiseSpeed)*boost*boost*(3-2*boost)
        var goal = orbitPath(f,time+2.5)
        if let index = chooseTarget(for:f), simd_length(positions[index])<1100, radial<1300 {
            let p = positions[index], v = velocities[index]
            let muzzle = f.firingMuzzles.first?.simdWorldTransform.columns.3.xyz ?? f.position
            goal = interceptPoint(from:muzzle,velocity:f.velocity,target:p,targetVelocity:v,speed:f.faction.projectileSpeed)
            if simd_distance(p,f.position)<24 && time>f.breakUntil+1 {
                let right = unit(simd_cross(f.forward,f.navigationUp))
                f.breakDirection = unit(f.forward*0.25+right*(f.pair%2 == 0 ? 0.9 : -0.9)+f.navigationUp*0.25)
                f.breakUntil = time+1.8
            }
        }
        var desired = time<f.breakUntil ? f.breakDirection : unit(goal-f.position)
        let lookAhead = max(80,simd_length(f.velocity)*3)
        var avoidance = V3.zero
        for rock in rocks {
            let to = rock.position-f.position
            let along = simd_dot(to,f.forward)
            let radius = rock.radius+f.faction.collisionRadius+12
            guard along > -radius && along<lookAhead, simd_length_squared(to)<pow(lookAhead+radius,2) else { continue }
            let closest = f.position+f.forward*max(0,along)-rock.position
            let separation = simd_length(closest)
            guard separation<radius else { continue }
            let side = separation>0.5 ? closest/separation : unit(f.navigationUp+V3(Float(f.pair%2)*2-1,0,0)*0.4)
            let urgency = max(0,1-max(0,along)/lookAhead)
            avoidance += side*(1-separation/radius)*urgency*3.5
            if along<radius*2 { speed = min(speed,max(f.cruiseSpeed*0.8,simd_length(f.velocity)-20)) }
        }
        let traffic = shipAvoidance(f,positions:positions,velocities:velocities,active:active,speed:&speed)
        desired = unit(desired+avoidance+traffic)
        let limitedDirection = turnToward(f.forward,desired,radians:f.turnRate*dt)
        let acceleration = bounded((limitedDirection*speed-f.velocity)/dt,length:f.accelerationLimit)
        f.velocity += acceleration*dt
        f.forward = unit(f.velocity)
        f.position += f.velocity*dt
        // Parallel-transport the cockpit up vector; don't rebuild a rolling ship from Euler angles.
        f.navigationUp = simd_quatf(from:oldForward,to:f.forward).act(f.navigationUp)
        let level = V3(0,1,0)-f.forward*simd_dot(V3(0,1,0),f.forward)
        if simd_length_squared(level)>0.08 { f.navigationUp = unit(mix(f.navigationUp,unit(level),1-exp(-dt*0.45))) }
        let right = unit(simd_cross(f.forward,f.navigationUp))
        let desiredBank = -simd_dot(acceleration,right)/f.accelerationLimit*0.7
        f.bank += (desiredBank-f.bank)*(1-exp(-dt*4))
        f.applyFlightPose()
        if f.spin == nil { tryAsteroidStrike(f,from:old,dt:dt) }
    }
}
