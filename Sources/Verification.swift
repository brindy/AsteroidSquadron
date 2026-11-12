import AppKit
import SceneKit
import Metal
import simd

func combatBenchmark() {
    for seed: UInt64 in [42,2026,51966] {
        autoreleasepool {
            let b = Dogfight(seed:seed,initialFactions:[.rebel,.empire],initialArrivals:false)
            b.automatic = false
            var activeSeconds: Float = 0
            for _ in 0..<7200 { activeSeconds += Float(b.activeCount)/60; b.update(dt:1.0/60) }
            print("COMBAT seed \(seed): \(b.shots) bolts, \(b.weaponHits) hits, \(b.destroyed) losses; \(b.shots == 0 ? 0 : Float(b.weaponHits)/Float(b.shots)) hit ratio; \(Float(b.shots)/max(1,activeSeconds)) bolts per active fighter-second; \(b.shipCollisions) ship collisions.")
            fflush(stdout)
        }
    }
}

func renderPlanetReview(directory: URL) {
    try! FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
    let renderer = SCNRenderer(device:MTLCreateSystemDefaultDevice(),options:nil)
    let scene = SCNScene(); scene.background.contents = color(0.002,0.004,0.009)
    let camera = SCNNode(); camera.camera = SCNCamera()
    camera.camera!.zNear = 0.1; camera.camera!.zFar = 12000; camera.camera!.fieldOfView = 45
    camera.camera!.wantsHDR = true; camera.camera!.exposureOffset = 0.2
    camera.camera!.wantsExposureAdaptation = false
    renderer.scene = scene; renderer.pointOfView = camera; scene.rootNode.addChildNode(camera)
    let sun = unit(V3(-0.4,0.3,0.86)), tangent = unit(simd_cross(sun,V3(0,1,0)))
    func aimCamera(degrees: Float) {
        let angle = degrees*Float.pi/180
        camera.simdPosition = (sun*cos(angle)+tangent*sin(angle))*1050
        camera.look(at:SCNVector3Zero)
    }
    func saveFrame(_ name: String, time: Float = 0) {
        let image = renderer.snapshot(atTime:Double(time),with:NSSize(width:1200,height:900),antialiasingMode:.multisampling4X)
        let bitmap = NSBitmapImageRep(data:image.tiffRepresentation!)!
        try! bitmap.representation(using:.png,properties:[:])!.write(to:directory.appendingPathComponent("\(name).png"))
    }
    for biome in PlanetBiome.allCases {
      for seed: UInt64 in [42,2026] {
        let planet = ProceduralPlanet(seed:seed,radius:300,sun:sun,biome:biome)
        scene.rootNode.addChildNode(planet.node)
        for (name,degrees,time) in [("day",Float(25),Float(0)),("terminator",80,0),("crescent",130,0),("night",165,0),("rotated",25,600)] {
            aimCamera(degrees:degrees)
            planet.update(time:time)
            saveFrame("planet-\(biome.slug)-\(seed)-\(name)",time:time)
            print("Rendered planet \(biome.slug) \(seed) \(name)"); fflush(stdout)
            if biome == .temperate && seed == 42 && name == "day" {
                for (layer,hideSurface,hideCloud,hideAtmosphere) in [("surface",false,true,true),("surface-clouds",false,false,true),("atmosphere",true,true,false)] {
                    planet.surface.isHidden = hideSurface; planet.clouds.isHidden = hideCloud; planet.atmosphere.isHidden = hideAtmosphere
                    saveFrame("planet-42-layer-\(layer)")
                }
                planet.surface.isHidden = false; planet.clouds.isHidden = false; planet.atmosphere.isHidden = false
            }
        }
        if biome == .temperate && seed == 42 {
            aimCamera(degrees:25)
            planet.update(time:0)
            for _ in PlanetBiome.allCases { planet.nextBiome() }
            check(planet.biome == biome,"Planet biome did not wrap after a full cycle")
            planet.clouds.isHidden = true; planet.atmosphere.isHidden = true
            saveFrame("planet-42-layer-surface-after-cycle")
        }
        planet.node.removeFromParentNode()
      }
    }
}

private func check(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() { print("FAIL: \(message)"); fflush(stdout); exit(1) }
}

private func pursuitRing(seed: UInt64) -> (Dogfight,[Int]) {
    let b = Dogfight(seed:seed,initialFactions:[.colonial,.cylon],initialArrivals:false)
    b.automatic = false
    for rock in b.rocks { rock.node.removeFromParentNode() }; b.rocks.removeAll()
    let roster = [0,1,4,5] // Alternating Vipers and Raiders, all with equal cruise speed.
    for i in b.fighters.indices where !roster.contains(i) { b.fighters[i].state = .destroyed; b.fighters[i].node.isHidden = true }
    for (slot,index) in roster.enumerated() {
        let angle = Float(slot)*tau/4, f = b.fighters[index]
        b.activateFlight(f,position:V3(sin(angle)*110,250,cos(angle)*110),forward:V3(cos(angle),0,-sin(angle)),speed:56)
        f.entry = .none; f.attackTarget = roster[(slot+1)%roster.count]; f.cooldown = 0
    }
    return (b,roster)
}

