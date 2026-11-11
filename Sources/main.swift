import AppKit
import SceneKit
import simd

// Asteroid Squadron — a self-contained, procedural, native macOS dogfight.
typealias V3 = SIMD3<Float>
let tau = Float.pi * 2
func mix(_ a: V3, _ b: V3, _ t: Float) -> V3 { a + (b - a) * t }
func unit(_ v: V3) -> V3 { simd_length_squared(v) > 0.0001 ? simd_normalize(v) : V3(0, 0, -1) }
func addMuzzle(to parent: SCNNode, at position: V3, name: String) {
    let muzzle = SCNNode(); muzzle.name = "muzzle.\(name)"; muzzle.simdPosition = position
    parent.addChildNode(muzzle)
}
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
    mutating func index(_ count: Int) -> Int { min(count-1,Int(next()*Float(count))) }
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
    g.radialSegmentCount = 16
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

// Closed, flat-shaded convex hull; every face has an explicit outward normal.
func hullMesh(_ vertices: [V3], faces: [[Int]], mat: SCNMaterial) -> SCNNode {
    let center = vertices.reduce(V3.zero,+) / Float(vertices.count)
    var positions: [SCNVector3] = [], normals: [SCNVector3] = []
    for face in faces {
        for i in 1..<(face.count-1) {
            var triangle = [vertices[face[0]],vertices[face[i]],vertices[face[i+1]]]
            var normal = unit(simd_cross(triangle[1]-triangle[0],triangle[2]-triangle[0]))
            if simd_dot(normal,triangle[0]-center)<0 { triangle.swapAt(1,2); normal = -normal }
            positions += triangle.map(SCNVector3.init)
            normals += Array(repeating:SCNVector3(normal),count:3)
        }
    }
    let g = SCNGeometry(sources:[SCNGeometrySource(vertices:positions),SCNGeometrySource(normals:normals)],elements:[SCNGeometryElement(indices:Array(0..<Int32(positions.count)),primitiveType:.triangles)])
    return node(g,mat)
}

