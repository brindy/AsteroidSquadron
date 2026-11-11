import SceneKit
import simd

// These meshes use the same local -Z flight axis and physical muzzle nodes
// as the rest of the fighter roster.
private func armorPlate(_ outline: [V3], depth: Float, material: SCNMaterial) -> SCNNode {
    let n = outline.count
    let vertices = outline + outline.map { $0-V3(0,depth,0) }
    let top = Array(0..<n)
    let bottom = Array(n..<2*n)
    let sides = (0..<n).map { i in [i,(i+1)%n,(i+1)%n+n,i+n] }
    return hullMesh(vertices,faces:[top,bottom]+sides,mat:material)
}

func f302() -> SCNNode {
    let ship = SCNNode()
    let gray = material(color(0.51,0.57,0.62),metal:0.38)
    let panels = material(color(0.24,0.30,0.34),metal:0.5)
    let canopy = material(color(0.06,0.18,0.24),metal:0.65)
    let exhaust = material(color(0.34,0.66,1),emission:color(0.8,1.8,3))
    let stripe = material(color(0.86,0.81,0.61))
    ship.addChildNode(armoredLoft([(-6.1,0.14,0.1,0),(-3.3,0.63,0.38,0),(1.6,0.83,0.54,0),(4,0.62,0.31,0)],mat:gray))
    ship.addChildNode(armoredLoft([(-3.2,0.22,0.08,0.37),(-1.7,0.52,0.3,0.48),(0.3,0.43,0.26,0.48),(1.15,0.27,0.06,0.41)],mat:canopy))
    for side: Float in [-1,1] {
        ship.addChildNode(armorPlate([V3(side*0.64,0.19,-2.2),V3(side*5.85,0.03,1.9),V3(side*5.28,0.02,3.6),V3(side*0.66,0.17,3.2)],depth:0.24,material:gray))
        ship.addChildNode(segment(V3(side*1.8,0.2,-0.8),V3(side*4.8,0.11,1.9),radius:0.055,mat:stripe))
        let engine = armoredLoft([(-0.35,0.43,0.43,0),(0.2,0.63,0.52,0),(3.8,0.62,0.49,0),(4.6,0.49,0.43,0)],mat:panels)
        engine.simdPosition.x = side*1.05
        ship.addChildNode(engine)
        ship.addChildNode(cylinder(0.37,0.23,exhaust,V3(side*1.05,0,4.63)))
        ship.addChildNode(armorPlate([V3(side*1.18,0.32,1.3),V3(side*1.77,1.69,3.45),V3(side*1.66,1.43,4.23),V3(side*1.10,0.34,4.1)],depth:0.16,material:gray))
        ship.addChildNode(cylinder(0.13,1.8,panels,V3(side*0.85,-0.13,-2.65)))
        addMuzzle(to:ship,at:V3(side*0.85,-0.13,-3.57),name:side<0 ? "left" : "right")
    }
    return ship
}

func deathGlider() -> SCNNode {
    let ship = SCNNode()
    let steel = material(color(0.31,0.39,0.45),metal:0.55)
    let gold = material(color(0.62,0.43,0.18),metal:0.65)
    let canopy = material(color(0.07,0.22,0.34),metal:0.67)
    let exhaust = material(color(0.44,0.67,1),emission:color(0.55,1.15,2.8))
    ship.addChildNode(armoredLoft([(-4.8,0.18,0.16,0),(-2.7,0.67,0.38,0),(1.45,0.92,0.49,0),(3.6,0.68,0.4,0)],mat:steel))
    ship.addChildNode(armoredLoft([(-3.5,0.18,0.11,0.33),(-2,0.56,0.43,0.45),(0.2,0.59,0.47,0.45),(1.3,0.35,0.15,0.42)],mat:canopy))
    ship.addChildNode(cylinder(0.46,0.25,exhaust,V3(0,0,3.65)))
    for side: Float in [-1,1] {
        let stations: [(Float,Float,Float,Float)] = [(0.66,0.10,-1.3,2.75),(2.5,0.19,-0.55,3.1),(4.5,0.12,-0.2,2.1),(6.15,-0.42,-1.55,0.25),(7,-0.82,-3.2,-2.72)]
        for i in 0..<(stations.count-1) {
            let (x,y,nose,tail) = stations[i]
            let (nextX,nextY,nextNose,nextTail) = stations[i+1]
            ship.addChildNode(armorPlate([V3(side*x,y,nose),V3(side*nextX,nextY,nextNose),V3(side*nextX,nextY,nextTail),V3(side*x,y,tail)],depth:0.20,material:steel))
            ship.addChildNode(segment(V3(side*x,y+0.04,nose),V3(side*nextX,nextY+0.04,nextNose),radius:0.055,mat:gold))
        }
        ship.addChildNode(cylinder(0.15,2.25,gold,V3(side*1.30,-0.22,-1.55)))
        addMuzzle(to:ship,at:V3(side*1.30,-0.22,-2.70),name:side<0 ? "left" : "right")
    }
    return ship
}

