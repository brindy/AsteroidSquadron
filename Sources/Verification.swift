import AppKit
import SceneKit
import Metal
import simd

private func check(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() { print("FAIL: \(message)"); fflush(stdout); exit(1) }
}

func verifySimulation() {
    verifyFactionLifecycle()
    verifyBlinkCarriers()
    verifyFormationAndControl()
    var fingerprints = Set<String>()
    for seed: UInt64 in [42,2026,0xCAFE] {
        autoreleasepool {
            print("Checking seed \(seed)"); fflush(stdout)
            let battle = Dogfight(seed:seed)
            let fingerprint = battle.rocks.prefix(5).map { String(describing:$0.position) }.joined()
            check(fingerprints.insert(fingerprint).inserted,"Arena seeds did not change the layout")
            let initialNodes = battle.persistentNodeCount
            var cameraVisits = Set<Int>()
            var maxLasers = 0, maxSparks = 0, maxEffects = 0, maxBlasts = 0
            var smallestShipClearance: Float = 999, smallestCameraClearance: Float = 999
            for frame in 0..<18000 {
                battle.update(dt:1.0/30.0)
                cameraVisits.insert(battle.cameraIndex)
                maxLasers = max(maxLasers,battle.lasers.count)
                maxSparks = max(maxSparks,battle.sparks.count)
                maxEffects = max(maxEffects,battle.effects.count)
                maxBlasts = max(maxBlasts,battle.blasts.count)
                check(battle.activeCount+battle.arrivingCount<=12,"Unbounded fleet")
                check(battle.sideFactions[0] != battle.sideFactions[1],"Opposing sides selected the same faction")
                for f in battle.fighters {
                    check(f.faction == battle.sideFactions[f.side],"Roster mixes faction models")
                    check(f.node.childNodes.count == 1,"Old fighter model survived a faction replacement")
                    check(f.position.x.isFinite && f.position.y.isFinite && f.position.z.isFinite,"Non-finite fighter position")
                    check(abs(simd_length(f.forward)-1)<0.01,"Invalid heading")
                    check(f.node.simdScale == V3(repeating:1),"Hyperspace stretched the ship geometry")
                    check(f.active != f.node.isHidden || f.state == .arriving,"Fleet visibility does not match its state")
                    if f.entry == .hangar { check(f.warp.isHidden,"TIE fighter used hyperspace instead of its carrier") }
                    check(f.entry != .hyperspace || f.faction == .rebel,"A carrier-launched fighter used hyperspace")
                    if frame%10 == 0 && !f.node.isHidden && f.spin == nil {
                        for rock in battle.rocks {
                            smallestShipClearance = min(smallestShipClearance,simd_distance(f.position,rock.position)-rock.radius)
                        }
                    }
                }
                for ship in battle.carriers where ship.faction.usesBlinkFTL {
                    check(ship.warp.isHidden,"BSG carrier produced a hyperspace streak")
                    if !ship.node.isHidden { check(simd_distance(ship.node.simdPosition,ship.origin)<0.001,"Blink-FTL capital ship slid through space") }
                }
                if frame%60 == 0 {
                    let expected = initialNodes+battle.lasers.count+battle.sparks.count+battle.effects.count+battle.blasts.count+battle.carriers.count*2
                    check(battle.scene.rootNode.childNodes.count == expected,"Leaked transient scene nodes")
                }
                check(battle.camera.simdPosition.x.isFinite,"Invalid camera position")
                if frame%10 == 0 {
                    for rock in battle.rocks {
                        smallestCameraClearance = min(smallestCameraClearance,simd_distance(battle.cameraPosition,rock.position)-rock.radius)
                    }
                }
            }
            check(cameraVisits.count == 6,"Not all cameras were visited")
            check(maxLasers<250 && maxSparks<1500 && maxEffects<100 && maxBlasts<40,"Unbounded effects")
            check(battle.destroyed>5 && battle.minimumFleet<=7,"No meaningful fleet attrition")
            check(battle.waveNumber>2 && battle.reinforcements>12,"No reinforcement waves")
            check((battle.formationArrivals == 0 || battle.director.formationCuts>0) && battle.director.carrierCuts>0,"Arrival cameras did not cover the incoming ships")
            check(battle.replacementCount>=2,"Faction elimination stopped progressing")
            check(battle.carrierVisits>0 && battle.carrierDepartures>=battle.carrierVisits-2,"Carrier did not leave after deployment")
            check(battle.spinOuts>0 && battle.recoveries+battle.asteroidLosses>0,"No asteroid incidents")
            check(smallestShipClearance>7,"Fighter intersects asteroid in seed \(seed): clearance \(smallestShipClearance)")
            check(smallestCameraClearance>0,"Camera enters asteroid in seed \(seed): clearance \(smallestCameraClearance)")
            print("PASS seed \(seed): 10 minutes, 6 cameras; \(battle.replacementCount) faction replacements, \(battle.encounteredFactions.map(\.rawValue).sorted()); \(battle.blinkArrivals)/\(battle.blinkDepartures) blink jumps; \(battle.destroyed) losses, \(battle.waveNumber) waves; \(battle.spinOuts) strikes / \(battle.recoveries) recoveries; min normal ship/camera clearance \(smallestShipClearance)/\(smallestCameraClearance); max effects \(maxLasers)/\(maxSparks)/\(maxEffects)/\(maxBlasts).")
            fflush(stdout)
        }
    }
    let repeatA = Dogfight(seed:1234), repeatB = Dogfight(seed:1234)
    check(repeatA.rocks.map(\.position) == repeatB.rocks.map(\.position),"Seed is not reproducible")
    print("PASS: different seeds randomize the arena; identical seeds reproduce it.")
}

