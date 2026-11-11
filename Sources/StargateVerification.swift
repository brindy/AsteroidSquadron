import AppKit
import Metal
import SceneKit
import simd

private func stargateCheck(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() {
        print("FAIL: \(message)")
        fflush(stdout)
        exit(1)
    }
}

func verifyStargate(renderDirectory: URL? = nil) {
    let patrol = Dogfight(seed:7302,initialFactions:[.tauri,.wraith],initialArrivals:false,firstAtlantisEncounter:nil)
    let pilot = patrol.fighters[0]
    for f in patrol.fighters.dropFirst() { f.state = .destroyed; f.node.isHidden = true }
    let origin = patrol.clearFlight(V3(40,120,25))
    patrol.activateFlight(pilot,position:origin,forward:V3(0,0,-1),speed:pilot.cruiseSpeed)
    _ = patrol.patrolDestination(for:pilot)
    stargateCheck(pilot.patrolRoute.count>=5,"A lone fighter had no multi-leg patrol")
    stargateCheck(pilot.patrolRoute.contains { simd_length($0)>540 } && pilot.patrolRoute.contains { simd_length($0)<335 },
                  "Patrol did not cover both the interior and outer belt")
    var farthest: Float = 0
    let dt: Float = 1/60
    for _ in 0..<3600 where pilot.active {
        patrol.time += dt
        let positions = patrol.fighters.map(\.position)
        let velocities = patrol.fighters.map(\.velocity)
        let active = patrol.fighters.map(\.active)
        if pilot.spin == nil {
            patrol.updateFlight(pilot,dt:dt,positions:positions,velocities:velocities,active:active)
        } else {
            patrol.updateSpinOut(pilot,dt:dt,positions:positions,velocities:velocities,active:active)
        }
        farthest = max(farthest,simd_distance(origin,pilot.position))
    }
    stargateCheck(farthest>520,"A lone fighter kept circling in the same spot")
    patrol.activateFlight(pilot,position:V3(0,440,2900),forward:V3(0,0,1),speed:175)
    pilot.patrolRoute.removeAll()
    let returnPoint = patrol.patrolDestination(for:pilot)
    stargateCheck(simd_length(returnPoint)<1000,"An outbound pilot could not plan a return to the belt")
    let foe = patrol.fighters[1]
    foe.state = .active
    stargateCheck(patrol.chooseTarget(for:pilot)==1,"A live enemy did not interrupt patrol")
    print("PASS: long asteroid patrol, with \(Int(farthest)) units of actual flight from its origin, and return to target selection.")

    let renderer = renderDirectory.map { _ in SCNRenderer(device:MTLCreateSystemDefaultDevice(),options:nil) }
    if let renderDirectory { try! FileManager.default.createDirectory(at:renderDirectory,withIntermediateDirectories:true) }
    func save(_ name: String, battle: Dogfight) {
        guard let renderer, let renderDirectory else { return }
        renderer.scene = battle.scene
        renderer.pointOfView = battle.camera
        let frame = renderer.snapshot(atTime:Double(battle.time),with:NSSize(width:1120,height:700),antialiasingMode:.multisampling2X)
        let bitmap = NSBitmapImageRep(data:frame.tiffRepresentation!)!
        try! bitmap.representation(using:.png,properties:[:])!.write(to:renderDirectory.appendingPathComponent(name+".png"))
        print("Rendered \(name)")
        fflush(stdout)
    }

    for faction: Faction in [.tauri,.goauld,.wraith] {
        let b = Dogfight(seed:7303,initialFactions:[faction,.rebel],firstAtlantisEncounter:nil)
        let ship = b.carriers.first!
        stargateCheck(ship.faction==faction && ship.squadron.count==6,"\(faction) did not receive its own carrier")
        var renderedLaunch = false
        for _ in 0..<360 {
            b.update(dt:dt)
            if !renderedLaunch && b.time>3.8 {
                save("\(faction.rawValue)-launch",battle:b)
                renderedLaunch = true
            }
        }
        stargateCheck(ship.squadron.allSatisfy { b.fighters[$0].active && b.fighters[$0].entry == .hangar && b.fighters[$0].firingMuzzles.count==2 },
                      "\(faction) did not deploy six armed fighters from its carrier")
        stargateCheck(ship.departing && b.carriers.isEmpty && b.carrierDepartures==1,"\(faction) carrier stayed after launch")
    }
    print("PASS: F-302s, Death Gliders and Wraith Darts launch in pairs from their respective carriers, which depart after deployment.")
    fflush(stdout)

    let b = Dogfight(seed:7304,initialFactions:[.tauri,.wraith],initialArrivals:false,firstAtlantisEncounter:0)
    let city = b.atlantis!
    stargateCheck(simd_length(city.position)>2500,"Atlantis arrived inside the asteroid field")
    stargateCheck(!b.fireAtAtlantis(from:0,city:city),"A fighter fired at Atlantis from the asteroid field")
    stargateCheck(!b.fire(from:0,to:1),"A squadron broke the siege truce")
    var rendered = Set<String>()
    var replaced = false
    var volleySizes: [Int] = []
    var previousLaunch: Float?
    var lookoutViews = Set<String>()
    var longestOverview: Float = 0
    var breach: Float?
    var longestRange: Float = 0
    var maxDrones = 0
    var destroyedTime: Float?
    var regroupDeadline: Float?
    for _ in 0..<14400 {
        b.update(dt:1.0/30)
        maxDrones = max(maxDrones,city.drones.count)
        // The fixture samples two physics steps at once. Count only drones
        // born during those steps, including launches between display frames.
        let newborn = city.drones.filter { $0.age<=1.0/30 }
        let launched = newborn.count
        if launched>0 {
            for drone in newborn {
                stargateCheck(drone.path.origin==city.dronePort && drone.position.y>city.dronePort.y,
                              "Drones did not rise from the tower tip")
                let guide = city.drones[0].path
                stargateCheck(drone.path.point(at:1)==guide.point(at:1),"Drones in the same stream took different routes")
            }
            if let previousLaunch {
                let spacing = b.time-previousLaunch
                if spacing>1 {
                    stargateCheck(spacing>=Atlantis.droneVolleyPause-0.04,"Atlantis fired again before its volley pause ended")
                    volleySizes.append(0)
                } else {
                    stargateCheck(spacing<0.1,"Drones did not launch as a continuous stream")
                }
            } else {
                volleySizes.append(0)
            }
            volleySizes[volleySizes.count-1] += launched
            previousLaunch = b.time
        }
        longestRange = max(longestRange,b.fighters.filter(\.active).map { simd_length($0.position) }.max() ?? 0)
        if city.shieldPoints>0 {
            stargateCheck(city.hullPoints==Atlantis.hullCapacity,"Hull took damage through the intact shield")
        } else if breach == nil {
            breach = b.time
        }
        if !replaced && city.shieldPoints<Atlantis.shieldCapacity-18 && city.shieldPoints>0 {
            let shield = city.shieldPoints
            let encounters = b.encountersCompleted
            for f in b.fighters where f.side==0 && f.active { b.destroy(f) }
            b.requestReplacement(for:0)
            stargateCheck(b.pendingSides.contains(0) && city.shieldPoints==shield && b.atlantis === city,
                          "Atlantis or its damage was lost when an attack wave was wiped out")
            stargateCheck(b.encountersCompleted==encounters,"Siege losses were credited as faction-versus-faction victories")
            replaced = true
        }
        let event = b.director.event
        let age = b.director.eventAge
        if city.intact && event == .none && b.fighters.contains(where:{$0.active && $0.spin == nil}) {
            longestOverview = max(longestOverview,b.cameraAge)
        }
        if event == .atlantisDefense && age>0.5, let lookout = b.director.atlantisLookout {
            lookoutViews.insert(b.director.caption ?? "")
            stargateCheck(simd_distance(b.cameraPosition,city.position)<480 &&
                          city.hullImpact(from:b.cameraPosition,to:b.cameraPosition)==nil,
                          "A lookout camera left Atlantis or clipped its hull")
            let focus = lookout.launchFocus ?? b.fighters[lookout.index].position
            let target = focus-b.cameraPosition
            stargateCheck(simd_dot(unit(target),unit(b.cameraLook-b.cameraPosition))>0.8,
                          "An Atlantis lookout lost its incoming fighter")
        }
        var shot: String?
        if event == .atlantisArrival && age>1.0 { shot = "atlantis-arrival" }
        if event == .atlantisAttack && age>0.5 { shot = city.shieldPoints>0 ? "atlantis-attack" : "atlantis-hull-run" }
        if event == .atlantisBreach && age>1.0 { shot = "atlantis-shield-down" }
        if event == .atlantisDestruction && age>1.7 { shot = "atlantis-breakup" }
        if event == .atlantisDefense && age>0.8 {
            switch b.director.caption {
            case "CENTRAL TOWER": shot = "atlantis-tower-view"
            case "OUTER PIER": shot = "atlantis-pier-view"
            case "ANCIENT DRONES LAUNCH": shot = "atlantis-spire-launch"
            default: break
            }
        }
        if let shot, rendered.insert(shot).inserted { save(shot,battle:b) }
        if city.drones.count>=25 && rendered.insert("atlantis-drone-volley").inserted {
            save("atlantis-drone-volley",battle:b)
        }
        if !city.intact && destroyedTime == nil {
            destroyedTime = b.time
            stargateCheck(b.nextAtlantisEncounter==b.encountersCompleted+10,"Atlantis cooldown is shorter than ten encounters")
        }
        if regroupDeadline == nil { regroupDeadline = b.atlantisRegroupUntil }
        if destroyedTime != nil && !b.returningFromAtlantis { break }
    }
    stargateCheck(replaced && maxDrones<=Atlantis.droneVolleySize && longestRange>2100,
                  "Siege did not produce multiple waves, bounded drones and long approaches")
    stargateCheck(volleySizes.count>=2 && volleySizes.dropLast().allSatisfy { $0==Atlantis.droneVolleySize },
                  "Atlantis did not repeat full drone volleys: \(volleySizes)")
    stargateCheck(lookoutViews.contains("OUTER PIER") &&
                  (lookoutViews.contains("CENTRAL TOWER") || lookoutViews.contains("ANCIENT DRONES LAUNCH")),
                  "The siege did not cut to both Atlantis lookouts")
    stargateCheck(longestOverview<=CinematicDirector.atlantisWideDuration+0.05,
                  "Atlantis overview lingered for \(longestOverview)s")
    stargateCheck(breach != nil && destroyedTime != nil,"Attack runs failed to collapse the shield and destroy Atlantis (shield \(city.shieldPoints), hull \(city.hullPoints), shots \(b.shots))")
    stargateCheck(!b.returningFromAtlantis && b.atlantis == nil && city.node.parent == nil && city.drones.isEmpty,
                  "Siege cleanup or return failed at \(b.time)s with \(b.arrivingCount) arriving and survivor distances \(b.fighters.filter(\.active).map { Int(simd_length($0.position)) })")
    stargateCheck(b.fighters.allSatisfy {!$0.active || simd_length($0.position)<1200},"A survivor stayed outside the belt")
    // This fixture observes every two physics steps. Compare with the actual
    // deadline, since observing the start can lag by half a display frame.
    stargateCheck(regroupDeadline.map { b.time>=$0 } == true,"The returning fighters did not get a patrol interval")
    let ready = b.nextAtlantisEncounter!
    for f in b.fighters { f.cooldown = 10000 }
    for _ in 0..<1080 { b.update(dt:1.0/30) }
    b.encountersCompleted = ready-1
    b.update(dt:0)
    stargateCheck(b.atlantis == nil,"Atlantis returned after only nine subsequent encounters")
    b.encountersCompleted = ready
    b.update(dt:0)
    stargateCheck(b.atlantisSiegeActive,"Atlantis could not return after the cooldown")
    print("PASS: \(volleySizes.count) drone volleys with 30 launches per completed volley and a ten-second pause. Peak active drones: \(maxDrones).")
    print("PASS: city shield breached at \(Int(breach!))s, city destroyed at \(Int(destroyedTime!))s, survivors returned, and ten encounters elapsed before eligibility.")
    fflush(stdout)
}