func verifyPursuitLimits() {
    let (selection,_) = pursuitRing(seed:313)
    let pilot = selection.fighters[0]
    selection.fighters[4].state = .destroyed; selection.fighters[4].node.isHidden = true
    let extra = selection.fighters[2]; extra.state = .active; extra.node.isHidden = false
    selection.activateFlight(pilot,position:V3(0,250,0),forward:V3(0,0,-1),speed:56)
    selection.activateFlight(selection.fighters[1],position:V3(0,250,-80),forward:V3(1,0,0),speed:56)
    selection.activateFlight(extra,position:V3(30,250,-30),forward:V3(1,0,0),speed:56)
    selection.activateFlight(selection.fighters[5],position:V3(0,250,-240),forward:V3(1,0,0),speed:56)
    selection.time = 20; pilot.attackTarget = 1; pilot.pursuitTarget = 1
    pilot.pursuitGeneration = selection.fighters[1].generation; pilot.pursuitDeadline = 19; pilot.burstShotsLeft = 4
    let before = pilot.position
    selection.updateFlight(pilot,dt:1.0/60,positions:selection.fighters.map(\.position),velocities:selection.fighters.map(\.velocity),active:selection.fighters.map(\.active))
    check(pilot.attackTarget == 2,"Timed-out pilot did not choose the next-nearest alternative enemy")
    check(pilot.burstShotsLeft == 0 && pilot.breakUntil>selection.time,"Pilot did not break off its expired attack")
    check(simd_distance(before,pilot.position)<2,"Pursuit break teleported the ship")
    let window = pilot.pursuitDeadline-pilot.breakUntil
    check(window>=5 && window<=10,"Next pursuit is not limited to 5–10 seconds")
    check(!selection.fire(from:0,to:2),"Pilot kept firing during its breakaway")
    // With no other enemy, retain the opponent but leave the old pursuit plane.
    for i in [1,5] { selection.fighters[i].state = .destroyed; selection.fighters[i].node.isHidden = true }
    selection.time = pilot.pursuitDeadline+0.1
    let forward = pilot.forward
    selection.breakPursuit(pilot,target:2,positions:selection.fighters.map(\.position))
    check(pilot.attackTarget == 2 && simd_dot(forward,pilot.breakDirection)<0.8,"Single-enemy fallback did not manoeuvre before re-engaging")
    for seed: UInt64 in [42,2026,51966,919] {
        autoreleasepool {
            let (b,roster) = pursuitRing(seed:seed)
            // Hold damage off long enough for all four pilots to exhaust a
            // pursuit window; an early broadside kill must not bypass this check.
            for i in roster { b.fighters[i].cooldown = 10000 }
            for _ in 0..<720 { b.update(dt:1.0/60) }
            check(roster.allSatisfy{b.fighters[$0].active && b.fighters[$0].pursuitBreakCount>0},"A pilot failed to abandon an unsuccessful pursuit within ten seconds")
            for i in roster { b.fighters[i].cooldown = 0 }
            var firstHit: Float?, firstLoss: Float?
            for _ in 0..<5400 {
                b.update(dt:1.0/60)
                if firstHit == nil && b.weaponHits>0 { firstHit = b.time }
                if firstLoss == nil && roster.contains(where:{b.fighters[$0].state == .destroyed || b.fighters[$0].generation>0}) { firstLoss = b.time }
                if firstHit != nil && firstLoss != nil { break }
            }
            check(firstHit != nil && firstLoss != nil,"Four equal-speed ships remained in a pursuit loop for seed \(seed): \(b.shots) bolts, \(b.weaponHits) hits, \(b.pursuitBreaks) breaks")
            print("PASS pursuit seed \(seed): first hit at \(firstHit!)s, first loss at \(firstLoss!)s; \(b.pursuitBreaks) tactical breaks.")
            fflush(stdout)
        }
    }
    print("PASS: 5–10 second pursuit windows, next-nearest retargeting, bounded breakaways, single-opponent manoeuvring, and four-ship chase-ring progress.")
}

private func furballFixture() -> Dogfight {
    let b = Dogfight(seed:141,initialFactions:[.rebel,.empire],initialArrivals:false)
    for rock in b.rocks { rock.node.removeFromParentNode() }
    b.rocks.removeAll()
    for (i,f) in b.fighters.enumerated() {
        let angle = Float(i)*tau/12
        b.activateFlight(f,position:V3(sin(angle)*190,250+Float(i%3)*10,cos(angle)*190),forward:V3(0,0,-1),speed:50)
        f.cooldown = 10000
    }
    b.director.prepareShot(in:b); b.cut = true; b.updateCamera(0)
    return b
}

private func verifyCriticalDirector() {
    let b = furballFixture()
    b.director.nextHighlightTime = 10000
    let cuts = b.director.hardCuts
    for _ in 0..<1200 {
        b.time += 1.0/30; b.cameraAge += 1.0/30; b.updateCamera(1.0/30)
        check(b.cameraIndex == 2 && b.director.event == .none,"Automatic camera cycled away from the furball without an event")
    }
    check(b.director.hardCuts == cuts,"A quiet furball triggered arbitrary camera cuts")
    let view = unit(b.cameraLook-b.cameraPosition)
    check(b.fighters.allSatisfy{simd_dot(unit($0.position-b.cameraPosition),view)>cos(24*Float.pi/180)},"Wide shot omitted fighters on the furball's edges")
    let a = b.fighters[0], target = b.fighters.first{$0.side != a.side}!
    b.activateFlight(a,position:V3(0,250,40),forward:V3(0,0,-1),speed:50)
    b.activateFlight(target,position:V3(0,250,-40),forward:V3(0,0,-1),speed:40)
    a.attackTarget = b.fighters.firstIndex{$0 === target}; a.burstShotsLeft = 4; target.hitPoints = 2
    b.director.nextHighlightTime = 0; b.director.considerCriticalMoment(in:b)
    check(b.director.event == .attack,"Critical firing opportunity did not trigger an attack shot")
    b.updateCamera(0)
    let attackCut = b.director.hardCuts
    b.destroy(target); b.updateCamera(1.0/60)
    check(b.director.event == .explosion && b.director.hardCuts == attackCut,"Attack-to-explosion tracking introduced an unnecessary cut")
    for _ in 0..<65 { b.time += 1.0/30; b.cameraAge += 1.0/30; b.updateCamera(1.0/30) }
    check(b.director.event == .none && b.cameraIndex == 2 && b.director.nextHighlightTime>b.time+8,"Highlight did not return to an uninterrupted wide hold")
    b.automatic = false; b.cameraIndex = 3; b.cut = true; b.updateCamera(0)
    b.director.requestSpin(0,in:b); b.director.considerCriticalMoment(in:b)
    check(b.director.event == .none && b.cameraIndex == 3,"Critical director overrode manual mode")
    print("PASS: whole-furball framing; forty seconds with no arbitrary cuts; critical attack and explosion continuity; wide return/dwell; manual camera control.")
}

private func distantSquadrons() -> Dogfight {
    let b = Dogfight(seed:42,initialFactions:[.rebel,.empire],initialArrivals:false)
    b.automatic = false; b.cameraIndex = 2
    var slots = [0,0]
    for f in b.fighters {
        let slot = slots[f.side]; slots[f.side] += 1
        let center = f.side == 0 ? V3(2500,500,-2100) : V3(-1900,900,2300)
        let position = center+V3(Float(slot%3-1)*38,Float(slot/3)*22,Float(slot/3)*32)
        b.activateFlight(f,position:position,forward:unit(-center),speed:50)
    }
    b.director.prepareShot(in:b); b.cut = true; b.updateCamera(0)
    return b
}

