import SceneKit
import simd

enum Daedalus {
    static let podX: Float = 55
    static let hangarY: Float = -5
    static let hangarMouth: Float = -60
    static let battery = V3(12,9,-87)

    static func launchPort(side: Float) -> V3 {
        V3(side*podX,hangarY,hangarMouth+0.3)
    }
}

private let daedalusPlating = """
#pragma declaration
float daedalusHash(float2 cell) {
    float3 p = fract(cell.xyx*0.1031);
    p += dot(p,p.yzx+33.33);
    return fract((p.x+p.y)*p.z);
}
float daedalusPanel(float2 p) {
    float2 tile = p/float2(4.2,7.8);
    tile.x += 0.5*fmod(abs(floor(tile.y)),2.0);
    float2 edges = min(fract(tile),1.0-fract(tile));
    float seam = smoothstep(0.012,0.043,min(edges.x,edges.y));
    return (0.81+0.34*daedalusHash(floor(tile)))*(0.65+0.35*seam);
}
#pragma body
float3 p = (scn_node.inverseModelViewTransform*float4(_surface.position,1.0)).xyz;
float3 n = abs(normalize((scn_node.inverseModelViewTransform*float4(_surface.normal,0.0)).xyz));
float3 weights = n*n*n*n;
weights /= max(0.001,weights.x+weights.y+weights.z);
float panels = dot(weights,float3(daedalusPanel(p.zy),daedalusPanel(p.xz),daedalusPanel(p.xy)));
float footprint = max(length(dfdx(p)),length(dfdy(p)));
float detail = 1.0-smoothstep(0.35,1.9,footprint);
float grain = daedalusHash(floor(float2(p.x+p.y*0.63,p.z-p.y*0.41)*3.2));
_surface.diffuse.rgb *= mix(0.90,panels,detail)+(grain-0.5)*0.14*(1.0-smoothstep(0.08,0.40,footprint));
_surface.roughness = mix(0.68,0.86,panels);
"""

private func daedalusRing(_ z: Float, width: Float, roof: Float, floor: Float) -> [V3] {
    [V3(width*0.76,roof,z),V3(width,roof*0.53,z),V3(width,floor*0.47,z),V3(width*0.76,floor,z),
     V3(-width*0.76,floor,z),V3(-width,floor*0.47,z),V3(-width,roof*0.53,z),V3(-width*0.76,roof,z)]
}

// The collar bridges the shell and liner without capping the mouth.
private func daedalusSleeve(_ rings: [[V3]], material: SCNMaterial, inward: Bool = false) -> SCNNode {
    var vertices: [SCNVector3] = []
    var normals: [SCNVector3] = []
    for (a,b) in zip(rings,rings.dropFirst()) {
        for i in a.indices {
            let j = (i+1)%a.count
            for face in [[a[i],b[i],b[j]],[a[i],b[j],a[j]]] {
                let triangle = inward ? Array(face.reversed()) : face
                let normal = unit(simd_cross(triangle[1]-triangle[0],triangle[2]-triangle[0]))
                vertices.append(contentsOf:triangle.map(SCNVector3.init))
                normals.append(contentsOf:Array(repeating:SCNVector3(normal),count:3))
            }
        }
    }
    let geometry = SCNGeometry(
        sources:[SCNGeometrySource(vertices:vertices),SCNGeometrySource(normals:normals)],
        elements:[SCNGeometryElement(indices:Array(0..<Int32(vertices.count)),primitiveType:.triangles)])
    return node(geometry,material)
}

