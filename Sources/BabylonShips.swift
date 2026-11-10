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

// A closed, smooth tube following a curved spine, tapering to a needle tip.
private func shadowSpine(_ points: [V3], radius: Float, mat: SCNMaterial) -> SCNNode {
    let rings = 22, slices = 8
    var vertices = [SCNVector3](), normals = [SCNVector3](), indices = [Int32]()
    func curve(_ t: Float) -> V3 {
        let u = 1-t
        // Keep vector overload resolution small on the older Swift compilers
        // used by hosted runners. Preserve the original arithmetic order.
        let a: V3 = points[0]*u*u*u
        let b: V3 = points[1]*3*u*u*t
        let c: V3 = points[2]*3*u*t*t
        let d: V3 = points[3]*t*t*t
        return a+b+c+d
    }
    for i in 0...rings {
        let t = Float(i)/Float(rings), p = curve(t)
        let tangent = unit(curve(min(1,t+0.002))-curve(max(0,t-0.002)))
        let right = unit(simd_cross(tangent,abs(tangent.y)<0.9 ? V3(0,1,0) : V3(1,0,0)))
        let up = unit(simd_cross(right,tangent))
        let width = max(0.008,radius*pow(1-t,0.85)*(1+0.12*sin(t*30)))
        for j in 0...slices {
            let a = Float(j%slices)*tau/Float(slices), n = right*cos(a)+up*sin(a)
            vertices.append(SCNVector3(p+n*width)); normals.append(SCNVector3(n))
        }
    }
    for i in 0..<rings { for j in 0..<slices {
        let a = Int32(i*(slices+1)+j), b = a+Int32(slices+1)
        indices += [a,b,a+1,a+1,b,b+1]
    } }
    // Ends are capped; a tiny final ring keeps triangles nondegenerate.
    for j in 1..<(slices-1) {
        indices += [0,Int32(j+1),Int32(j)]
        let end = Int32(rings*(slices+1)); indices += [end,end+Int32(j),end+Int32(j+1)]
    }
    let g = SCNGeometry(sources:[SCNGeometrySource(vertices:vertices),SCNGeometrySource(normals:normals)],elements:[SCNGeometryElement(indices:indices,primitiveType:.triangles)])
    return node(g,mat)
}

private func shadowSkin() -> SCNMaterial {
    let m = material(color(0.085,0.065,0.105),metal:0.75)
    m.roughness.contents = 0.46
    m.shaderModifiers = [.surface:"""
    #pragma body
    float3 p = (scn_node.inverseModelViewTransform * float4(_surface.position,1.0)).xyz * 2.7;
    float veins = pow(abs(sin(p.x*2.1+sin(p.y*2.8))*sin(p.z*3.2+cos(p.x))),12.0);
    _surface.diffuse.rgb *= 0.65 + 0.55*veins;
    _surface.emission.rgb = float3(0.045,0.015,0.065)*veins;
    """]
    return m
}

func shadowFighter() -> SCNNode {
    let root = SCNNode(), skin = shadowSkin()
    let body = node(SCNSphere(radius:1),skin,V3(0,0,0.4)); body.simdScale = V3(1.5,0.75,2.4); root.addChildNode(body)
    for side: Float in [-1,1] {
        root.addChildNode(shadowSpine([V3(side*0.8,0,1.4),V3(side*4.7,0.5,3.2),V3(side*6.8,0.2,-0.5),V3(side*3.6,0,-4.7)],radius:0.85,mat:skin))
        root.addChildNode(shadowSpine([V3(side*1,0,0),V3(side*3.4,-0.3,-1.7),V3(side*2.6,0.2,-4.5),V3(side*1.3,0,-5.8)],radius:0.45,mat:skin))
        let eye = material(color(0.5,0.08,0.65),emission:color(1.2,0.05,1.5))
        root.addChildNode(cylinder(0.13,0.13,eye,V3(side*1.05,0,-1.8)))
        addMuzzle(to:root,at:V3(side*1.05,0,-1.95),name:"\(side)")
    }
    return root
}

func shadowCapital() -> SCNNode {
    let root = SCNNode(), skin = shadowSkin()
    let body = node(SCNSphere(radius:1),skin); body.simdScale = V3(43,15,61); root.addChildNode(body)
    for side: Float in [-1,1] { for i in 0..<4 {
        let z = Float(i)*29-43
        let reach = Float(152-i*12)
        root.addChildNode(shadowSpine([V3(side*25,0,z),V3(side*reach,Float(i%2)*20+12,z+35),V3(side*(reach+13),-15,z-45),V3(side*(reach-17),-5,z-105)],radius:Float(12-i),mat:skin))
        // Ribbed carapace / dark violet seams rather than a featureless black blob.
        root.addChildNode(shadowSpine([V3(side*12,12,z),V3(side*40,20,z+12),V3(side*64,9,z+9),V3(side*72,2,z-9)],radius:2,mat:skin))
    } }
    let bay = material(color(0.24,0.035,0.32),emission:color(0.42,0.025,0.6))
    for side: Float in [-1,1] {
        let opening = node(SCNSphere(radius:1),bay,V3(side*22,-14,-39)); opening.simdScale = V3(10,1.5,12); root.addChildNode(opening)
    }
    return root
}