private func verifyBattlefieldFraming() {
    let b = distantSquadrons()
    func readableShips() -> Int {
        let forward = unit(b.cameraLook-b.cameraPosition)
        return b.fighters.filter { f in
            let to = f.position-b.cameraPosition, distance = simd_length(to)
            return f.active && simd_dot(unit(to),forward)>cos(24*Float.pi/180) && f.faction.collisionRadius/distance>0.01
        }.count
    }
    check(readableShips()>=6,"Battlefield camera did not frame a distant squadron at a readable size")
    check(simd_length(b.cameraLook)>2000,"Battlefield camera remained locked to the empty asteroid belt")
    let index = b.director.overviewSubject!
    b.destroy(b.fighters[index]); b.updateCamera(1.0/60)
    check(readableShips()>=5,"Battlefield view lost the ships when its subject was destroyed")
    print("PASS: battlefield view frames readable ships thousands of units outside the belt, separates distant squadrons, and replaces destroyed subjects.")
}

private func verifyShipTraffic() {
    func pair(_ faction: Faction = .rebel, friendly: Bool = true) -> (Dogfight,Fighter,Fighter) {
        let enemy: Faction = faction == .empire ? .rebel : .empire
        let b = Dogfight(seed:919,initialFactions:[faction,enemy],initialArrivals:false)
        b.automatic = false; b.rocks.removeAll()
        let a = b.fighters[0], other = b.fighters.first{$0 !== a && ($0.side == a.side) == friendly}!
        for f in b.fighters where f !== a && f !== other { f.state = .destroyed; f.node.isHidden = true }
        for f in [a,other] { f.entry = .none; f.cooldown = 10000 }
        return (b,a,other)
    }
    for faction in Faction.allCases {
        let (b,a,c) = pair(faction)
        b.activateFlight(a,position:V3(0,250,115),forward:V3(0,0,-1),speed:56)
        b.activateFlight(c,position:V3(0,250,-115),forward:V3(0,0,1),speed:56)
        a.patrolRoute = [V3(0,250,-500)]
        c.patrolRoute = [V3(0,250,500)]
        var clearance: Float = 1000
        var lateralSeparation: Float = 0
        // Exercise steering directly so unrelated fleet replacement and gunfire cannot
        // mask whether the two friendly pilots actually avoided a head-on collision.
        for _ in 0..<240 {
            let positions = b.fighters.map(\.position), velocities = b.fighters.map(\.velocity), active = b.fighters.map(\.active)
            b.time += 1.0/60
            b.updateFlight(a,dt:1.0/60,positions:positions,velocities:velocities,active:active)
            b.updateFlight(c,dt:1.0/60,positions:positions,velocities:velocities,active:active)
            clearance = min(clearance,simd_distance(a.position,c.position))
            lateralSeparation = max(lateralSeparation,abs(a.position.x-c.position.x))
        }
        check(clearance>a.faction.collisionRadius+c.faction.collisionRadius+3,"Friendly \(faction) pilots failed to avoid a head-on encounter: \(clearance)")
        check(lateralSeparation>10,"\(faction) pilots did not choose different passing lanes")
    }
    // An overtaking pilot must yield instead of flying through a slower wingman.
    let (traffic,fast,slow) = pair(.colonial)
    traffic.activateFlight(fast,position:V3(0,250,90),forward:V3(0,0,-1),speed:90)
    traffic.activateFlight(slow,position:V3(0,250,0),forward:V3(0,0,-1),speed:40)
    fast.patrolRoute = [V3(0,250,-500)]
    slow.patrolRoute = [V3(0,250,-500)]
    var nearest: Float = 1000
    for _ in 0..<240 {
        let p = traffic.fighters.map(\.position), v = traffic.fighters.map(\.velocity), active = traffic.fighters.map(\.active)
        traffic.time += 1.0/60
        traffic.updateFlight(fast,dt:1.0/60,positions:p,velocities:v,active:active)
        traffic.updateFlight(slow,dt:1.0/60,positions:p,velocities:v,active:active)
        nearest = min(nearest,simd_distance(fast.position,slow.position))
    }
    check(nearest>14,"Overtaking pilot ran into a wingman")
    for friendly in [true,false] {
        let (b,a,c) = pair(.rebel,friendly:friendly)
        b.activateFlight(a,position:V3(-8,250,0),forward:V3(1,0,0),speed:10)
        b.activateFlight(c,position:V3(8,250,0),forward:V3(-1,0,0),speed:10)
        let start = b.fighters.map(\.position), active = b.fighters.map(\.active)
        a.position.x = -6; c.position.x = 6
        b.resolveShipCollisions(from:start,wasActive:active,dt:0.2)
        check(a.active && c.active && a.hitPoints<6 && c.hitPoints<6,"Gentle contact did not damage both \(friendly ? "friendly" : "enemy") ships")
        check(a.spin != nil && c.spin != nil,"Collision did not knock survivors out of control")
        check(simd_distance(a.position,c.position)>=a.faction.collisionRadius+c.faction.collisionRadius,"Contact left overlapping hulls")
        check(simd_length(a.velocity+c.velocity)<0.001,"Collision failed momentum conservation")
        let hp = a.hitPoints
        // The same sustained contact is one impact, not 60 impacts per second.
        c.position = a.position+V3(a.faction.collisionRadius+c.faction.collisionRadius-0.1,0,0)
        b.resolveShipCollisions(from:b.fighters.map(\.position),wasActive:active,dt:1.0/60)
        check(a.hitPoints == hp && b.shipCollisions == 1,"A sustained contact charged repeated damage")
    }
    let (fatal,a,c) = pair(.empire)
    fatal.activateFlight(a,position:V3(-40,250,0),forward:V3(1,0,0),speed:160)
    fatal.activateFlight(c,position:V3(40,250,0),forward:V3(-1,0,0),speed:160)
    let start = fatal.fighters.map(\.position), active = fatal.fighters.map(\.active)
    a.position.x = 40; c.position.x = -40 // crossed entirely between endpoints
    fatal.resolveShipCollisions(from:start,wasActive:active,dt:0.5)
    check(!a.active && !c.active && fatal.shipCollisionLosses == 2,"High-speed swept collision failed to destroy both ships")
    check(fatal.blasts.count == 2,"Fatal collision did not create explosions")
    print("PASS: Nine-faction friendly head-on avoidance, overtaking separation, friendly/enemy collision damage, contact persistence, momentum, and fatal swept crossings.")
}