func xWing() -> SCNNode {
    let root = SCNNode()
    let hull = material(color(0.68, 0.72, 0.71), metal: 0.55)
    let pale = material(color(0.84, 0.85, 0.78), metal: 0.3)
    let dark = material(color(0.055, 0.075, 0.085), metal: 0.7)
    let red = material(color(0.55, 0.065, 0.025), metal: 0.2)
    let glass = material(color(0.035, 0.12, 0.17), emission: color(0.015, 0.05, 0.075), metal: 0.85)
    let glow = material(color(1, 0.22, 0.36), emission: color(2.5, 0.27, 0.55))
    root.addChildNode(box(V3(1.35, 0.9, 4.3), hull, V3(0, 0, -0.2), chamfer: 0.3))
    root.addChildNode(hullMesh([
        V3(-0.65,-0.4,-1.65), V3(0.65,-0.4,-1.65), V3(0.65,0.4,-1.65), V3(-0.65,0.4,-1.65),
        V3(-0.11,-0.08,-6.45), V3(0.11,-0.08,-6.45), V3(0.11,0.08,-6.45), V3(-0.11,0.08,-6.45)
    ],faces:[[0,1,2,3],[4,7,6,5],[0,4,5,1],[3,2,6,7],[0,3,7,4],[1,5,6,2]],mat:pale))
    let stripe = box(V3(0.10,0.025,4.76),red,V3(0,0.255,-4.04))
    stripe.simdEulerAngles.x = -atan2(0.32,4.8)
    root.addChildNode(stripe)
    let cockpit = box(V3(0.9, 0.58, 1.65), glass, V3(0, 0.62, -0.85), chamfer: 0.19)
    cockpit.eulerAngles.x = -0.1
    root.addChildNode(cockpit)
    root.addChildNode(box(V3(0.95, 0.09, 0.085), pale, V3(0, 0.94, -0.5)))
    root.addChildNode(box(V3(1.45, 0.12, 2), red, V3(0, -0.48, 0.5)))
    // Astromech dome behind the cockpit.
    let droid = cylinder(0.28,0.30,pale,V3(0,0.59,0.55))
    droid.simdOrientation = simd_quatf(angle:0,axis:V3(0,1,0))
    root.addChildNode(droid)
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
            addMuzzle(to:foil,at:V3(sx*4.2,0,-4.12),name:"\(sx).\(sy)")
            foil.addChildNode(cylinder(0.43, 2.7, hull, V3(sx * 1.15, 0, 0.6)))
            foil.addChildNode(cylinder(0.34,0.05,dark,V3(sx * 1.15,0,-0.77)))
            foil.addChildNode(cylinder(0.12,0.07,hull,V3(sx * 1.15,0,-0.81)))
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
    for s: Float in [-1,1] {
        root.addChildNode(cylinder(0.12,0.5,frame,V3(s*0.43,-0.55,-1.1)))
        addMuzzle(to:root,at:V3(s*0.43,-0.55,-1.42),name:"\(s)")
    }
    for s: Float in [-1, 1] {
        root.addChildNode(box(V3(2.5, 0.4, 0.45), frame, V3(s * 1.75, 0, 0)))
        let p: [V3] = [V3(0,-3.7,-1.8), V3(0,-2.6,2.3), V3(0,2.6,2.3), V3(0,3.7,-1.8), V3(0,2.5,-3), V3(0,-2.5,-3)]
        let vertices = p.map { SCNVector3($0 + V3(s * 3.1, 0, 0)) }
        let indices: [Int32] = [0,1,2, 0,2,3, 0,3,4, 0,4,5]
        let geo = SCNGeometry(sources: [SCNGeometrySource(vertices: vertices),SCNGeometrySource(normals:Array(repeating:SCNVector3(s,0,0),count:vertices.count))], elements: [SCNGeometryElement(indices: indices, primitiveType: .triangles)])
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
    let node = SCNNode()
    var faction: Faction
    let side: Int
    var generation = 0
    var encountersSurvived = 0
    var enemyKills = 0
    var isAce = false
    var aceEligible: Bool { active && encountersSurvived>=3 && enemyKills>=6 }
    let aceBadge = AceBadge()
    var patrolRoute: [V3] = []
    var atlantisEgress: V3?
    var steeringDirection = V3(0,0,-1)
    var aimDirection = V3(0,0,-1)
    var orbitRate: Float = 0.185
    var scanner: SCNNode?
    var jumpClipper: JumpClipper?
    var muzzles: [SCNNode] = []
    var gunCycle = 0
    var velocity = V3.zero
    var navigationUp = V3(0,1,0)
    var bank: Float = 0
    var motionInitialized = false
    var breakUntil: Float = -1
    var breakDirection = V3.zero
    var breakSpeed: Float = 0
    var pursuitTarget: Int?
    var pursuitGeneration = -1
    var pursuitDeadline: Float = 0
    var pursuitBreakCount = 0
    var history: [(Float,V3)] = []
    var entrySpeed: Float { entry == .hyperspace ? 28 : (entry == .jumpWindow ? 85 : 160) }
    var cruiseSpeed: Float { faction == .rebel ? 48 : (faction == .empire ? 52 : 56) }
    let accelerationLimit: Float = 90
    let turnRate: Float = 2.0
    var pivotUntil: Float = -100
    var pivotCooldown: Float = 0
    var pivotExit = V3(0,0,-1)
    var pivotCount = 0
    var burstShotsLeft = 0
    let pair: Int
    let trailing: Bool
    var position = V3.zero
    var forward = V3(0, 0, -1)
    var cooldown: Float
    enum State { case active, destroyed, arriving }
    var state: State = .active
    var active: Bool { state == .active }
    var arrival: Float = 0
    var arrivalDelay: Float = 0
    var hitPoints = 6
    enum Entry { case none, hyperspace, hangar, jumpWindow }
    var entry: Entry = .none
    var entryTime: Float = -1000
    var entryPosition = V3.zero
    var entryForward = V3(0,0,-1)
    var formationSlot = 0
    var attackTarget: Int?
    var spin: SpinOut?
    var collisionCooldown: Float = 20
    var formationHold: Float { (entry == .hyperspace || entry == .jumpWindow) ? 2.1+Float(formationSlot)*0.13 : 0.8+Float(formationSlot)*0.08 }
    let warp = SCNNode()
    init(faction: Faction, side: Int, pair: Int, trailing: Bool, cooldown: Float) {
        self.faction = faction; self.side = side; self.pair = pair; self.trailing = trailing; self.cooldown = cooldown
        node.addChildNode(faction.fighterModel())
        scanner = node.childNode(withName:"scanner",recursively:true)
        cacheMuzzles()
        let glow = material(color(0.55,0.85,1),emission:color(1.4,2.2,3))
        warp.addChildNode(box(V3(0.3,0.3,1),glow))
        warp.addChildNode(box(V3(0.85,0.85,1),material(color(0.15,0.4,1,0.25),emission:color(0.15,0.4,1,0.25))))
        warp.isHidden = true
    }
    func replaceFaction(_ replacement: Faction) {
        for child in node.childNodes { child.removeFromParentNode() }
        faction = replacement; generation += 1
        encountersSurvived = 0; enemyKills = 0; isAce = false; aceBadge.reset(); patrolRoute.removeAll(); atlantisEgress = nil
        node.addChildNode(replacement.fighterModel())
        scanner = node.childNode(withName:"scanner",recursively:true)
        cacheMuzzles()
        state = .destroyed; node.isHidden = true; node.opacity = 1
        node.simdScale = V3(repeating:1); warp.isHidden = true
        entry = .none; entryTime = -1000; spin = nil; attackTarget = nil
        arrival = 0; hitPoints = 6; collisionCooldown = 25
        motionInitialized = false; velocity = .zero; navigationUp = V3(0,1,0); bank = 0
        history.removeAll(keepingCapacity:true); breakUntil = -1
        pursuitTarget = nil; pursuitGeneration = -1; pursuitDeadline = 0; breakSpeed = 0; burstShotsLeft = 0
        pursuitBreakCount = 0
        pivotUntil = -100; pivotCooldown = 0; pivotCount = 0
    }
    func cacheMuzzles() {
        jumpClipper = faction == .earth ? JumpClipper(root:node) : nil
        muzzles.removeAll(keepingCapacity:true)
        node.enumerateChildNodes { child,_ in
            if child.name?.hasPrefix("muzzle.") == true { self.muzzles.append(child) }
        }
        muzzles.sort { ($0.name ?? "")<($1.name ?? "") }; gunCycle = 0
    }
    var firingMuzzles: [SCNNode] {
        if muzzles.count == 4 { return gunCycle%2 == 0 ? [muzzles[0],muzzles[3]] : [muzzles[1],muzzles[2]] }
        return muzzles
    }
}
struct Laser {
    let node: SCNNode
    var position: V3
    let velocity: V3
    var life: Float
    let sourceSide: Int
    let generations: [Int]
    let launchOrigin: V3
    let launchForward: V3
    let inheritedVelocity: V3
    let length: Float
    var sourceIndex: Int? = nil
    var targetsAtlantis = false
}
struct Spark {
    enum Kind { case debris, ember, impact }
    let node: SCNNode
    var position: V3
    let velocity: V3
    var life: Float
    let duration: Float
    let scale: Float
    let spin: V3
    let kind: Kind
}
struct Transient {
    enum Kind { case flash, light, arrival, jump }
    let node: SCNNode
    let kind: Kind
    var life: Float
    let duration: Float
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

func stoneTexture(seed: UInt64) -> NSImage {
    let size = 256
    let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: size*4, bitsPerPixel: 32)!
    var rng = Random(state: seed)
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
    var effects: [Transient] = []
    var clouds: [GasCloud] = []
    var blasts: [ExplosionVolume] = []
    var carriers: [Carrier] = []
    var carrier: Carrier? { director.featuredCarrier ?? carriers.first(where:{$0.start<=time}) ?? carriers.first }
    var sideFactions: [Faction] = [.rebel,.empire]
    var pendingSides = Set<Int>()
    var fleetRequests: [FleetRequest] = []
    var replacements: [FleetReplacement] = []
    var replacementCount = 0
    var encounteredFactions = Set<Faction>()
    var starfuryPivots = 0
    var squadronEncounters = [0,0]
    var encountersCompleted = 0
    var atlantis: Atlantis?
    var nextAtlantisEncounter: Int?
    var returningFromAtlantis = false
    var atlantisRegroupUntil: Float?
    var acePromotions = 0
    var aceKillRecord = 0
    var acesEmerged = 0
    var longestEncounterStreak = 0
    // Only the latest honoured generation per roster slot is needed: bounded
    // history prevents counting the same pilot again after losing the title.
    var honouredAceGenerations: [Int:Int] = [:]
    var acePilot: (index: Int,generation: Int)?
    var topUpWaves = 0
    var nextArrivalTime: Float = 0
    var persistentNodeCount = 0
    var blinkArrivals = 0
    var blinkDepartures = 0
    let director: CinematicDirector
    var carrierVisits = 0
    var carrierDepartures = 0
    var formationArrivals = 0
    var spinOuts = 0
    var shipCollisions = 0
    var shipCollisionLosses = 0
    var shipContacts = Set<ShipContact>()
    var recoveries = 0
    var asteroidLosses = 0
    let seed: UInt64
    var rng: Random
    var arenaRotation = simd_quatf(angle:0,axis:V3(0,1,0))
    var orbitPhase: Float = 0
    var orbitRadius: Float = 110
    var waveCountdown: Float? { fleetRequests.map(\.countdown).min() }
    var waveNumber = 0
    var reinforcements = 0
    var minimumFleet = 12
    var followedIndex = 0
    var wreckHold: Float = 0
    var wreckPosition = V3.zero
    var time: Float = 0
    var physicsAccumulator: Double = 0
    var physicsSteps = 0
    var planetPosition = V3.zero
    var planetRadius: Float = 440
    var planet: ProceduralPlanet?
    var planetSunDirection = V3(0,0,1)
    var cameraAge: Float = 0
    var viewportAspect: Float = 1.6
    var cameraIndex = 2
    var automatic = true
    var paused = false
    var cameraPosition = V3(0,20,100)
    var cameraLook = V3.zero
    var cut = true
    var cameraChanged: (() -> Void)?
    var destroyed = 0
    var shots = 0
    var weaponHits = 0
    var pursuitBreaks = 0
    let cameraNames = ["ON THEIR SIX", "ASTEROID RUN", "THE BATTLEFIELD", "WINGMAN", "INTERCEPT VECTOR", "IN THE CROSSFIRE"]
    let cameraDetails = ["PURSUIT / ENGAGEMENT TRACKING", "LOW CAMERA / FLIGHT CORRIDOR", "WIDE ESTABLISHING SHOT", "LATERAL DOLLY / SQUADRON TRACKING", "FORWARD FLYBY / APPROACH CAMERA", "TWO-SHIP ENGAGEMENT CAMERA"]
    let projectileMaterials = Dictionary(uniqueKeysWithValues:Faction.allCases.map{($0,$0.shotMaterial())})
    let sparkMaterials = [material(color(1,0.7,0.2), emission: color(3,1.3,0.2)), material(color(1,0.25,0.06), emission: color(2,0.3,0.03)), material(color(0.6,0.6,0.6), metal: 0.8)]

    var activeCount: Int { fighters.filter(\.active).count }
    var rebelCount: Int { fighters.filter { $0.active && $0.faction == .rebel }.count }
    var empireCount: Int { fighters.filter { $0.active && $0.faction == .empire }.count }
    var arrivingCount: Int { fighters.filter { $0.state == .arriving }.count }
    func sideCount(_ side: Int) -> Int { fighters.filter { $0.side == side && $0.active }.count }

    init(seed: UInt64 = UInt64.random(in:1...UInt64.max), initialFactions: [Faction]? = nil, initialArrivals: Bool = true, firstAtlantisEncounter: Int? = 3) {
        self.seed = seed
        nextAtlantisEncounter = firstAtlantisEncounter
        rng = Random(state:seed)
        director = CinematicDirector(seed:seed)
        arenaRotation = simd_quatf(angle:rng.range(0,tau),axis:V3(0,1,0)) * simd_quatf(angle:rng.range(-0.35,0.35),axis:V3(0,0,1))
        orbitPhase = rng.range(0,tau)
        orbitRadius = rng.range(100,130)
        scene.background.contents = color(0.003,0.007,0.016)
        scene.fogColor = color(0.009,0.017,0.03)
        scene.fogStartDistance = 1800; scene.fogEndDistance = 7000
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
        planetSunDirection = unit(sun.simdOrientation.act(V3(0,0,1)))
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
        makeClouds()
        if let initialFactions, initialFactions.count == 2, initialFactions[0] != initialFactions[1] {
            sideFactions = initialFactions
        } else {
            var options = Faction.allCases
            let first = options.remove(at:rng.index(options.count))
            sideFactions = [first,options[rng.index(options.count)]]
        }
        encounteredFactions.formUnion(sideFactions)
        for pair in 0..<6 {
            for trailing in [false, true] {
                let side = trailing ? 1-pair%2 : pair%2
                let f = Fighter(faction:sideFactions[side],side:side,pair:pair,trailing:trailing,cooldown:rng.range(0.2,2.0))
                f.orbitRate = rng.range(0.17,0.21)
                scene.rootNode.addChildNode(f.node)
                scene.rootNode.addChildNode(f.warp)
                fighters.append(f)
                f.collisionCooldown = rng.range(15,45)
            }
        }
        persistentNodeCount = scene.rootNode.childNodes.count
        if initialArrivals {
            for f in fighters { f.state = .destroyed; f.node.isHidden = true }
            deployReinforcements()
        }
        selectCameraSubject(); director.prepareShot(in:self)
        update(dt: 0)
    }

    func makeStars() {
        makeStarfieldSkybox()
    }
    func makeClouds() {
        let palettes = [color(0.19,0.37,0.49),color(0.31,0.23,0.43),color(0.16,0.39,0.37)]
        for i in 0..<9 {
            let a = Float(i)*tau/9+rng.range(-0.25,0.25)
            let radius = rng.range(200,470)
            let p = arenaRotation.act(V3(sin(a)*radius,rng.range(-150,110),cos(a)*radius))
            let cloud = GasCloud(position:p,scale:V3(rng.range(160,255),rng.range(65,135),rng.range(140,230)),tint:palettes[i%palettes.count],seed:rng.range(0,100))
            clouds.append(cloud)
            scene.rootNode.addChildNode(cloud.node)
        }
    }
    func makeRocks() {
        let texture = stoneTexture(seed:seed)
        var geometries: [SCNGeometry] = []
        for _ in 0..<12 {
            _ = rng.next()
            let g = rockGeometry(seed:rng.state)
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
                p = arenaRotation.act(V3(sin(a)*rad,rng.range(-115,115),cos(a)*rad))
                r = rng.range(2.5,11)
            } else {
                p = unit(rng.vector(1))*rng.range(350,1000)
                r = rng.range(5,42)
            }
            if i < 2 { r = rng.range(20,29) }
            let n = SCNNode(geometry:geometries[i%geometries.count])
            n.simdScale = V3(r*rng.range(0.8,1.35),r*rng.range(0.7,1.2),r)
            n.simdEulerAngles = rng.vector(.pi)
            let bounds = max(n.simdScale.x,max(n.simdScale.y,n.simdScale.z))*1.25
            // Rejection sampling leaves navigable gaps instead of intersecting exclusion shells.
            let margin: Float = i<75 ? 24 : 12
            for _ in 0..<200 {
                if !rocks.contains(where:{ simd_distance($0.position,p)<$0.radius+bounds+margin }) { break }
                if i<75 {
                    let angle = rng.range(0,tau), radius = rng.range(65,300)
                    p = arenaRotation.act(V3(sin(angle)*radius,rng.range(-125,125),cos(angle)*radius))
                } else {
                    p = unit(rng.vector(1))*rng.range(350,1000)
                }
            }
            n.simdPosition = p
            scene.rootNode.addChildNode(n)
            rocks.append(Rock(node:n,position:p,radius:bounds,spin:rng.vector(0.035)))
        }
    }
    func makePlanet() {
        planetRadius = rng.range(300,480)
        _ = rng.range(0.5,1) // Keep the existing arena random stream stable.
        let variation = rng.range(-1.1,1.1)
        let a = atan2(-planetSunDirection.x,-planetSunDirection.z)+variation
        planetPosition = V3(sin(a)*2400,rng.range(100,650),cos(a)*2400)
        let world = ProceduralPlanet(seed:seed,radius:planetRadius,sun:planetSunDirection)
        world.node.simdPosition = planetPosition
        scene.rootNode.addChildNode(world.node); planet = world
        world.update(time:0)
    }

    func orbitPath(_ f: Fighter, _ t: Float) -> V3 {
        let phase = Float(f.pair) * tau / 6 + orbitPhase
        let a = t * f.orbitRate + phase - (f.trailing ? 0.14 : 0)
        let radius = orbitRadius + Float(f.pair % 3) * 22
        var p = V3(sin(a)*radius + sin(a*2.0+phase)*24,
                   sin(a*2.0+phase)*30 + cos(a*3.0)*13,
                   cos(a)*radius*0.8 + sin(a*3.0+phase)*17)
        p = arenaRotation.act(p)
        return clearFlight(p)
    }
    func clearFlight(_ point: V3) -> V3 {
        var p = point
        for _ in 0..<8 {
            var moved = false
            for rock in rocks {
                let delta = p-rock.position
                let clearance = rock.radius + 9
                if simd_length_squared(delta) < clearance*clearance {
                    p = rock.position + unit(delta)*(clearance+0.01)
                    moved = true
                }
            }
            if !moved { break }
        }
        return p
    }

    func update(dt: Float) {
        guard !paused else { return }
        if dt<=0 { simulateStep(0); return }
        physicsAccumulator += Double(min(0.12,dt))
        let step = 1.0/60.0
        while physicsAccumulator+0.00000001>=step {
            simulateStep(Float(step))
            physicsAccumulator = max(0,physicsAccumulator-step)
            physicsSteps += 1
        }
    }
    private func simulateStep(_ dt: Float) {
        time += dt; cameraAge += dt
        for rock in rocks { rock.node.simdEulerAngles += rock.spin*dt }
        for f in fighters where f.active && !f.motionInitialized {
            let point = orbitPath(f,time)
            activateFlight(f,position:point,forward:unit(orbitPath(f,time+0.07)-point),speed:f.cruiseSpeed)
        }
        let positions = fighters.map(\.position), velocities = fighters.map(\.velocity), active = fighters.map(\.active)
        for f in fighters {
            guard f.state != .destroyed else { continue }
            f.cooldown -= dt; f.collisionCooldown = max(0,f.collisionCooldown-dt)
            if f.spin != nil { updateSpinOut(f,dt:dt,positions:positions,velocities:velocities,active:active) }
            else if f.state == .arriving {
                if !updateArrival(f) { continue }
                if !f.active {
                    f.node.simdPosition = f.position
                    f.node.look(at:SCNVector3(f.position+f.forward),up:SCNVector3(0,1,0),localFront:SCNVector3(0,0,-1))
                }
            } else { updateFlight(f,dt:dt,positions:positions,velocities:velocities,active:active) }
            f.scanner?.simdPosition.x = sin(time*3+Float(f.pair))*0.49
            f.aceBadge.updatePose(f)
        }
        resolveShipCollisions(from:positions,wasActive:active,dt:dt)
        if dt>0 && atlantisSiegeActive {
            for i in fighters.indices where fighters[i].active {
                let f = fighters[i]
                resolveAtlantisCollision(f,from:active[i] ? positions[i] : f.position)
            }
        }
        for f in fighters {
            if f.active && dt>0 {
                f.history.append((time,f.position))
                if f.history.count>120 { f.history.removeFirst(f.history.count-120) }
            }
        }
        for i in fighters.indices {
            let f = fighters[i]
            guard dt>0, f.cooldown<=0, f.active, f.spin == nil, time>=f.entryTime+f.formationHold, time>=f.breakUntil else { continue }
            if let city = atlantis, city.intact {
                f.cooldown = fireAtAtlantis(from:i,city:city) ? rng.range(0.23,0.32) : 0.07
                continue
            }
            if let target = chooseTarget(for:f), fire(from:i,to:target) {
                if f.burstShotsLeft == 0 { f.burstShotsLeft = 4 }
                else { f.burstShotsLeft -= 1 }
                f.cooldown = f.burstShotsLeft>0 ? 0.11 : rng.range(0.24,0.45)
            } else { f.burstShotsLeft = 0; f.cooldown = 0.04 }
        }
        updateLasers(dt); updateSparks(dt); updateEffects(dt)
        updateAtlantis(dt,starts:positions,wasActive:active)
        updateReinforcements(dt); updateCarrier(); updateFighterJumpClipping(); updateAce(); updateCamera(dt); updateBlasts(dt)
        for cloud in clouds { cloud.update(time:time,camera:cameraPosition) }
        planet?.update(time:time)
    }
    func destroy(_ fighter: Fighter) {
        guard fighter.active else { return }
        if automatic { director.requestExplosion(fighter,in:self) }
        else if fighter === cameraSubject(), cameraIndex != 2 {
            wreckHold = 1.15; wreckPosition = fighter.position
        }
        let velocity = fighter.velocity
        burst(at:fighter.position,count:42,big:true,velocity:velocity)
        fighter.state = .destroyed; fighter.node.isHidden = true; fighter.warp.isHidden = true
        fighter.spin = nil
        destroyed += 1
        minimumFleet = min(minimumFleet,activeCount)
        updateAce()
    }

    func arrivalFlash(at p: V3) {
        let m = material(color(0.5,0.8,1),emission:color(1.1,1.8,2.5))
        let g = SCNSphere(radius:1); g.segmentCount = 12
        let n = node(g,m,p); n.simdScale = V3(3,3,3)
        scene.rootNode.addChildNode(n)
        effects.append(Transient(node:n,kind:.arrival,life:0.45,duration:0.45))
    }
    func clearCamera(_ point: V3, insideAtlantisShield: Bool = false) -> V3 {
        var p = point
        for _ in 0..<3 {
            for rock in rocks {
                let delta = p-rock.position, clearance = rock.radius+5
                if simd_length_squared(delta)<clearance*clearance { p = rock.position+unit(delta)*clearance }
            }
            for f in fighters where f.active {
                let delta = p-f.position
                let clearance: Float = f === cameraSubject() ? 17 : 10
                if simd_length_squared(delta)<clearance*clearance { p = f.position+unit(delta)*clearance }
            }
            for ship in carriers where !ship.node.isHidden {
                let transform = ship.node.simdWorldTransform
                let inverse = transform.inverse
                for (center,bounds) in ship.cameraVolumes {
                    let local = (inverse*SIMD4<Float>(p.x,p.y,p.z,1)).xyz
                    let normalized = (local-center)/bounds
                    if simd_length_squared(normalized)<1 {
                        let safe = unit(normalized)*bounds+center
                        p = (transform*SIMD4<Float>(safe.x,safe.y,safe.z,1)).xyz
                    }
                }
            }
        }
        if let city = atlantis, city.intact {
            let hit = insideAtlantisShield ? city.hullImpact(from:p,to:p,padding:10)
                                           : city.impact(from:p,to:p,padding:10)
            if hit != nil { p = city.position+unit(p-city.position)*(Atlantis.shieldRadius+12) }
        }
        return p
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

final class HUDLabel: NSTextField {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}
func label(_ text: String, size: CGFloat, weight: NSFont.Weight = .regular, color c: NSColor = .white, mono: Bool = false) -> NSTextField {
    let l = HUDLabel(labelWithString:text)
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
    private var dragWindowOrigin: NSPoint?
    private var dragMouseOrigin: NSPoint?
    var lastPointerEvent = "none"
    var dragEventCount = 0
    var isDraggingWindow: Bool { dragWindowOrigin != nil }
    override var acceptsFirstResponder: Bool { true }
    override func keyDown(with event: NSEvent) {
        if let key = event.charactersIgnoringModifiers?.lowercased() { keyHandler?(key); activity?() }
    }
    override func mouseMoved(with event: NSEvent) { activity?() }
    override func mouseDown(with event: NSEvent) {
        lastPointerEvent = "down / \(event.clickCount) clicks"
        activity?()
        guard let window, !window.styleMask.contains(.fullScreen) else { return }
        if event.clickCount == 2 { window.performZoom(nil) }
        else {
            dragWindowOrigin = window.frame.origin
            dragMouseOrigin = window.convertPoint(toScreen:event.locationInWindow)
        }
    }
    override func mouseDragged(with event: NSEvent) {
        guard let window, let origin = dragWindowOrigin, let mouse = dragMouseOrigin else { return }
        let current = window.convertPoint(toScreen:event.locationInWindow)
        dragEventCount += 1
        lastPointerEvent = "drag"
        window.setFrameOrigin(NSPoint(x:origin.x+current.x-mouse.x,y:origin.y+current.y-mouse.y))
        activity?()
    }
    override func mouseUp(with event: NSEvent) {
        lastPointerEvent = "up"
        dragWindowOrigin = nil; dragMouseOrigin = nil
    }
    override func smartMagnify(with event: NSEvent) {
        if let window, !window.styleMask.contains(.fullScreen) { window.performZoom(nil) }
    }
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
    var aceHistory: NSTextField!
    var aceStatus: NSTextField!
    var sector: NSTextField!
    var eventStatus: NSTextField!
    var hint: NSTextField!
    var autoButton: NSButton!
    var pauseButton: NSButton!
    var awakeItem: NSMenuItem!
    var autoItem: NSMenuItem!
    var pauseItem: NSMenuItem!
    var hudHidden = false
    var highQuality = false
    var activityToken: NSObjectProtocol?
    var pointerMonitor: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        // Use the compiled bundle icon everywhere, including the Dock. A raw
        // NSImage override bypasses native icon rendering and hides bundle bugs.
        buildMenu()
        battle = Dogfight(seed:requestedSeed(),initialFactions:requestedFactions(),
                          firstAtlantisEncounter:CommandLine.arguments.contains("--atlantis") ? 0 : 3)
        let screen = NSScreen.main?.visibleFrame ?? NSRect(x:0,y:0,width:1440,height:900)
        let width = min(1440,screen.width-80), height = min(900,screen.height-80)
        window = NSWindow(contentRect:NSRect(x:0,y:0,width:width,height:height),styleMask:[.titled,.closable,.miniaturizable,.resizable,.fullSizeContentView],backing:.buffered,defer:false)
        window.title = "Asteroid Squadron"
        window.titleVisibility = .hidden; window.titlebarAppearsTransparent = true
        window.backgroundColor = .black; window.isMovableByWindowBackground = false
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
        // Intercept the scene's drag before SceneKit's gesture recognizers consume it.
        // Keep buttons and native window chrome on their normal AppKit event paths.
        pointerMonitor = NSEvent.addLocalMonitorForEvents(matching:[.leftMouseDown,.leftMouseDragged,.leftMouseUp]) { [weak self] event in
            guard let self, event.window === self.window, !self.window.styleMask.contains(.fullScreen) else { return event }
            if event.type == .leftMouseDown {
                let point = self.view.convert(event.locationInWindow,from:nil)
                guard self.view.bounds.contains(point), point.y<self.view.bounds.height-28 else { return event }
                var hit = self.view.hitTest(point)
                while let candidate = hit {
                    if candidate is NSButton { return event }
                    hit = candidate.superview
                }
                self.view.mouseDown(with:event)
                return nil
            }
            if self.view.isDraggingWindow {
                if event.type == .leftMouseDragged { self.view.mouseDragged(with:event) }
                if event.type == .leftMouseUp { self.view.mouseUp(with:event) }
                return nil
            }
            return event
        }
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
        menuView.addItem(withTitle:"Fill / Restore Window",action:#selector(fillWindow),keyEquivalent:"")
        menuView.addItem(withTitle:"Toggle 30 / 60 FPS",action:#selector(toggleQuality),keyEquivalent:"j")
        menuView.addItem(withTitle:"Generate New Arena",action:#selector(newArena),keyEquivalent:"r")
        menuView.addItem(withTitle:"Next Planet Biome",action:#selector(nextBiome),keyEquivalent:"b")
        viewItem.submenu = menuView
        for item in menu.items+menuView.items { if item.action != nil && item.action != #selector(NSApplication.hide(_:)) && item.action != #selector(NSApplication.terminate(_:)) { item.target = self } }
        NSApp.mainMenu = bar
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
        sector = label("",size:10,color:color(0.46,0.64,0.69),mono:true)
        place(sector,x:38,y:h-105,width:550,height:17,mask:[.minYMargin])
        status = label("",size:11,weight:.medium,color:cyan,mono:true)
        status.alignment = .right
        place(status,x:w-360,y:h-80,width:322,height:20,mask:[.minXMargin,.minYMargin])
        eventStatus = label("",size:9,color:color(0.4,0.56,0.61),mono:true)
        eventStatus.alignment = .right
        place(eventStatus,x:w-390,y:h-101,width:352,height:16,mask:[.minXMargin,.minYMargin])
        cameraTitle = label("",size:21,weight:.light,color:color(0.9,0.95,0.94))
        place(cameraTitle,x:38,y:48,width:420,height:30)
        cameraDetail = label("",size:9,color:cyan,mono:true)
        place(cameraDetail,x:39,y:27,width:430,height:17)
        aceHistory = label("",size:10,color:color(0.8,0.66,0.4),mono:true)
        aceHistory.toolTip = "Distinct pilots who have held the sole Ace title, and the most completed enemy encounters survived by any one pilot in this arena. Records remain after a pilot is lost; a new arena resets them."
        place(aceHistory,x:38,y:130,width:w-76,height:17,mask:[.width])
        aceStatus = label(battle.aceHUDStatus,size:11,weight:.medium,color:color(1,0.78,0.37),mono:true)
        place(aceStatus,x:38,y:150,width:w-76,height:17,mask:[.width])
        telemetry = label("",size:10,color:color(0.45,0.62,0.66),mono:true)
        place(telemetry,x:38,y:107,width:680,height:17)
        autoButton = button("AUTO  ON",action:#selector(toggleAutomatic),tooltip:"Action-directed cinematic camera cuts (A)")
        place(autoButton,x:w-410,y:38,width:93,height:34,mask:[.minXMargin])
        let next = button("NEXT  →",action:#selector(nextCamera),tooltip:"Next camera (C or right arrow)")
        place(next,x:w-305,y:38,width:89,height:34,mask:[.minXMargin])
        pauseButton = button("Ⅱ",action:#selector(togglePause),tooltip:"Pause flight; keep awake stays on (Space)")
        place(pauseButton,x:w-204,y:38,width:44,height:34,mask:[.minXMargin])
        let full = button("⛶",action:#selector(fullscreen),tooltip:"Full screen (F). Double-click the scene to fill / restore the window instead.")
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
        battle.viewportAspect = Float(view.bounds.width/max(1,view.bounds.height))
        let now = ProcessInfo.processInfo.systemUptime
        let dt = Float(min(0.08,now-lastTime)); lastTime = now
        SCNTransaction.begin(); SCNTransaction.animationDuration = 0
        battle.update(dt:dt)
        SCNTransaction.commit()
        if now-lastHUD > 1 {
            lastHUD = now
            let duration = Int(now-startTime)
            telemetry.stringValue = String(format:"%02d %@ / %02d %@   ·   WAVE %02d   ·   %02d:%02d:%02d",battle.sideCount(0),battle.sideFactions[0].fighterName,battle.sideCount(1),battle.sideFactions[1].fighterName,battle.waveNumber,duration/3600,(duration/60)%60,duration%60)
            aceStatus.stringValue = battle.aceHUDStatus
            aceHistory.stringValue = String(format:"ACES EMERGED  %02d   ·   LONGEST SURVIVAL  %d %@",battle.acesEmerged,battle.longestEncounterStreak,battle.longestEncounterStreak == 1 ? "ENCOUNTER" : "ENCOUNTERS")
            sector.stringValue = String(format:"PROCEDURAL ARENA  /  SECTOR %08llX",battle.seed & 0xFFFFFFFF)+"  /  "+(battle.planet?.biome.title ?? "")
            if let city = battle.atlantis, city.intact {
                let shield = Int(ceil(100*Double(city.shieldPoints)/Double(Atlantis.shieldCapacity)))
                let hull = Int(ceil(100*Double(city.hullPoints)/Double(Atlantis.hullCapacity)))
                eventStatus.stringValue = "ATLANTIS   /   SHIELD \(shield)%   /   HULL \(hull)%"
                eventStatus.textColor = shield>0 ? cyan : orange
            } else if battle.returningFromAtlantis {
                eventStatus.stringValue = battle.atlantisRegroupUntil == nil ? "ATLANTIS LOST   /   RETURN TO ASTEROID FIELD" : "ATLANTIS LOST   /   BELT PATROL"
                eventStatus.textColor = orange
            } else if let request = battle.fleetRequests.min(by:{$0.countdown<$1.countdown}) {
                eventStatus.stringValue = String(format:"%@ INBOUND / ETA %02d SEC",battle.sideFactions[request.side].title,max(0,Int(ceil(request.countdown))))
                eventStatus.textColor = cyan
            } else if battle.fighters.contains(where:{$0.state == .arriving && $0.entry == .hyperspace && battle.time>=$0.entryTime-1.25}) {
                eventStatus.stringValue = "X-WING FORMATION EXITING HYPERSPACE"
                eventStatus.textColor = cyan
            } else if let ship = battle.carrier {
                let age = battle.time-ship.start
                if age<0 { eventStatus.stringValue = "\(ship.faction.carrierName) APPROACHING" }
                else if age<ship.arrivalDuration {
                    eventStatus.stringValue = ship.faction.usesJumpWindow ? (ship.faction == .earth ? "JUMP POINT OPENING" : "SHADOW CAPITAL EXITING JUMP POINT") : (ship.faction.usesBlinkFTL ? "FTL DISPLACEMENT DETECTED" : "CAPITAL SHIP EXITING HYPERSPACE")
                }
                else if !ship.departing { eventStatus.stringValue = "\(ship.faction == .earth ? "JUMP POINT" : "HANGAR LAUNCH") / \(ship.faction.fighterName) DEPLOYING" }
                else { eventStatus.stringValue = "\(ship.faction.carrierName) DEPARTING" }
                eventStatus.textColor = cyan
            } else {
                eventStatus.stringValue = String(format:"%03d LOSSES   /   %03d REINFORCEMENTS",battle.destroyed,battle.reinforcements)
                eventStatus.textColor = color(0.4,0.56,0.61)
            }
            hint.isHidden = overlay.bounds.width<1120
            let idle = now-lastActivity > 9
            if !hudHidden { overlay.alphaValue = idle ? 0.34 : 1 }
            updateStatus()
            writeRuntimeStatus()
        }
    }
    func showControls() {
        lastActivity = ProcessInfo.processInfo.systemUptime
        if !hudHidden { overlay.alphaValue = 1 }
    }
    func updateCameraHUD() {
        cameraTitle.stringValue = battle.director.caption ?? battle.cameraNames[battle.cameraIndex]
        cameraDetail.stringValue = battle.director.detail ?? String(format:"CAM %02d / 06   ·   %@",battle.cameraIndex+1,battle.cameraDetails[battle.cameraIndex])
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
        case "r": newArena()
        case "b": nextBiome()
        case "?", "/": showHelp()
        case "\u{1b}": if window.styleMask.contains(.fullScreen) { fullscreen() }
        default: break
        }
    }
    @objc func nextCamera() { battle.nextCamera(); showControls() }
    @objc func toggleAutomatic() {
        battle.automatic.toggle(); battle.cameraAge = 0
        if battle.automatic { battle.director.endEvent(in:battle) }
        updateCameraHUD(); showControls()
    }
    @objc func nextBiome() {
        if let planet = battle.planet { planet.setBiome(PlanetBiome.allCases[(planet.biome.rawValue+1)%PlanetBiome.allCases.count]) }
        showControls()
    }
    @objc func togglePause() {
        battle.paused.toggle(); pauseButton.title = battle.paused ? "▶" : "Ⅱ"
        pauseItem.title = battle.paused ? "Resume Flight" : "Pause Flight"
        view.isPlaying = !battle.paused; view.rendersContinuously = !battle.paused
        showControls()
    }
    @objc func toggleAwake() { if awake.enabled { awake.stop() } else { _ = awake.start() }; updateStatus(); showControls() }
    @objc func toggleHUD() { hudHidden.toggle(); overlay.isHidden = hudHidden; showControls() }
    @objc func fullscreen() { window.toggleFullScreen(nil); showControls() }
    @objc func fillWindow() { if !window.styleMask.contains(.fullScreen) { window.performZoom(nil) }; showControls() }
    @objc func toggleQuality() {
        highQuality.toggle(); view.preferredFramesPerSecond = highQuality ? 60 : 30
        view.antialiasingMode = highQuality ? .multisampling4X : .multisampling2X
        startTimer(); showControls()
    }
    @objc func newArena() {
        let wasPaused = battle.paused, wasAutomatic = battle.automatic
        battle = Dogfight()
        battle.paused = wasPaused; battle.automatic = wasAutomatic
        battle.cameraChanged = { [weak self] in self?.updateCameraHUD() }
        view.scene = battle.scene; view.pointOfView = battle.camera
        aceStatus.stringValue = battle.aceHUDStatus
        updateCameraHUD(); showControls()
    }
    @objc func about() {
        NSApp.orderFrontStandardAboutPanel(options:[.applicationName:"Asteroid Squadron",.applicationVersion:Bundle.main.object(forInfoDictionaryKey:"CFBundleShortVersionString") as? String ?? "",.credits:NSAttributedString(string:"An endless, procedural crossover starfighter dogfight.\nBuilt for quiet company while your agents work.\n\nUnofficial fan project. Star Wars, Battlestar Galactica, Babylon 5 and Stargate belong to their respective owners.")])
    }
    @objc func showHelp() {
        let alert = NSAlert()
        alert.messageText = "Asteroid Squadron"
        alert.informativeText = "Drag the scene to move the window.\nDouble-click the scene to fill / restore the desktop area.\n\nC / →   Next camera\nA          Wide battle / critical-moment director\nF          True full screen (Escape to leave)\nSpace   Pause / resume flight\nH          Show / hide overlay\nK          Toggle keep awake\nJ           Switch 30 / 60 fps\nR          Generate a new random arena\nB          Cycle planet biomes\n⌘Q       Quit and release keep awake\n\nWhen a faction loses its entire squadron, a different faction is randomly selected to replace it. X-wings jump in formation; TIEs launch from an Imperial carrier. Colonial Vipers launch from Galactica and Cylon Raiders from a basestar. BSG capital ships blink into and out of space using FTL. Starfuries and the Shadow capital use blue-black jump windows. After two survived enemy encounters, squadrons replace their losses before the next opponent arrives. A pilot needs three survived encounters, six enemy kills, and a kill count above the previous Ace record. The current Ace carries a gold star. The title can stay vacant until the record is beaten. Without opponents, pilots patrol through and around the belt. Both squadrons attack Atlantis when it appears beyond the field. After its destruction, surviving fighters return to the belt. The HUD records distinct Ace pilots and the longest completed-encounter survival streak in this arena, even after pilots are lost. R resets these arena records. The stars and galactic arms are an infinitely distant procedural skybox. Asteroid strikes can cause a recoverable spin or an explosion.\n\nKeep awake uses caffeinate -d -i while running, paused, or minimized. Closing the window quits and releases its assertions. Default: 30 fps. No audio or network.\n\nUnofficial fan project. Star Wars, Battlestar Galactica, Babylon 5 and Stargate belong to their respective owners."
        alert.addButton(withTitle:"Back to the dogfight")
        alert.beginSheetModal(for:window) { [weak self] _ in self?.window.makeFirstResponder(self?.view) }
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
    func applicationWillTerminate(_ notification: Notification) {
        timer?.invalidate(); awake.stop()
        if let pointerMonitor { NSEvent.removeMonitor(pointerMonitor) }
        if let token = activityToken { ProcessInfo.processInfo.endActivity(token) }
    }
    func windowDidBecomeKey(_ notification: Notification) { window.makeFirstResponder(view) }
    func windowWillUseStandardFrame(_ window: NSWindow, defaultFrame newFrame: NSRect) -> NSRect {
        window.screen?.visibleFrame ?? newFrame
    }
    func windowDidResize(_ notification: Notification) { writeRuntimeStatus() }
    func windowDidMove(_ notification: Notification) { writeRuntimeStatus() }
    func smokeTest() {
        let output = URL(fileURLWithPath:CommandLine.arguments.drop(while:{$0 != "--smoke-test"}).dropFirst().first ?? "/tmp/asteroid-squadron-smoke.png")
        let image = view.snapshot()
        if let tiff = image.tiffRepresentation, let bitmap = NSBitmapImageRep(data:tiff), let png = bitmap.representation(using:.png,properties:[:]) { try? png.write(to:output) }
        // Export the actual NSApplication icon as part of an explicit smoke
        // test, so launch-time overrides and bundled artwork can be checked.
        if let data = NSApp.applicationIconImage?.tiffRepresentation,
           let icon = NSBitmapImageRep(data:data),
           let png = icon.representation(using:.png,properties:[:]) {
            try? png.write(to:output.deletingPathExtension().appendingPathExtension("app-icon.png"))
        }
        writeRuntimeStatus()
    }
    func writeRuntimeStatus() {
        guard CommandLine.arguments.contains("--smoke-test"), let battle, let window else { return }
        let path = CommandLine.arguments.drop(while:{$0 != "--smoke-test"}).dropFirst().first ?? "/tmp/asteroid-squadron-smoke.png"
        let output = URL(fileURLWithPath:path)
        let stats: [String:Any] = ["fighters":battle.activeCount,"asteroids":battle.rocks.count,"clouds":battle.clouds.count,"seed":String(battle.seed),"waves":battle.waveNumber,"reinforcements":battle.reinforcements,"destroyed":battle.destroyed,"keepAwake":awake.enabled,"camera":battle.cameraIndex,"elapsed":battle.time,"shots":battle.shots,"pursuitBreaks":battle.pursuitBreaks,"aces":battle.fighters.filter(\.isAce).filter(\.active).count,"acesEmerged":battle.acesEmerged,"longestEncounterStreak":battle.longestEncounterStreak,"aceKills":battle.fighters.first(where:{$0.isAce})?.enemyKills ?? 0,"encounters":battle.encountersCompleted,"topUpWaves":battle.topUpWaves,"starfuryPivots":battle.starfuryPivots,"windowFrame":NSStringFromRect(window.frame),"visibleScreen":NSStringFromRect(window.screen?.visibleFrame ?? .zero),"isFullScreen":window.styleMask.contains(.fullScreen),"isZoomed":window.isZoomed,"pointerEvent":view?.lastPointerEvent ?? "none","dragEvents":view?.dragEventCount ?? 0,"formationCuts":battle.director.formationCuts,"carrierCuts":battle.director.carrierCuts,"carrierVisits":battle.carrierVisits,"carrierDepartures":battle.carrierDepartures,"factions":battle.sideFactions.map(\.rawValue),"encounteredFactions":battle.encounteredFactions.map(\.rawValue).sorted(),"replacements":battle.replacementCount,"blinkArrivals":battle.blinkArrivals,"blinkDepartures":battle.blinkDepartures,"spinOuts":battle.spinOuts,"shipCollisions":battle.shipCollisions,"shipCollisionLosses":battle.shipCollisionLosses,"recoveries":battle.recoveries,"asteroidLosses":battle.asteroidLosses]
        if let data = try? JSONSerialization.data(withJSONObject:stats,options:[.prettyPrinted,.sortedKeys]) { try? data.write(to:output.deletingPathExtension().appendingPathExtension("json")) }
    }
}

func requestedSeed() -> UInt64 {
    if let i = CommandLine.arguments.firstIndex(of:"--seed"), i+1<CommandLine.arguments.count, let seed = UInt64(CommandLine.arguments[i+1]) { return seed }
    return UInt64.random(in:1...UInt64.max)
}

if CommandLine.arguments.contains("--verify-stargate") {
    let args = CommandLine.arguments
    let output = args.firstIndex(of:"--render-stargate-review").flatMap { index in
        index+1<args.count ? URL(fileURLWithPath:args[index+1]) : nil
    }
    verifyStargate(renderDirectory:output)
} else if CommandLine.arguments.contains("--verify-veterans") {
    verifyVeteransAndSkybox()
} else if let index = CommandLine.arguments.firstIndex(of:"--render-veteran-review"), index+1<CommandLine.arguments.count {
    renderVeteranReview(directory:URL(fileURLWithPath:CommandLine.arguments[index+1]))
} else if CommandLine.arguments.contains("--verify-simulation") {
    verifySimulation()
} else if CommandLine.arguments.contains("--verify-babylon") {
    verifyBabylon()
} else if let index = CommandLine.arguments.firstIndex(of:"--render-babylon-review"), index+1<CommandLine.arguments.count {
    renderBabylonReview(directory:URL(fileURLWithPath:CommandLine.arguments[index+1]))
} else if CommandLine.arguments.contains("--verify-pursuit") {
    verifyPursuitLimits()
} else if CommandLine.arguments.contains("--combat-benchmark") {
    combatBenchmark()
} else if let index = CommandLine.arguments.firstIndex(of:"--render-planet-review"), index+1<CommandLine.arguments.count {
    renderPlanetReview(directory:URL(fileURLWithPath:CommandLine.arguments[index+1]))
} else if let index = CommandLine.arguments.firstIndex(of:"--render-review"), index+1<CommandLine.arguments.count {
    renderReview(directory:URL(fileURLWithPath:CommandLine.arguments[index+1]))
} else {
    let app = NSApplication.shared
    let delegate = App()
    app.delegate = delegate
    app.run()
}
