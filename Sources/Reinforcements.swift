import SceneKit
import simd

extension Dogfight {
    func path(_ f: Fighter, _ t: Float) -> V3 {
        let age = t-f.entryTime
        guard f.entry != .none, age<18 else { return orbitPath(f,t) }
        guard age>0 else { return f.entryPosition }
        let speed: Float = f.entry == .hyperspace ? 28 : 100
        let hold = f.formationHold
        if age<hold { return clearFlight(f.entryPosition+f.entryForward*speed*age) }
        let split = age-hold
        let duration: Float = f.entry == .hyperspace ? 6.5 : 8
        let start = f.entryPosition+f.entryForward*speed*hold
        let ownOrbit = orbitPath(f,t)
        var attack = ownOrbit
        if let target = f.attackTarget {
            let enemy = fighters[target]
            let targetPosition = orbitPath(enemy,t)
            let targetForward = unit(orbitPath(enemy,t+0.1)-targetPosition)
            attack = targetPosition-targetForward*25
        }
        let approach = unit(attack-start)
        let a = min(1,split/duration), b = 1-a
        let curved = start*(b*b*b)+(start+f.entryForward*110)*(3*b*b*a)+(attack-approach*75)*(3*b*a*a)+attack*(a*a*a)
        let rejoin = max(0,min(1,(split-duration)/4))
        let smooth = rejoin*rejoin*(3-2*rejoin)
        return clearFlight(mix(curved,ownOrbit,smooth))
    }

    func assignTargets(_ squadron: [Int]) {
        var used = Set<Int>()
        for index in squadron {
            let f = fighters[index]
            let enemies = fighters.indices.filter { fighters[$0].faction != f.faction && fighters[$0].state != .destroyed }
            let pool = enemies.filter { !used.contains($0) }
            let candidates = pool.isEmpty ? enemies : pool
            let target = candidates.min { simd_distance_squared(orbitPath(fighters[$0],time+5),f.entryPosition)<simd_distance_squared(orbitPath(fighters[$1],time+5),f.entryPosition) }
            f.attackTarget = target
            if let target { used.insert(target) }
        }
    }

    func updateReinforcements(_ dt: Float) {
        if waveCountdown == nil && arrivingCount == 0 && carrier == nil && (activeCount<=7 || rebelCount<=2 || empireCount<=2) {
            waveCountdown = rng.range(3.5,5.5)
        }
        guard let countdown = waveCountdown else { return }
        waveCountdown = countdown-dt
        guard countdown<=dt else { return }
        waveNumber += 1; waveCountdown = nil
        deployReinforcements()
    }

    func deployReinforcements() {
        let rebels = fighters.indices.filter { fighters[$0].state == .destroyed && fighters[$0].faction == .rebel }
        let empire = fighters.indices.filter { fighters[$0].state == .destroyed && fighters[$0].faction == .empire }
        // Find a clear entry corridor for the complete V formation, not separate random landings.
        let slots: [V3] = [V3(0,0,0),V3(-14,-1,-13),V3(14,-1,-13),V3(-28,-2,-26),V3(28,-2,-26),V3(0,8,-32)]
        var origin = V3.zero, heading = V3(0,0,-1), right = V3(1,0,0)
        for attempt in 0..<80 {
            let a = rng.range(0,tau)
            origin = V3(sin(a)*210,245+Float(attempt)*2,cos(a)*210)
            heading = unit(V3(-origin.x,-65,-origin.z)); right = unit(simd_cross(heading,V3(0,1,0)))
            let blocked = slots.contains { slot in
                let point = origin+right*slot.x+V3(0,slot.y,0)+heading*slot.z
                let segment = heading*95
                return rocks.contains { rock in
                    let u = max(0,min(1,simd_dot(rock.position-point,segment)/simd_length_squared(segment)))
                    return simd_distance(point+segment*u,rock.position)<rock.radius+17
                }
            }
            if !blocked { break }
        }
        for (slot,index) in rebels.enumerated() {
            let f = fighters[index], offset = slots[slot]
            f.state = .arriving; f.entry = .hyperspace; f.entryTime = time+1.25
            f.entryPosition = origin+right*offset.x+V3(0,offset.y,0)+heading*offset.z
            f.entryForward = heading; f.formationSlot = slot; f.arrival = 0
            f.hitPoints = 6; f.cooldown = 1
        }
        if !rebels.isEmpty {
            formationArrivals += 1
            director.arrivalFlight = ArrivalFlight(indices:rebels,origin:origin,forward:heading,start:time)
        }
        if !empire.isEmpty {
            let a = rng.range(0,tau)
            let position = V3(sin(a)*1320,460,cos(a)*1320)
            let direction = unit(-position)
            let start = time+(rebels.isEmpty ? 0 : 6.5)
            let ship = Carrier(origin:position,forward:direction,start:start,squadron:empire)
            carrier = ship
            scene.rootNode.addChildNode(ship.node); scene.rootNode.addChildNode(ship.warp)
            let side = unit(simd_cross(direction,V3(0,1,0)))
            for (slot,index) in empire.enumerated() {
                let f = fighters[index]
                f.state = .arriving; f.entry = .hangar; f.entryTime = start+2.5+Float(slot)*0.35
                let age = f.entryTime-start
                f.entryPosition = ship.station(age)+side*(slot%2 == 0 ? -11 : 11)+V3(0,-16,0)-direction*15
                f.entryForward = direction; f.formationSlot = slot; f.arrival = 0
                f.hitPoints = 6; f.cooldown = 1.2; f.warp.isHidden = true
            }
        }
        // Assign after both rosters are marked arriving, so each fighter gets its own opponent.
        assignTargets(rebels); assignTargets(empire)
    }