private func verifyWeaponsAndMotion() {
    for faction in Faction.allCases {
        let enemy: Faction = faction == .empire ? .rebel : .empire
        let b = Dogfight(seed:707,initialFactions:[faction,enemy],initialArrivals:false)
        b.automatic = false; b.rocks.removeAll()
        let shooter = b.fighters[0], target = b.fighters[6]
        for f in b.fighters where f !== shooter && f !== target { f.state = .destroyed; f.node.isHidden = true }
        let orientation = simd_quatf(angle:0.7,axis:unit(V3(0.3,1,0.2)))
        let forward = orientation.act(V3(0,0,-1))
        shooter.position = V3(0,250,0); shooter.forward = forward; shooter.velocity = forward*50
        shooter.node.simdPosition = shooter.position; shooter.node.simdOrientation = orientation
        let muzzles = shooter.firingMuzzles.map { $0.simdWorldTransform }
        check(muzzles.count == 2,"Missing paired gun muzzles for \(faction)")
        target.position = shooter.position+forward*120; target.velocity = forward*30
        target.node.simdPosition = target.position
        check(b.fire(from:0,to:6),"Aligned \(faction) refused to fire")
        check(b.lasers.count == muzzles.count,"Wrong barrel count for \(faction)")
        for (laser,muzzle) in zip(b.lasers,muzzles) {
            check(simd_distance(laser.launchOrigin,muzzle.columns.3.xyz)<0.0001,"Bolt missed its gun muzzle")
            check(simd_dot(laser.launchForward,forward)>0.99999,"Gun does not point along the model nose")
            check(simd_distance(laser.launchForward,unit(-muzzle.columns.2.xyz))<0.0001,"Bolt steered away from its barrel")
            check(simd_dot(unit(laser.velocity-laser.inheritedVelocity),forward)>0.99999,"Projectile has sideways muzzle velocity")
        }
        target.position = shooter.position-forward*120; target.node.simdPosition = target.position
        check(!b.fire(from:0,to:6),"\(faction) fired backwards")
        target.position = shooter.position+orientation.act(V3(80,0,-120)); target.node.simdPosition = target.position
        check(!b.fire(from:0,to:6),"\(faction) fired sideways")
        let bolt = b.lasers[0]
        target.position = bolt.launchOrigin+unit(bolt.velocity)*30; target.node.simdPosition = target.position
        target.node.simdOrientation = orientation
        let hp = target.hitPoints
        b.updateLasers(0.12)
        check(target.hitPoints<hp,"Forward projectile failed a swept physical hit for \(faction)")
        for laser in b.lasers { laser.node.removeFromParentNode() }; b.lasers.removeAll()
        target.position = shooter.position+forward*120; target.node.simdPosition = target.position
        check(b.fire(from:0,to:6),"Second aligned volley failed")
        target.position += orientation.act(V3(100,0,0)); target.node.simdPosition = target.position
        let escapedHP = target.hitPoints
        b.updateLasers(0.5)
        check(target.hitPoints == escapedHP,"Projectile homed onto an evading target")
    }
    let a = Dogfight(seed:708,initialFactions:[.rebel,.empire],initialArrivals:false)
    let b = Dogfight(seed:708,initialFactions:[.rebel,.empire],initialArrivals:false)
    for battle in [a,b] {
        battle.automatic = false; battle.rocks.removeAll()
        for f in battle.fighters { f.cooldown = 10000 }
    }
    a.update(dt:0); b.update(dt:0)
    for _ in 0..<600 {
        a.update(dt:1.0/30)
        for _ in 0..<2 {
            let before = b.fighters.map { ($0.position,$0.velocity,$0.forward,$0.active,$0.spin != nil,$0.generation) }
            b.update(dt:1.0/60)
            for (f,old) in zip(b.fighters,before) {
                // Impact impulses and uncontrolled tumbles deliberately override normal piloting limits.
                guard f.active && old.3 && f.spin == nil && !old.4 && f.generation == old.5 else { continue }
                check(simd_distance(f.velocity,old.1)<=f.accelerationLimit/60+0.001,"Unbounded flight acceleration")
                check(simd_distance(f.position,old.0)<=215/60+0.001,"Flight teleported")
                check(acos(max(-1,min(1,simd_dot(f.forward,old.2))))<=f.turnRate/60+0.001,"Unbounded nose rotation")
                check(simd_dot(unit(-f.node.simdWorldTransform.columns.2.xyz),unit(f.velocity))>0.9999,"Model nose does not follow velocity")
                check(f.history.count<=120,"Unbounded camera flight history")
            }
        }
        for (x,y) in zip(a.fighters,b.fighters) {
            check(simd_distance(x.position,y.position)<0.001 && simd_distance(x.velocity,y.velocity)<0.001,"30/60 fps flight differs")
        }
    }
    check(a.physicsSteps == b.physicsSteps,"Frame rate changed simulation time")
    let f = a.fighters[0]
    a.rocks = [Rock(node:SCNNode(),position:V3(0,250,0),radius:15,spin:.zero)]
    f.position = V3(0,250,10); f.velocity = V3(0,0,-60)
    a.tryAsteroidStrike(f,from:V3(0,250,50),dt:1.0/60)
    check(f.spin != nil && f.velocity.z>0 && f.position.z>=15+f.faction.collisionRadius,"Swept asteroid impact did not reflect velocity at contact")
    print("PASS: all nine models fire forwards from paired muzzles; physical hits and evasion; bounded, identical 30/60 fps flight; swept asteroid collision.")
}

