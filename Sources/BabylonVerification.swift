import AppKit
import SceneKit
import Metal
import simd

private func babylonCheck(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() { print("FAIL: \(message)"); fflush(stdout); exit(1) }
}

func verifyBabylon() {
    verifyJumpClipping()
    for faction in [Faction.earth,.shadow] {
        let b = Dogfight(seed:1818,initialFactions:[faction,.rebel],initialArrivals:false)
        b.rocks.removeAll()
        for f in b.fighters where f.side == 0 { b.destroy(f) }
        b.deployReinforcements(side:0)
        let ship = b.carriers[0], window = ship.jumpWindow!
        let nodes = b.scene.rootNode.childNodes.count
        var sawPortalFirst = false, sawDeparture = false, sawHandoff = false
        for _ in 0..<720 {
            for f in b.fighters { f.cooldown = 10000 }
            b.update(dt:1.0/60)
            let age = b.time-ship.start
            if age>0.7 && age<0.8 {
                babylonCheck(!window.node.isHidden && window.openness>0.7,"Jump point did not open before craft emergence")
                babylonCheck(ship.node.isHidden && b.sideCount(0) == 0,"Ships appeared before the jump point opened")
                sawPortalFirst = true
            }
            babylonCheck(ship.node.simdScale == V3(repeating:6),"Jump point stretched the Shadow model")
            if faction == .shadow {
                if age<ship.arrivalDuration || age>=ship.departureAge {
                    babylonCheck(ship.jumpClipper?.plane != nil,"Shadow transit lost its clipping plane")
                } else if age<ship.departureAge-0.65 {
                    babylonCheck(ship.jumpClipper?.plane == nil,"Normal-space Shadow hull remained clipped")
                }
            }
            if faction == .earth {
                for f in b.fighters where f.active && f.side == 0 {
                    let crossing = simd_dot(f.position-f.entryPosition,f.entryForward)<f.faction.collisionRadius+1
                    babylonCheck((f.jumpClipper?.plane != nil) == crossing,"Starfury clipping did not match its aperture crossing")
                }
            }
            for f in b.fighters where f.side == 0 {
                babylonCheck(f.warp.isHidden,"Babylon fighter used an individual hyperspace streak")
                babylonCheck(f.node.simdScale == V3(repeating:1),"Jump point stretched a fighter")
                babylonCheck(f.entry == (faction == .earth ? .jumpWindow : .hangar),"Incorrect Babylon deployment source")
            }
            if age>0.7 && age<2.0 {
                let tangent = tan(Float(b.camera.camera!.fieldOfView)*Float.pi/360)
                for x: Float in [-0.85,0.85] { for y: Float in [-0.85,0.85] {
                    let point = window.node.simdConvertPosition(V3(x*window.radius,y*window.radius,0),to:nil)
                    let local = b.camera.simdConvertPosition(point,from:nil)
                    babylonCheck(local.z<0 && abs(local.y)<(-local.z)*tangent && abs(local.x)<(-local.z)*tangent*b.viewportAspect,"Opening jump point was cropped by the reveal camera")
                } }
            }
            if faction == .shadow && age>3.9 && age<ship.departureAge {
                let ray = ship.origin-b.cameraPosition
                let plane = simd_dot(window.node.simdPosition-b.cameraPosition,ship.forward)/simd_dot(ray,ship.forward)
                if plane>0 && plane<1 {
                    let crossing = b.cameraPosition+ray*plane
                    babylonCheck(simd_distance(crossing,window.node.simdPosition)>window.radius*window.node.simdScale.x,"Departure window obscures the Shadow capital")
                }
            }
            if age>2.45 && age<2.5 { babylonCheck(b.sideCount(0) == 0,"Fighter launched before the opening cinematic") }
            if age>ship.lastLaunchAge+0.02 && age<ship.departureAge {
                babylonCheck(b.sideCount(0) == 6,"Jump point did not deploy a complete squadron")
            }
            if ship.departing {
                sawDeparture = true
                babylonCheck(age>=ship.lastLaunchAge,"Departure happened before the last fighter")
                if age<ship.departureAge+ship.departureDuration-0.04 {
                    babylonCheck(b.director.event == .carrierArrival && b.director.featuredCarrier === ship,"Jump point departure lost its continuous camera scene")
                }
            }
            if b.director.event == .handoff { sawHandoff = true }
        }
        babylonCheck(sawPortalFirst && sawDeparture && sawHandoff,"Incomplete jump point camera/lifecycle")
        babylonCheck(b.carriers.isEmpty && window.node.parent == nil && window.node.isHidden,"Jump window leaked after departure")
        babylonCheck(b.scene.rootNode.childNodes.count<=nodes,"Jump window left transient nodes")
        if faction == .earth, let f = b.fighters.first(where:{$0.side == 0 && $0.active}) {
            f.position = f.entryPosition-f.entryForward*30
            b.updateFighterJumpClipping()
            babylonCheck(f.jumpClipper?.plane == nil,"Returning past a closed jump point reactivated clipping")
        }
    }
    let b = Dogfight(seed:1819,initialFactions:[.earth,.shadow],initialArrivals:false)
    b.automatic = false; b.rocks.removeAll()
    let f = b.fighters[0], target = b.fighters[6]
    for other in b.fighters where other !== f && other !== target { other.state = .destroyed; other.node.isHidden = true }
    b.activateFlight(f,position:V3(0,250,0),forward:V3(0,0,-1),speed:f.cruiseSpeed)
    b.activateFlight(target,position:V3(150,250,30),forward:V3(0,0,-1),speed:0)
    f.attackTarget = 6; f.pursuitTarget = 6; f.pursuitGeneration = target.generation; f.pursuitDeadline = 100; f.pivotCooldown = 0
    var driftSeen = false, aimedShot = false, burnSeen = false
    for _ in 0..<300 {
        b.time += 1.0/60
        let oldVelocity = f.velocity, oldPosition = f.position, oldForward = f.forward
        b.updateFlight(f,dt:1.0/60,positions:b.fighters.map(\.position),velocities:b.fighters.map(\.velocity),active:b.fighters.map(\.active))
        babylonCheck(simd_distance(oldVelocity,f.velocity)<=f.accelerationLimit/60+0.001,"Starfury pivot exceeded acceleration limit")
        babylonCheck(acos(max(-1,min(1,simd_dot(oldForward,f.forward))))<=f.turnRate/60+0.001,"Starfury pivot snapped orientation")
        babylonCheck(simd_distance(oldPosition,f.position)<215/60,"Starfury pivot teleported")
        if b.time<f.pivotUntil && simd_dot(unit(f.velocity),f.forward)<0.5 {
            driftSeen = true
            if b.fire(from:0,to:6) { aimedShot = true }
        }
        if b.time>f.pivotUntil+0.8 && b.time<f.pivotUntil+1.3 {
            burnSeen = simd_length(f.velocity)>45 && simd_dot(unit(f.velocity),f.pivotExit)>0.9
        }
        b.updateLasers(1.0/60)
    }
    babylonCheck(f.pivotCount == 1 && driftSeen && aimedShot && burnSeen,"Starfury did not drift, pivot, fire and burn along its new heading")
    // A hazard on the drift path must override a nose pointed elsewhere.
    f.pivotUntil = b.time+2; f.pivotCooldown = b.time+20
    f.forward = V3(1,0,0); f.velocity = V3(0,0,-56)
    b.rocks = [Rock(node:SCNNode(),position:f.position+V3(0,0,-65),radius:20,spin:.zero)]
    b.updateFlight(f,dt:1.0/60,positions:b.fighters.map(\.position),velocities:b.fighters.map(\.velocity),active:b.fighters.map(\.active))
    babylonCheck(f.pivotUntil<b.time,"Starfury ignored a hazard on its inertial path")
    print("PASS: Babylon jump windows precede ships, deploy six fighters, depart in one scene, hand off and clean up; Starfury bounded drift/pivot, forward firing, new-heading burn and flight-path hazard override.")
    fflush(stdout)
}

