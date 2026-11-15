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
        ship.addChildNode(EngineNozzle(at:V3(side*1.05,0,4.75),radius:0.37,tint:V3(0.21,0.57,1)))
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
    ship.addChildNode(EngineNozzle(at:V3(0,0,3.78),radius:0.46,tint:V3(0.32,0.49,1)))
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
