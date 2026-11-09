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

    func requestReplacement(for side: Int) {
        let roster = fighters.filter { $0.side == side }
        guard !pendingSides.contains(side), roster.allSatisfy({$0.state == .destroyed}), !carriers.contains(where:{$0.side == side}) else { return }
        let previous = sideFactions[side]
        let options = Faction.allCases.filter { $0 != previous && $0 != sideFactions[1-side] }
        let next = options[rng.index(options.count)]
        sideFactions[side] = next
        for f in roster { f.replaceFaction(next); f.orbitRate = rng.range(0.17,0.21) }
        pendingSides.insert(side)
        fleetRequests.append(FleetRequest(side:side,countdown:rng.range(2.5,4.5)))
        replacementCount += 1
        replacements.append(FleetReplacement(side:side,defeated:previous,incoming:next,time:time))
        if replacements.count>64 { replacements.removeFirst(replacements.count-64) }
        encounteredFactions.insert(next)
    }

    func updateReinforcements(_ dt: Float) {
        // Partial squadrons stay depleted. A new faction is chosen only after total defeat.
        for side in 0..<2 { requestReplacement(for:side) }
        for i in fleetRequests.indices.reversed() {
            fleetRequests[i].countdown -= dt
            if fleetRequests[i].countdown<=0 {
                let side = fleetRequests[i].side
                fleetRequests.remove(at:i); pendingSides.remove(side)
                deployReinforcements(side:side)
            }
        }
    }

    func deployReinforcements() {
        for side in 0..<2 where fighters.filter({$0.side == side}).allSatisfy({$0.state == .destroyed}) {
            deployReinforcements(side:side)
        }
    }

    func deployReinforcements(side: Int) {
        let squadron = fighters.indices.filter { fighters[$0].side == side }
        guard squadron.allSatisfy({fighters[$0].state == .destroyed}) else { return }
        let faction = sideFactions[side]
        let start = max(time,nextArrivalTime)
        nextArrivalTime = start+7.2
        waveNumber += 1
        if faction == .rebel {
            // The complete V formation gets one collision-free entry corridor.
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
            for (slot,index) in squadron.enumerated() {
                let f = fighters[index], offset = slots[slot]
                f.state = .arriving; f.entry = .hyperspace; f.entryTime = start+1.25
                f.entryPosition = origin+right*offset.x+V3(0,offset.y,0)+heading*offset.z
                f.entryForward = heading; f.formationSlot = slot; f.arrival = 0
                f.hitPoints = 6; f.cooldown = 1; f.collisionCooldown = 25
            }
            formationArrivals += 1
            director.arrivalFlight = ArrivalFlight(indices:squadron,origin:origin,forward:heading,start:start)
        } else {
            var position = V3.zero
            for _ in 0..<80 {
                let a = rng.range(0,tau)
                position = V3(sin(a)*1320,460,cos(a)*1320)
                if carriers.allSatisfy({simd_distance($0.origin,position)>650}) { break }
            }
            let direction = unit(-position)
            let ship = Carrier(faction:faction,side:side,origin:position,forward:direction,start:start,squadron:squadron)
            carriers.append(ship)
            scene.rootNode.addChildNode(ship.node); scene.rootNode.addChildNode(ship.warp)
            for (slot,index) in squadron.enumerated() {
                let f = fighters[index]
                f.state = .arriving; f.entry = .hangar; f.entryTime = start+2.5+Float(slot)*0.35
                f.entryPosition = ship.launchPosition(slot:slot,at:f.entryTime-start)
                f.entryForward = direction; f.formationSlot = slot; f.arrival = 0
                f.hitPoints = 6; f.cooldown = 1.2; f.warp.isHidden = true; f.collisionCooldown = 25
            }
        }
        for side in 0..<2 {
            assignTargets(fighters.indices.filter{fighters[$0].side == side && fighters[$0].state != .destroyed})
        }
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
        for i in carriers.indices.reversed() {
            let ship = carriers[i], age = time-ship.start
            guard age>=0 else { continue }
            if !ship.announced {
                ship.announced = true; carrierVisits += 1
                director.requestCarrierArrival(ship,in:self)
            }
            // Finish the other capital ship's launch shot before cutting to this departure.
            if age>=ship.departureAge && !ship.departing && director.event == .carrierArrival && director.featuredCarrier !== ship {
                ship.departureAge = age+0.2
            }
            var position = ship.station(age)
            var beam: Float = 0
            if ship.faction.usesBlinkFTL {
                ship.warp.isHidden = true
                if age<ship.arrivalDuration {
                    ship.node.isHidden = true
                } else if age<ship.departureAge {
                    if !ship.blinkEntered {
                        ship.blinkEntered = true; blinkArrivals += 1
                        jumpPulse(at:ship.origin,radius:ship.cameraBounds.z*1.25)
                    }
                    ship.node.isHidden = false
                } else {
                    if !ship.blinkExited {
                        ship.blinkExited = true; ship.departing = true
                        blinkDepartures += 1; carrierDepartures += 1
                        jumpPulse(at:ship.origin,radius:ship.cameraBounds.z*1.25)
                        director.requestCarrierDeparture(ship,in:self)
                    }
                    ship.node.isHidden = true
                }
            } else {
                if age<1.4 {
                    let t = age/1.4
                    position = ship.origin-ship.forward*2800*pow(1-t,4)
                    ship.node.isHidden = t<0.68; beam = (1-t)*1000
                } else if age>ship.departureAge {
                    if !ship.departing {
                        ship.departing = true; carrierDepartures += 1
                        director.requestCarrierDeparture(ship,in:self)
                    }
                    let t = min(1,(age-ship.departureAge)/1.4)
                    position += ship.forward*3000*pow(t,3)
                    ship.node.isHidden = t>0.7; beam = t*1500
                } else { ship.node.isHidden = false }
                ship.warp.isHidden = beam<1
                ship.warp.simdPosition = position-ship.forward*beam*0.5
                ship.warp.simdOrientation = simd_quatf(from:V3(0,0,-1),to:ship.forward)
                ship.warp.simdScale = V3(1,1,max(1,beam))
            }
            ship.node.simdPosition = position
            let linger: Float = ship.faction.usesBlinkFTL ? 0.65 : 1.8
            if age>ship.departureAge+linger {
                ship.node.removeFromParentNode(); ship.warp.removeFromParentNode(); carriers.remove(at:i)
            }
        }
    }
}
