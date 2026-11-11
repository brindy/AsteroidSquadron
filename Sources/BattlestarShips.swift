import AppKit
import SceneKit
import simd

func armoredLoft(_ sections: [(Float,Float,Float,Float)], mat: SCNMaterial) -> SCNNode {
    var vertices: [V3] = [], flat: [SCNVector3] = [], normals: [SCNVector3] = [], topology: [Int] = []
    let profile: [(Float,Float)] = [(0.65,1),(1,0.5),(1,-0.5),(0.65,-1),(-0.65,-1),(-1,-0.5),(-1,0.5),(-0.65,1)]
    for (z,w,h,y) in sections { vertices += profile.map { V3($0.0*w,y+$0.1*h,z) } }
    func face(_ ids: [Int], reference: V3) {
        for i in 1..<(ids.count-1) {
            var ids = [ids[0],ids[i],ids[i+1]]
            var n = unit(simd_cross(vertices[ids[1]]-vertices[ids[0]],vertices[ids[2]]-vertices[ids[0]]))
            let center = (vertices[ids[0]]+vertices[ids[1]]+vertices[ids[2]])/3
            if simd_dot(n,center-reference)<0 { ids.swapAt(1,2); n = -n }
            topology += ids
            flat += ids.map{SCNVector3(vertices[$0])}
            normals += Array(repeating:SCNVector3(n),count:3)
        }
    }
    // A bent loft is not globally convex: each ring pair needs its own interior
    // reference, otherwise a whole-arm centroid can turn individual faces inside out.
    face(Array(0..<8),reference:V3(0,sections[1].3,sections[1].0))
    face(Array((vertices.count-8)..<vertices.count),reference:V3(0,sections[sections.count-2].3,sections[sections.count-2].0))
    for ring in 0..<(sections.count-1) { for i in 0..<8 {
        let a = ring*8+i, b = ring*8+(i+1)%8
        let center = V3(0,(sections[ring].3+sections[ring+1].3)/2,(sections[ring].0+sections[ring+1].0)/2)
        face([a,b,b+8,a+8],reference:center)
    } }
    if CommandLine.arguments.contains("--verify-simulation") {
        var edges: [String:(Int,Int)] = [:]
        for i in stride(from:0,to:topology.count,by:3) { for j in 0..<3 {
            let a = topology[i+j], b = topology[i+(j+1)%3]
            let key = "\(min(a,b))/\(max(a,b))", prior = edges[key] ?? (0,0)
            edges[key] = (prior.0+1,prior.1+(a<b ? 1 : -1))
        } }
        if !edges.values.allSatisfy({$0.0 == 2 && $0.1 == 0}) {
            print("FAIL: capital-ship loft contains an open or reversed face"); fflush(stdout); exit(1)
        }
    }
    let geometry = SCNGeometry(sources:[SCNGeometrySource(vertices:flat),SCNGeometrySource(normals:normals)],elements:[SCNGeometryElement(indices:Array(0..<Int32(flat.count)),primitiveType:.triangles)])
    return node(geometry,mat)
}

private func raiderWing(sign: Float, mat: SCNMaterial) -> SCNNode {
    let spans = 24, chords = 8, row = chords+1
    let layer = (spans+1)*row
    var vertices: [V3] = [], indices: [Int32] = []
    for side in 0..<2 { for i in 0...spans { for j in 0...chords {
        let s = Float(i)/Float(spans), v = Float(j)/Float(chords)
        let sweep = pow(s,2.2), front = -1-4.8*sweep, back = 2.2-8*sweep
        let arch = sin(s*Float.pi)*sin(v*Float.pi)
        let thickness = 0.08+0.22*(1-s)
        let y = side == 0 ? thickness+arch*0.42 : -thickness*0.65+arch*0.18
        vertices.append(V3(sign*s*6.4,y,front+(back-front)*v))
    } } }
    func quad(_ a: Int,_ b: Int,_ c: Int,_ d: Int,_ outward: V3) {
        for triple in [[a,b,c],[a,c,d]] {
            var t = triple
            if simd_dot(simd_cross(vertices[t[1]]-vertices[t[0]],vertices[t[2]]-vertices[t[0]]),outward)<0 { t.swapAt(1,2) }
            indices += t.map(Int32.init)
        }
    }
    for i in 0..<spans { for j in 0..<chords {
        let a = i*row+j
        quad(a,a+row,a+row+1,a+1,V3(0,1,0))
        quad(a+layer,a+row+layer,a+row+1+layer,a+1+layer,V3(0,-1,0))
    } }
    for i in 0..<spans {
        let a = i*row, b = (i+1)*row
        quad(a,b,b+layer,a+layer,V3(0,0,-1))
        quad(a+chords,b+chords,b+chords+layer,a+chords+layer,V3(0,0,1))
    }
    for j in 0..<chords {
        quad(j,j+1,j+1+layer,j+layer,V3(-sign,0,0))
        let a = spans*row+j
        quad(a,a+1,a+1+layer,a+layer,V3(sign,0,0))
    }
    var normals = Array(repeating:V3.zero,count:vertices.count)
    for i in stride(from:0,to:indices.count,by:3) {
        let a = Int(indices[i]), b = Int(indices[i+1]), c = Int(indices[i+2])
        let n = simd_cross(vertices[b]-vertices[a],vertices[c]-vertices[a])
        normals[a] += n; normals[b] += n; normals[c] += n
    }
    let geometry = SCNGeometry(sources:[SCNGeometrySource(vertices:vertices.map(SCNVector3.init)),SCNGeometrySource(normals:normals.map{SCNVector3(unit($0))})],elements:[SCNGeometryElement(indices:indices,primitiveType:.triangles)])
    return node(geometry,mat)
}