private func verifyFactionLifecycle() {
    let b = Dogfight(seed:505,initialFactions:[.rebel,.empire],initialArrivals:false)
    b.automatic = false
    for f in b.fighters { f.cooldown = 10000; f.collisionCooldown = 10000 }
    let roster = b.fighters.filter{$0.side == 0}
    for f in roster.dropLast() { b.destroy(f) }
    for _ in 0..<120 { b.update(dt:1.0/30.0) }
    check(b.replacementCount == 0 && b.sideCount(0) == 1,"Depleted faction was replaced before its last ship died")
    for round in 0..<12 {
        let side = round%2, previous = b.sideFactions[side], opponent = b.sideFactions[1-side]
        for f in b.fighters where f.side == side && f.active { b.destroy(f) }
        let priorGeneration = b.fighters.first{$0.side == side}!.generation
        b.update(dt:1.0/30.0)
        check(b.pendingSides.contains(side),"Defeated side did not schedule a replacement")
        check(b.sideFactions[side] != previous && b.sideFactions[side] != opponent,"Replacement repeated the defeated faction or the opponent")
        let incoming = b.fighters.first{$0.side == side}!
        check(incoming.generation == priorGeneration+1,"Model generation did not advance")
        // An old projectile aimed at this roster slot must not damage its new occupant.
        incoming.state = .active; incoming.node.isHidden = false
        let hp = incoming.hitPoints
        let bolt = SCNNode(); b.scene.rootNode.addChildNode(bolt)
        b.lasers.append(Laser(node:bolt,position:incoming.position,velocity:.zero,life:0.01,target:b.fighters.firstIndex{$0 === incoming}!,hits:true,faction:previous,targetGeneration:priorGeneration))
        b.updateLasers(0)
        check(incoming.hitPoints == hp,"Old-generation projectile damaged a replacement faction")
        b.updateLasers(0.1); incoming.state = .destroyed; incoming.node.isHidden = true
        for _ in 0..<900 {
            for f in b.fighters { f.cooldown = 10000; f.collisionCooldown = 10000 }
            b.update(dt:1.0/30.0)
        }
        check(b.sideCount(side) == 6,"Replacement squadron did not fully deploy")
        check(b.carriers.isEmpty,"Replacement carrier failed to depart")
    }
    check(b.replacementCount == 12 && b.encounteredFactions.count == 4,"Faction selection did not cover the four-faction catalog")
    print("PASS: no partial refills; twelve distinct-side replacements across all four factions; stale projectiles cannot damage new generations.")
}

private func verifyBlinkCarriers() {
    for faction in [Faction.colonial,.cylon] {
        let b = Dogfight(seed:999,initialFactions:[faction,.rebel],initialArrivals:false)
        for f in b.fighters where f.side == 0 { b.destroy(f) }
        b.deployReinforcements(side:0)
        let ship = b.carriers[0]
        for _ in 0..<390 {
            for f in b.fighters { f.cooldown = 10000; f.collisionCooldown = 10000 }
            b.update(dt:1.0/30.0)
            let age = b.time-ship.start
            check(ship.warp.isHidden,"Blink-FTL used a hyperspace trail")
            check(ship.node.simdScale == V3(repeating:1),"Capital model stretched during FTL")
            if age<0.84 { check(ship.node.isHidden,"Capital ship appeared before the FTL blink") }
            if age>0.87 && age<ship.departureAge {
                check(!ship.node.isHidden && simd_distance(ship.node.simdPosition,ship.origin)<0.001,"Capital ship did not blink into a fixed location")
            }
            if age>ship.departureAge { check(ship.node.isHidden,"Capital ship faded or slid away instead of blinking out") }
        }
        check(b.blinkArrivals == 1 && b.blinkDepartures == 1 && b.carriers.isEmpty,"FTL lifecycle did not complete exactly once")
        check(b.sideCount(0) == 6 && b.fighters.filter{$0.side == 0}.allSatisfy{$0.entry == .hangar && $0.warp.isHidden},"BSG fighters did not launch from their own capital ship")
    }
    print("PASS: Galactica and basestar blink in and out at fixed positions; Vipers and Raiders launch from their respective hangars.")
}