func renderBabylonReview(directory: URL) {
    try! FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
    let renderer = SCNRenderer(device:MTLCreateSystemDefaultDevice(),options:nil)
    func save(_ name: String, time: Float) {
        let image = renderer.snapshot(atTime:Double(time),with:NSSize(width:1280,height:800),antialiasingMode:.multisampling2X)
        let bitmap = NSBitmapImageRep(data:image.tiffRepresentation!)!
        try! bitmap.representation(using:.png,properties:[:])!.write(to:directory.appendingPathComponent(name+".png"))
        print("Rendered \(name)"); fflush(stdout)
    }
    for faction in [Faction.earth,.shadow] {
        let b = Dogfight(seed:1818,initialFactions:[faction,.rebel],initialArrivals:false)
        for f in b.fighters where f.side == 0 { b.destroy(f) }
        b.deployReinforcements(side:0)
        let ship = b.carriers[0]
        renderer.scene = b.scene; renderer.pointOfView = b.camera
        var captured = Set<String>()
        for _ in 0..<660 {
            for f in b.fighters { f.cooldown = 10000 }
            b.update(dt:1.0/60)
            let age = b.time-ship.start
            let beats: [(String,Float)] = [("window",0.8),("emergence",1.6),("launch-close",2.6),("squadron",4.3),("departure",ship.departureAge+0.8),("handoff",ship.departureAge+ship.departureDuration+0.8)]
            for (name,at) in beats where age>=at && captured.insert(name).inserted { save(faction.rawValue+"-"+name,time:b.time) }
            if faction == .shadow, let window = ship.jumpWindow {
                for (name,at) in [("before-emergence",Float(1.05)),("crossing",1.6)] where age>=at && captured.insert(name).inserted {
                    let position = b.camera.simdPosition, orientation = b.camera.simdOrientation
                    let right = unit(simd_cross(ship.forward,V3(0,1,0)))
                    for (view,offset) in [("side",right*2.8),("rear",-ship.forward*2.8+right*0.4)] {
                        b.camera.simdPosition = window.node.simdPosition+offset*window.radius+V3(0,window.radius*0.2,0)
                        b.camera.look(at:SCNVector3(window.node.simdPosition))
                        save("shadow-\(name)-\(view)",time:b.time)
                    }
                    b.camera.simdPosition = position; b.camera.simdOrientation = orientation
                }
            }
        }
    }
    let scene = SCNScene(); scene.background.contents = color(0.04,0.05,0.07)
    let key = SCNNode(); key.light = SCNLight(); key.light!.type = .directional; key.light!.intensity = 1700
    key.simdEulerAngles = V3(-0.6,-0.4,0); scene.rootNode.addChildNode(key)
    let fill = SCNNode(); fill.light = SCNLight(); fill.light!.type = .ambient; fill.light!.intensity = 900; scene.rootNode.addChildNode(fill)
    let camera = SCNNode(); camera.camera = SCNCamera(); camera.camera!.zFar = 3000; scene.rootNode.addChildNode(camera)
    renderer.scene = scene; renderer.pointOfView = camera
    for (name,model,scale) in [("starfury",starfury(),Float(1)),("shadow-fighter",shadowFighter(),1),("shadow-capital",shadowCapital(),25)] {
        scene.rootNode.addChildNode(model)
        for (i,p) in [V3(12,8,-18),V3(0,0,-23),V3(-14,7,17)].enumerated() {
            camera.simdPosition = p*scale; camera.look(at:SCNVector3(0,0,0))
            save(name+"-\(i+1)",time:0)
        }
        model.removeFromParentNode()
    }
}