// All craft face local -Z, like the existing fighters. Models are generated locally.
func colonialViper() -> SCNNode {
    let root = SCNNode()
    let ivory = material(color(0.77,0.79,0.73),metal:0.35)
    let armor = material(color(0.42,0.46,0.45),metal:0.65)
    let red = material(color(0.52,0.055,0.025),metal:0.2)
    let dark = material(color(0.035,0.045,0.055),metal:0.65)
    let glass = material(color(0.015,0.055,0.075),metal:0.9)
    let exhaust = material(color(0.65,0.75,1),emission:color(1.2,1.6,2.5))
    root.addChildNode(hullMesh([
        V3(-0.7,-0.45,1.8),V3(0.7,-0.45,1.8),V3(0.6,0.55,1.8),V3(-0.6,0.55,1.8),
        V3(-0.13,-0.16,-6.8),V3(0.13,-0.16,-6.8),V3(0.13,0.03,-6.8),V3(-0.13,0.03,-6.8)
    ],faces:[[0,1,2,3],[4,7,6,5],[0,4,5,1],[3,2,6,7],[0,3,7,4],[1,5,6,2]],mat:ivory))
    let stripe = box(V3(0.22,0.025,5.25),red,V3(0,0.25,-4.05))
    stripe.simdEulerAngles.x = -0.060
    root.addChildNode(stripe)
    root.addChildNode(box(V3(0.88,0.65,2.0),dark,V3(0,0.64,-1.4),chamfer:0.2))
    root.addChildNode(box(V3(0.72,0.43,1.8),glass,V3(0,0.85,-1.45),chamfer:0.14))
    for z: Float in [-2.1,-1.2,-0.55] { root.addChildNode(box(V3(0.82,0.06,0.055),ivory,V3(0,1.07,z))) }
    for p in [V3(-0.95,-0.25,1.2),V3(0.95,-0.25,1.2),V3(0,0.95,1.55)] {
        root.addChildNode(cylinder(0.5,3.7,ivory,p))
        root.addChildNode(cylinder(0.39,0.08,dark,p+V3(0,0,-1.9)))
        root.addChildNode(cylinder(0.25,0.10,armor,p+V3(0,0,-1.96)))
        root.addChildNode(cylinder(0.4,0.24,armor,p+V3(0,0,1.93)))
        root.addChildNode(cylinder(0.31,0.1,exhaust,p+V3(0,0,2.07)))
        let plume = node(SCNSphere(radius:1),exhaust,p+V3(0,0,2.45))
        plume.simdScale = V3(0.21,0.21,0.6); root.addChildNode(plume)
        for z: Float in [-0.2,0.35,0.9] { root.addChildNode(cylinder(0.505,0.04,armor,p+V3(0,0,z))) }
    }
    for sign: Float in [-1,1] {
        let wing = hullMesh([V3(sign*0.7,-0.12,-0.6),V3(sign*3.9,-0.33,1.05),V3(sign*3.5,-0.33,2.8),V3(sign*0.7,-0.12,2.6),V3(sign*0.7,-0.27,-0.6),V3(sign*3.9,-0.47,1.05),V3(sign*3.5,-0.47,2.8),V3(sign*0.7,-0.27,2.6)],faces:[[0,1,2,3],[4,7,6,5],[0,4,5,1],[1,5,6,2],[2,6,7,3],[3,7,4,0]],mat:ivory)
        root.addChildNode(wing)
        root.addChildNode(box(V3(0.6,0.025,1.5),red,V3(sign*2.7,-0.32,1.6)))
        root.addChildNode(cylinder(0.105,4.5,armor,V3(sign*3.45,-0.30,0.1)))
        root.addChildNode(cylinder(0.06,1.25,dark,V3(sign*3.45,-0.30,-2.5)))
        addMuzzle(to:root,at:V3(sign*3.45,-0.30,-3.22),name:"\(sign)")
        root.addChildNode(box(V3(0.45,0.2,0.55),armor,V3(sign*1.6,-0.5,1.3)))
    }
    root.addChildNode(hullMesh([V3(-0.12,1.0,0.5),V3(-0.12,2.8,1.9),V3(-0.12,2.5,3.2),V3(-0.12,0.9,3.2),V3(0.12,1,0.5),V3(0.12,2.8,1.9),V3(0.12,2.5,3.2),V3(0.12,0.9,3.2)],faces:[[0,1,2,3],[4,7,6,5],[0,4,5,1],[1,5,6,2],[2,6,7,3],[3,7,4,0]],mat:red))
    return root
}