private func verifyPlanetaryReveals() {
    for (seed,aspect,side) in [(UInt64(42),Float(0.85),0),(7304,1.6,1),(1818,2,0)] {
        for faction in Faction.allCases {
            var factions: [Faction] = [.empire,.rebel]
            factions[side] = faction
            factions[1-side] = faction == .rebel ? .empire : .rebel
            let b = Dogfight(seed:seed,initialFactions:factions,initialArrivals:false)
            b.viewportAspect = aspect
            for f in b.fighters { f.cooldown = 10000; f.collisionCooldown = 10000 }
            for f in b.fighters where f.side == side { b.destroy(f) }
            b.deployReinforcements(side:side)
            let ship = b.carriers.first
            let origin = ship?.origin ?? b.director.arrivalFlight!.origin
            let planetDirection = unit(b.planetPosition)
            let beltEdge = b.rocks.map { simd_length($0.position)+$0.radius }.max()!
            let depth = simd_dot(origin,planetDirection)
            check(depth>beltEdge && depth<simd_length(b.planetPosition)-b.planetRadius,
                  "\(faction) arrived outside the planet-facing gap")
            for f in b.fighters where f.side == side {
                let end = f.entryPosition+f.entryForward*f.entrySpeed*f.formationHold
                check(!b.rocks.contains { sphereImpact(from:f.entryPosition,to:end,center:$0.position,
                                                        radius:$0.radius+f.faction.collisionRadius) != nil },
                      "\(faction) formation or launch corridor intersects an asteroid")
            }
            for _ in 0..<18 { b.update(dt:1.0/60) }
            let wide = Float(b.camera.camera!.fieldOfView)
            for _ in 18..<106 { b.update(dt:1.0/60) }
            let tight = Float(b.camera.camera!.fieldOfView)
            let tangent = tan(tight*Float.pi/360)
            func framed(_ point: V3) -> Bool {
                let p = b.camera.simdConvertPosition(point,from:nil)
                return p.z < -1 && abs(p.y)<(-p.z)*tangent && abs(p.x)<(-p.z)*tangent*aspect
            }
            let points = ship.map { carrier in
                carrier.framingPoints.map { carrier.origin+carrier.node.simdOrientation.act($0*carrier.scale) }
            } ?? b.fighters.filter { $0.side == side }.map(\.position)
            check(points.allSatisfy(framed) && framed(b.planetPosition),
                  "\(faction) reveal lost the arriving ships or the planet at aspect \(aspect)")
            if faction.usesBlinkFTL || faction == .rebel {
                check(wide-tight>7,"\(faction) reveal did not tighten its lens in response to arrival")
            }
        }
    }
    print("PASS: all nine factions arrive in clear lanes between the belt and planet; planetary reveals fit three window shapes; the lens reacts to blink and formation arrivals.")
}

private func verifyContinuousDeployments() {
  for aspect: Float in [1.0,1.6,2.0] {
    for faction in [Faction.empire,.colonial,.cylon,.shadow,.tauri,.goauld,.wraith] {
        let b = Dogfight(seed:710,initialFactions:[faction,.rebel],initialArrivals:false)
        b.viewportAspect = aspect
        b.rocks.removeAll()
        for f in b.fighters where f.side == 0 { b.destroy(f) }
        b.deployReinforcements(side:0)
        let ship = b.carriers[0]
        check(ship.scale == 6,"Capital ship lost its epic scale")
        check(ship.departureAge-ship.lastLaunchAge<=0.2,"Capital ship lingers after last launch")
        var cuts: Int?, departed = false, lastLaunch: Float?, closeDistance: Float?, wideDistance: Float?, handoffChecked = false
        for _ in 0..<660 {
            for f in b.fighters { f.cooldown = 10000 }
            b.update(dt:1.0/60)
            let age = b.time-ship.start
            if b.fighters.filter({$0.side == 0}).allSatisfy(\.active), lastLaunch == nil { lastLaunch = age }
            if age>2.3 && age<ship.departureAge+ship.departureDuration-0.02 {
                check(b.director.featuredCarrier === ship && b.director.event == .carrierArrival,"Camera cut away before departure completed")
                if let cuts { check(cuts == b.director.hardCuts,"Fighter launch and departure contain an extra camera cut") }
                else { cuts = b.director.hardCuts }
            }
            if age>2.5 && age<2.58, let hero = ship.squadron.first {
                let f = b.fighters[hero]
                closeDistance = simd_distance(b.cameraPosition,f.position)
                check(closeDistance!<125,"\(faction) launch shot did not begin close to the first fighter: \(closeDistance!)")
                check(simd_dot(unit(f.position-b.cameraPosition),unit(b.cameraLook-b.cameraPosition))>0.98,"Launching fighter is outside the composition")
            }
            if age>4.28 && age<ship.departureAge+ship.departureDuration-0.02 {
                let group = ship.squadron.map { b.fighters[$0].position }.reduce(V3.zero,+)/Float(ship.squadron.count)
                wideDistance = simd_distance(b.cameraPosition,group)
                check(simd_distance(b.cameraLook,group)<4,"Pullback stopped tracking the fighter group")
                func framed(_ point: V3) -> Bool {
                    let p = b.camera.simdConvertPosition(point,from:nil)
                    let tangent = tan(Float(b.camera.camera!.fieldOfView)*Float.pi/360)
                    return p.z < -1 && abs(p.y)<(-p.z)*tangent && abs(p.x)<(-p.z)*tangent*b.viewportAspect
                }
                check(ship.squadron.allSatisfy{framed(b.fighters[$0].position)},"Pullback lost one of the emerging fighters")
                for local in ship.framingPoints where age<ship.departureAge {
                    let world = ship.station(age)+ship.node.simdOrientation.act(local*ship.scale)
                    check(framed(world),"Pullback did not reveal the whole \(faction) capital ship")
                }
            }
            if ship.departing && !departed {
                departed = true
                check(lastLaunch != nil && age-lastLaunch!<=0.22,"Capital departure did not immediately follow the final fighter")
            }
            if b.director.event == .handoff {
                let group = ship.squadron.map { b.fighters[$0].position }.reduce(V3.zero,+)/Float(ship.squadron.count)
                if !handoffChecked {
                    check(age>ship.departureAge+ship.departureDuration,"Handoff interrupted the capital departure")
                    let expected = b.fighters.indices.filter { b.fighters[$0].active && !ship.squadron.contains($0) }.min { simd_distance_squared(b.fighters[$0].position,group)<simd_distance_squared(b.fighters[$1].position,group) }
                    check(b.director.handoffAnchor == expected,"Departure handoff did not choose the nearest existing ship")
                    handoffChecked = true
                }
                check(simd_distance(b.cameraLook,group)<0.1,"Handoff camera is not trained on the incoming squadron")
                let local = b.camera.simdConvertPosition(b.fighters[b.followedIndex].position,from:nil)
                let tangent = tan(Float(b.camera.camera!.fieldOfView)*Float.pi/360)
                check(local.z<0 && abs(local.y)<(-local.z)*tangent && abs(local.x)<(-local.z)*tangent*b.viewportAspect,"Existing fighter left the handoff composition")
            }
        }
        check(departed && b.carriers.isEmpty && b.director.carrierLaunchCuts == 1,"Capital deployment shot sequence failed")
        check(closeDistance != nil && wideDistance != nil && wideDistance!>closeDistance!*4,"Launch camera did not physically pull back")
        check(handoffChecked && b.director.handoffCuts == 1,"Capital departure did not hand off to an existing fighter")
    }
  }
    print("PASS: seven capital ships, three window shapes: close launch, continuous pullback framing the full capital and all fighters, and group tracking through departure.")
}