func wraithDart() -> SCNNode {
    let ship = SCNNode()
    let shell = material(color(0.27,0.35,0.30),metal:0.24)
    let ridge = material(color(0.45,0.44,0.29),metal:0.38)
    let canopy = material(color(0.12,0.25,0.21),metal:0.75)
    let power = material(color(0.43,1,0.69),emission:color(0.48,2.4,1.2))
    ship.addChildNode(armoredLoft([(-7.6,0.06,0.09,-0.09),(-3.1,0.38,0.28,-0.08),(-0.7,1.00,0.57,0),(2.7,1.17,0.60,0),(4.6,0.32,0.26,0.12)],mat:shell))
    ship.addChildNode(armoredLoft([(-2.9,0.18,0.08,0.27),(-0.85,0.58,0.32,0.48),(1.45,0.53,0.24,0.43),(2.6,0.28,0.12,0.34)],mat:canopy))
    for side: Float in [-1,1] {
        ship.addChildNode(armorPlate([V3(side*0.65,0.17,-1.75),V3(side*4.9,-0.35,3.92),V3(side*3.4,-0.25,4.5),V3(side*0.8,0.07,3.14)],depth:0.26,material:shell))
        ship.addChildNode(segment(V3(side*0.7,0.28,-1.4),V3(side*4.7,-0.26,3.92),radius:0.13,mat:ridge))
        ship.addChildNode(cylinder(0.30,0.25,power,V3(side*0.64,0.02,3.91)))
        ship.addChildNode(cylinder(0.11,1.55,ridge,V3(side*0.50,-0.15,-2.22)))
        addMuzzle(to:ship,at:V3(side*0.50,-0.15,-3.03),name:side<0 ? "left" : "right")
    }
    return ship
}

func daedalus() -> SCNNode {
    let ship = SCNNode()
    let armor = material(color(0.39,0.45,0.50),metal:0.45)
    let rails = material(color(0.57,0.60,0.62),metal:0.40)
    let dark = material(color(0.035,0.06,0.08),metal:0.45)
    let lights = material(color(0.52,0.78,1),emission:color(0.7,1.5,2.4))
    ship.addChildNode(armoredLoft([(-138,14,6,-3),(-117,29,10,-2),(-24,33,12,0),(20,32,15,0),(102,25,15,0),(120,19,12,0)],mat:armor))
    ship.addChildNode(box(V3(36,11,53),rails,V3(0,18,24),chamfer:2))
    ship.addChildNode(box(V3(24,12,28),armor,V3(0,27,39),chamfer:2))
    ship.addChildNode(box(V3(19,1.2,0.5),lights,V3(0,29,24.8)))
    for side: Float in [-1,1] {
        ship.addChildNode(box(V3(25,13,52),armor,V3(side*37,0,15),chamfer:2))
        let pod = armoredLoft([(-85,11,7,-6),(-75,16,11,-5),(58,17,11,-5),(70,12,9,-5)],mat:armor)
        pod.simdPosition.x = side*51
        ship.addChildNode(pod)
        ship.addChildNode(box(V3(15,8,0.9),dark,V3(side*51,-6,-85.2)))
        for x: Float in [-8,8] {
            ship.addChildNode(box(V3(0.65,8,0.7),lights,V3(side*51+x,-6,-85.8)))
        }
        for i in 0..<11 {
            let z = -69+Float(i)*12
            ship.addChildNode(box(V3(17,0.6,5),rails,V3(side*51,6.1,z)))
            ship.addChildNode(box(V3(0.65,0.85,2.6),lights,V3(side*66.5,-1,z)))
            ship.addChildNode(box(V3(13,0.65,5),dark,V3(side*50,-15.9,z)))
            ship.addChildNode(box(V3(2.6,0.7,1.6),lights,V3(side*47,-16.25,z)))
        }
        for i in 0..<8 {
            let z = -91+Float(i)*23
            ship.addChildNode(box(V3(7,0.75,15),rails,V3(side*17,-12.4,z),chamfer:0.35))
        }
        for x: Float in [9,24,47] {
            let z: Float = x==47 ? 71 : 120
            let radius: CGFloat = x==47 ? 6.5 : 7.5
            ship.addChildNode(cylinder(radius,9,dark,V3(side*x,-3,z)))
            ship.addChildNode(cylinder(radius*0.76,1.3,lights,V3(side*x,-3,z+5)))
        }
    }
    return ship
}