private func daedalusPod(armor: SCNMaterial, plate: SCNMaterial, recess: SCNMaterial,
                         lights: SCNMaterial, caution: SCNMaterial) -> SCNNode {
    let pod = SCNNode()
    let mouth = Daedalus.hangarMouth
    let exterior = [daedalusRing(mouth, width:14,roof:9.3,floor:-8.3),
                    daedalusRing(-48,width:18.8,roof:13,floor:-10),
                    daedalusRing(-30,width:21,roof:15,floor:-12),
                    daedalusRing(34,width:21,roof:15,floor:-12),
                    daedalusRing(71,width:19,roof:12.5,floor:-10.5),
                    daedalusRing(91,width:14,roof:8.7,floor:-8)]
    let interior = [daedalusRing(mouth,width:11.8,roof:5.7,floor:-5.6),
                    daedalusRing(mouth+7,width:11.1,roof:5.25,floor:-5.25),
                    daedalusRing(12,width:11.1,roof:5.25,floor:-5.25)]
    pod.addChildNode(daedalusSleeve(exterior,material:armor))
    pod.addChildNode(daedalusSleeve(interior,material:recess,inward:true))
    pod.addChildNode(daedalusSleeve([interior[0],exterior[0]],material:plate))
    let stern = exterior[exterior.count-1]
    pod.addChildNode(hullMesh(Array(stern.reversed()),faces:[Array(stern.indices)],mat:recess))
    pod.addChildNode(box(V3(22,10.4,1.8),recess,V3(0,0,12)))
    pod.addChildNode(box(V3(14,7,0.45),plate,V3(0,-0.8,10.95),chamfer:0.6))
    pod.addChildNode(box(V3(10,0.22,0.24),caution,V3(0,2.84,10.63)))

    let fittings = SCNNode()
    for z in stride(from:mouth+10,through:6,by:8) {
        let rib = [daedalusRing(z-0.44,width:11.15,roof:5.3,floor:-5.3),
                   daedalusRing(z-0.22,width:10.55,roof:4.87,floor:-4.99),
                   daedalusRing(z+0.22,width:10.55,roof:4.87,floor:-4.99),
                   daedalusRing(z+0.44,width:11.15,roof:5.3,floor:-5.3)]
        pod.addChildNode(daedalusSleeve(rib,material:plate,inward:true))
    }
    for side: Float in [-1,1] {
        fittings.addChildNode(box(V3(0.34,0.09,65),plate,V3(side*6.65,-5.12,-19)))
        for z in stride(from:mouth+2,through:8,by:4) {
            fittings.addChildNode(box(V3(0.72,0.12,1.30),lights,V3(side*7.5,-4.99,z)))
            if z < -43 {
                fittings.addChildNode(box(V3(0.48,0.1,0.68),caution,V3(side*5.8,-5.01,z+0.8)))
            }
        }
        for z in stride(from:Float(-46),through:6,by:8) {
            fittings.addChildNode(box(V3(0.6,0.14,2.9),lights,V3(side*5.4,5.05,z)))
            fittings.addChildNode(box(V3(0.20,1.26,3.8),plate,V3(side*11.03,-1.17,z+1),chamfer:0.13))
            fittings.addChildNode(box(V3(0.25,0.14,1.1),caution,V3(side*10.88,-0.87,z+1)))
        }
        for z: Float in [-20,-6,9,24,42,56] {
            let height: Float = z<=34 ? 15 : 15-(z-34)*2.5/37
            fittings.addChildNode(box(V3(10,0.71,9.1),plate,V3(side*6.6,height+0.18,z),chamfer:0.36))
            fittings.addChildNode(box(V3(1.2,0.19,6.2),recess,V3(side*5.6,height+0.57,z),chamfer:0.08))
        }
    }
    pod.addChildNode(fittings.flattenedClone())
    return pod
}

private func daedalusEngine(at position: V3, radius: CGFloat, shell: SCNMaterial,
                            trim: SCNMaterial, ceramic: SCNMaterial, glow: SCNMaterial) -> SCNNode {
    let engine = SCNNode()
    engine.simdPosition = position
    let size = Float(radius)
    func collar(inner: CGFloat, outer: CGFloat, length: CGFloat, z: Float, surface: SCNMaterial) {
        let geometry = SCNTube(innerRadius:inner,outerRadius:outer,height:length)
        geometry.radialSegmentCount = 24
        let ring = node(geometry,surface,V3(0,0,z))
        ring.eulerAngles.x = .pi/2
        engine.addChildNode(ring)
    }
    collar(inner:radius*0.78,outer:radius,length:radius*1.25,z:0,surface:shell)
    collar(inner:radius*0.72,outer:radius*1.015,length:radius*0.17,z:size*0.64,surface:trim)
    collar(inner:radius*0.55,outer:radius*0.77,length:radius*0.34,z:size*0.20,surface:ceramic)
    engine.addChildNode(cylinder(radius*0.54,0.42,glow,V3(0,0,size*0.03)))
    engine.addChildNode(cylinder(radius*0.15,0.28,trim,V3(0,0,size*0.08)))
    let ribs = SCNNode()
    for i in 0..<16 {
        let angle = Float(i)*tau/16
        let fin = box(V3(size*0.08,size*0.21,size*0.58),shell,
                      V3(sin(angle)*size*0.70,cos(angle)*size*0.70,size*0.29))
        fin.simdEulerAngles.z = -angle
        ribs.addChildNode(fin)
    }
    engine.addChildNode(ribs.flattenedClone())
    return engine
}

