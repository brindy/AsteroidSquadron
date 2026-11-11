import AppKit
import SceneKit
import simd

func imperialCarrier() -> SCNNode {
    let root = SCNNode()
    let hull = material(color(0.43,0.48,0.52),metal:0.6)
    let upper = material(color(0.58,0.62,0.63),metal:0.4)
    let dark = material(color(0.035,0.05,0.065),metal:0.5)
    let blue = material(color(0.3,0.6,1),emission:color(0.6,1.4,2.6))
    root.addChildNode(hullMesh([V3(0,0,-115),V3(-64,0,94),V3(64,0,94),V3(0,11,-80),V3(-59,11,90),V3(59,11,90),V3(0,-9,-83),V3(-56,-9,90),V3(56,-9,90)],faces:[[3,4,5],[6,8,7],[0,1,4,3],[0,3,5,2],[1,2,5,4],[0,6,7,1],[0,2,8,6],[1,7,8,2]],mat:hull))
    // Terraced superstructure and the unmistakable bridge tower.
    for (w,h,l,y,z) in [(80.0,8.0,90.0,15.0,43.0),(58,7,66,22.5,49),(35,7,44,29.5,55)] {
        root.addChildNode(box(V3(Float(w),Float(h),Float(l)),upper,V3(0,Float(y),Float(z)),chamfer:1))
    }
    root.addChildNode(box(V3(13,22,13),hull,V3(0,42,69)))
    root.addChildNode(box(V3(47,8,13),upper,V3(0,53,68),chamfer:1))
    root.addChildNode(box(V3(43,1.3,0.3),blue,V3(0,54,61.3)))
    for x: Float in [-16,16] {
        root.addChildNode(segment(V3(x,57,68),V3(x,63,68),radius:0.7,mat:hull))
        let dome = SCNSphere(radius:3.5); dome.segmentCount = 12
        root.addChildNode(node(dome,upper,V3(x,64,68)))
    }
    // A recessed, illuminated ventral hangar; TIE launch coordinates use this bay.
    root.addChildNode(box(V3(37,1,48),dark,V3(0,-9.6,27)))
    for x: Float in [-19,19] { root.addChildNode(box(V3(0.7,0.5,47),blue,V3(x,-10.3,27))) }
    root.addChildNode(box(V3(37,0.4,0.7),blue,V3(0,-10.3,3)))
    for x: Float in [-31,0,31] {
        root.addChildNode(cylinder(x == 0 ? 12 : 9,5,dark,V3(x,0,96)))
        root.addChildNode(cylinder(x == 0 ? 10 : 7.5,0.6,blue,V3(x,0,99)))
    }
    for side: Float in [-1,1] {
        for row in 0..<7 {
            let z = Float(row)*21-50
            let x = side*(z+115)*0.285
            root.addChildNode(box(V3(1,0.55,8),dark,V3(x,12,z)))
            if row>3 {
                root.addChildNode(box(V3(5,3,6),dark,V3(x,15,z)))
                root.addChildNode(segment(V3(x,16,z),V3(x,16,z-9),radius:0.45,mat:hull))
            }
            root.addChildNode(box(V3(0.65,0.6,2),blue,V3(side*(z+115)*0.30,0,z)))
        }
    }
    return root
}

func monCalamariCruiser() -> SCNNode {
    let root = SCNNode()
    let armor = material(color(0.53,0.48,0.39),metal:0.45)
    let panels = material(color(0.36,0.35,0.32),metal:0.5)
    let lights = material(color(0.57,0.78,1),emission:color(0.65,1.5,2.4))
    func lobe(_ center: V3, _ axes: V3, _ surface: SCNMaterial) {
        let body = node(SCNSphere(radius:1),surface,center)
        body.simdScale = axes
        root.addChildNode(body)
    }
    lobe(.zero,V3(36,21,127),armor)
    lobe(V3(0,16,-44),V3(22,11,35),armor)
    for side: Float in [-1,1] {
        lobe(V3(side*29,0,23),V3(32,18,82),armor)
        for row in 0..<5 {
            let z = -34+Float(row)*23
            lobe(V3(side*(26+Float(row%2)*8),13,z),V3(14,7,19),panels)
            root.addChildNode(box(V3(2,1,6),lights,V3(side*43,15,z)))
        }
    }
    for x: Float in [-38,-17,17,38] {
        let z: Float = abs(x)>20 ? 96 : 106
        root.addChildNode(cylinder(9,14,panels,V3(x,0,z)))
        root.addChildNode(cylinder(7.5,2,lights,V3(x,0,z+8)))
    }
    return root
}