func cylonRaider() -> SCNNode {
    let root = SCNNode()
    let metal = material(color(0.34,0.39,0.42),metal:0.8)
    let edge = material(color(0.55,0.6,0.6),metal:0.8)
    let dark = material(color(0.055,0.065,0.075),metal:0.6)
    let glow = material(color(1,0.035,0.01),emission:color(3,0.025,0.005))
    // Closed, smooth, curved wings taper into forward-pointing crescent tips.
    metal.roughness.contents = 0.38
    root.addChildNode(raiderWing(sign:-1,mat:metal))
    root.addChildNode(raiderWing(sign:1,mat:metal))
    let head = node(SCNSphere(radius:1),metal,V3(0,0.22,-0.7))
    head.simdScale = V3(1.05,0.6,1.4); root.addChildNode(head)
    root.addChildNode(box(V3(1.3,0.14,0.12),dark,V3(0,0.24,-2.0),chamfer:0.04))
    root.addChildNode(box(V3(1.15,0.045,0.13),material(color(0.38,0.01,0),emission:color(0.5,0.005,0)),V3(0,0.24,-2.08)))
    let eye = box(V3(0.22,0.06,0.15),glow,V3(0,0.24,-2.10),chamfer:0.02)
    eye.name = "scanner"; root.addChildNode(eye)
    func wingSurface(_ x: Float,_ v: Float,_ sign: Float) -> V3 {
        let s = x/6.4, sweep = pow(s,2.2)
        let front = -1-4.8*sweep, back = 2.2-8*sweep
        let y = 0.08+0.22*(1-s)+sin(s*Float.pi)*sin(v*Float.pi)*0.42+0.025
        return V3(sign*x,y,front+(back-front)*v)
    }
    for s: Float in [-1,1] {
        for i in 0..<5 {
            let x = Float(i)*0.74+1.6
            root.addChildNode(segment(wingSurface(x,0.3,s),wingSurface(x+0.25,0.8,s),radius:0.025,mat:dark))
        }
        for i in 0..<8 {
            let x = 0.8+Float(i)*0.55
            root.addChildNode(segment(wingSurface(x,0.12,s),wingSurface(x+0.55,0.12,s),radius:0.025,mat:edge))
        }
        root.addChildNode(cylinder(0.13,1.0,dark,V3(s*2.5,-0.2,-1.3)))
        addMuzzle(to:root,at:V3(s*2.5,-0.2,-1.88),name:"\(s)")
        root.addChildNode(cylinder(0.2,0.1,material(color(0.4,0.6,1),emission:color(0.35,0.7,1.4)),V3(s*1.6,-0.18,1.8)))
    }
    return root
}