func daedalus() -> SCNNode {
    let ship = SCNNode()
    let armor = material(color(0.29,0.35,0.40),metal:0.49)
    let plates = material(color(0.40,0.45,0.49),metal:0.54)
    for steel in [armor,plates] { steel.shaderModifiers = [.surface:daedalusPlating] }
    let recess = material(color(0.057,0.072,0.095),metal:0.36)
    let blue = material(color(0.47,0.68,0.93),emission:color(0.46,0.77,1.35))
    let window = material(color(0.63,0.76,0.87),emission:color(0.44,0.59,0.76))
    let caution = material(color(0.67,0.41,0.13),emission:color(0.41,0.22,0.055))
    let exhaust = material(color(0.34,0.60,0.93),emission:color(0.47,1.14,2.65))

    // The neck narrows behind the long armoured prow. The aft block deepens
    // around the flight pods and steps up into the engineering and bridge decks.
    ship.addChildNode(armoredLoft([(-145,10,3.3,-3),(-138,17,6,-3),(-116,24,9,-2),
                                   (-87,25,10,-2),(-67,22,9,-2),(-40,20,10,-1),
                                   (-16,28,12,0),(16,35,15,1),(73,36,16,1),
                                   (102,33,14,0),(120,28,11,-1),(127,23,10,-1)],mat:armor))
    ship.addChildNode(armoredLoft([(-142,9,1.5,0.1),(-129,13,2.4,3.9),(-112,17,3.3,7.9),
                                   (-78,16.5,2.7,7.8),(-65,12,1.3,6.9)],mat:plates))
    ship.addChildNode(armoredLoft([(-119,16,2,-8),(-108,22,3.5,-10.7),
                                   (-64,21,3.8,-10.9),(-48,15,2.1,-8.8)],mat:armor))
    ship.addChildNode(armoredLoft([(-27,14,2.2,10),(-12,25,5.8,13.5),(14,32,7.6,15),
                                   (76,32,7.2,18),(106,27,6.5,16),(119,21,3,12)],mat:plates))
    ship.addChildNode(armoredLoft([(8,10.5,2.6,22),(19,16,4,25),(56,16,4.7,26),
                                   (67,12,3,25.7)],mat:armor))
    ship.addChildNode(armoredLoft([(24,7.5,2,28),(32,11,3.7,30),(50,11,3.7,31.2),
                                   (59,8,2.6,30.2)],mat:plates))

    let detail = SCNNode()
    for side: Float in [-1,1] {
        let pod = daedalusPod(armor:armor,plate:plates,recess:recess,lights:blue,caution:caution)
        pod.name = side<0 ? "port F-302 hangar" : "starboard F-302 hangar"
        pod.simdPosition = V3(side*Daedalus.podX,Daedalus.hangarY,0)
        ship.addChildNode(pod)
        let shoulder = armoredLoft([(-39,5,4,0),(-23,9.5,7,-0.4),(32,9.5,9,-0.7),
                                      (67,9,7,-1.2),(80,6,3,-2)],mat:armor)
        shoulder.simdPosition.x = side*34
        ship.addChildNode(shoulder)
        for z: Float in [-107,-96,-85,-74] {
            let top: Float = z < -78 ? 11.05 : 10.0
            detail.addChildNode(box(V3(7.6,0.76,7.8),plates,V3(side*9.4,top,z),chamfer:0.42))
            detail.addChildNode(box(V3(3.8,0.23,4.6),recess,V3(side*9.4,top+0.46,z)))
        }
        for (index,z) in [Float(6),19,32,45,58,71,84,97].enumerated() {
            let height: Float = z < 14 ? 21.6 : (z<76 ? 22.6+(z-14)*2.6/62 : 25.2-(z-76)*2.7/30)
            detail.addChildNode(box(V3(7.6,0.87,10.3),plates,V3(side*16.2,height+0.12,z),chamfer:0.56))
            for x: Float in [14,16.2,18.4] {
                let housing = box(V3(1.15,0.4,7.4),recess,V3(side*x,height+0.69,z))
                detail.addChildNode(housing)
            }
            if index.isMultiple(of:2) {
                detail.addChildNode(box(V3(1.7,0.24,1.05),window,V3(side*18,height+0.61,z-4)))
            }
        }
        for z: Float in [31,36,42,48,53] {
            detail.addChildNode(box(V3(0.28,0.44,2.35),window,V3(side*10.5,32,z)))
        }
        detail.addChildNode(segment(V3(side*12,2,-134),V3(side*12,1.4,-158),radius:0.29,mat:armor))
        detail.addChildNode(segment(V3(side*14,26,24),V3(side*14,48,24),radius:0.32,mat:plates))
        detail.addChildNode(segment(V3(side*7,32,49),V3(side*7,43,49),radius:0.30,mat:plates))
        for (x,y,z,radius) in [(11.5,4.3,129.3,8.9),(20.5,-8.0,127.6,6.5),(51.5,-4.4,93.0,7.25)] {
            ship.addChildNode(daedalusEngine(at:V3(side*Float(x),Float(y),Float(z)),radius:radius,
                                              shell:armor,trim:plates,ceramic:recess,glow:exhaust))
        }
    }
    ship.addChildNode(detail.flattenedClone())
    return ship
}