// Render real production meshes without the gate disk, so that it cannot hide
// a failed ship shader. Check front, side and rear views at an offset, rotated
// world-space plane, including the opposite plane used for departures.
func verifyJumpClipping() {
    let renderer = SCNRenderer(device:MTLCreateSystemDefaultDevice(),options:nil)
    let scene = SCNScene(); scene.background.contents = NSColor.black
    let light = SCNNode(); light.light = SCNLight(); light.light!.type = .ambient; light.light!.intensity = 1500
    scene.rootNode.addChildNode(light)
    let camera = SCNNode(); camera.camera = SCNCamera(); camera.camera!.zNear = 0.1; camera.camera!.zFar = 1000
    scene.rootNode.addChildNode(camera)
    renderer.scene = scene; renderer.pointOfView = camera
    func visiblePixels() -> Int {
        let image = renderer.snapshot(atTime:0,with:NSSize(width:160,height:160),antialiasingMode:.none)
        let bitmap = NSBitmapImageRep(data:image.tiffRepresentation!)!
        var visible = 0
        for y in 0..<bitmap.pixelsHigh { for x in 0..<bitmap.pixelsWide {
            if let c = bitmap.colorAt(x:x,y:y)?.usingColorSpace(.deviceRGB), c.redComponent+c.greenComponent+c.blueComponent>0.035 { visible += 1 }
        } }
        return visible
    }
    let origin = V3(123,74,-211), normal = unit(V3(0.4,0.3,-0.85))
    let orientation = simd_quatf(from:V3(0,0,-1),to:normal)
    for (name,model,scale) in [("Starfury",starfury(),Float(1)),("Shadow capital",shadowCapital(),0.035)] {
        let root = SCNNode(); root.addChildNode(model); root.simdScale = V3(repeating:scale); root.simdOrientation = orientation
        scene.rootNode.addChildNode(root)
        let clipper = JumpClipper(root:root)
        babylonCheck(!clipper.materials.isEmpty,"Missing clipping materials on \(name)")
        var sawPartialHull = false
        for direction in [V3(0,0,-1),V3(1,0.1,0),V3(0,0,1)] {
            for sign: Float in [-1,1] {
                let n = normal*sign
                root.simdPosition = origin-n*18
                camera.simdPosition = root.simdPosition+orientation.act(unit(direction))*24
                camera.look(at:SCNVector3(root.simdPosition))
                clipper.clear()
                let unclipped = visiblePixels()
                babylonCheck(unclipped>80,"Render fixture cannot see \(name)")
                clipper.setPlane(origin:origin,normal:n)
                babylonCheck(visiblePixels() == 0,"\(name) visible behind jump plane from \(direction), side \(sign)")
                root.simdPosition = origin
                camera.simdPosition = origin+orientation.act(unit(direction))*24
                camera.look(at:SCNVector3(origin))
                let partial = visiblePixels()
                clipper.clear()
                let whole = visiblePixels()
                // From an end-on view the removed half may already have been
                // occluded, or all remaining faces may face away from the camera.
                // A side view must expose an actual partially visible hull.
                babylonCheck(partial<=whole,"\(name) gained pixels when clipped")
                if partial>5 && partial<whole-5 { sawPartialHull = true }
                root.simdPosition = origin+n*18
                camera.simdPosition = root.simdPosition+orientation.act(unit(direction))*24
                camera.look(at:SCNVector3(root.simdPosition))
                let normalPixels = visiblePixels()
                clipper.setPlane(origin:origin,normal:n)
                babylonCheck(visiblePixels() == normalPixels,"\(name) lost visible hull after clearing the jump plane")
            }
        }
        babylonCheck(sawPartialHull,"\(name) never rendered a partially emerged hull")
        root.removeFromParentNode()
    }
    print("PASS: rendered Starfury and Shadow hulls are invisible behind the jump plane, partially clipped at crossing, and complete after crossing, from front/side/rear on arrival and departure.")
    fflush(stdout)
}
