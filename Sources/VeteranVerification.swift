import AppKit
import SceneKit
import Metal
import simd

private func veteranCheck(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() { print("FAIL: \(message)"); fflush(stdout); exit(1) }
}

func verifyVeteransAndSkybox() {
    verifyAceLeadership()
    let b = Dogfight(seed:1414,initialFactions:[.rebel,.empire],initialArrivals:false)
    b.automatic = false; b.rocks.removeAll()
    for f in b.fighters { f.cooldown = 10000 }
    let friends = b.fighters.filter{$0.side == 0}
    let veteran = friends[0]
    b.destroy(friends[4]); b.destroy(friends[5])
    veteran.hitPoints = 3
    let identity = veteran.generation, position = veteran.position, velocity = veteran.velocity
    b.creditEncounter(surviving:0)
    veteranCheck(b.topUpWaves == 0 && b.squadronEncounters[0] == 1,"A squadron was topped up after only one encounter")
    b.creditEncounter(surviving:0)
    veteranCheck(b.topUpWaves == 1 && b.arrivingCount == 2,"A veteran squadron did not refill only its two losses")
    veteranCheck(veteran.generation == identity && veteran.position == position && veteran.velocity == velocity && veteran.hitPoints == 3,"Top-up reset or repaired a surviving pilot")
    veteranCheck(friends[4].generation == 1 && friends[4].encountersSurvived == 0,"A replacement inherited the old pilot's record")
    for enemy in b.fighters where enemy.side == 1 { b.destroy(enemy) }
    b.requestReplacement(for:1)
    let encounters = b.encountersCompleted
    b.requestReplacement(for:1)
    veteranCheck(b.encountersCompleted == encounters,"A defeated faction was credited more than once")
    veteranCheck(veteran.encountersSurvived == 3 && !veteran.isAce,"Survival alone qualified a pilot without six kills")
    var friendlyReady: Float?, enemyFirst: Float?
    for _ in 0..<1200 {
        b.time += 1.0/60
        b.updateReinforcements(1.0/60)
        for f in b.fighters where f.state == .arriving { _ = b.updateArrival(f) }
        b.updateCarrier(); b.updateFighterJumpClipping()
        if friends.allSatisfy(\.active), friendlyReady == nil { friendlyReady = b.time }
        if b.fighters.contains(where:{$0.side == 1 && $0.active}), enemyFirst == nil { enemyFirst = b.time }
    }
    veteranCheck(friendlyReady != nil && enemyFirst != nil && friendlyReady!<enemyFirst!,"Enemy arrived before friendly top-up completed")
    veteranCheck(b.sideCount(0) == 6 && b.sideFactions[0] == .rebel,"Top-up changed faction or lost a roster slot")
    b.creditEncounter(surviving:0)
    veteranCheck(!veteran.isAce && veteran.encountersSurvived == 4 && b.acePromotions == 0,"Survival alone promoted pilots without kills")
    veteran.enemyKills = 6; b.updateAce()
    veteranCheck(veteran.isAce && b.fighters.filter(\.isAce).count == 1,"Qualified veteran did not receive the sole Ace title")
    veteranCheck(friends[4].encountersSurvived == 1 && !friends[4].isAce,"A newcomer received encounters it did not survive")
    veteranCheck(veteran.aceBadge.visible && veteran.node.childNodes.count == 1,"Ace badge did not preserve the model hierarchy")
    for i in 5...45 { veteran.encountersSurvived = i; b.updateAce() }
    veteranCheck(veteran.aceBadge.node.childNodes.isEmpty,"Ace badge accumulated extra geometry")
    veteran.node.simdOrientation = simd_quatf(angle:1.2,axis:V3(0,0,1)); veteran.aceBadge.updatePose(veteran)
    let world = veteran.aceBadge.node.simdWorldPosition-veteran.node.simdWorldPosition
    veteranCheck(abs(world.x)<0.001 && world.y>=2.5,"Ace badge rolled around the fighter instead of hovering above it")
    veteran.replaceFaction(.colonial); b.updateAce()
    veteranCheck(veteran.encountersSurvived == 0 && !veteran.isAce && veteran.aceBadge.node.parent == nil,"A new pilot inherited an ace badge")
    let empty = Dogfight(seed:1415,initialFactions:[.rebel,.empire],initialArrivals:false)
    for f in empty.fighters { empty.destroy(f) }
    empty.requestReplacement(for:0); empty.requestReplacement(for:1)
    veteranCheck(empty.encountersCompleted == 0,"Mutual destruction awarded survival credit")

    // A steady approach with alternating tiny target offsets should not turn
    // into a sequence of left/right roll corrections. Large manoeuvres and
    // obstacle avoidance are exercised by the regular flight/traffic checks.
    let flight = Dogfight(seed:1416,initialFactions:[.rebel,.empire],initialArrivals:false)
    flight.rocks.removeAll(); flight.automatic = false
    let pilot = flight.fighters[0], target = flight.fighters[6]
    for f in flight.fighters where f !== pilot && f !== target { f.state = .destroyed; f.node.isHidden = true }
    flight.activateFlight(pilot,position:V3(0,250,0),forward:V3(0,0,-1),speed:48)
    flight.activateFlight(target,position:V3(0,250,-400),forward:V3(0,0,-1),speed:0)
    pilot.attackTarget = 6; pilot.pursuitTarget = 6; pilot.pursuitGeneration = target.generation; pilot.pursuitDeadline = 100
    var bankTravel: Float = 0, headingTravel: Float = 0
    for i in 0..<120 {
        flight.time += 1.0/60; target.position.x = i%2 == 0 ? 1.5 : -1.5
        let bank = pilot.bank, forward = pilot.forward
        flight.updateFlight(pilot,dt:1.0/60,positions:flight.fighters.map(\.position),velocities:flight.fighters.map(\.velocity),active:flight.fighters.map(\.active))
        bankTravel += abs(pilot.bank-bank)
        headingTravel += acos(max(-1,min(1,simd_dot(forward,pilot.forward))))
    }
    veteranCheck(bankTravel<0.08 && headingTravel<0.08,"Small sensor/aim corrections still make the pilot shake")

    let sky = ProceduralStarfield(seed:1414), same = ProceduralStarfield(seed:1414), other = ProceduralStarfield(seed:1415)
    let image = sky.image(width:512)
    veteranCheck(image.tiffRepresentation == same.image(width:512).tiffRepresentation,"Skybox seed was not reproducible")
    veteranCheck(image.tiffRepresentation != other.image(width:512).tiffRepresentation,"Skybox seed did not change the galaxy")
    let renderer = SCNRenderer(device:MTLCreateSystemDefaultDevice(),options:nil), scene = SCNScene()
    let camera = SCNNode(); camera.camera = SCNCamera(); scene.rootNode.addChildNode(camera)
    scene.background.contents = image; renderer.scene = scene; renderer.pointOfView = camera
    func pixels(_ position: V3) -> Data {
        camera.simdPosition = position; camera.look(at:SCNVector3(position+V3(0,0,-1)),up:SCNVector3(0,1,0),localFront:SCNVector3(0,0,-1))
        let snapshot = renderer.snapshot(atTime:0,with:NSSize(width:320,height:200),antialiasingMode:.none)
        return NSBitmapImageRep(data:snapshot.tiffRepresentation!)!.representation(using:.png,properties:[:])!
    }
    veteranCheck(pixels(.zero) == pixels(V3(12000,4000,-10000)),"Starfield has translation parallax instead of being an infinite skybox")
    print("PASS: two-win top-ups preserve survivors, arrive before the enemy, protect generations, and preserve the exclusive qualified Ace; world-up Ace stars; steady micro-steering; seeded infinite galaxy skybox with no translation parallax.")
    fflush(stdout)
}

