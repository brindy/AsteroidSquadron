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

final class Carrier {
    let node = imperialCarrier()
    let warp: SCNNode
    let origin: V3
    let forward: V3
    let start: Float
    let squadron: [Int]
    var announced = false
    var departing = false
    init(origin: V3, forward: V3, start: Float, squadron: [Int]) {
        self.origin = origin; self.forward = forward; self.start = start; self.squadron = squadron
        warp = box(V3(3,3,1),material(color(0.5,0.8,1),emission:color(1,2,3)))
        node.isHidden = true; warp.isHidden = true
        node.look(at:SCNVector3(forward),up:SCNVector3(0,1,0),localFront:SCNVector3(0,0,-1))
    }
    func station(_ age: Float) -> V3 { origin+forward*max(0,min(8.6,age-1.4))*3 }
}
