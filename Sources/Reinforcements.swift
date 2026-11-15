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
        guard atlantisAttackingSide == nil, !pendingSides.contains(side), roster.allSatisfy({$0.state == .destroyed}),
              !carriers.contains(where:{$0.side == side}) else { return }
        let winner = 1-side
        if let next = nextAtlantisEncounter, sideCount(winner)>0, encountersCompleted+1>=next {
            creditEncounter(survivingSides:[winner],replenish:false)
            atlantisAttackingSide = winner
            atlantisTopUpPending = true
            return
        }
        // Credit and stage the winning squadron's replacements first. Global
        // arrival scheduling then keeps the next enemy behind that deployment.
        creditEncounter(surviving:winner)
        queueFactionReplacement(for:side, afterVictory:sideCount(winner)>0)
    }

    func queueFactionReplacement(for side: Int, afterVictory: Bool = false) {
        squadronEncounters[side] = 0
        let previous = sideFactions[side]
        let options = Faction.allCases.filter { $0 != previous && $0 != sideFactions[1-side] }
        let next = options[rng.index(options.count)]
        sideFactions[side] = next
        for f in fighters where f.side == side { f.replaceFaction(next); f.orbitRate = rng.range(0.17,0.21) }
        let lane = arrivalLane(for:next,side:side)
        if afterVictory { plotVictoryReposition(for:1-side,awayFrom:lane.origin) }
        pendingSides.insert(side)
        let delay = afterVictory ? rng.range(4.5,6.0) : rng.range(2.5,4.5)
        fleetRequests.append(FleetRequest(side:side,lane:lane,countdown:delay))
        replacementCount += 1
        replacements.append(FleetReplacement(side:side,defeated:previous,incoming:next,time:time))
        if replacements.count>64 { replacements.removeFirst(replacements.count-64) }
        encounteredFactions.insert(next)
    }

    func updateReinforcements(_ dt: Float) {
        guard !returningFromAtlantis else { return }
        if let side = atlantisAttackingSide {
            // If Atlantis wipes out the assault wave, only its original
            // opponent can return. The empty rival side stays out of play.
            if atlantisSiegeActive && sideCount(side)==0 && arrivingCount==0 && carriers.isEmpty {
                let reserves = atlantisReinforcements(for:side)
                deploySquadron(reserves,side:side)
            }
            return
        }
        // Only defeated factions rotate. Veteran top-ups are staged before their next opponent.
        for side in 0..<2 { requestReplacement(for:side) }
        guard atlantisAttackingSide == nil else { return }
        for i in fleetRequests.indices.reversed() {
            fleetRequests[i].countdown -= dt
            if fleetRequests[i].countdown<=0 {
                let request = fleetRequests.remove(at:i)
                pendingSides.remove(request.side)
                deployReinforcements(side:request.side,lane:request.lane)
            }
        }
    }

    func deployReinforcements() {
        for side in 0..<2 where fighters.filter({$0.side == side}).allSatisfy({$0.state == .destroyed}) {
            deployReinforcements(side:side)
        }
    }

    private func arrivalLane(for faction: Faction, side: Int) -> ArrivalLane {
        let radial = unit(V3(planetPosition.x,0,planetPosition.z))
        let tangent = unit(simd_cross(radial,V3(0,1,0)))
        // The two fleets stage on opposite sides of the sightline to the planet.
        let sign: Float = side == 0 ? -1 : 1
        let distance: Float
        let offset: Float
        let course: Float
        switch faction {
        case .rebel: (distance,offset,course) = (1210,210,0.12)
        case .earth: (distance,offset,course) = (1450,265,0.28)
        case .colonial,.cylon: (distance,offset,course) = (2100,480,0.66)
        // Keep the Shadow transit tangent to the belt so its departure window
        // opens in clear space even when the whole carrier is on the move.
        case .shadow: (distance,offset,course) = (2390,400,2.2)
        default: (distance,offset,course) = (2340,450,1.2)
        }
        let origin = radial*distance+tangent*(sign*(offset+rng.range(-50,50)))
            + V3(0,unit(planetPosition).y*1500+rng.range(120,200),0)
        let forward = unit(-radial-tangent*course)
        return ArrivalLane(origin:origin,forward:forward)
    }

    func deployReinforcements(side: Int, topUp: Bool = false, lane: ArrivalLane? = nil) {
        let roster = fighters.indices.filter { fighters[$0].side == side && !fighters[$0].isSiegeReserve }
        let squadron = topUp ? roster.filter { fighters[$0].state == .destroyed } : roster
        guard !squadron.isEmpty, squadron.allSatisfy({fighters[$0].state == .destroyed}) else { return }
        if topUp {
            guard sideCount(side)>0, squadronEncounters[side]>=2 else { return }
            topUpWaves += 1
        }
        deploySquadron(squadron,side:side,lane:lane)
    }

    func atlantisReinforcements(for side: Int) -> [Int] {
        let faction = sideFactions[side]
        let slots = fighters.indices.filter { fighters[$0].side == side }
        let missing = slots.filter { !fighters[$0].isSiegeReserve && fighters[$0].state == .destroyed }
        let reserveSlots = slots.filter { fighters[$0].isSiegeReserve }
        var squadron = missing
        if squadron.isEmpty {
            // A full squadron can still receive a reserve pilot at each beat.
            if let reserve = reserveSlots.first(where:{fighters[$0].state == .destroyed}) {
                squadron = [reserve]
            } else if reserveSlots.count<2 {
                let reserve = Fighter(faction:faction,side:side,pair:6+reserveSlots.count,trailing:true,
                                      cooldown:1.2,isSiegeReserve:true)
                scene.rootNode.addChildNode(reserve.node)
                scene.rootNode.addChildNode(reserve.warp)
                squadron = [fighters.count]
                fighters.append(reserve)
                persistentNodeCount += 2
            }
        }
        for i in squadron { fighters[i].replaceFaction(faction) }
        if !squadron.isEmpty { topUpWaves += 1 }
        return squadron
    }

    func stageHangarLaunch(_ ship: Carrier) {
        for (slot,index) in ship.squadron.enumerated() {
            let f = fighters[index]
            f.state = .arriving; f.entry = ship.portalOnly ? .jumpWindow : .hangar
            f.entryTime = ship.start+2.5+Float(slot)*0.35
            f.entryPosition = ship.launchPosition(slot:slot,at:f.entryTime-ship.start)
            f.entryForward = ship.forward; f.formationSlot = slot; f.arrival = 0
            f.hitPoints = Fighter.fullHull; f.cooldown = 1.2; f.warp.isHidden = true; f.collisionCooldown = 25
        }
    }

    func deploySquadron(_ squadron: [Int], side: Int, lane: ArrivalLane? = nil) {
        guard !squadron.isEmpty else { return }
        let faction = sideFactions[side]
        let start = max(time,nextArrivalTime)
        nextArrivalTime = start+(faction == .shadow ? 7.2 : 6.5)
        waveNumber += 1
        let approach = lane ?? arrivalLane(for:faction,side:side)
        let origin = approach.origin, heading = approach.forward
        if faction == .rebel {
            // The whole V can form up outside the rocks before splitting.
            let slots: [V3] = [V3(0,0,0),V3(-14,-1,-13),V3(14,-1,-13),V3(-28,-2,-26),V3(28,-2,-26),V3(0,8,-32)]
            let right = unit(simd_cross(heading,V3(0,1,0)))
            for (slot,index) in squadron.enumerated() {
                let f = fighters[index], offset = slots[slot]
                f.state = .arriving; f.entry = .hyperspace; f.entryTime = start+1.25
                f.entryPosition = origin+right*offset.x+V3(0,offset.y,0)+heading*offset.z
                f.entryForward = heading; f.formationSlot = slot; f.arrival = 0
                f.hitPoints = Fighter.fullHull; f.cooldown = 1; f.collisionCooldown = 25
            }
            formationArrivals += 1
            director.arrivalFlight = ArrivalFlight(indices:squadron,origin:origin,forward:heading,start:start)
        } else {
            let ship = Carrier(faction:faction,side:side,origin:origin,forward:heading,start:start,squadron:squadron)
            carriers.append(ship)
            scene.rootNode.addChildNode(ship.node); scene.rootNode.addChildNode(ship.warp)
            stageHangarLaunch(ship)
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
        let appearance = hyperspaceRamp(progress,from:0.55,to:0.67)
        f.position = f.entryPosition-f.forward*(1400*pow(remaining,4)+f.entrySpeed*1.25*remaining)
        f.node.isHidden = appearance == 0; f.node.opacity = CGFloat(appearance)
        if time>=f.entryTime-1.25 {
            f.warp.arrive(distant:f.entryPosition-f.forward*960,stern:f.position-f.forward*7,
                          progress:progress,width:3.1)
        }
        if progress>=1 {
            f.state = .active; f.node.opacity = 1; f.warp.isHidden = true
            activateFlight(f,position:f.entryPosition+f.entryForward*f.entrySpeed*max(0,time-f.entryTime),forward:f.entryForward,speed:f.entrySpeed)
            reinforcements += 1
        }
        return true
    }

    func blinkCapitalIn(_ ship: Carrier) {
        guard !ship.blinkEntered else { return }
        ship.blinkEntered = true; blinkArrivals += 1
        jumpPulse(at:ship.origin,radius:ship.worldRadius*1.25)
    }

    func capitalHyperspaceEntry(_ ship: Carrier, age: Float) -> V3 {
        let t = min(1,max(0,age/ship.arrivalDuration))
        let drift: Float = ship.isSiegeShip ? 0 : 3
        let position = ship.origin-ship.forward*(2800*pow(1-t,4)+drift*ship.arrivalDuration*(1-t))
        let appearance = hyperspaceRamp(t,from:0.55,to:0.67)
        ship.node.isHidden = appearance == 0
        ship.node.opacity = CGFloat(appearance)
        ship.hyperspaceTrail?.arrive(distant:ship.hyperspaceArrivalPoint,
                                    stern:position-ship.forward*ship.sternOffset,
                                    progress:t,width:ship.scale*4.5)
        return position
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
            if ship.faction.usesJumpWindow {
                position = updateJumpWindow(ship,age:age)
            } else if ship.faction.usesBlinkFTL {
                ship.warp.isHidden = true
                if age<ship.arrivalDuration {
                    ship.node.isHidden = true
                } else if age<ship.departureAge {
                    blinkCapitalIn(ship)
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
                if age<ship.arrivalDuration {
                    ship.node.simdPosition = capitalHyperspaceEntry(ship,age:age)
                    continue
                }
                if age>ship.departureAge {
                    if !ship.departing {
                        ship.departing = true; carrierDepartures += 1
                        director.requestCarrierDeparture(ship,in:self)
                    }
                    let t = min(1,(age-ship.departureAge)/ship.departureDuration)
                    let flight = min(1,t/0.63)
                    let start = position-ship.forward*ship.sternOffset
                    let end = mix(start,ship.hyperspaceDeparturePoint,pow(flight,3))
                    position = end+ship.forward*ship.sternOffset
                    let hull = 1-hyperspaceRamp(flight,from:0.87,to:1)
                    ship.node.isHidden = hull == 0
                    ship.node.opacity = CGFloat(hull)
                    let retreat = hyperspaceRamp(t,from:0.63,to:0.96)
                    let visibility = 1-hyperspaceRamp(t,from:0.89,to:1)
                    ship.hyperspaceTrail?.show(from:mix(start,end,retreat),to:end,lightAt:end,
                                               width:ship.scale*4.5,opacity:visibility,
                                               pointOpacity:hyperspaceRamp(flight,from:0.84,to:1)*visibility)
                } else {
                    ship.node.isHidden = false
                    ship.node.opacity = 1
                    ship.warp.isHidden = true
                }
            }
            ship.node.simdPosition = position
            let linger = ship.departureDuration
            if age>ship.departureAge+linger {
                ship.node.removeFromParentNode(); ship.warp.removeFromParentNode(); carriers.remove(at:i)
            }
        }
    }
}