private func verifyFormationAndControl() {
    let b = Dogfight(seed:777,initialFactions:[.rebel,.empire],initialArrivals:false)
    b.automatic = false
    for f in b.fighters { b.destroy(f) }
    b.deployReinforcements()
    let rebels = b.fighters.filter { $0.faction == .rebel }
    let targets = Set(rebels.compactMap(\.attackTarget))
    check(targets.count == 6,"X-wings did not receive six individual targets")
    for _ in 0..<90 { b.update(dt:1.0/30.0) }
    for f in rebels {
        let expected = f.entryPosition+f.entryForward*28*(b.time-f.entryTime)
        check(simd_distance(f.position,expected)<0.05,"X-wing V formation did not hold its offsets")
    }
    check(b.fighters.filter{$0.faction == .empire}.allSatisfy{$0.state == .arriving && $0.entry == .hangar && $0.warp.isHidden},"TIEs arrived without their carrier")
    check(b.director.formationCuts == 0 && b.director.carrierCuts == 0,"Automatic events overrode manual camera mode")
    for _ in 0..<120 { b.update(dt:1.0/30.0) }
    check(rebels.contains{simd_distance($0.position,$0.entryPosition+$0.entryForward*28*(b.time-$0.entryTime))>20},"Formation never broke toward attack targets")
    let control = Dogfight(seed:888,initialFactions:[.rebel,.empire],initialArrivals:false); control.automatic = false
    for f in control.fighters { f.cooldown = 1000; f.collisionCooldown = 1000 }
    let survivor = control.fighters[0], casualty = control.fighters[1]
    survivor.position = V3(0,230,0); casualty.position = V3(60,230,0)
    for (f,fatal) in [(survivor,false),(casualty,true)] {
        f.spin = SpinOut(origin:f.position,velocity:V3(0,8,15),axis:V3(1,0,0),orientation:f.node.simdOrientation,duration:2,fatal:fatal)
    }
    for _ in 0..<180 { control.update(dt:1.0/30.0) }
    check(survivor.active && survivor.spin == nil && control.recoveries>0,"Recoverable spin did not regain control")
    check(casualty.state == .destroyed && control.asteroidLosses>0,"Fatal spin did not explode")
    print("PASS: V formation, distinct attack targets, split-up, carrier-only TIE deployment, manual camera control, and both spin-out outcomes.")
}

