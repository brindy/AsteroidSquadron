import AppKit
import SceneKit
import simd

// Procedural Aurora: a short cockpit suspended between four swept engine arms.
// As with every fighter, local -Z is the gun axis; thrusters never aim the shots.
func starfury() -> SCNNode {
    let root = SCNNode()
    let armor = material(color(0.48,0.51,0.49),metal:0.65)
    let edge = material(color(0.67,0.69,0.63),metal:0.5)
    let dark = material(color(0.055,0.065,0.075),metal:0.7)
    let glass = material(color(0.018,0.07,0.10),metal:0.9)
    let marking = material(color(0.63,0.31,0.065),metal:0.3)
    let glow = material(color(0.4,0.7,1),emission:color(0.7,1.4,2.5))
    root.addChildNode(box(V3(1.8,2.2,2.8),armor,V3(0,0,0.2),chamfer:0.45))
    root.addChildNode(box(V3(1.32,1.5,0.38),glass,V3(0,0.15,-1.27),chamfer:0.18))
    for x: Float in [-0.65,0,0.65] { root.addChildNode(segment(V3(x,-0.62,-1.5),V3(x,0.88,-1.5),radius:0.045,mat:edge)) }
    root.addChildNode(segment(V3(-0.7,0.2,-1.51),V3(0.7,0.2,-1.51),radius:0.045,mat:edge))
    for sx: Float in [-1,1] { for sy: Float in [-1,1] {
        let arm = SCNNode()
        arm.simdPosition = V3(sx*2.45,sy*1.85,0.65)
        arm.simdEulerAngles.z = sx*sy*0.58
        arm.addChildNode(box(V3(4.6,0.42,1.6),armor,chamfer:0.12))
        arm.addChildNode(box(V3(3.7,0.045,0.3),edge,V3(0,sy*0.23,-0.48)))
        arm.addChildNode(box(V3(0.6,0.46,1.65),marking,V3(sx*0.85,0,0)))
        root.addChildNode(arm)
        let p = V3(sx*4.5,sy*3.2,0.9)
        root.addChildNode(box(V3(1.3,1.15,3.8),armor,p,chamfer:0.24))
        root.addChildNode(box(V3(1.35,0.18,1.2),dark,p+V3(0,sy*0.55,0.4)))
        for z: Float in [-0.8,0,0.8] { root.addChildNode(box(V3(1.34,0.08,0.18),edge,p+V3(0,sy*0.5,z))) }
        root.addChildNode(cylinder(0.48,0.2,dark,p+V3(0,0,2)))
        let drive = cylinder(0.33,0.10,glow,p+V3(0,0,2.13)); drive.name = "drive.\(sx).\(sy)"; root.addChildNode(drive)
        root.addChildNode(EngineNozzle(at:p+V3(0,0,2.18),radius:0.33,tint:V3(0.24,0.57,1)))
        root.addChildNode(cylinder(0.25,0.18,dark,p+V3(0,0,-1.98)))
        // Small directional control jets give the pivot a visible physical cause.
        let jet = node(SCNSphere(radius:1),glow,p+V3(sx*0.7,sy*0.35,0))
        jet.simdScale = V3(0.38,0.12,0.12); jet.name = "rcs.\(sx).\(sy)"; jet.opacity = 0
        root.addChildNode(jet)
        let gun = V3(sx*3.5,sy*2.4,-1.1)
        root.addChildNode(cylinder(0.12,1.6,dark,gun))
        root.addChildNode(cylinder(0.075,0.5,edge,gun+V3(0,0,-0.95)))
        addMuzzle(to:root,at:gun+V3(0,0,-1.24),name:"\(sx).\(sy)")
    } }
    return root
}
