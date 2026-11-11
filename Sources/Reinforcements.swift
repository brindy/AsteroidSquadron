import SceneKit
import simd

extension Dogfight {
    // Navigation references are not assigned directly to a flying ship's position.
    func path(_ f: Fighter, _ t: Float) -> V3 {
        let age = t-f.entryTime
        if f.entry != .none && age<f.formationHold {
            return f.entryPosition+f.entryForward*f.entrySpeed*max(0,age)
        }
        return orbitPath(f,t)
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
            f.pursuitTarget = nil; f.pursuitDeadline = 0
            if let target { used.insert(target) }
        }
    }

    func requestReplacement(for side: Int) {
        let roster = fighters.filter { $0.side == side }
        guard !pendingSides.contains(side), roster.allSatisfy({$0.state == .destroyed}), !carriers.contains(where:{$0.side == side}) else { return }
        // Credit and stage the winning squadron's replacements first. Global
        // arrival scheduling then keeps the next enemy behind that deployment.
        if !fleetTruce { creditEncounter(surviving:1-side) }
        squadronEncounters[side] = 0
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
        guard !returningFromAtlantis else { return }
        // Only defeated factions rotate. Veteran top-ups are staged before their next opponent.
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

    func deployReinforcements(side: Int, topUp: Bool = false) {
        let roster = fighters.indices.filter { fighters[$0].side == side }
        let squadron = topUp ? roster.filter { fighters[$0].state == .destroyed } : roster
        guard !squadron.isEmpty, squadron.allSatisfy({fighters[$0].state == .destroyed}) else { return }
        if topUp {
            guard roster.contains(where:{fighters[$0].active}), squadronEncounters[side]>=2 else { return }
            topUpWaves += 1
        }
        let faction = sideFactions[side]
        let start = max(time,nextArrivalTime)
        nextArrivalTime = start+(faction == .shadow ? 7.2 : 6.5)
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
                let distance: Float = faction == .earth ? 1450 : 3300
                position = V3(sin(a)*distance,faction == .earth ? 600 : 900,cos(a)*distance)
                let radius: Float = (faction == .shadow ? 210 : (faction == .cylon ? 158 : 130))*6
                let clearOfCity = atlantis.map { simd_distance($0.position,position)>radius+Atlantis.shieldRadius+500 } ?? true
                if clearOfCity && carriers.allSatisfy({simd_distance($0.origin,position)>2100}) && simd_distance(position,planetPosition)>radius+planetRadius+250 { break }
            }
            let direction = unit(-position)
            let ship = Carrier(faction:faction,side:side,origin:position,forward:direction,start:start,squadron:squadron)
            carriers.append(ship)
            scene.rootNode.addChildNode(ship.node); scene.rootNode.addChildNode(ship.warp)
            for (slot,index) in squadron.enumerated() {
                let f = fighters[index]
                f.state = .arriving; f.entry = faction == .earth ? .jumpWindow : .hangar; f.entryTime = start+2.5+Float(slot)*0.35
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
        if f.entry == .hangar || f.entry == .jumpWindow {
            guard time>=f.entryTime else { return false }
            activateFlight(f,position:f.entryPosition+f.entryForward*f.entrySpeed*max(0,time-f.entryTime),forward:f.entryForward,speed:f.entrySpeed)
            f.state = .active; f.arrival = 1; f.node.isHidden = false; f.node.opacity = 1
            f.warp.isHidden = true; reinforcements += 1
            if f.entry == .jumpWindow { f.jumpClipper?.setPlane(origin:f.entryPosition,normal:f.entryForward) }
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
            activateFlight(f,position:f.entryPosition+f.entryForward*f.entrySpeed*max(0,time-f.entryTime),forward:f.entryForward,speed:f.entrySpeed)
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
            var position = ship.station(age)
            var beam: Float = 0
            if ship.faction.usesJumpWindow {
                position = updateJumpWindow(ship,age:age)
            } else if ship.faction.usesBlinkFTL {
                ship.warp.isHidden = true
                if age<ship.arrivalDuration {
                    ship.node.isHidden = true
                } else if age<ship.departureAge {
                    if !ship.blinkEntered {
                        ship.blinkEntered = true; blinkArrivals += 1
                        jumpPulse(at:ship.origin,radius:ship.worldRadius*1.25)
                    }
                    ship.node.isHidden = false
                } else {
                    if !ship.blinkExited {
                        ship.blinkExited = true; ship.departing = true
                        blinkDepartures += 1; carrierDepartures += 1
                        jumpPulse(at:ship.origin,radius:ship.worldRadius*1.25)
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
                ship.warp.simdScale = V3(ship.scale,ship.scale,max(1,beam))
            }
            ship.node.simdPosition = position
            let linger = ship.departureDuration
            if age>ship.departureAge+linger {
                ship.node.removeFromParentNode(); ship.warp.removeFromParentNode(); carriers.remove(at:i)
            }
        }
    }
}
