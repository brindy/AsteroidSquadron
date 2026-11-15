import SceneKit
import simd

enum Basestar {
    static let hangarX: Float = 22
    static let hangarY: Float = -33
    static let hangarMouth: Float = -36

    static func launchPort(side: Float) -> V3 {
        V3(side*hangarX,hangarY,hangarMouth+0.7)
    }
}

private let basestarPlating = """
#pragma declaration
float basestarHash(float2 cell) {
    float3 p = fract(cell.xyx*0.1031);
    p += dot(p,p.yzx+33.33);
    return fract((p.x+p.y)*p.z);
}
float basestarPlates(float2 p) {
    p.x += sin(p.y*0.12)*1.8;
    float2 tile = p/float2(4.3,10.6);
    tile.y += fmod(abs(floor(tile.x)),2.0)*0.5;
    float2 edge = min(fract(tile),1.0-fract(tile));
    float seam = smoothstep(0.012,0.037,min(edge.x,edge.y));
    return (0.83+0.30*basestarHash(floor(tile)))*(0.73+0.27*seam);
}
#pragma body
float3 p = (scn_node.inverseModelViewTransform*float4(_surface.position,1.0)).xyz;
float3 normal = abs(normalize((scn_node.inverseModelViewTransform*float4(_surface.normal,0.0)).xyz));
float3 w = normal*normal*normal;
w /= max(0.001,w.x+w.y+w.z);
float plating = dot(w,float3(basestarPlates(p.yz),basestarPlates(p.xz),basestarPlates(p.xy)));
float footprint = max(length(dfdx(p)),length(dfdy(p)));
float detail = 1.0-smoothstep(0.28,1.8,footprint);
float stains = sin(p.z*0.17+p.x*0.44)*sin(p.z*0.39-p.x*0.08+p.y*0.7);
_surface.diffuse.rgb *= mix(0.91,plating,detail)*(0.91+0.075*stains);
_surface.roughness = mix(0.56,0.86,plating);
"""

private struct BasestarArmStation {
    let z: Float
    let width: Float
    let thickness: Float
    let height: Float
}

private func basestarArm(tier: Float, armor: SCNMaterial, edge: SCNMaterial,
                         dark: SCNMaterial, lights: SCNMaterial) -> SCNNode {
    // Preserve the plan view of each wing. The keels and machinery sit inside
    // this outline and add relief mainly when the viewer sees the wing edge-on.
    let stations = [BasestarArmStation(z:-12,width:18,thickness:5,height:tier*12),
                    BasestarArmStation(z:-50,width:20,thickness:5,height:tier*19),
                    BasestarArmStation(z:-110,width:8,thickness:3,height:tier*22),
                    BasestarArmStation(z:-143,width:1,thickness:1,height:tier*17)]
    let arm = armoredLoft(stations.map { ($0.z,$0.width,$0.thickness,$0.height) },mat:armor)
    func profile(_ z: Float) -> BasestarArmStation {
        let (a,b) = zip(stations,stations.dropFirst()).first { z >= $0.1.z }
            ?? (stations[2],stations[3])
        let t = (z-a.z)/(b.z-a.z)
        return BasestarArmStation(z:z,width:a.width+(b.width-a.width)*t,
                                  thickness:a.thickness+(b.thickness-a.thickness)*t,
                                  height:a.height+(b.height-a.height)*t)
    }
    func face(_ z: Float, _ x: Float, _ direction: Float, lift: Float = 0) -> V3 {
        let p = profile(z)
        let bevel = max(0,(abs(x)-0.65)/0.35)*0.5
        return V3(p.width*x,p.height+direction*(p.thickness*(1-bevel)+lift),z)
    }

    // The lower wings show structure on both faces when viewed through the gap
    // between the two tiers. Keep the dorsal face of the upper tier clear.
    let exposedFaces: [Float] = tier < 0 ? [-1,1] : [-1]
    let fittings = SCNNode()
    for direction in exposedFaces {
        let keelZ: [Float] = [-18,-35,-50,-74,-106,-124,-136]
        let keel = keelZ.map { z -> (Float,Float,Float,Float) in
            let p = profile(z)
            let depth = min(2.6,p.width*0.27)
            return (z,p.width*0.47,depth,p.height+direction*(p.thickness+depth*0.18))
        }
        arm.addChildNode(armoredLoft(keel,mat:dark))
        for side: Float in [-1,1] {
            for (a,b) in zip(keelZ,keelZ.dropFirst()) {
                fittings.addChildNode(segment(face(a,side*0.50,direction,lift:0.45),
                                               face(b,side*0.50,direction,lift:0.45),radius:0.48,mat:edge))
            }
            for z in stride(from:Float(-27),through:-124,by:-8.4) {
                let p = profile(z)
                let hood = box(V3(p.width*0.22,1.0,3.7),armor,face(z,side*0.73,direction,lift:0.20),chamfer:0.42)
                hood.simdEulerAngles.z = -side*direction*0.18
                fittings.addChildNode(hood)
                fittings.addChildNode(segment(face(z-1,side*0.87,direction,lift:0.15),
                                               face(z+1,side*0.51,direction,lift:1.05),radius:0.34,mat:edge))
            }
        }
        for z: Float in [-31,-50,-73,-96,-117,-129] {
            let armWidth = profile(z).width
            let width = armWidth*0.71
            let keelFace = min(2.6,armWidth*0.27)*1.18
            fittings.addChildNode(box(V3(width,0.52,4.8),dark,face(z,0,direction,lift:keelFace+0.11),chamfer:0.22))
            for i in -3...3 {
                let x = Float(i)*0.10
                fittings.addChildNode(box(V3(width*0.062,0.29,3.8),edge,
                                           face(z,x,direction,lift:keelFace+0.46),chamfer:0.08))
            }
            fittings.addChildNode(box(V3(width*0.10,0.19,1.35),lights,face(z-0.7,0,direction,lift:keelFace+0.66)))
        }
    }
    arm.addChildNode(fittings.flattenedClone())
    return arm
}

