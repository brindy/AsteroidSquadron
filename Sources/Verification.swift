import AppKit
import SceneKit
import Metal
import simd

private func check(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() { print("FAIL: \(message)"); fflush(stdout); exit(1) }
}

func verifySimulation() {
    var fingerprints = Set<String>()
    for seed: UInt64 in [42,2026,0xCAFE] {
        autoreleasepool {
            print("Checking seed \(seed)"); fflush(stdout)
            let battle = Dogfight(seed:seed)
            let fingerprint = battle.rocks.prefix(5).map { String(describing:$0.position) }.joined()
            check(fingerprints.insert(fingerprint).inserted,"Arena seeds did not change the layout")
            let initialNodes = battle.scene.rootNode.childNodes.count
            var cameraVisits = Set<Int>()
            var maxLasers = 0, maxSparks = 0, maxEffects = 0
            var smallestShipClearance: Float = 999, smallestCameraClearance: Float = 999
            for frame in 0..<18000 {
                battle.update(dt:1.0/30.0)
                cameraVisits.insert(battle.cameraIndex)
                maxLasers = max(maxLasers,battle.lasers.count)
                maxSparks = max(maxSparks,battle.sparks.count)
                maxEffects = max(maxEffects,battle.effects.count)
                check(battle.activeCount+battle.arrivingCount<=12,"Unbounded fleet")
                for f in battle.fighters {
                    check(f.position.x.isFinite && f.position.y.isFinite && f.position.z.isFinite,"Non-finite fighter position")
                    check(abs(simd_length(f.forward)-1)<0.01,"Invalid heading")
                    check(f.node.simdScale == V3(repeating:1),"Hyperspace stretched the ship geometry")
                    check(f.active != f.node.isHidden || f.state == .arriving,"Fleet visibility does not match its state")
                    if frame%10 == 0 && !f.node.isHidden {
                        for rock in battle.rocks {
                            smallestShipClearance = min(smallestShipClearance,simd_distance(f.position,rock.position)-rock.radius)
                        }
                    }
                }
                check(battle.camera.simdPosition.x.isFinite,"Invalid camera position")
                if frame%10 == 0 {
                    for rock in battle.rocks {
                        smallestCameraClearance = min(smallestCameraClearance,simd_distance(battle.cameraPosition,rock.position)-rock.radius)
                    }
                }
            }
            check(cameraVisits.count == 6,"Not all cameras were visited")
            check(maxLasers<250 && maxSparks<1500 && maxEffects<100,"Unbounded effects")
            check(battle.destroyed>5 && battle.minimumFleet<=7,"No meaningful fleet attrition")
            check(battle.waveNumber>2 && battle.reinforcements>12,"No reinforcement waves")
            check(battle.scene.rootNode.childNodes.count<initialNodes+maxLasers+maxSparks+maxEffects,"Leaked transient scene nodes")
            check(smallestShipClearance>7,"Fighter intersects asteroid in seed \(seed): clearance \(smallestShipClearance)")
            check(smallestCameraClearance>0,"Camera enters asteroid in seed \(seed): clearance \(smallestCameraClearance)")
            print("PASS seed \(seed): 10 minutes, 6 cameras, \(battle.destroyed) losses, \(battle.waveNumber) waves / \(battle.reinforcements) arrivals; min ship/camera clearance \(smallestShipClearance)/\(smallestCameraClearance); max effects \(maxLasers)/\(maxSparks)/\(maxEffects).")
            fflush(stdout)
        }
    }
    let repeatA = Dogfight(seed:1234), repeatB = Dogfight(seed:1234)
    check(repeatA.rocks.map(\.position) == repeatB.rocks.map(\.position),"Seed is not reproducible")
    print("PASS: different seeds randomize the arena; identical seeds reproduce it.")
}

func renderReview(directory: URL) {
    try! FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
    let battle = Dogfight(seed:requestedSeed())
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
    for _ in 0..<6 { battle.update(dt:1.0/30.0) }
    battle.camera.simdPosition = wreck+V3(24,12,24)
    battle.camera.look(at:SCNVector3(wreck))
    for cloud in battle.clouds { cloud.update(time:battle.time,camera:battle.camera.simdPosition) }
    save("explosion",at:Double(battle.time))
    while battle.activeCount>6 { battle.destroy(battle.fighters.first(where:\.active)!) }
    for _ in 0..<300 {
        battle.update(dt:1.0/30.0)
        if let arriving = battle.fighters.first(where:{$0.state == .arriving && $0.arrival>0.88 && $0.arrival<0.96}) {
            let right = unit(simd_cross(arriving.forward,V3(0,1,0)))
            battle.camera.simdPosition = arriving.position-arriving.forward*80+right*75+V3(0,40,0)
            battle.camera.look(at:SCNVector3(arriving.position))
            for cloud in battle.clouds { cloud.update(time:battle.time,camera:battle.camera.simdPosition) }
            save("hyperspace-wave",at:Double(battle.time))
            break
        }
    }
    // Examine actual production ship meshes from three directions against a neutral backdrop.
    let scene = SCNScene()
    scene.background.contents = color(0.02,0.035,0.05)
    let key = SCNNode(); key.light = SCNLight(); key.light!.type = .directional; key.light!.intensity = 1500
    key.simdEulerAngles = V3(-0.6,-0.4,0); scene.rootNode.addChildNode(key)
    let ambient = SCNNode(); ambient.light = SCNLight(); ambient.light!.type = .ambient; ambient.light!.intensity = 700
    scene.rootNode.addChildNode(ambient)
    let camera = SCNNode(); camera.camera = SCNCamera(); camera.camera!.zNear = 0.1
    scene.rootNode.addChildNode(camera)
    renderer.scene = scene; renderer.pointOfView = camera
    for (name,ship) in [("xwing",xWing()),("tie",tieFighter())] {
        scene.rootNode.addChildNode(ship)
        for (index,position) in [V3(12,7,-16),V3(0,1,-20),V3(-13,5,15)].enumerated() {
            camera.simdPosition = position; camera.look(at:SCNVector3(0,0,-1))
            save("\(name)-\(index+1)",at:0)
        }
        ship.removeFromParentNode()
    }
}