func goauldMothership() -> SCNNode {
    let ship = SCNNode()
    let gold = material(color(0.65,0.46,0.19),metal:0.6)
    let dark = material(color(0.19,0.13,0.064),metal:0.62)
    let amber = material(color(1,0.62,0.18),emission:color(2.5,0.81,0.09))
    let saucer = SCNCylinder(radius:103,height:13)
    saucer.radialSegmentCount = 8
    ship.addChildNode(node(saucer,dark,V3(0,-6,0)))
    let apron = SCNCylinder(radius:94,height:9)
    apron.radialSegmentCount = 8
    ship.addChildNode(node(apron,gold,V3(0,3,0)))
    let pyramid = hullMesh([
        V3(-71.5,7,-71.5),V3(71.5,7,-71.5),V3(71.5,7,71.5),V3(-71.5,7,71.5),V3(0,109,0)
    ],faces:[[0,1,2,3],[0,4,1],[1,4,2],[2,4,3],[3,4,0]],mat:gold)
    ship.addChildNode(pyramid)
    for i in 0..<12 {
        let height = 10+Float(i)*7.5
        let size = 143*(109-height)/102+0.75
        for side: Float in [-1,1] {
            ship.addChildNode(box(V3(size,0.8,0.9),dark,V3(0,height,side*size/2)))
            ship.addChildNode(box(V3(0.9,0.8,size),dark,V3(side*size/2,height,0)))
        }
    }
    for i in 0..<24 {
        let a = Float(i)*tau/24
        ship.addChildNode(box(V3(2,1.7,2),amber,V3(sin(a)*95,-5,cos(a)*95)))
    }
    for x: Float in [-29,29] {
        ship.addChildNode(box(V3(22,8,27),dark,V3(x,-17,-59),chamfer:1.5))
        ship.addChildNode(box(V3(18,0.8,0.8),amber,V3(x,-21.1,-73)))
    }
    return ship
}

func wraithHive() -> SCNNode {
    let ship = SCNNode()
    let carapace = material(color(0.27,0.33,0.32),metal:0.33)
    carapace.shaderModifiers = [.surface:"""
        float3 p = (scn_node.inverseModelViewTransform*float4(_surface.position,1)).xyz;
        float grain = sin(p.z*0.28 + sin(p.x*0.35)*1.5)*sin(p.y*0.35 + p.x*0.16);
        _surface.diffuse.rgb *= 0.79 + grain*0.14;
        """]
    let ridges = material(color(0.43,0.43,0.33),metal:0.35)
    let cavities = material(color(0.039,0.074,0.068),metal:0.2)
    let green = material(color(0.40,0.95,0.67),emission:color(0.33,1.45,0.78))
    ship.addChildNode(armoredLoft([(-154,4,4,-3),(-123,23,12,-3),(-62,47,20,2),(12,59,29,4),(79,54,25,3),(128,35,15,-1),(150,13,7,-2)],mat:carapace))
    ship.addChildNode(armoredLoft([(-93,5,3,14),(-49,11,6,24),(38,14,8,34),(100,8,6,25),(137,3,2,10)],mat:ridges))
    for side: Float in [-1,1] {
        let lobe = armoredLoft([(-110,4,4,-2),(-66,17,12,1),(14,26,17,1),(79,21,13,-2),(128,3,4,-6)],mat:carapace)
        lobe.simdPosition.x = side*49
        lobe.simdEulerAngles.y = side*0.24
        ship.addChildNode(lobe)
        for i in 0..<15 {
            let z = -88+Float(i)*14
            let width = 42+22*sin(Float(i)*Float.pi/15)
            ship.addChildNode(segment(V3(side*12,25,z+11),V3(side*width,9,z-7),radius:1.55,mat:ridges))
            ship.addChildNode(box(V3(3.1,1.45,3.1),green,V3(side*(width-5),10,z+1)))
            if i>2 && i<13 {
                ship.addChildNode(segment(V3(side*11,-24,z+5),V3(side*43,-16,z-5),radius:1.1,mat:ridges))
                ship.addChildNode(box(V3(2.5,0.65,5),green,V3(side*15,-24.5,z)))
            }
        }
        ship.addChildNode(box(V3(19,10,32),cavities,V3(side*32,-21,-75),chamfer:2.5))
        ship.addChildNode(box(V3(16,1.2,0.8),green,V3(side*32,-25,-91.5)))
        ship.addChildNode(cylinder(8,3,green,V3(side*22,-5,142)))
    }
    return ship
}