private func basestarHub(armor: SCNMaterial, edge: SCNMaterial, dark: SCNMaterial,
                        lights: SCNMaterial) -> SCNNode {
    let hub = SCNNode()
    let chamber = node(SCNSphere(radius:1),dark)
    chamber.simdScale = V3(24,24,24)
    hub.addChildNode(chamber)
    for tier: Float in [-1,1] {
        // Wide collars tie into the arm roots. The narrower waist exposes the
        // supporting ribs and openings between the two hulls.
        let shoulder = SCNCylinder(radius:29,height:9)
        shoulder.radialSegmentCount = 36
        hub.addChildNode(node(shoulder,armor,V3(0,tier*13,0)))
        let rim = SCNTube(innerRadius:22,outerRadius:29.65,height:1.28)
        rim.radialSegmentCount = 36
        hub.addChildNode(node(rim,edge,V3(0,tier*9.5,0)))
        let collar = SCNCylinder(radius:22,height:6)
        collar.radialSegmentCount = 36
        hub.addChildNode(node(collar,armor,V3(0,tier*21,0)))
    }
    for index in 0..<18 {
        let rib = SCNNode()
        rib.simdEulerAngles.y = Float(index)*tau/18
        rib.addChildNode(box(V3(5.8,14.5,2.8),armor,V3(0,0,-24.7),chamfer:0.74))
        rib.addChildNode(box(V3(2.8,9.4,0.38),dark,V3(0,0,-26.19),chamfer:0.18))
        for y: Float in [-2.4,0,2.4] {
            rib.addChildNode(box(V3(1.5,0.30,0.2),lights,V3(0,y,-26.42)))
        }
        hub.addChildNode(rib.flattenedClone())
    }
    return hub
}

private func basestarHangar(armor: SCNMaterial, dark: SCNMaterial, edge: SCNMaterial,
                            lights: SCNMaterial, beacon: SCNMaterial) -> SCNNode {
    let bay = SCNNode()
    let outer = [armoredHullRing(0,width:11.8,roof:7.1,floor:-4.8),
                 armoredHullRing(5,width:13.6,roof:8.5,floor:-6.0),
                 armoredHullRing(14,width:14.2,roof:11.8,floor:-6.15),
                 armoredHullRing(27,width:12.7,roof:12.7,floor:-4.7)]
    let liner = [armoredHullRing(0,width:10.4,roof:4.75,floor:-3.6),
                 armoredHullRing(5,width:10.9,roof:4.95,floor:-3.6),
                 armoredHullRing(27,width:10.9,roof:4.95,floor:-3.6)]
    bay.addChildNode(armoredSleeve(outer,material:armor))
    bay.addChildNode(armoredSleeve(liner,material:dark,inward:true))
    bay.addChildNode(armoredSleeve([liner[0],outer[0]],material:edge))
    let stern = outer[outer.count-1]
    bay.addChildNode(hullMesh(Array(stern.reversed()),faces:[Array(stern.indices)],mat:armor))
    bay.addChildNode(box(V3(16.7,6.3,0.45),armor,V3(0,0.55,26.73),chamfer:0.6))
    let rails = SCNNode()
    for side: Float in [-1,1] {
        for z: Float in [1.3,5.5,9.7,13.9,18.1,22.3] {
            rails.addChildNode(box(V3(0.9,0.16,1.49),lights,V3(side*7.0,-3.49,z)))
            rails.addChildNode(box(V3(0.50,3.6,0.92),armor,V3(side*10.37,0.59,z+0.7)))
        }
        rails.addChildNode(box(V3(0.68,0.27,1.9),beacon,V3(side*6,-3.47,0.9)))
    }
    bay.addChildNode(rails.flattenedClone())
    return bay
}

func cylonBasestar() -> SCNNode {
    let root = SCNNode()
    let armor = material(color(0.33,0.38,0.43),metal:0.54)
    armor.shaderModifiers = [.surface:basestarPlating]
    let edge = material(color(0.42,0.47,0.51),metal:0.58)
    let dark = material(color(0.082,0.10,0.13),metal:0.4)
    let lights = material(color(0.58,0.66,0.77),emission:color(0.34,0.40,0.51))
    let beacon = material(color(0.62,0.069,0.046),emission:color(0.64,0.036,0.025))
    root.addChildNode(basestarHub(armor:armor,edge:edge,dark:dark,lights:lights))
    for tier: Float in [-1,1] {
        for index in 0..<3 {
            let arm = basestarArm(tier:tier,armor:armor,edge:edge,dark:dark,lights:lights)
            arm.simdEulerAngles.y = Float(index)*tau/3+(tier<0 ? Float.pi/3 : 0)
            root.addChildNode(arm)
        }
    }
    for side: Float in [-1,1] {
        let bay = basestarHangar(armor:armor,dark:dark,edge:edge,lights:lights,beacon:beacon)
        bay.name = side<0 ? "port Raider hangar" : "starboard Raider hangar"
        bay.simdPosition = V3(side*Basestar.hangarX,Basestar.hangarY,Basestar.hangarMouth)
        root.addChildNode(bay)
    }
    return root
}
