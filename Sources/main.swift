import AppKit
import SceneKit
import simd

// Asteroid Squadron — a self-contained, procedural, native macOS dogfight.
typealias V3 = SIMD3<Float>
let tau = Float.pi * 2
func mix(_ a: V3, _ b: V3, _ t: Float) -> V3 { a + (b - a) * t }
func unit(_ v: V3) -> V3 { simd_length_squared(v) > 0.0001 ? simd_normalize(v) : V3(0, 0, -1) }
func color(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> NSColor {
    NSColor(calibratedRed: r, green: g, blue: b, alpha: a)
}
let cyan = color(0.38, 0.89, 0.94)
let orange = color(1, 0.43, 0.19)

struct Random {
    var state: UInt64 = 0x5EED_CAFE
    mutating func next() -> Float {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return Float((state >> 40) & 0xFFFFFF) / Float(0xFFFFFF)
    }
    mutating func range(_ lo: Float, _ hi: Float) -> Float { lo + (hi - lo) * next() }
    mutating func vector(_ radius: Float) -> V3 {
        V3(range(-radius, radius), range(-radius, radius), range(-radius, radius))
    }
}

func material(_ base: NSColor, emission: NSColor? = nil, metal: CGFloat = 0) -> SCNMaterial {
    let m = SCNMaterial()
    m.diffuse.contents = base
    m.lightingModel = .physicallyBased
    m.roughness.contents = 0.65
    m.metalness.contents = metal
    if let emission { m.emission.contents = emission }
    return m
}
func node(_ geometry: SCNGeometry, _ mat: SCNMaterial, _ position: V3 = .zero) -> SCNNode {
    geometry.materials = [mat]
    let n = SCNNode(geometry: geometry)
    n.simdPosition = position
    return n
}
func box(_ size: V3, _ mat: SCNMaterial, _ p: V3 = .zero, chamfer: CGFloat = 0) -> SCNNode {
    node(SCNBox(width: CGFloat(size.x), height: CGFloat(size.y), length: CGFloat(size.z), chamferRadius: chamfer), mat, p)
}
func cylinder(_ radius: CGFloat, _ length: CGFloat, _ mat: SCNMaterial, _ p: V3 = .zero) -> SCNNode {
    let g = SCNCylinder(radius: radius, height: length)
    g.radialSegmentCount = 10
    let n = node(g, mat, p)
    n.eulerAngles.x = .pi / 2
    return n
}
func segment(_ from: V3, _ to: V3, radius: CGFloat, mat: SCNMaterial) -> SCNNode {
    let n = cylinder(radius, CGFloat(simd_distance(from, to)), mat)
    // Cylinder's own Y axis is its length axis.
    n.simdOrientation = simd_quatf(from: V3(0, 1, 0), to: unit(to - from))
    n.simdPosition = (from + to) / 2
    return n
}

enum Faction { case rebel, empire }

func xWing() -> SCNNode {
    let root = SCNNode()
    let hull = material(color(0.68, 0.72, 0.71), metal: 0.55)
    let pale = material(color(0.84, 0.85, 0.78), metal: 0.3)
    let dark = material(color(0.055, 0.075, 0.085), metal: 0.7)
    let red = material(color(0.55, 0.065, 0.025), metal: 0.2)
    let glass = material(color(0.035, 0.12, 0.17), emission: color(0.015, 0.05, 0.075), metal: 0.85)
    let glow = material(color(1, 0.22, 0.36), emission: color(2.5, 0.27, 0.55))
    root.addChildNode(box(V3(1.35, 0.9, 4.3), hull, V3(0, 0, -0.2), chamfer: 0.3))
    let nose = SCNCone(topRadius: 0.12, bottomRadius: 0.68, height: 4.7)
    nose.radialSegmentCount = 4
    let n = node(nose, pale, V3(0, -0.02, -4.15))
    n.eulerAngles = SCNVector3(-Float.pi / 2, Float.pi / 4, 0)
    root.addChildNode(n)
    root.addChildNode(box(V3(0.075, 0.075, 4.2), red, V3(0, 0.52, -3.45)))
    let cockpit = box(V3(0.9, 0.58, 1.65), glass, V3(0, 0.62, -0.85), chamfer: 0.19)
    cockpit.eulerAngles.x = -0.1
    root.addChildNode(cockpit)
    root.addChildNode(box(V3(0.95, 0.09, 0.085), pale, V3(0, 0.94, -0.5)))
    root.addChildNode(box(V3(1.45, 0.12, 2), red, V3(0, -0.48, 0.5)))
    // Astromech dome behind the cockpit.
    root.addChildNode(cylinder(0.31, 0.45, pale, V3(0, 0.65, 0.55)))
    root.addChildNode(node(SCNSphere(radius: 0.31), material(color(0.12, 0.3, 0.65), metal: 0.8), V3(0, 0.88, 0.55)))
    for sx: Float in [-1, 1] {
        for sy: Float in [-1, 1] {
            let foil = SCNNode()
            foil.simdEulerAngles.z = sx * sy * 0.31
            foil.position = SCNVector3(sx * 0.4, sy * 0.18, 0.45)
            foil.addChildNode(box(V3(4.15, 0.14, 1.7), pale, V3(sx * 2.15, 0, 0)))
            foil.addChildNode(box(V3(1.1, 0.155, 1.72), red, V3(sx * 2.85, 0, 0)))
            foil.addChildNode(box(V3(0.18, 0.19, 1.72), hull, V3(sx * 3.5, 0, 0)))
            foil.addChildNode(cylinder(0.13, 4.6, dark, V3(sx * 4.2, 0, -0.9)))
            foil.addChildNode(cylinder(0.08, 1.5, pale, V3(sx * 4.2, 0, -3.3)))
            foil.addChildNode(cylinder(0.43, 2.7, hull, V3(sx * 1.15, 0, 0.6)))
            foil.addChildNode(cylinder(0.34, 0.2, dark, V3(sx * 1.15, 0, 2.02)))
            foil.addChildNode(cylinder(0.245, 0.23, glow, V3(sx * 1.15, 0, 2.14)))
            let flame = node(SCNSphere(radius: 1), glow, V3(sx * 1.15, 0, 2.53))
            flame.simdScale = V3(0.19, 0.19, 0.75)
            foil.addChildNode(flame)
            root.addChildNode(foil)
        }
    }
    return root
}

func tieFighter() -> SCNNode {
    let root = SCNNode()
    let frame = material(color(0.32, 0.37, 0.4), metal: 0.7)
    let edges = material(color(0.48, 0.53, 0.54), metal: 0.7)
    let panel = material(color(0.023, 0.035, 0.052), metal: 0.3)
    let glass = material(color(0.025, 0.075, 0.095), emission: color(0.015, 0.035, 0.045), metal: 0.9)
    let core = SCNSphere(radius: 1.13)
    core.segmentCount = 18
    root.addChildNode(node(core, frame))
    root.addChildNode(cylinder(0.78, 0.16, edges, V3(0, 0, -0.91)))
    root.addChildNode(cylinder(0.65, 0.18, glass, V3(0, 0, -1.02)))
    for i in 0..<8 {
        let a = Float(i) * tau / 8
        root.addChildNode(segment(V3(0, 0, -1.13), V3(sin(a) * 0.65, cos(a) * 0.65, -1.13), radius: 0.025, mat: frame))
    }
    root.addChildNode(cylinder(0.22, 0.2, frame, V3(0, 0, -1.15)))
    for s: Float in [-1, 1] {
        root.addChildNode(box(V3(2.5, 0.4, 0.45), frame, V3(s * 1.75, 0, 0)))
        let p: [V3] = [V3(0,-3.7,-1.8), V3(0,-2.6,2.3), V3(0,2.6,2.3), V3(0,3.7,-1.8), V3(0,2.5,-3), V3(0,-2.5,-3)]
        let vertices = p.map { SCNVector3($0 + V3(s * 3.1, 0, 0)) }
        let indices: [Int32] = [0,1,2, 0,2,3, 0,3,4, 0,4,5]
        let geo = SCNGeometry(sources: [SCNGeometrySource(vertices: vertices)], elements: [SCNGeometryElement(indices: indices, primitiveType: .triangles)])
        let pm = panel.copy() as! SCNMaterial
        pm.isDoubleSided = true
        root.addChildNode(node(geo, pm))
        for i in 0..<6 {
            let a = p[i] + V3(s * 3.1, 0, 0)
            let b = p[(i+1)%6] + V3(s * 3.1, 0, 0)
            root.addChildNode(segment(a, b, radius: 0.1, mat: edges))
            root.addChildNode(segment(V3(s * 3.1, 0, 0), a, radius: 0.045, mat: frame))
        }
        for stripe in -6...6 {
            let y = Float(stripe) * 0.38
            root.addChildNode(segment(V3(s * 3.12, y, -2.6), V3(s * 3.12, y, 2.15), radius: 0.012, mat: frame))
        }
        let glow = material(color(0.3, 0.8, 1), emission: color(0.3, 0.8, 1.3))
        root.addChildNode(cylinder(0.14, 0.15, glow, V3(s * 0.5, -0.25, 1.05)))
    }
    return root
}

struct Rock {
    let node: SCNNode
    let position: V3
    let radius: Float
    let spin: V3
}
final class Fighter {
    let node: SCNNode
    let faction: Faction
    let pair: Int
    let trailing: Bool
    var position = V3.zero
    var forward = V3(0, 0, -1)
    var cooldown: Float
    var respawn: Float = 0
    var hitPoints = 4
    init(faction: Faction, pair: Int, trailing: Bool, cooldown: Float) {
        self.faction = faction; self.pair = pair; self.trailing = trailing; self.cooldown = cooldown
        node = faction == .rebel ? xWing() : tieFighter()
    }
}
struct Laser {
    let node: SCNNode
    var position: V3
    let velocity: V3
    var life: Float
    let target: Int
    let hits: Bool
    let faction: Faction
}
struct Spark {
    let node: SCNNode
    var position: V3
    let velocity: V3
    var life: Float
    let duration: Float
    let scale: Float
}

func rockGeometry(seed: UInt64) -> SCNGeometry {
    var rng = Random(state: seed)
    let rings = 9, slices = 14
    let phase = rng.range(0,tau)
    var vertices: [SCNVector3] = []
    for y in 0...rings {
        let phi = Float(y) / Float(rings) * .pi
        for x in 0...slices {
            let theta = Float(x % slices) / Float(slices) * tau
            let r: Float = 1 + 0.11*sin(theta*3+phase)*sin(phi)*sin(phi) + 0.08*cos(phi*4+phase) + 0.055*sin(theta*5-phi*3+phase)*sin(phi)
            vertices.append(SCNVector3(sin(phi) * cos(theta) * r, cos(phi) * r, sin(phi) * sin(theta) * r))
        }
    }
    var indices: [Int32] = []
    for y in 0..<rings {
        for x in 0..<slices {
            let a = Int32(y * (slices+1) + x), b = a + Int32(slices+1)
            indices += [a,a+1,b, a+1,b+1,b]
        }
    }
    // Per-face normals keep a chipped, faceted silhouette.
    var flat: [SCNVector3] = [], normals: [SCNVector3] = []
    for i in stride(from: 0, to: indices.count, by: 3) {
        let a = V3(vertices[Int(indices[i])]), b = V3(vertices[Int(indices[i+1])]), c = V3(vertices[Int(indices[i+2])])
        let normal = unit(simd_cross(b-a, c-a))
        flat += [SCNVector3(a), SCNVector3(b), SCNVector3(c)]
        normals += [SCNVector3(normal), SCNVector3(normal), SCNVector3(normal)]
    }
    let uv = flat.map { v -> CGPoint in
        let p = unit(V3(v)); return CGPoint(x: CGFloat(atan2(p.z,p.x) / tau + 0.5), y: CGFloat(acos(p.y) / .pi))
    }
    return SCNGeometry(sources: [SCNGeometrySource(vertices: flat), SCNGeometrySource(normals: normals), SCNGeometrySource(textureCoordinates: uv)], elements: [SCNGeometryElement(indices: (0..<Int32(flat.count)).map{$0}, primitiveType: .triangles)])
}

func stoneTexture() -> NSImage {
    let size = 256
    let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: size*4, bitsPerPixel: 32)!
    var rng = Random(state: 0xA57E201D)
    let data = bitmap.bitmapData!
    for y in 0..<size {
        for x in 0..<size {
            let broad = sin(Float(x)*0.11+cos(Float(y)*0.045)*3) * 0.07 + cos(Float(y)*0.15+Float(x)*0.05)*0.055
            let b = rng.range(0.36,0.65) + broad
            let i = (y*size+x)*4
            data[i] = UInt8(max(0,min(255,b*220)))
            data[i+1] = UInt8(max(0,min(255,b*207)))
            data[i+2] = UInt8(max(0,min(255,b*193)))
            data[i+3] = 255
        }
    }
    let image = NSImage(size: NSSize(width:size,height:size)); image.addRepresentation(bitmap)
    return image
}