func renderVeteranReview(directory: URL) {
    try! FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
    let b = Dogfight(seed:1414,initialFactions:[.earth,.shadow],initialArrivals:false)
    b.automatic = false
    for rock in b.rocks { rock.node.isHidden = true }
    for cloud in b.clouds { cloud.node.isHidden = true }
    b.planet?.node.isHidden = true
    let hero = b.fighters[0]
    for f in b.fighters where f !== hero { f.node.isHidden = true }
    b.activateFlight(hero,position:.zero,forward:V3(0,0,-1),speed:0)
    let renderer = SCNRenderer(device:MTLCreateSystemDefaultDevice(),options:nil)
    renderer.scene = b.scene; renderer.pointOfView = b.camera
    func save(_ name: String) {
        let snapshot = renderer.snapshot(atTime:0,with:NSSize(width:1280,height:800),antialiasingMode:.multisampling2X)
        let bitmap = NSBitmapImageRep(data:snapshot.tiffRepresentation!)!
        try! bitmap.representation(using:.png,properties:[:])!.write(to:directory.appendingPathComponent(name+".png"))
        print("Rendered \(name)"); fflush(stdout)
    }
    b.camera.camera!.fieldOfView = 49
    b.camera.simdPosition = V3(13,12,-32); b.camera.look(at:SCNVector3(0,4,0),up:SCNVector3(0,1,0),localFront:SCNVector3(0,0,-1))
    hero.enemyKills = 6
    hero.encountersSurvived = 3; b.updateAce()
    save("ace-star")
    hero.node.simdOrientation = simd_quatf(angle:0.9,axis:V3(0,0,1)); hero.aceBadge.updatePose(hero)
    save("ace-banking")
    hero.node.isHidden = true
    let sky = ProceduralStarfield(seed:1414)
    b.camera.simdPosition = .zero
    b.camera.look(at:SCNVector3(sky.rotation.inverse.act(V3(0,0,1))),up:SCNVector3(0,1,0),localFront:SCNVector3(0,0,-1))
    save("galactic-arms")
    // Find a centered core view in the renderer's spherical-map projection.
    // This is an inspection camera only; the production sky remains fixed.
    let g = sky.galaxyForward
    var bestDirection = g, bestCore: CGFloat = -1
    let horizontal: [(Float,Float)] = [(g.x,g.z),(-g.x,g.z),(g.x,-g.z),(-g.x,-g.z),(g.z,g.x),(-g.z,g.x),(g.z,-g.x),(-g.z,-g.x)]
    for (x,z) in horizontal { for y in [g.y,-g.y] {
        let direction = V3(x,y,z)
        b.camera.look(at:SCNVector3(direction),up:SCNVector3(0,1,0),localFront:SCNVector3(0,0,-1))
        let snapshot = renderer.snapshot(atTime:0,with:NSSize(width:64,height:64),antialiasingMode:.none)
        let bitmap = NSBitmapImageRep(data:snapshot.tiffRepresentation!)!
        var brightness: CGFloat = 0
        for yy in 31...33 { for xx in 31...33 {
            let c = bitmap.colorAt(x:xx,y:yy)!.usingColorSpace(.deviceRGB)!
            brightness += c.redComponent+c.greenComponent+c.blueComponent
        } }
        if brightness>bestCore { bestCore = brightness; bestDirection = direction }
    } }
    b.camera.look(at:SCNVector3(bestDirection),up:SCNVector3(0,1,0),localFront:SCNVector3(0,0,-1))
    save("spiral-galaxy")
    let bitmap = NSBitmapImageRep(data:sky.image().tiffRepresentation!)!
    try! bitmap.representation(using:.png,properties:[:])!.write(to:directory.appendingPathComponent("skybox-panorama.png"))
}