func battlestarGalactica() -> SCNNode {
    let root = SCNNode()
    let hull = material(color(0.35,0.38,0.39),metal:0.6)
    let plates = material(color(0.48,0.49,0.46),metal:0.45)
    let ribs = material(color(0.19,0.23,0.24),metal:0.65)
    let dark = material(color(0.018,0.025,0.03),metal:0.4)
    let red = material(color(0.35,0.035,0.02),metal:0.2)
    let light = material(color(0.75,0.8,0.9),emission:color(0.7,0.9,1.3))
    root.addChildNode(box(V3(38,22,153),hull,V3(0,0,18),chamfer:9))
    root.addChildNode(armoredLoft([(-119,14,5,0),(-113,24,8,0),(-88,29,11,0),(-47,23,9,0),(-36,19,8,0)],mat:plates))
    for z in stride(from:Float(-105),through:-48,by:10) {
        root.addChildNode(box(V3(42,0.7,2),ribs,V3(0,10,z),chamfer:0.2))
    }
    root.addChildNode(box(V3(25,9,37),hull,V3(0,15,-24),chamfer:4))
    root.addChildNode(box(V3(14,6,18),plates,V3(0,22,-26),chamfer:2))
    root.addChildNode(box(V3(10,0.6,0.5),light,V3(0,23,-35)))
    for side: Float in [-1,1] {
        for z: Float in [-38,38] { root.addChildNode(box(V3(38,8,13),ribs,V3(side*35,-2,z),chamfer:2)) }
        let pod = box(V3(25,14,166),hull,V3(side*57,-3,1),chamfer:6)
        root.addChildNode(pod)
        root.addChildNode(box(V3(18,8,1.0),dark,V3(side*57,-3,-82.2)))
        root.addChildNode(box(V3(18,0.45,1.0),light,V3(side*57,-7.1,-83)))
        root.addChildNode(box(V3(18,1.0,132),plates,V3(side*57,4.2,5),chamfer:0.5))
        root.addChildNode(box(V3(3,1.1,130),red,V3(side*57,4.8,5)))
        for z in stride(from:Float(-67),through:70,by:9) {
            root.addChildNode(box(V3(26,1.2,2),ribs,V3(side*57,3.4,z),chamfer:0.3))
        }
        for z in stride(from:Float(-20),through:65,by:12) {
            root.addChildNode(box(V3(7,3,6),ribs,V3(side*13,13,z)))
            root.addChildNode(segment(V3(side*13,15,z),V3(side*13,15,z-8),radius:0.5,mat:plates))
        }
    }
    for z in stride(from:Float(-27),through:75,by:7) {
        root.addChildNode(box(V3(40,1.8,2.0),plates,V3(0,10.7,z),chamfer:0.4))
    }
    for x: Float in [-12,-4,4,12] {
        root.addChildNode(cylinder(4,1,ribs,V3(x,-1,96)))
        root.addChildNode(cylinder(2.9,0.3,light,V3(x,-1,96.7)))
    }
    return root
}

func cylonBasestar() -> SCNNode {
    let root = SCNNode()
    let metal = material(color(0.37,0.4,0.42),metal:0.85)
    let edge = material(color(0.53,0.55,0.55),metal:0.75)
    let dark = material(color(0.11,0.13,0.15),metal:0.6)
    let red = material(color(0.55,0.025,0.01),emission:color(0.9,0.025,0.008))
    let core = node(SCNSphere(radius:1),metal)
    core.simdScale = V3(28,23,28); root.addChildNode(core)
    for tier: Float in [-1,1] {
        let level = SCNNode()
        level.simdEulerAngles.y = tier<0 ? .pi/3 : 0
        for arm in 0..<3 {
            let branch = SCNNode(); branch.simdEulerAngles.y = Float(arm)*tau/3
            let sections: [(Float,Float,Float,Float)] = [(-12,18,5,tier*12),(-50,20,5,tier*19),(-110,8,3,tier*22),(-143,1,1,tier*17)]
            branch.addChildNode(armoredLoft(sections,mat:metal))
            func surface(_ z: Float,_ widthFraction: Float) -> V3 {
                for i in 0..<(sections.count-1) {
                    let a = sections[i], b = sections[i+1]
                    if z<=a.0 && z>=b.0 {
                        let t = (z-a.0)/(b.0-a.0)
                        return V3((a.1+(b.1-a.1)*t)*widthFraction,a.3+(b.3-a.3)*t+a.2+(b.2-a.2)*t+0.2,z)
                    }
                }
                return V3(0,tier*12+6,z)
            }
            for s: Float in [-1,1] {
                for i in 0..<(sections.count-1) {
                    branch.addChildNode(segment(surface(sections[i].0,s*0.6),surface(sections[i+1].0,s*0.6),radius:0.3,mat:edge))
                }
                for i in 0..<9 {
                    let z = -25-Float(i)*11
                    branch.addChildNode(segment(surface(z,s*0.5),surface(z-6,s*0.25),radius:0.18,mat:dark))
                }
            }
            branch.addChildNode(box(V3(2,0.5,3),red,surface(-27,0)))
            level.addChildNode(branch)
        }
        root.addChildNode(level)
    }
    return root
}