final class Dogfight {
    let scene = SCNScene()
    let camera = SCNNode()
    var fighters: [Fighter] = []
    var rocks: [Rock] = []
    var lasers: [Laser] = []
    var sparks: [Spark] = []
    var rng = Random()
    var time: Float = 0
    var cameraAge: Float = 0
    var cameraIndex = 0
    var automatic = true
    var paused = false
    var cameraPosition = V3(0,20,100)
    var cameraLook = V3.zero
    var cut = true
    var cameraChanged: (() -> Void)?
    var destroyed = 0
    var shots = 0
    let cameraNames = ["RED LEADER", "IMPERIAL PURSUIT", "THE ASTEROID BELT", "WINGMAN", "INTERCEPT VECTOR", "IN THE CROSSFIRE"]
    let cameraDetails = ["X-WING CHASE CAM", "TIE FIGHTER CHASE CAM", "WIDE ORBITAL CAMERA", "SQUADRON TRACKING CAM", "FORWARD PURSUIT CAM", "BATTLEFIELD TRACKING CAM"]
    let shotMaterialRed = material(color(1,0.13,0.045), emission: color(3,0.12,0.025))
    let shotMaterialGreen = material(color(0.2,1,0.2), emission: color(0.15,3,0.15))
    let sparkMaterials = [material(color(1,0.7,0.2), emission: color(3,1.3,0.2)), material(color(1,0.25,0.06), emission: color(2,0.3,0.03)), material(color(0.6,0.6,0.6), metal: 0.8)]