private func handoffFixture() -> Dogfight {
    let b = Dogfight(seed:411,initialFactions:[.rebel,.empire],initialArrivals:false)
    for rock in b.rocks { rock.node.removeFromParentNode() }; b.rocks.removeAll()
    let roster = [0,1,4,5]
    for i in b.fighters.indices where !roster.contains(i) { b.fighters[i].state = .destroyed; b.fighters[i].node.isHidden = true }
    for (index,position) in [(0,V3(0,250,-500)),(4,V3(35,265,-520)),(1,V3(0,250,0)),(5,V3(300,250,80))] {
        b.activateFlight(b.fighters[index],position:position,forward:V3(0,0,-1),speed:52)
    }
    let carrier = Carrier(faction:.empire,side:0,origin:V3(0,250,-700),forward:V3(0,0,1),start:0,squadron:[0,4])
    b.director.rememberIncomingSquadron(carrier,in:b)
    return b
}

private func verifyArrivalHandoff() {
    let b = handoffFixture()
    check(b.director.startArrivalHandoff(in:b),"Handoff rejected a valid existing fighter")
    b.updateCamera(0)
    check(b.director.handoffAnchor == 1,"Handoff chose a newly arrived or more distant fighter")
    let anchor = b.fighters[1]
    check(simd_dot(b.cameraPosition-anchor.position,anchor.forward)<(-10),"Handoff did not place the camera behind the existing pilot")
    check(b.camera.simdConvertPosition(anchor.position,from:nil).z<0,"Existing pilot is not in front of the handoff camera")
    b.destroy(anchor); b.updateCamera(1.0/60)
    check(b.director.event == .handoff && b.director.handoffAnchor == 5,"Destroyed handoff anchor did not fall back to another existing survivor")
    b.fighters[5].replaceFaction(.colonial); b.fighters[5].state = .active; b.fighters[5].node.isHidden = false
    b.updateCamera(1.0/60)
    check(b.director.event == .none && b.cameraIndex == 2,"Handoff attached to a replacement generation instead of returning wide")
    let manual = handoffFixture(); manual.automatic = false
    check(!manual.director.startArrivalHandoff(in:manual) && manual.director.event == .none,"Handoff overrode manual camera mode")
    let initial = Dogfight(seed:412,initialFactions:[.colonial,.cylon])
    for _ in 0..<330 { initial.update(dt:1.0/60) }
    check(initial.director.handoffCuts == 0 && initial.director.event == .none,"Initial deployment invented an existing ship to follow")
    print("PASS: nearest existing pilot, rear camera pose, incoming aim, destroyed-anchor fallback, generation protection, manual control and no-existing-ship fallback.")
}

func verifyCinematicOptics(renderDirectory: URL? = nil) {
    let b = Dogfight(seed:7304,initialFactions:[.rebel,.empire],initialArrivals:false,firstAtlantisEncounter:nil)
    let planetDirection = unit(b.planetPosition)
    let lateral = unit(simd_cross(planetDirection,V3(0,1,0)))
    let start = b.planetPosition
    let far = start-lateral*2000
    let angularShift = acos(max(-1,min(1,simd_dot(unit(start),unit(far)))))
    let a = asin(b.planetRadius/simd_length(start))
    let c = asin(b.planetRadius/simd_length(far))
    check(angularShift<0.04 && abs(c/a-1)<0.025,"The planet has local-scale motion parallax")
    check(sin(a)>0.19,"The distant planet lost its epic angular size")
    let hero = b.fighters[0]
    for f in b.fighters where f !== hero { f.state = .destroyed; f.node.isHidden = true }
    for rock in b.rocks { rock.node.removeFromParentNode() }
    b.rocks.removeAll()
    b.activateFlight(hero,position:V3(0,220,0),forward:planetDirection,speed:48)
    let backdrop = b.fighters[1]
    backdrop.node.isHidden = false
    backdrop.node.simdPosition = hero.position+planetDirection*95+lateral*28
    backdrop.node.simdOrientation = hero.node.simdOrientation
    backdrop.node.simdScale = V3(repeating:4)
    b.cameraIndex = 0; b.followedIndex = 0; b.automatic = false
    b.director.prepareShot(in:b); b.cut = true; b.updateCamera(0)
    let lens = b.camera.camera!
    let focus = simd_dot(hero.position-b.cameraPosition,unit(b.cameraLook-b.cameraPosition))
    check(lens.wantsDepthOfField && abs(Float(lens.focusDistance)-focus)<0.01,
          "The pursuit camera focused past its fighter")
    let renderer = SCNRenderer(device:MTLCreateSystemDefaultDevice(),options:nil)
    renderer.scene = b.scene; renderer.pointOfView = b.camera
    func pixels(_ name: String) -> NSBitmapImageRep {
        let image = renderer.snapshot(atTime:0,with:NSSize(width:1120,height:700),antialiasingMode:.multisampling2X)
        let bitmap = NSBitmapImageRep(data:image.tiffRepresentation!)!
        if let renderDirectory {
            try! bitmap.representation(using:.png,properties:[:])!.write(to:renderDirectory.appendingPathComponent(name+".png"))
        }
        return bitmap
    }
    let focused = pixels("lens-subject-focus")
    lens.wantsDepthOfField = false
    let deep = pixels("lens-deep-focus")
    var changed = 0
    for y in stride(from:0,to:focused.pixelsHigh,by:3) {
        for x in stride(from:0,to:focused.pixelsWide,by:3) {
            let p = focused.colorAt(x:x,y:y)!.usingColorSpace(.deviceRGB)!
            let q = deep.colorAt(x:x,y:y)!.usingColorSpace(.deviceRGB)!
            if abs(p.redComponent-q.redComponent)+abs(p.greenComponent-q.greenComponent)+abs(p.blueComponent-q.blueComponent)>0.03 {
                changed += 1
            }
        }
    }
    check(changed>100,"The rendered camera did not produce visible depth of field")
    print("PASS: a large distant planet with restrained parallax; fighter focus matches the subject; native depth of field changes \(changed) sampled pixels.")
}