    func updateArrival(_ f: Fighter) -> Bool {
        if f.entry == .hangar {
            guard time>=f.entryTime else { return false }
            f.position = path(f,time); f.forward = unit(path(f,time+0.08)-f.position)
            f.state = .active; f.arrival = 1; f.node.isHidden = false; f.node.opacity = 1
            f.warp.isHidden = true; reinforcements += 1
            return true
        }
        let progress = max(0,min(1,1+(time-f.entryTime)/1.25))
        f.arrival = progress; f.forward = f.entryForward
        let remaining = 1-progress
        f.position = f.entryPosition-f.forward*1400*pow(remaining,4)
        f.node.isHidden = progress<0.82; f.node.opacity = CGFloat(max(0,min(1,(progress-0.82)/0.1)))
        f.warp.isHidden = false
        let length = max(1,remaining*280)
        f.warp.simdPosition = f.position-f.forward*length*0.5
        f.warp.simdOrientation = simd_quatf(from:V3(0,0,-1),to:f.forward)
        f.warp.simdScale = V3(1,1,length); f.warp.opacity = CGFloat(remaining)
        if progress>=1 {
            f.state = .active; f.node.opacity = 1; f.warp.isHidden = true
            arrivalFlash(at:f.entryPosition); reinforcements += 1
        }
        return true
    }

    func updateCarrier() {
        guard let ship = carrier else { return }
        let age = time-ship.start
        guard age>=0 else { return }
        if !ship.announced {
            ship.announced = true; carrierVisits += 1
            director.requestCarrierArrival(in:self)
        }
        var position = ship.station(age)
        var beam: Float = 0
        if age<1.4 {
            let t = age/1.4
            position = ship.origin-ship.forward*2800*pow(1-t,4)
            ship.node.isHidden = t<0.68; beam = (1-t)*1000
        } else if age>10 {
            if !ship.departing {
                ship.departing = true; carrierDepartures += 1
                director.requestCarrierDeparture(in:self)
            }
            let t = min(1,(age-10)/1.4)
            position += ship.forward*3000*pow(t,3)
            ship.node.isHidden = t>0.7; beam = t*1500
        } else { ship.node.isHidden = false }
        ship.node.simdPosition = position
        ship.warp.isHidden = beam<1
        ship.warp.simdPosition = position-ship.forward*beam*0.5
        ship.warp.simdOrientation = simd_quatf(from:V3(0,0,-1),to:ship.forward)
        ship.warp.simdScale = V3(1,1,max(1,beam))
        if age>11.8 {
            ship.node.removeFromParentNode(); ship.warp.removeFromParentNode(); carrier = nil
        }
    }
}