    init() {
        scene.background.contents = color(0.003,0.007,0.016)
        scene.fogColor = color(0.009,0.017,0.03)
        scene.fogStartDistance = 1000; scene.fogEndDistance = 3300
        scene.lightingEnvironment.contents = color(0.18,0.22,0.28)
        scene.lightingEnvironment.intensity = 0.65
        camera.camera = SCNCamera()
        camera.camera!.zNear = 0.3
        camera.camera!.zFar = 12000
        camera.camera!.fieldOfView = 58
        camera.camera!.wantsHDR = true
        camera.camera!.bloomIntensity = 0.7
        camera.camera!.bloomThreshold = 1.1
        camera.camera!.bloomBlurRadius = 7
        camera.camera!.vignettingIntensity = 0.65
        camera.camera!.vignettingPower = 1.2
        camera.camera!.exposureOffset = 0.2
        camera.camera!.wantsExposureAdaptation = false
        scene.rootNode.addChildNode(camera)
        let sun = SCNNode(); sun.light = SCNLight(); sun.light!.type = .directional
        sun.light!.color = color(1,0.79,0.59); sun.light!.intensity = 1650
        sun.eulerAngles = SCNVector3(-0.6,-0.7,0.1)
        scene.rootNode.addChildNode(sun)
        let fill = SCNNode(); fill.light = SCNLight(); fill.light!.type = .directional
        fill.light!.color = color(0.3,0.6,1); fill.light!.intensity = 850
        fill.eulerAngles = SCNVector3(0.5,2.0,0)
        scene.rootNode.addChildNode(fill)
        let ambient = SCNNode(); ambient.light = SCNLight(); ambient.light!.type = .ambient
        ambient.light!.color = color(0.35,0.43,0.55); ambient.light!.intensity = 330
        scene.rootNode.addChildNode(ambient)
        makeStars()
        makeRocks()
        makePlanet()
        for pair in 0..<6 {
            let leader: Faction = pair % 2 == 0 ? .rebel : .empire
            for trailing in [false, true] {
                let faction = trailing ? (leader == .rebel ? Faction.empire : Faction.rebel) : leader
                let f = Fighter(faction:faction,pair:pair,trailing:trailing,cooldown:rng.range(0.2,2.0))
                scene.rootNode.addChildNode(f.node)
                fighters.append(f)
            }
        }
        update(dt: 0)
    }

    func makeStars() {
        var vertices: [SCNVector3] = []
        for _ in 0..<4200 {
            let p = unit(rng.vector(1)) * rng.range(1800,2600)
            vertices.append(SCNVector3(p))
        }
        let g = SCNGeometry(sources: [SCNGeometrySource(vertices: vertices)], elements: [SCNGeometryElement(indices: (0..<Int32(vertices.count)).map{$0}, primitiveType: .point)])
        g.elements[0].pointSize = 1.8; g.elements[0].minimumPointScreenSpaceRadius = 0.65; g.elements[0].maximumPointScreenSpaceRadius = 1.6
        let m = material(color(0.64,0.76,0.85), emission: color(0.64,0.76,0.85))
        m.lightingModel = .constant; m.readsFromDepthBuffer = false; m.writesToDepthBuffer = false
        let stars = node(g,m); stars.renderingOrder = -10
        scene.rootNode.addChildNode(stars)
        // Faint dust clouds give the black sky depth without a downloaded skybox.
        for i in 0..<20 {
            let p = V3(Float(i-10)*280, sin(Float(i)*0.35)*240+700, -3500)
            let cloud = SCNPlane(width: 1800, height: 1000)
            let cm = SCNMaterial(); cm.lightingModel = .constant
            cm.diffuse.contents = nebulaTexture()
            cm.blendMode = .add; cm.writesToDepthBuffer = false; cm.isDoubleSided = true
            let n = node(cloud,cm,p); n.simdEulerAngles.z = Float(i)*0.5; n.renderingOrder = -20
            scene.rootNode.addChildNode(n)
        }
    }
    func nebulaTexture() -> NSImage {
        let size = 128
        let bitmap = NSBitmapImageRep(bitmapDataPlanes:nil,pixelsWide:size,pixelsHigh:size,bitsPerSample:8,samplesPerPixel:4,hasAlpha:true,isPlanar:false,colorSpaceName:.deviceRGB,bytesPerRow:size*4,bitsPerPixel:32)!
        let data = bitmap.bitmapData!
        for y in 0..<size {
            for x in 0..<size {
                let dx = Float(x-64)/64, dy = Float(y-64)/64
                let intensity = pow(max(0,1-dx*dx-dy*dy),3)
                let i = (y*size+x)*4
                data[i] = 12; data[i+1] = 29; data[i+2] = 49
                data[i+3] = UInt8(intensity*22)
            }
        }
        let image = NSImage(size:NSSize(width:size,height:size)); image.addRepresentation(bitmap)
        return image
    }
    func makeRocks() {
        let texture = stoneTexture()
        var geometries: [SCNGeometry] = []
        for i in 0..<12 {
            let g = rockGeometry(seed: UInt64(i+1)*234879)
            let m = material(color(0.47,0.43,0.38),metal:0.13)
            m.diffuse.contents = texture
            m.roughness.contents = 0.94
            g.materials = [m]; geometries.append(g)
        }
        for i in 0..<245 {
            var p: V3
            var r: Float
            if i < 75 {
                let a = rng.range(0,tau), rad = rng.range(65,280)
                p = V3(sin(a)*rad,rng.range(-115,115),cos(a)*rad)
                r = rng.range(2.5,11)
            } else {
                p = rng.vector(850)
                r = rng.range(5,42)
            }
            // A few hero asteroids make close passes easy to read.
            if i == 0 { p = V3(0,-46,0); r = 29 }
            if i == 1 { p = V3(155,18,-100); r = 24 }
            let n = SCNNode(geometry:geometries[i%geometries.count])
            n.simdPosition = p
            n.simdScale = V3(r*rng.range(0.8,1.35),r*rng.range(0.7,1.2),r)
            n.simdEulerAngles = rng.vector(.pi)
            scene.rootNode.addChildNode(n)
            rocks.append(Rock(node:n,position:p,radius:r*1.5,spin:rng.vector(0.035)))
        }
    }
    func makePlanet() {
        let g = SCNSphere(radius: 440); g.segmentCount = 72
        let m = material(color(0.045,0.11,0.16), metal:0.15)
        m.roughness.contents = 0.9
        let n = node(g,m,V3(-1050,350,-2400))
        scene.rootNode.addChildNode(n)
        let atmosphere = SCNSphere(radius:450); atmosphere.segmentCount = 72
        let am = SCNMaterial(); am.diffuse.contents = color(0.08,0.35,0.5,0.06)
        am.emission.contents = color(0.04,0.15,0.22,0.05)
        am.transparency = 0.12; am.isDoubleSided = false; am.writesToDepthBuffer = false
        n.addChildNode(node(atmosphere,am))
    }