func verifySimulation() {
    verifyCinematicOptics()
    verifyVeteransAndSkybox()
    verifyBabylon()
    verifyArrivalHandoff()
    verifyPursuitLimits()
    verifyCriticalDirector()
    verifyBattlefieldFraming()
    verifyShipTraffic()
    verifyWeaponsAndMotion()
    verifyPlanetaryReveals()
    verifyContinuousDeployments()
    verifyFactionLifecycle()
    verifyBlinkCarriers()
    verifyFormationAndControl()
    var fingerprints = Set<String>()
    for seed: UInt64 in [42,2026,0xCAFE] {
        autoreleasepool {
            print("Checking seed \(seed)"); fflush(stdout)
            let battle = Dogfight(seed:seed,firstAtlantisEncounter:nil)
            let fingerprint = battle.rocks.prefix(5).map { String(describing:$0.position) }.joined()
            check(fingerprints.insert(fingerprint).inserted,"Arena seeds did not change the layout")
            let initialNodes = battle.persistentNodeCount
            var wideFrames = 0, combatFrames = 0
            var maxLasers = 0, maxSparks = 0, maxEffects = 0, maxBlasts = 0
            var smallestShipClearance: Float = 999, smallestCameraClearance: Float = 999
            var activeSeconds: Float = 0
            for frame in 0..<18000 {
                activeSeconds += Float(battle.activeCount)/30
                battle.update(dt:1.0/30.0)
                let event = battle.director.event
                if event != .formation && event != .carrierArrival && event != .carrierDeparture && event != .handoff && battle.activeCount>0 {
                    combatFrames += 1
                    if event == .none && battle.cameraIndex == 2 { wideFrames += 1 }
                }
                maxLasers = max(maxLasers,battle.lasers.count)
                maxSparks = max(maxSparks,battle.sparks.count)
                maxEffects = max(maxEffects,battle.effects.count)
                maxBlasts = max(maxBlasts,battle.blasts.count)
                check(battle.activeCount+battle.arrivingCount<=12,"Unbounded fleet")
                let aces = battle.fighters.filter(\.isAce)
                check(aces.count<=1,"More than one global Ace")
                if let ace = aces.first {
                    check(ace.aceEligible && ace.aceBadge.visible && ace.enemyKills == battle.aceKillRecord,"Ineligible Ace, incorrect record or missing star")
                    check(!battle.fighters.contains(where:{$0.aceEligible && $0.enemyKills>ace.enemyKills}),"Ace does not lead the eligible kill counts")
                }
                check(battle.fighters.filter{$0.aceBadge.visible}.count == aces.count,"A non-Ace displays a star")
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
                    if frame%10 == 0 && f.active && f.spin == nil {
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
                    for i in battle.fighters.indices where battle.fighters[i].active {
                        for j in battle.fighters.indices where j>i && battle.fighters[j].active {
                            let a = battle.fighters[i], c = battle.fighters[j]
                            check(simd_distance(a.position,c.position)>=a.faction.collisionRadius+c.faction.collisionRadius-0.1,"Unresolved fighter overlap in seed \(seed)")
                        }
                    }
                    for rock in battle.rocks {
                        smallestCameraClearance = min(smallestCameraClearance,simd_distance(battle.cameraPosition,rock.position)-rock.radius)
                    }
                }
            }
            let wideShare = Float(wideFrames)/Float(max(1,combatFrames))
            check(wideShare>0.65,"Combat was not predominantly shown as a furball: \(wideShare)")
            check(battle.director.attackCuts+battle.director.explosionCuts+battle.director.dangerCuts>0,"Critical moments did not trigger camera coverage")
            // Twelve fighters can briefly sustain ~360 bolts with five-volley
            // bursts and a 1.8-second lifetime. Node cleanup is checked separately.
            check(maxLasers<400 && maxSparks<1500 && maxEffects<100 && maxBlasts<40,"Unbounded effects: \(maxLasers) bolts / \(maxSparks) sparks / \(maxEffects) effects / \(maxBlasts) blasts")
            check(battle.destroyed>5 && battle.minimumFleet<=7,"No meaningful fleet attrition")
            check(Float(battle.shots)/max(1,activeSeconds)>0.8 && battle.weaponHits>50,"Pilots did not sustain aggressive, effective gunfire")
            check(battle.waveNumber>2 && battle.reinforcements>12,"No reinforcement waves")
            check((battle.formationArrivals == 0 || battle.director.formationCuts>0) && battle.director.carrierCuts>0,"Arrival cameras did not cover the incoming ships")
            check(battle.replacementCount>=2,"Faction elimination stopped progressing")
            check(battle.carrierVisits>0 && battle.carrierDepartures>=battle.carrierVisits-2,"Carrier did not leave after deployment")
            check(battle.spinOuts>0 && battle.recoveries+battle.asteroidLosses>0,"No asteroid incidents")
            check(smallestShipClearance>5,"Fighter intersects asteroid in seed \(seed): clearance \(smallestShipClearance)")
            check(smallestCameraClearance>0,"Camera enters asteroid in seed \(seed): clearance \(smallestCameraClearance)")
            print("PASS seed \(seed): 10 minutes, \(Int(wideShare*100))% wide combat, \(battle.director.attackCuts)/\(battle.director.explosionCuts)/\(battle.director.dangerCuts) attack/explosion/danger highlights; \(battle.replacementCount) faction replacements; \(battle.destroyed) losses; \(battle.shipCollisions) ship collisions; \(battle.starfuryPivots) Starfury pivots; \(battle.topUpWaves) veteran top-ups; \(battle.acePromotions) ace promotions; min normal ship/camera clearance \(smallestShipClearance)/\(smallestCameraClearance); max effects \(maxLasers)/\(maxSparks)/\(maxEffects)/\(maxBlasts).")
            fflush(stdout)
        }
    }
    let repeatA = Dogfight(seed:1234), repeatB = Dogfight(seed:1234)
    check(repeatA.rocks.map(\.position) == repeatB.rocks.map(\.position),"Seed is not reproducible")
    print("PASS: different seeds randomize the arena; identical seeds reproduce it.")
}