func renderReview(directory: URL) {
    try! FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
    let battle = Dogfight(seed:requestedSeed(),initialFactions:[.rebel,.empire],initialArrivals:false)
    battle.automatic = false
    let renderer = SCNRenderer(device:MTLCreateSystemDefaultDevice(),options:nil)
    renderer.scene = battle.scene; renderer.pointOfView = battle.camera
    func save(_ name: String, at time: TimeInterval) {
        let image = renderer.snapshot(atTime:time,with:NSSize(width:1280,height:800),antialiasingMode:.multisampling2X)
        let bitmap = NSBitmapImageRep(data:image.tiffRepresentation!)!
        try! bitmap.representation(using:.png,properties:[:])!.write(to:directory.appendingPathComponent(name+".png"))
        print("Rendered \(name)")
        fflush(stdout)
    }
    for _ in 0..<90 { battle.update(dt:1.0/30.0) }
    for i in 0..<6 {
        if i>0 { battle.nextCamera(); battle.update(dt:0) }
        save("camera-\(i+1)",at:Double(battle.time))
    }
    // Inspect combat effects and real arrival geometry, including the separate warp streak.
    battle.cameraIndex = 2
    let victim = battle.fighters.first(where:\.active)!
    let wreck = victim.position
    battle.destroy(victim)
    for (name,frames) in [("explosion-flash",2),("explosion-fire",14),("explosion-cooling",27),("explosion-smoke",42)] {
        for _ in 0..<frames { battle.update(dt:1.0/30.0) }
        battle.camera.simdPosition = wreck+V3(25,12,25)
        battle.camera.look(at:SCNVector3(wreck))
        for cloud in battle.clouds { cloud.update(time:battle.time,camera:battle.camera.simdPosition) }
        save(name,at:Double(battle.time))
    }
    for f in battle.fighters where f.active { battle.destroy(f) }
    battle.automatic = true; battle.deployReinforcements()
    var captured = Set<String>()
    for _ in 0..<840 {
        battle.update(dt:1.0/30.0)
        var name: String?
        let age = battle.director.eventAge
        switch battle.director.event {
        case .formation:
            if age>0.95 && age<1.05 { name = "formation-hyperspace" }
            if age>2.5 && age<2.6 { name = "formation-held" }
            if age>4.7 && age<4.8 { name = "formation-break" }
        case .carrierArrival:
            if age>1.6 && age<1.7 { name = "carrier-arrival" }
            if age>3.7 && age<3.8 { name = "carrier-hangar" }
        case .carrierDeparture:
            if age>0.55 && age<0.65 { name = "carrier-departure" }
        default: break
        }
        if let name, captured.insert(name).inserted {
            save(name,at:Double(battle.time))
        }
    }
    // Exercise both BSG capital ships with the production director and blink timing.
    let bsg = Dogfight(seed:requestedSeed(),initialFactions:[.colonial,.cylon])
    renderer.scene = bsg.scene; renderer.pointOfView = bsg.camera
    var jumps = Set<String>()
    for _ in 0..<640 {
        bsg.update(dt:1.0/30.0)
        guard let ship = bsg.director.featuredCarrier else { continue }
        let age = bsg.time-ship.start, prefix = ship.faction.rawValue
        var name: String?
        if bsg.director.event == .carrierArrival {
            if age>0.79 && age<0.85 { name = prefix+"-before-blink" }
            if age>0.86 && age<0.94 { name = prefix+"-blink-in" }
            if age>1.45 && age<1.55 { name = prefix+"-arrived" }
            if age>3.9 && age<4.05 { name = prefix+"-launch" }
        } else if bsg.director.event == .carrierDeparture {
            if bsg.director.eventAge<0.09 { name = prefix+"-blink-out" }
            if bsg.director.eventAge>0.5 && bsg.director.eventAge<0.6 { name = prefix+"-after-blink" }
        }
        if let name, jumps.insert(name).inserted { save(name,at:Double(bsg.time)) }
    }
    // Examine actual production ship meshes from three directions against a neutral backdrop.
    let scene = SCNScene()
    scene.background.contents = color(0.02,0.035,0.05)
    let key = SCNNode(); key.light = SCNLight(); key.light!.type = .directional; key.light!.intensity = 1500
    key.simdEulerAngles = V3(-0.6,-0.4,0); scene.rootNode.addChildNode(key)
    let ambient = SCNNode(); ambient.light = SCNLight(); ambient.light!.type = .ambient; ambient.light!.intensity = 700
    scene.rootNode.addChildNode(ambient)
    let camera = SCNNode(); camera.camera = SCNCamera(); camera.camera!.zNear = 0.1; camera.camera!.zFar = 3000
    scene.rootNode.addChildNode(camera)
    renderer.scene = scene; renderer.pointOfView = camera
    for (name,ship) in [("xwing",xWing()),("tie",tieFighter()),("viper",colonialViper()),("raider",cylonRaider())] {
        scene.rootNode.addChildNode(ship)
        for (index,position) in [V3(12,7,-16),V3(0,1,-20),V3(-13,5,15)].enumerated() {
            camera.simdPosition = position; camera.look(at:SCNVector3(0,0,-1),up:SCNVector3(0,1,0),localFront:SCNVector3(0,0,-1))
            save("\(name)-\(index+1)",at:0)
        }
        ship.removeFromParentNode()
    }
    for (name,ship) in [("galactica",battlestarGalactica()),("basestar",cylonBasestar())] {
        scene.rootNode.addChildNode(ship)
        for (index,position) in [V3(260,140,-300),V3(0,350,-110),V3(-250,90,280)].enumerated() {
            camera.simdPosition = position
            camera.look(at:SCNVector3(0,0,0),up:SCNVector3(0,1,0),localFront:SCNVector3(0,0,-1))
            save("\(name)-\(index+1)",at:0)
        }
        ship.removeFromParentNode()
    }
}