    func path(_ f: Fighter, _ t: Float) -> V3 {
        let phase = Float(f.pair) * tau / 6
        let a = t * 0.185 + phase - (f.trailing ? 0.14 : 0)
        let radius = 110 + Float(f.pair % 3) * 22
        var p = V3(sin(a)*radius + sin(a*2.0+phase)*24,
                   sin(a*2.0+phase)*30 + cos(a*3.0)*13,
                   cos(a)*radius*0.8 + sin(a*3.0+phase)*17)
        // Smoothly bend flight corridors around nearby asteroid hulls.
        for rock in rocks.prefix(75) {
            let delta = p-rock.position
            let clearance = rock.radius + 16
            let distance = simd_length(delta)
            if distance < clearance {
                let push = (clearance-distance) / clearance
                p += unit(delta) * (push*push*clearance*0.85)
            }
        }
        return p
    }

    func update(dt: Float) {
        guard !paused else { return }
        time += dt; cameraAge += dt
        if automatic && cameraAge > 14 { nextCamera() }
        for rock in rocks { rock.node.simdEulerAngles += rock.spin * dt }
        for f in fighters {
            f.position = path(f,time)
            f.forward = unit(path(f,time+0.07)-f.position)
            f.node.simdPosition = f.position
            let up = V3(sin(time*0.8+Float(f.pair))*0.22,1,cos(time*0.7+Float(f.pair))*0.12)
            f.node.look(at:SCNVector3(f.position+f.forward*20), up:SCNVector3(up), localFront:SCNVector3(0,0,-1))
            if f.respawn > 0 {
                f.respawn -= dt
                if f.respawn <= 0 { f.node.isHidden = false; f.hitPoints = 4 }
            }
            f.cooldown -= dt
        }
        for i in 0..<fighters.count {
            let f = fighters[i]
            guard f.cooldown <= 0, f.respawn <= 0 else { continue }
            let target = i ^ 1
            guard fighters[target].respawn <= 0 else { continue }
            if f.trailing {
                fire(from:i,to:target)
                f.cooldown = rng.range(0.28,0.75)
            } else if rng.next() < 0.025 {
                // Leaders occasionally fire a long burst into the field.
                fire(from:i,to:(i+3)%fighters.count,aimed:false)
                f.cooldown = rng.range(0.8,1.8)
            }
        }
        updateLasers(dt)
        updateSparks(dt)
        updateCamera(dt)
    }
    func fire(from: Int, to: Int, aimed: Bool = true) {
        let f = fighters[from], target = fighters[to]
        let predicted = path(target,time+0.1)
        let aim = aimed ? unit(predicted-f.position) : f.forward
        let hit = aimed && rng.next() < 0.2 && cameraAge > 3
        let right = unit(simd_cross(f.forward,V3(0,1,0)))
        for s: Float in [-1,1] {
            let p = f.position+f.forward*4+right*s*(f.faction == .rebel ? 3.7 : 0.5)
            let mat = f.faction == .rebel ? shotMaterialRed : shotMaterialGreen
            let n = box(V3(0.12,0.12,4.2),mat,p)
            let spread = hit ? V3.zero : rng.vector(0.08)
            let direction = unit(aim+spread)
            n.simdOrientation = simd_quatf(from:V3(0,0,-1),to:direction)
            scene.rootNode.addChildNode(n)
            lasers.append(Laser(node:n,position:p,velocity:direction*340,life:1.5,target:to,hits:hit,faction:f.faction))
        }
        shots += 2
    }
    func updateLasers(_ dt: Float) {
        for i in lasers.indices.reversed() {
            lasers[i].life -= dt
            let old = lasers[i].position
            lasers[i].position += lasers[i].velocity*dt
            let p = lasers[i].position
            lasers[i].node.simdPosition = p
            let target = fighters[lasers[i].target]
            let travel = p-old
            let factor = max(0,min(1,simd_dot(target.position-old,travel)/max(0.001,simd_length_squared(travel))))
            let distance = simd_distance(old+travel*factor,target.position)
            var remove = lasers[i].life <= 0
            if target.respawn <= 0 && lasers[i].hits && distance < 6 {
                target.hitPoints -= 1
                burst(at:target.position,count:9,big:false)
                remove = true
                if target.hitPoints <= 0 {
                    // Preserve a stable camera subject; other ships regenerate offscreen.
                    if target !== cameraSubject() {
                        burst(at:target.position,count:55,big:true)
                        target.respawn = 4.5; target.node.isHidden = true; destroyed += 1
                    }
                }
            }
            if remove { lasers[i].node.removeFromParentNode(); lasers.remove(at:i) }
        }
    }
    func burst(at p: V3, count: Int, big: Bool) {
        for i in 0..<count {
            let duration = rng.range(0.3,big ? 1.8 : 0.6)
            let scale = rng.range(0.1,big ? 1.6 : 0.5)
            let g: SCNGeometry = i%3 == 0 ? SCNBox(width:1,height:0.5,length:1.4,chamferRadius:0) : SCNSphere(radius:0.6)
            if let s = g as? SCNSphere { s.segmentCount = 6 }
            let n = node(g,sparkMaterials[i%3],p)
            n.simdScale = V3(repeating:scale)
            n.simdEulerAngles = rng.vector(.pi)
            scene.rootNode.addChildNode(n)
            sparks.append(Spark(node:n,position:p,velocity:rng.vector(big ? 24 : 10),life:duration,duration:duration,scale:scale))
        }
        if big {
            let light = SCNNode(); light.light = SCNLight(); light.light!.type = .omni
            light.light!.color = orange; light.light!.intensity = 2500; light.light!.attenuationEndDistance = 100
            light.simdPosition = p; scene.rootNode.addChildNode(light)
            light.runAction(.sequence([.wait(duration:0.15),.fadeOut(duration:0.4),.removeFromParentNode()]))
        }
    }
    func updateSparks(_ dt: Float) {
        for i in sparks.indices.reversed() {
            sparks[i].life -= dt; sparks[i].position += sparks[i].velocity*dt
            sparks[i].node.simdPosition = sparks[i].position
            let t = max(0,sparks[i].life/sparks[i].duration)
            sparks[i].node.opacity = CGFloat(t)
            sparks[i].node.simdScale = V3(repeating:sparks[i].scale*(0.4+t))
            if sparks[i].life <= 0 { sparks[i].node.removeFromParentNode(); sparks.remove(at:i) }
        }
    }
    func cameraSubject() -> Fighter? {
        switch cameraIndex {
        case 0: return fighters[0]
        case 1: return fighters[1]
        case 3: return fighters[4]
        case 4: return fighters[7]
        case 5: return fighters[8]
        default: return nil
        }
    }
    func nextCamera() {
        cameraIndex = (cameraIndex+1)%cameraNames.count
        cameraAge = 0; cut = true
        if let subject = cameraSubject(), subject.respawn > 0 {
            subject.respawn = 0; subject.hitPoints = 4; subject.node.isHidden = false
        }
        cameraChanged?()
    }
    func updateCamera(_ dt: Float) {
        var desired: V3, look: V3
        let f = cameraSubject() ?? fighters[0]
        let right = unit(simd_cross(f.forward,V3(0,1,0)))
        switch cameraIndex {
        case 0:
            desired = f.position-f.forward*25+V3(0,9,0)+right*12
            look = f.position+f.forward*28
        case 1:
            desired = f.position-f.forward*28+V3(0,6,0)-right*7
            look = fighters[0].position+f.forward*15
        case 2:
            let a = time*0.035
            desired = V3(sin(a)*310,145+sin(a*2)*35,cos(a)*310)
            look = V3(0,-2,0)
        case 3:
            desired = f.position+right*23-f.forward*9+V3(0,4,0)
            look = f.position+f.forward*18
        case 4:
            desired = f.position+f.forward*24+right*10+V3(0,5,0)
            look = f.position-f.forward*25
        default:
            desired = f.position-f.forward*65+right*35+V3(0,30,0)
            look = mix(f.position,fighters[9].position,0.3)
        }
        // Keep camera bodies outside asteroid surfaces too.
        for rock in rocks {
            let delta = desired-rock.position, clearance = rock.radius+6
            if simd_length(delta)<clearance { desired = rock.position+unit(delta)*clearance }
        }
        let smoothing: Float = cut ? 1 : 1-exp(-dt*4)
        cameraPosition = mix(cameraPosition,desired,smoothing)
        cameraLook = mix(cameraLook,look,cut ? 1 : 1-exp(-dt*5))
        camera.simdPosition = cameraPosition
        let roll = cameraIndex == 2 ? Float(0) : sin(time*0.3)*0.045
        camera.look(at:SCNVector3(cameraLook),up:SCNVector3(roll,1,0),localFront:SCNVector3(0,0,-1))
        camera.camera!.fieldOfView = cameraIndex == 2 ? 65 : 58
        cut = false
    }
}