private func verifyFactionLifecycle() {
    let b = Dogfight(seed:505,initialFactions:[.rebel,.empire],initialArrivals:false,firstAtlantisEncounter:nil)
    b.automatic = false
    b.rocks.removeAll() // Isolate roster lifecycle from intentionally dangerous flight.
    for f in b.fighters { f.cooldown = 10000; f.collisionCooldown = 10000 }
    let roster = b.fighters.filter{$0.side == 0}
    for f in roster.dropLast() { b.destroy(f) }
    for _ in 0..<120 { b.update(dt:1.0/30.0) }
    check(b.replacementCount == 0 && b.sideCount(0) == 1,"Depleted faction was replaced before its last ship died")
    for round in 0..<(Faction.allCases.count*5) {
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
        var generations = b.fighters.map(\.generation)
        generations[b.fighters.firstIndex{$0 === incoming}!] = priorGeneration
        b.lasers.append(Laser(node:bolt,position:incoming.position,velocity:.zero,life:0.01,sourceSide:1-side,generations:generations,launchOrigin:incoming.position,launchForward:V3(0,0,-1),inheritedVelocity:.zero,length:0))
        b.updateLasers(0)
        check(incoming.hitPoints == hp,"Old-generation projectile damaged a replacement faction")
        b.updateLasers(0.1); incoming.state = .destroyed; incoming.node.isHidden = true
        for _ in 0..<900 {
            for f in b.fighters { f.cooldown = 10000; f.collisionCooldown = 10000 }
            b.update(dt:1.0/30.0)
        }
        check(b.sideCount(side) == 6,"Replacement squadron did not fully deploy")
        check(b.carriers.isEmpty,"Replacement carrier failed to depart")
        if round>=11 && b.encounteredFactions.count==Faction.allCases.count { break }
    }
    check(b.replacementCount>=12 && b.encounteredFactions.count == Faction.allCases.count,"Faction selection did not cover the nine-faction catalog")
    print("PASS: no premature refills; \(b.replacementCount) distinct-side replacements across all nine factions; stale projectiles cannot damage new generations.")
}

private func verifyBlinkCarriers() {
    for faction in [Faction.colonial,.cylon] {
        let b = Dogfight(seed:999,initialFactions:[faction,.rebel],initialArrivals:false)
        b.rocks.removeAll()
        for f in b.fighters where f.side == 0 { b.destroy(f) }
        b.deployReinforcements(side:0)
        let ship = b.carriers[0]
        for _ in 0..<390 {
            for f in b.fighters { f.cooldown = 10000; f.collisionCooldown = 10000 }
            b.update(dt:1.0/30.0)
            let age = b.time-ship.start
            check(ship.warp.isHidden,"Blink-FTL used a hyperspace trail")
            check(ship.node.simdScale == V3(repeating:ship.scale),"Capital model stretched during FTL")
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
    control.rocks.removeAll()
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
    verifyCinematicOptics(renderDirectory:directory)
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
        battle.cameraIndex = i; battle.cut = true; battle.director.prepareShot(in:battle); battle.update(dt:0)
        save("camera-\(i+1)",at:Double(battle.time))
    }
    let distant = distantSquadrons()
    renderer.scene = distant.scene; renderer.pointOfView = distant.camera
    save("battlefield-distant-squadron",at:0)
    let furball = furballFixture()
    renderer.scene = furball.scene; renderer.pointOfView = furball.camera
    save("battlefield-whole-furball",at:0)
    renderer.scene = battle.scene; renderer.pointOfView = battle.camera
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
            if age>1.52 && age<1.6 { name = "formation-planet" }
            if age>2.5 && age<2.6 { name = "formation-held" }
            if age>4.7 && age<4.8 { name = "formation-break" }
        case .carrierArrival:
            if age>2.55 && age<2.65 { name = "carrier-launch-close" }
            if age>1.6 && age<1.7 { name = "carrier-arrival" }
            if age>3.7 && age<3.8 { name = "carrier-hangar" }
            if age>4.26 && age<4.36 { name = "carrier-pullback" }
            if let ship = battle.director.featuredCarrier, battle.time-ship.start>ship.departureAge+0.55 { name = "carrier-departure" }
        case .carrierDeparture:
            if age>0.55 && age<0.65 { name = "carrier-departure" }
        case .handoff:
            if age>0.7 && age<0.8 { name = "carrier-handoff" }
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
        if bsg.director.event == .handoff && bsg.director.eventAge>0.7 && bsg.director.eventAge<0.8 {
            let prefix = bsg.director.handoffIncoming.first.map { bsg.fighters[$0.index].faction.rawValue } ?? "squadron"
            let name = prefix+"-handoff"
            if jumps.insert(name).inserted { save(name,at:Double(bsg.time)) }
        }
        guard let ship = bsg.director.featuredCarrier else { continue }
        let age = bsg.time-ship.start, prefix = ship.faction.rawValue
        var name: String?
        if bsg.director.event == .carrierArrival {
            if age>0.79 && age<0.85 { name = prefix+"-before-blink" }
            if age>0.86 && age<0.94 { name = prefix+"-blink-in" }
            if age>1.45 && age<1.55 { name = prefix+"-arrived" }
            if age>2.55 && age<2.65 { name = prefix+"-launch-close" }
            if age>3.9 && age<4.05 { name = prefix+"-launch" }
            if age>4.26 && age<4.36 { name = prefix+"-pullback" }
            let sinceDeparture = age-ship.departureAge
            if sinceDeparture>0 && sinceDeparture<0.09 { name = prefix+"-blink-out" }
            if sinceDeparture>0.5 && sinceDeparture<0.6 { name = prefix+"-after-blink" }
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
    for (name,ship) in [("xwing",xWing()),("tie",tieFighter()),("viper",colonialViper()),("raider",cylonRaider()),("wraith-dart",wraithDart())] {
        scene.rootNode.addChildNode(ship)
        for (index,position) in [V3(12,7,-16),V3(0,1,-20),V3(-13,5,15)].enumerated() {
            camera.simdPosition = position; camera.look(at:SCNVector3(0,0,-1),up:SCNVector3(0,1,0),localFront:SCNVector3(0,0,-1))
            save("\(name)-\(index+1)",at:0)
        }
        ship.removeFromParentNode()
    }
    for (name,ship) in [("galactica",battlestarGalactica()),("basestar",cylonBasestar()),("wraith-hive",wraithHive())] {
        scene.rootNode.addChildNode(ship)
        for (index,position) in [V3(260,140,-300),V3(0,350,-110),V3(-250,90,280)].enumerated() {
            camera.simdPosition = position
            camera.look(at:SCNVector3(0,0,0),up:SCNVector3(0,1,0),localFront:SCNVector3(0,0,-1))
            save("\(name)-\(index+1)",at:0)
        }
        ship.removeFromParentNode()
    }
}