func omegaDestroyer() -> SCNNode {
    let root = SCNNode()
    let armor = material(color(0.48,0.49,0.50),metal:0.52)
    let dark = material(color(0.14,0.17,0.21),metal:0.48)
    let lights = material(color(0.36,0.63,1),emission:color(0.65,1.35,2.6))
    root.addChildNode(armoredLoft([(-131,26,14,0),(-86,30,17,0),(-56,19,12,0),(82,20,13,0),(109,28,20,0),(127,26,18,0)],mat:armor))
    root.addChildNode(box(V3(38,19,1.1),dark,V3(0,0,-131.2)))
    root.addChildNode(box(V3(32,1.1,1.5),lights,V3(0,8,-132)))
    let habitat = SCNNode()
    habitat.addChildNode(cylinder(19,42,dark,V3(0,0,13)))
    for side: Float in [-1,1] {
        habitat.addChildNode(box(V3(34,25,39),armor,V3(side*33,0,13),chamfer:3))
        habitat.addChildNode(box(V3(25,1,12),lights,V3(side*33,12.6,5)))
        for y: Float in [-11,11] {
            root.addChildNode(cylinder(9,10,dark,V3(side*15,y,127)))
            root.addChildNode(cylinder(7,2,lights,V3(side*15,y,133)))
        }
    }
    let spin = CABasicAnimation(keyPath:"rotation")
    spin.fromValue = NSValue(scnVector4:SCNVector4(0,0,1,0))
    spin.toValue = NSValue(scnVector4:SCNVector4(0,0,1,2*Double.pi))
    spin.duration = 15; spin.repeatCount = .infinity
    habitat.addAnimation(spin,forKey:"habitat-spin")
    root.addChildNode(habitat)
    return root
}