final class KeepAwake {
    private var process: Process?
    var enabled: Bool { process?.isRunning ?? false }
    @discardableResult func start() -> Bool {
        guard !enabled else { return true }
        let p = Process()
        p.executableURL = URL(fileURLWithPath:"/usr/bin/caffeinate")
        p.arguments = ["-d", "-i", "-w", String(ProcessInfo.processInfo.processIdentifier)]
        p.standardOutput = FileHandle.nullDevice; p.standardError = FileHandle.nullDevice
        do { try p.run(); process = p; return true }
        catch { NSLog("Could not start caffeinate: %@",error.localizedDescription); return false }
    }
    func stop() { if let p = process, p.isRunning { p.terminate() }; process = nil }
    deinit { stop() }
}

func label(_ text: String, size: CGFloat, weight: NSFont.Weight = .regular, color c: NSColor = .white, mono: Bool = false) -> NSTextField {
    let l = NSTextField(labelWithString:text)
    l.font = mono ? .monospacedSystemFont(ofSize:size,weight:weight) : .systemFont(ofSize:size,weight:weight)
    l.textColor = c; l.lineBreakMode = .byClipping
    return l
}

final class Overlay: NSView {
    override var isOpaque: Bool { false }
    override func hitTest(_ point: NSPoint) -> NSView? {
        let result = super.hitTest(point)
        return result === self ? nil : result
    }
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        let top = NSRect(x:0,y:bounds.height-180,width:bounds.width,height:180)
        NSGradient(starting:color(0.01,0.025,0.045,0),ending:color(0.01,0.025,0.045,0.9))!.draw(in:top,angle:90)
        NSGradient(starting:color(0.005,0.015,0.025,0.94),ending:color(0.005,0.015,0.025,0))!.draw(in:NSRect(x:0,y:0,width:bounds.width,height:190),angle:90)
        color(0.5,0.8,0.85,0.2).setStroke()
        let line = NSBezierPath(); line.lineWidth = 0.5
        line.move(to:NSPoint(x:32,y:94)); line.line(to:NSPoint(x:bounds.width-32,y:94)); line.stroke()
        // Delicate targeting marks keep the cinema feel without a game HUD.
        color(0.6,0.86,0.9,0.22).setStroke()
        for x: CGFloat in [24,bounds.width-24] {
            let path = NSBezierPath(); path.lineWidth = 1
            let direction: CGFloat = x < bounds.width/2 ? 1 : -1
            path.move(to:NSPoint(x:x,y:bounds.height/2-16)); path.line(to:NSPoint(x:x,y:bounds.height/2+16))
            path.move(to:NSPoint(x:x,y:bounds.height/2)); path.line(to:NSPoint(x:x+8*direction,y:bounds.height/2)); path.stroke()
        }
    }
}

final class FlightView: SCNView {
    var keyHandler: ((String)->Void)?
    var activity: (()->Void)?
    override var acceptsFirstResponder: Bool { true }
    override func keyDown(with event: NSEvent) {
        if let key = event.charactersIgnoringModifiers?.lowercased() { keyHandler?(key); activity?() }
    }
    override func mouseMoved(with event: NSEvent) { activity?() }
    override func mouseDown(with event: NSEvent) { activity?() }
}

final class App: NSObject, NSApplicationDelegate, NSWindowDelegate {
    var window: NSWindow!
    var view: FlightView!
    var overlay: Overlay!
    var battle: Dogfight!
    let awake = KeepAwake()
    var timer: Timer?
    var lastTime = ProcessInfo.processInfo.systemUptime
    var lastActivity = ProcessInfo.processInfo.systemUptime
    var lastHUD: TimeInterval = 0
    var startTime = ProcessInfo.processInfo.systemUptime
    var cameraTitle: NSTextField!
    var cameraDetail: NSTextField!
    var status: NSTextField!
    var telemetry: NSTextField!
    var hint: NSTextField!
    var autoButton: NSButton!
    var pauseButton: NSButton!
    var awakeItem: NSMenuItem!
    var autoItem: NSMenuItem!
    var pauseItem: NSMenuItem!
    var hudHidden = false
    var highQuality = false
    var activityToken: NSObjectProtocol?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.applicationIconImage = appIcon()
        buildMenu()
        battle = Dogfight()
        let screen = NSScreen.main?.visibleFrame ?? NSRect(x:0,y:0,width:1440,height:900)
        let width = min(1440,screen.width-80), height = min(900,screen.height-80)
        window = NSWindow(contentRect:NSRect(x:0,y:0,width:width,height:height),styleMask:[.titled,.closable,.miniaturizable,.resizable,.fullSizeContentView],backing:.buffered,defer:false)
        window.title = "Asteroid Squadron"
        window.titleVisibility = .hidden; window.titlebarAppearsTransparent = true
        window.backgroundColor = .black; window.isMovableByWindowBackground = true
        window.minSize = NSSize(width:840,height:540)
        window.collectionBehavior = [.fullScreenPrimary]
        window.delegate = self; window.acceptsMouseMovedEvents = true
        window.setFrameAutosaveName("AsteroidSquadronWindow")
        if !window.setFrameUsingName("AsteroidSquadronWindow") { window.center() }
        view = FlightView(frame:window.contentView!.bounds)
        view.autoresizingMask = [.width,.height]
        view.scene = battle.scene; view.pointOfView = battle.camera
        view.backgroundColor = .black
        view.antialiasingMode = .multisampling2X
        view.preferredFramesPerSecond = 30
        view.isPlaying = true; view.rendersContinuously = true
        view.allowsCameraControl = false
        view.keyHandler = { [weak self] key in self?.handleKey(key) }
        view.activity = { [weak self] in self?.showControls() }
        window.contentView = view
        buildHUD()
        battle.cameraChanged = { [weak self] in self?.updateCameraHUD() }
        updateCameraHUD()
        _ = awake.start(); updateStatus()
        // Protect timers from App Nap while this explicitly requested agent display runs.
        // caffeinate owns sleep prevention; this activity only prevents App Nap.
        activityToken = ProcessInfo.processInfo.beginActivity(options:.userInitiatedAllowingIdleSystemSleep,reason:"Render the active dogfight display")
        startTimer()
        window.makeKeyAndOrderFront(nil); window.makeFirstResponder(view)
        NSApp.activate(ignoringOtherApps:true)
        if CommandLine.arguments.contains("--fullscreen") { window.toggleFullScreen(nil) }
        if CommandLine.arguments.contains("--smoke-test") {
            DispatchQueue.main.asyncAfter(deadline:.now()+3) { [weak self] in self?.smokeTest() }
        }
    }
    func buildMenu() {
        let bar = NSMenu()
        let appItem = NSMenuItem(); bar.addItem(appItem)
        let menu = NSMenu()
        menu.addItem(withTitle:"About Asteroid Squadron",action:#selector(about),keyEquivalent:"")
        menu.addItem(.separator())
        awakeItem = menu.addItem(withTitle:"Keep Computer & Display Awake",action:#selector(toggleAwake),keyEquivalent:"k")
        menu.addItem(.separator())
        menu.addItem(withTitle:"Hide Asteroid Squadron",action:#selector(NSApplication.hide(_:)),keyEquivalent:"h")
        menu.addItem(withTitle:"Quit Asteroid Squadron",action:#selector(NSApplication.terminate(_:)),keyEquivalent:"q")
        appItem.submenu = menu
        let viewItem = NSMenuItem(); bar.addItem(viewItem)
        let menuView = NSMenu(title:"Flight")
        menuView.addItem(withTitle:"Next Camera",action:#selector(nextCamera),keyEquivalent:"n")
        autoItem = menuView.addItem(withTitle:"Automatic Camera Cuts",action:#selector(toggleAutomatic),keyEquivalent:"a")
        pauseItem = menuView.addItem(withTitle:"Pause Flight",action:#selector(togglePause),keyEquivalent:"p")
        menuView.addItem(withTitle:"Show / Hide Overlay",action:#selector(toggleHUD),keyEquivalent:"u")
        menuView.addItem(withTitle:"Toggle Full Screen",action:#selector(fullscreen),keyEquivalent:"f")
        menuView.addItem(withTitle:"Toggle 30 / 60 FPS",action:#selector(toggleQuality),keyEquivalent:"j")
        viewItem.submenu = menuView
        for item in menu.items+menuView.items { if item.action != nil && item.action != #selector(NSApplication.hide(_:)) && item.action != #selector(NSApplication.terminate(_:)) { item.target = self } }
        NSApp.mainMenu = bar
    }
    func appIcon() -> NSImage {
        NSImage(size:NSSize(width:256,height:256),flipped:false) { rect in
            let background = NSBezierPath(roundedRect:rect.insetBy(dx:10,dy:10),xRadius:52,yRadius:52)
            NSGradient(starting:color(0.05,0.14,0.2),ending:color(0.005,0.02,0.04))!.draw(in:background,angle:-60)
            color(0.3,0.8,0.88,0.25).setStroke(); background.lineWidth = 2; background.stroke()
            color(0.65,0.82,0.86).setFill()
            for p in [NSPoint(x:49,y:181),NSPoint(x:204,y:200),NSPoint(x:195,y:61),NSPoint(x:53,y:80)] {
                NSBezierPath(ovalIn:NSRect(x:p.x,y:p.y,width:2,height:2)).fill()
            }
            let wings = NSBezierPath()
            wings.move(to:NSPoint(x:47,y:84)); wings.line(to:NSPoint(x:207,y:145))
            wings.move(to:NSPoint(x:47,y:145)); wings.line(to:NSPoint(x:207,y:84))
            color(0.75,0.83,0.83).setStroke(); wings.lineWidth = 13; wings.stroke()
            let body = NSBezierPath(); body.move(to:NSPoint(x:128,y:211)); body.line(to:NSPoint(x:116,y:77))
            body.line(to:NSPoint(x:140,y:77)); body.close()
            color(0.9,0.92,0.86).setFill(); body.fill()
            color(0.75,0.12,0.055).setFill(); NSBezierPath(rect:NSRect(x:123,y:135,width:10,height:31)).fill()
            for x: CGFloat in [49,202] {
                for y: CGFloat in [84,144] {
                    color(1,0.2,0.37).setFill(); NSBezierPath(ovalIn:NSRect(x:x-4,y:y-4,width:8,height:8)).fill()
                }
            }
            return true
        }
    }
    func place(_ child: NSView, x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat, mask: NSView.AutoresizingMask = []) {
        child.frame = NSRect(x:x,y:y,width:width,height:height); child.autoresizingMask = mask
        overlay.addSubview(child)
    }
    func button(_ title: String, action: Selector, tooltip: String) -> NSButton {
        let b = NSButton(title:title,target:self,action:action)
        b.bezelStyle = .recessed; b.isBordered = false
        b.font = .monospacedSystemFont(ofSize:11,weight:.medium)
        b.contentTintColor = color(0.7,0.83,0.86)
        b.wantsLayer = true; b.layer?.backgroundColor = color(0.12,0.2,0.24,0.65).cgColor
        b.layer?.borderColor = color(0.4,0.7,0.75,0.22).cgColor
        b.layer?.borderWidth = 0.5; b.layer?.cornerRadius = 6
        b.toolTip = tooltip
        return b
    }
    func buildHUD() {
        overlay = Overlay(frame:view.bounds); overlay.autoresizingMask = [.width,.height]
        view.addSubview(overlay)
        let w = overlay.bounds.width, h = overlay.bounds.height
        let brand = label("A S T E R O I D   S Q U A D R O N",size:18,weight:.medium,color:color(0.88,0.94,0.94))
        place(brand,x:36,y:h-83,width:550,height:27,mask:[.minYMargin])
        place(label("A NEVER-ENDING DOGFIGHT  /  OUTER RIM SECTOR 07",size:10,color:color(0.46,0.64,0.69),mono:true),x:38,y:h-105,width:550,height:17,mask:[.minYMargin])
        status = label("",size:11,weight:.medium,color:cyan,mono:true)
        status.alignment = .right
        place(status,x:w-360,y:h-80,width:322,height:20,mask:[.minXMargin,.minYMargin])
        let sub = label("LOCAL SIMULATION  ·  NO NETWORK REQUIRED",size:9,color:color(0.4,0.56,0.61),mono:true)
        sub.alignment = .right
        place(sub,x:w-360,y:h-101,width:322,height:16,mask:[.minXMargin,.minYMargin])
        cameraTitle = label("",size:21,weight:.light,color:color(0.9,0.95,0.94))
        place(cameraTitle,x:38,y:48,width:420,height:30)
        cameraDetail = label("",size:9,color:cyan,mono:true)
        place(cameraDetail,x:39,y:27,width:430,height:17)
        telemetry = label("",size:10,color:color(0.45,0.62,0.66),mono:true)
        place(telemetry,x:38,y:107,width:680,height:17)
        autoButton = button("AUTO  ON",action:#selector(toggleAutomatic),tooltip:"Automatic camera changes every 14 seconds (A)")
        place(autoButton,x:w-410,y:38,width:93,height:34,mask:[.minXMargin])
        let next = button("NEXT  →",action:#selector(nextCamera),tooltip:"Next camera (C or right arrow)")
        place(next,x:w-305,y:38,width:89,height:34,mask:[.minXMargin])
        pauseButton = button("Ⅱ",action:#selector(togglePause),tooltip:"Pause flight; keep awake stays on (Space)")
        place(pauseButton,x:w-204,y:38,width:44,height:34,mask:[.minXMargin])
        let full = button("⛶",action:#selector(fullscreen),tooltip:"Full screen (F). Escape exits full screen.")
        place(full,x:w-148,y:38,width:44,height:34,mask:[.minXMargin])
        let help = button("?",action:#selector(showHelp),tooltip:"Controls & information (?)")
        place(help,x:w-92,y:38,width:54,height:34,mask:[.minXMargin])
        hint = label("C  CAMERA     F  FULL SCREEN     SPACE  PAUSE     H  HIDE HUD     ?  HELP",size:9,color:color(0.4,0.55,0.59),mono:true)
        hint.alignment = .right
        place(hint,x:w-680,y:108,width:642,height:17,mask:[.minXMargin])
    }
    func startTimer() {
        timer?.invalidate(); lastTime = ProcessInfo.processInfo.systemUptime
        timer = Timer(timeInterval:1.0/(highQuality ? 60 : 30),repeats:true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(timer!,forMode:.common)
    }
    func tick() {
        let now = ProcessInfo.processInfo.systemUptime
        let dt = Float(min(0.08,now-lastTime)); lastTime = now
        SCNTransaction.begin(); SCNTransaction.animationDuration = 0
        battle.update(dt:dt)
        SCNTransaction.commit()
        if now-lastHUD > 1 {
            lastHUD = now
            let duration = Int(now-startTime)
            telemetry.stringValue = String(format:"12 FIGHTERS   /   245 ASTEROIDS   /   %02d:%02d:%02d ELAPSED",duration/3600,(duration/60)%60,duration%60)
            let idle = now-lastActivity > 9
            if !hudHidden { overlay.alphaValue = idle ? 0.34 : 1 }
            updateStatus()
        }
    }
    func showControls() {
        lastActivity = ProcessInfo.processInfo.systemUptime
        if !hudHidden { overlay.alphaValue = 1 }
    }
    func updateCameraHUD() {
        cameraTitle.stringValue = battle.cameraNames[battle.cameraIndex]
        cameraDetail.stringValue = String(format:"CAM %02d / 06   ·   %@",battle.cameraIndex+1,battle.cameraDetails[battle.cameraIndex])
        autoButton.title = battle.automatic ? "AUTO  ON" : "AUTO  OFF"
        autoItem.state = battle.automatic ? .on : .off
    }
    func updateStatus() {
        status.stringValue = awake.enabled ? "●  CAFFEINATE ACTIVE  /  DISPLAY AWAKE" : "○  KEEP AWAKE OFF"
        status.textColor = awake.enabled ? cyan : orange
        awakeItem.state = awake.enabled ? .on : .off
    }
    func handleKey(_ key: String) {
        switch key {
        case "c", "n", "\u{f703}": nextCamera()
        case "a": toggleAutomatic()
        case " ", "p": togglePause()
        case "f": fullscreen()
        case "h", "u": toggleHUD()
        case "k": toggleAwake()
        case "j": toggleQuality()
        case "?", "/": showHelp()
        case "\u{1b}": if window.styleMask.contains(.fullScreen) { fullscreen() }
        default: break
        }
    }
    @objc func nextCamera() { battle.nextCamera(); showControls() }
    @objc func toggleAutomatic() { battle.automatic.toggle(); battle.cameraAge = 0; updateCameraHUD(); showControls() }
    @objc func togglePause() {
        battle.paused.toggle(); pauseButton.title = battle.paused ? "▶" : "Ⅱ"
        pauseItem.title = battle.paused ? "Resume Flight" : "Pause Flight"
        view.isPlaying = !battle.paused; view.rendersContinuously = !battle.paused
        showControls()
    }
    @objc func toggleAwake() { if awake.enabled { awake.stop() } else { _ = awake.start() }; updateStatus(); showControls() }
    @objc func toggleHUD() { hudHidden.toggle(); overlay.isHidden = hudHidden; showControls() }
    @objc func fullscreen() { window.toggleFullScreen(nil); showControls() }
    @objc func toggleQuality() {
        highQuality.toggle(); view.preferredFramesPerSecond = highQuality ? 60 : 30
        view.antialiasingMode = highQuality ? .multisampling4X : .multisampling2X
        startTimer(); showControls()
    }
    @objc func about() {
        NSApp.orderFrontStandardAboutPanel(options:[.applicationName:"Asteroid Squadron",.applicationVersion:"1.0",.credits:NSAttributedString(string:"An endless, procedural X-wing and TIE fighter dogfight.\nBuilt for quiet company while your agents work.\n\nUnofficial fan project. Star Wars belongs to Lucasfilm.")])
    }
    @objc func showHelp() {
        let alert = NSAlert()
        alert.messageText = "Asteroid Squadron"
        alert.informativeText = "C / →   Next camera\nA          Automatic camera cuts\nF          Toggle full screen\nSpace   Pause / resume flight\nH          Show / hide overlay\nK          Toggle keep awake\nJ           Switch 30 / 60 fps\n⌘Q       Quit and release keep awake\n\nKeep awake uses the macOS caffeinate tool with -d -i. It prevents idle display and system sleep while the app runs, including while flight is paused or the window is minimized. Closing the window quits the app and releases its assertions.\n\nThe default is 30 fps to leave resources for your agents. No audio, network, or downloaded assets.\n\nUnofficial fan project. Star Wars belongs to Lucasfilm."
        alert.addButton(withTitle:"Back to the dogfight")
        alert.beginSheetModal(for:window) { [weak self] _ in self?.window.makeFirstResponder(self?.view) }
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
    func applicationWillTerminate(_ notification: Notification) {
        timer?.invalidate(); awake.stop()
        if let token = activityToken { ProcessInfo.processInfo.endActivity(token) }
    }
    func windowDidBecomeKey(_ notification: Notification) { window.makeFirstResponder(view) }
    func smokeTest() {
        let output = URL(fileURLWithPath:CommandLine.arguments.drop(while:{$0 != "--smoke-test"}).dropFirst().first ?? "/tmp/asteroid-squadron-smoke.png")
        let image = view.snapshot()
        if let tiff = image.tiffRepresentation, let bitmap = NSBitmapImageRep(data:tiff), let png = bitmap.representation(using:.png,properties:[:]) { try? png.write(to:output) }
        let stats: [String:Any] = ["fighters":battle.fighters.count,"asteroids":battle.rocks.count,"keepAwake":awake.enabled,"camera":battle.cameraIndex,"elapsed":battle.time,"shots":battle.shots,"snapshot":output.path]
        if let data = try? JSONSerialization.data(withJSONObject:stats,options:[.prettyPrinted,.sortedKeys]) { try? data.write(to:output.deletingPathExtension().appendingPathExtension("json")) }
    }
}

if CommandLine.arguments.contains("--verify-simulation") {
    let battle = Dogfight()
    var cameraVisits = Set<Int>()
    var maxLasers = 0, maxSparks = 0
    for _ in 0..<18000 {
        battle.update(dt:1.0/30.0)
        cameraVisits.insert(battle.cameraIndex)
        maxLasers = max(maxLasers,battle.lasers.count); maxSparks = max(maxSparks,battle.sparks.count)
        for f in battle.fighters {
            precondition(f.position.x.isFinite && f.position.y.isFinite && f.position.z.isFinite,"Non-finite fighter position")
            precondition(abs(simd_length(f.forward)-1)<0.01,"Invalid heading")
        }
        precondition(battle.camera.simdPosition.x.isFinite,"Invalid camera position")
    }
    precondition(cameraVisits.count == 6,"Not all cameras were visited")
    precondition(maxLasers < 250 && maxSparks < 1500,"Unbounded effects")
    precondition(battle.destroyed > 0,"Combat never produces a kill")
    print("PASS: 10 simulated minutes, all 6 cameras, \(battle.shots) shots, \(battle.destroyed) regenerating kills; max \(maxLasers) lasers / \(maxSparks) particles.")
} else {
    let app = NSApplication.shared
    let delegate = App()
    app.delegate = delegate
    app.run()
}