final class Carrier {
    let node: SCNNode
    let faction: Faction
    let side: Int
    let warp: SCNNode
    let jumpWindow: JumpWindow?
    // Siege batteries attach to the model before the first transit frame.
    private(set) lazy var jumpClipper: JumpClipper? =
        faction.usesJumpWindow && (faction != .earth || squadron.isEmpty) ? JumpClipper(root:node) : nil
    let origin: V3
    let forward: V3
    let start: Float
    let squadron: [Int]
    let framingPoints: [V3]
    var announced = false
    var departing = false
    var departureAge: Float { lastLaunchAge+0.18 }
    var lastLaunchAge: Float { 2.5+Float(max(0,squadron.count-1))*0.35 }
    var departureDuration: Float { faction == .earth ? 0.7 : (faction == .shadow ? 2.6 : (faction.usesBlinkFTL ? 0.65 : 1.5)) }
    let scale: Float = 6
    var blinkEntered = false
    var blinkExited = false
    var arrivalDuration: Float { faction.usesJumpWindow ? 2.1 : (faction.usesBlinkFTL ? 0.85 : 1.4) }
    var cameraBounds: V3 {
        switch faction { case .colonial: return V3(84,30,130); case .cylon: return V3(158,30,158); case .shadow: return V3(180,24,170); case .earth: return squadron.isEmpty ? V3(55,36,135) : V3(37,37,1); case .rebel: return V3(65,34,131); case .tauri: return V3(73,36,145); case .goauld: return V3(106,74,106); case .wraith: return V3(101,50,162); default: return V3(77,44,130) }
    }
    // The Imperial bridge is above the hull. Centering its exclusion volume at
    // the origin incorrectly blocked empty space beneath the launch bay.
    var cameraCenter: V3 {
        if faction == .empire { return V3(0,26,0) }
        if faction == .goauld { return V3(0,39,0) }
        return .zero
    }
    var cameraVolumes: [(V3,V3)] {
        switch faction {
        case .tauri:
            return [(V3(0,2,-4),V3(34,32,140)),
                    (V3(-51,-5,-7),V3(18,12,80)),
                    (V3(51,-5,-7),V3(18,12,80))]
        case .wraith:
            return [(V3(0,3,0),V3(62,39,154)),
                    (V3(-51,0,6),V3(33,22,130)),
                    (V3(51,0,6),V3(33,22,130))]
        default:
            return [(cameraCenter,cameraBounds)]
        }
    }
    var framingScale: Float { (faction == .cylon ? 1.4 : (faction == .colonial ? 1.12 : 1))*scale }
    var worldRadius: Float { max(cameraBounds.x,max(cameraBounds.y,cameraBounds.z))*scale }
    init(faction: Faction = .empire, side: Int = 1, origin: V3, forward: V3, start: Float, squadron: [Int]) {
        self.faction = faction; self.side = side
        let portalOnly = faction == .earth && !squadron.isEmpty
        node = portalOnly ? SCNNode() : faction.capitalModel()
        self.origin = origin; self.forward = forward; self.start = start; self.squadron = squadron
        let modelRoot = node
        var corners = [V3]()
        node.enumerateChildNodes { child,_ in
            guard let geometry = child.geometry else { return }
            let bounds = geometry.boundingBox, lo = V3(bounds.min), hi = V3(bounds.max)
            for x in [lo.x,hi.x] { for y in [lo.y,hi.y] { for z in [lo.z,hi.z] {
                corners.append(child.simdConvertPosition(V3(x,y,z),to:modelRoot))
            } } }
        }
        // Cache the model's support points instead of framing empty corners of
        // one enormous bounding box around a long hull or six-armed basestar.
        var silhouette = [V3]()
        for x: Float in [-1,0,1] { for y: Float in [-1,0,1] { for z: Float in [-1,0,1] {
            let direction = V3(x,y,z)
            if direction != .zero, let point = corners.max(by:{simd_dot($0,direction)<simd_dot($1,direction)}), !silhouette.contains(point) { silhouette.append(point) }
        } } }
        if portalOnly {
            silhouette = [V3(-37,-37,0),V3(-37,37,0),V3(37,-37,0),V3(37,37,0)]
        }
        framingPoints = silhouette
        if faction.usesJumpWindow {
            let window = JumpWindow(radius:portalOnly ? 220 : 1250,forward:forward)
            jumpWindow = window; warp = window.node
        } else {
            jumpWindow = nil
            warp = box(V3(3,3,1),material(color(0.5,0.8,1),emission:color(1,2,3)))
        }
        node.isHidden = true; warp.isHidden = true
        node.simdScale = V3(repeating:scale)
        node.look(at:SCNVector3(forward),up:SCNVector3(0,1,0),localFront:SCNVector3(0,0,-1))
    }
    func station(_ age: Float) -> V3 { (faction.usesBlinkFTL || faction.usesJumpWindow) ? origin : origin+forward*max(0,min(departureAge-1.4,age-1.4))*3 }
    func launchPosition(slot: Int, at age: Float) -> V3 {
        let sign: Float = slot%2 == 0 ? -1 : 1
        let port: V3
        switch faction {
        case .colonial: port = V3(sign*57,-3,-90)
        case .cylon: port = V3(sign*20,-34,-30)
        case .shadow: port = V3(sign*22,-32,-56)
        case .earth: port = V3(sign*(4+Float(slot/2)*3),Float(slot%3-1)*3,0)
        case .tauri: port = V3(sign*51,-6,-87)
        case .goauld: port = V3(sign*29,-18,-74)
        case .wraith: port = V3(sign*32,-22,-93)
        default: port = V3(sign*11,-16,15)
        }
        return station(age)+node.simdOrientation.act(port*scale)
    }
}
