import AppKit
import SceneKit
import simd

private struct GalacticaSection {
    let z: Float
    let width: Float
    let roof: Float
    let keel: Float

    init(_ z: Float, _ width: Float, _ roof: Float, _ keel: Float) {
        self.z = z; self.width = width; self.roof = roof; self.keel = keel
    }

    func point(_ spoke: Int, lift: Float = 0) -> V3 {
        let angle = Float(spoke)*tau/32
        let x = sin(angle), y = cos(angle)
        let curveX = copysign(pow(abs(x),0.82),x)
        let curveY = pow(abs(y),0.80)
        return V3(curveX*(width+lift),curveY*(y>=0 ? roof+lift : keel-lift),z)
    }

    var ring: [V3] { (0..<32).map { point($0) } }
}

private func galacticaSection(at z: Float, along sections: [GalacticaSection]) -> GalacticaSection {
    let (a,b) = zip(sections,sections.dropFirst()).first { z<=$0.1.z }
        ?? (sections[sections.count-2],sections[sections.count-1])
    let t = max(0,min(1,(z-a.z)/(b.z-a.z)))
    return GalacticaSection(z,a.width+(b.width-a.width)*t,a.roof+(b.roof-a.roof)*t,a.keel+(b.keel-a.keel)*t)
}

private func galacticaSkin(_ rings: [[V3]], material: SCNMaterial, inward: Bool = false,
                           smooth: Bool = false, wrapped: Bool = true) -> SCNNode {
    let vertices = rings.flatMap { $0 }
    let count = rings[0].count
    var indices: [Int32] = []
    var normals = Array(repeating:V3.zero,count:vertices.count)
    var flatPositions: [SCNVector3] = []
    var flatNormals: [SCNVector3] = []
    for ring in 0..<(rings.count-1) {
        for spoke in 0..<(wrapped ? count : count-1) {
            let a = ring*count+spoke, b = ring*count+(spoke+1)%count
            for face in [[a,a+count,b+count],[a,b+count,b]] {
                let triangle = inward ? Array(face.reversed()) : face
                let normal = unit(simd_cross(vertices[triangle[1]]-vertices[triangle[0]],
                                             vertices[triangle[2]]-vertices[triangle[0]]))
                if smooth {
                    indices.append(contentsOf:triangle.map(Int32.init))
                    for index in triangle { normals[index] += normal }
                } else {
                    flatPositions.append(contentsOf:triangle.map { SCNVector3(vertices[$0]) })
                    flatNormals.append(contentsOf:Array(repeating:SCNVector3(normal),count:3))
                }
            }
        }
    }
    let positions = smooth ? vertices.map(SCNVector3.init) : flatPositions
    let directions = smooth ? normals.map { SCNVector3(unit($0)) } : flatNormals
    let faces = smooth ? indices : Array(0..<Int32(flatPositions.count))
    let geometry = SCNGeometry(
        sources:[SCNGeometrySource(vertices:positions),SCNGeometrySource(normals:directions)],
        elements:[SCNGeometryElement(indices:faces,primitiveType:.triangles)])
    return node(geometry,material)
}

private func galacticaBody(_ sections: [GalacticaSection], material: SCNMaterial) -> SCNNode {
    let root = galacticaSkin(sections.map(\.ring),material:material,smooth:true)
    let facing = sections[0].ring
    let tail = Array(sections[sections.count-1].ring.reversed())
    for cap in [facing,tail] {
        root.addChildNode(hullMesh(cap,faces:[Array(cap.indices)],mat:material))
    }
    return root
}

private func galacticaRib(at z: Float, along sections: [GalacticaSection], spokes: ClosedRange<Int>,
                          rise: Float, material: SCNMaterial) -> SCNNode {
    let offsets: [Float] = [-0.78,-0.42,0.42,0.78]
    let rings = offsets.enumerated().map { index,offset in
        let section = galacticaSection(at:z+offset,along:sections)
        let height: Float = index == 0 || index == 3 ? 0.06 : rise
        return spokes.map { spoke in
            let falloff = min(1,Float(min(spoke-spokes.lowerBound,spokes.upperBound-spoke))*0.4)
            return section.point(spoke,lift:0.04+height*falloff)
        }
    }
    return galacticaSkin(rings,material:material,smooth:true,wrapped:false)
}

private let galacticaPanelShader = """
#pragma declaration
float galacticaHash(float2 cell) {
    float3 p = fract(float3(cell.xyx)*0.1031);
    p += dot(p,p.yzx+33.33);
    return fract((p.x+p.y)*p.z);
}
float galacticaWear(float2 uv) {
    float2 corner = floor(uv);
    float2 t = smoothstep(0.0,1.0,fract(uv));
    float a = mix(galacticaHash(corner),galacticaHash(corner+float2(1,0)),t.x);
    float b = mix(galacticaHash(corner+float2(0,1)),galacticaHash(corner+float2(1,1)),t.x);
    return mix(a,b,t.y);
}
float galacticaPlate(float2 uv) {
    float2 scale = float2(3.5,6.0);
    float2 plate = uv/scale;
    plate.x += 0.5*fmod(abs(floor(plate.y)),2.0);
    float2 local = fract(plate);
    float2 edge = min(local,1.0-local)*scale;
    float seam = smoothstep(0.035,0.13,min(edge.x,edge.y));
    return (0.83+0.26*galacticaHash(floor(plate)))*(0.63+0.37*seam);
}
#pragma body
float3 p = (scn_node.inverseModelViewTransform*float4(_surface.position,1.0)).xyz;
float3 n = abs(normalize((scn_node.inverseModelViewTransform*float4(_surface.normal,0.0)).xyz));
float3 blend = n*n*n;
blend /= max(0.001,blend.x+blend.y+blend.z);
float pattern = dot(blend,float3(galacticaPlate(p.yz),galacticaPlate(p.xz),galacticaPlate(p.xy)));
float footprint = max(length(dfdx(p)),length(dfdy(p)));
float detail = 1.0-smoothstep(0.40,2.1,footprint);
float wear = galacticaWear(float2(p.x+p.y*0.52,p.z)/float2(13.0,21.0));
float grain = galacticaHash(floor(float2(p.x+p.y*0.74,p.z-p.y*0.48)*3.1));
_surface.diffuse.rgb *= (0.79+0.25*wear)*mix(0.92,pattern,detail)
    +(grain-0.5)*0.16*(1.0-smoothstep(0.08,0.32,footprint));
_surface.roughness = mix(0.74,0.92,pattern);
"""

private func galacticaSteel(_ base: NSColor) -> SCNMaterial {
    let steel = material(base,metal:0.5)
    steel.shaderModifiers = [.surface:galacticaPanelShader]
    return steel
}

enum GalacticaFlightPod {
    static let centerX: Float = 57
    static let centerY: Float = -4
    static let mouth: Float = -47
    static let rear: Float = 92

    static func launchPort(side: Float) -> V3 {
        V3(side*centerX,centerY,mouth+0.8)
    }

    // The exterior and liner share their end planes. The two bevelled rims
    // join the shells without putting a face across the launch corridor.
    private static func ring(z: Float, width: Float, height: Float) -> [V3] {
        // Project the rounded shell's spokes onto the liner's flat faces.
        let cornerSlope: Float = (1-0.54)/(1-0.76)
        return (0..<32).map { spoke in
            let angle = Float(spoke)*tau/32
            let x = sin(angle), y = cos(angle)
            let horizontal = abs(x)/width, vertical = abs(y)/height
            let bevel = (1+cornerSlope*0.76)/(vertical+cornerSlope*horizontal)
            let radius = min(1/max(0.0001,horizontal),1/max(0.0001,vertical),bevel)
            return V3(x*radius,y*radius,z)
        }
    }

    static func model(side: Float, hull: SCNMaterial, armor: SCNMaterial,
                      dark: SCNMaterial, stripe: SCNMaterial, lights: SCNMaterial) -> SCNNode {
        let pod = SCNNode()
        pod.name = side<0 ? "port flight pod" : "starboard flight pod"
        pod.simdPosition = V3(side*centerX,centerY,0)

        let sections = [GalacticaSection(mouth,12.5,7.5,-7.3),GalacticaSection(-40,14.4,10,-8.2),
                        GalacticaSection(-29,17.3,13.7,-9.5),GalacticaSection(-11,18.5,15.1,-10.9),
                        GalacticaSection(23,18.7,15.7,-11.2),GalacticaSection(54,17.7,14.6,-10.7),
                        GalacticaSection(73,15.6,12.3,-9.4),GalacticaSection(85,13.4,9.2,-8.0),
                        GalacticaSection(rear,12.4,7.3,-7.3)]
        var exterior = sections.map(\.ring)
        // The upper edge overhangs the runway and reads as a sloping visor.
        exterior[0] = exterior[0].map { V3($0.x,$0.y,$0.z-max(0,$0.y)*0.65) }
        let interior = [ring(z:mouth,width:10.4,height:5.8),ring(z:mouth+7,width:10.2,height:5.5),
                        ring(z:rear-7,width:10.2,height:5.5),ring(z:rear,width:10.4,height:5.8)]
        pod.addChildNode(galacticaSkin(exterior,material:hull,smooth:true))
        pod.addChildNode(galacticaSkin(interior,material:dark,inward:true))
        pod.addChildNode(galacticaSkin([interior[0],exterior[0]],material:armor))
        pod.addChildNode(galacticaSkin([exterior[exterior.count-1],interior[interior.count-1]],material:armor))
        for z in stride(from:mouth+15,through:rear-12,by:16) {
            let rib = [ring(z:z-0.8,width:10.23,height:5.53),ring(z:z-0.4,width:9.88,height:5.30),
                       ring(z:z+0.4,width:9.88,height:5.30),ring(z:z+0.8,width:10.23,height:5.53)]
            pod.addChildNode(galacticaSkin(rib,material:armor,inward:true))
        }

        // Runway lights sit against the floor edges and the upper wall bevel.
        // The middle of the tunnel stays clear of geometry all the way through.
        let fittings = SCNNode()
        let runwayLength = rear-mouth-18
        let runwayCenter = (mouth+rear)*0.5
        for edge: Float in [-1,1] {
            fittings.addChildNode(box(V3(0.44,0.09,runwayLength),stripe,V3(edge*6.5,-5.38,runwayCenter)))
            for z in stride(from:mouth+5,through:rear-4,by:8) {
                fittings.addChildNode(box(V3(0.65,0.11,2),lights,V3(edge*7.2,-5.27,z)))
                fittings.addChildNode(box(V3(0.15,0.88,1.3),armor,V3(edge*10.14,1.95,z)))
                fittings.addChildNode(box(V3(0.20,0.20,0.85),lights,V3(edge*10.01,1.95,z)))
            }
        }
        pod.addChildNode(fittings.flattenedClone())
        let ribs = SCNNode()
        for z in stride(from:Float(-26),through:73,by:4.5) {
            let spans = side>0 ? 4...13 : -13 ... -4
            ribs.addChildNode(galacticaRib(at:z,along:sections,spokes:spans,rise:0.52,material:hull))
        }
        pod.addChildNode(ribs.flattenedClone())
        let stripeStations: [Float] = [-40,-36,-31]
        pod.addChildNode(galacticaSkin(stripeStations.map { z in
            let section = galacticaSection(at:z,along:sections)
            return (3...13).map { section.point(side>0 ? $0 : 32-$0,lift:0.45) }
        },material:stripe,inward:side<0,smooth:true,wrapped:false))
        return pod
    }
}

func battlestarGalactica() -> SCNNode {
    let root = SCNNode()
    let hull = galacticaSteel(color(0.29,0.33,0.39))
    let armor = galacticaSteel(color(0.42,0.45,0.51))
    let rib = galacticaSteel(color(0.31,0.35,0.41))
    let spine = galacticaSteel(color(0.14,0.16,0.20))
    let recess = material(color(0.045,0.054,0.072),metal:0.34)
    let red = galacticaSteel(color(0.40,0.094,0.086))
    let lamps = material(color(0.68,0.75,0.86),emission:color(0.48,0.63,0.8))
    let thrusters = material(color(0.62,0.73,1),emission:color(0.84,1.08,1.65))

    let sections = [
        GalacticaSection(-133,17.8,3.0,-4.9),GalacticaSection(-130,23.5,5.4,-8.7),
        GalacticaSection(-122,26.5,9.6,-13.1),GalacticaSection(-110,31.5,15.2,-18),
        GalacticaSection(-95,36.5,19.9,-20.5),GalacticaSection(-77,39.5,23,-22.0),
        GalacticaSection(-58,39.8,23.4,-22.5),GalacticaSection(-45,37.5,22.4,-21.2),
        GalacticaSection(-32,31.7,19,-17),GalacticaSection(-19,25,15.2,-13),
        GalacticaSection(0,21,13,-11.8),GalacticaSection(26,22.4,13.2,-12.5),
        GalacticaSection(48,26.2,13.8,-14.0),GalacticaSection(66,33,15.8,-16.0),
        GalacticaSection(84,35.5,16.5,-16.3),GalacticaSection(103,31,14.4,-15.0),
        GalacticaSection(118,27,11,-11.5)
    ]
    root.addChildNode(galacticaBody(sections,material:hull))
    let bowGrille = SCNNode()
    bowGrille.addChildNode(box(V3(25,2.8,0.34),spine,V3(0,-1.7,-133.12),chamfer:0.28))
    for x in stride(from:Float(-10),through:10,by:2) {
        let height: Float = abs(x)>6 ? 1.20 : 1.66
        bowGrille.addChildNode(box(V3(1.35,height,0.18),recess,V3(x,-1.58,-133.34),chamfer:0.12))
    }
    for side: Float in [-1,1] {
        bowGrille.addChildNode(box(V3(4.0,1.1,0.46),armor,V3(side*12,-3.32,-133.10),chamfer:0.18))
    }
    root.addChildNode(bowGrille.flattenedClone())

    func patch(from start: Float, to end: Float, spokes: ClosedRange<Int>,
               lift: Float, material: SCNMaterial) -> SCNNode {
        let stations = [start]+sections.map(\.z).filter { $0>start && $0<end }+[end]
        let profile = stations.map { z in
            let section = galacticaSection(at:z,along:sections)
            return spokes.map { section.point($0,lift:lift) }
        }
        return galacticaSkin(profile,material:material,smooth:true,wrapped:false)
    }

    // Armor runs along the roof and leaves recessed machinery down its centre.
    let armorPanels: [(Float,Float)] = [(-130,-113),(-111,-91),(-89,-67),(-65,-43),(-41,-26)]
    for (start,end) in armorPanels {
        for range in [-5 ... -1,1...5] {
            root.addChildNode(patch(from:start,to:end,spokes:range,lift:0.24,material:armor))
        }
    }
    let machinery: [(Float,Float)] = [(-112,-103),(-97,-83),(-74,-62),(-54,-47),(-35,-24),(-15,38)]
    let equipment = SCNNode()
    for (start,end) in machinery {
        root.addChildNode(patch(from:start,to:end,spokes:-1...1,lift:0.10,material:spine))
        for z in stride(from:start+0.9,to:end-0.5,by:2.4) {
            let section = galacticaSection(at:z,along:sections)
            let rail = box(V3(section.width*0.41,0.44,0.54),rib,V3(0,section.roof+0.13,z))
            equipment.addChildNode(rail)
            for side: Float in [-1,1] {
                let x = section.width*side*0.13
                equipment.addChildNode(box(V3(1.35,0.52,1.4),spine,V3(x,section.roof+0.16,z+0.8),chamfer:0.14))
            }
        }
    }
    root.addChildNode(equipment.flattenedClone())

    // Narrow transverse ribs follow the curved sides and taper into the armour.
    let flankRibs = SCNNode()
    for z in stride(from:Float(-124),through:61,by:3.7) {
        for range in [-15 ... -4,4...15] {
            flankRibs.addChildNode(galacticaRib(at:z,along:sections,spokes:range,rise:0.84,material:rib))
        }
    }
    root.addChildNode(flankRibs.flattenedClone())
    for range in [-5 ... -1,1...5] {
        root.addChildNode(patch(from:-117,to:-112,spokes:range,lift:0.48,material:red))
    }
    root.addChildNode(armoredLoft([(-47,5,0.5,22),(-43,7,1.0,22.3),(-35,7.5,1.6,21.6),
                                  (-24,6,1.1,16.8)],mat:armor))
    root.addChildNode(box(V3(5,0.25,0.1),lamps,V3(0,22.9,-43.1)))

    for side: Float in [-1,1] {
        for z: Float in [-17,46] {
            let arm = armoredLoft([(0,19,7.2,4),(9,18.5,7.5,2),
                                    (21,15.5,5.6,-0.6),(27,12.5,4.4,-1.8)],mat:hull)
            arm.simdPosition = V3(side*18,0,z)
            arm.simdEulerAngles.y = side*Float.pi/2
            root.addChildNode(arm)
        }
        root.addChildNode(GalacticaFlightPod.model(side:side,hull:hull,armor:armor,dark:recess,stripe:red,lights:lamps))
        let nacelle = galacticaBody([GalacticaSection(45,4,3,-2),GalacticaSection(59,10,7.5,-5.5),
                                     GalacticaSection(78,12,10,-7.0),GalacticaSection(108,12,9.7,-7.1),
                                     GalacticaSection(121,9.5,7.8,-6.0)],material:armor)
        nacelle.simdPosition = V3(side*20,8,0)
        root.addChildNode(nacelle)
    }
    for x: Float in [-22,-8,8,22] {
        let y: Float = abs(x)>10 ? 5 : -2
        root.addChildNode(cylinder(6.4,6,armor,V3(x,y,119)))
        root.addChildNode(cylinder(5.3,1.2,recess,V3(x,y,122.2)))
        root.addChildNode(cylinder(4.2,0.4,thrusters,V3(x,y,122.9)))
    }
    return root
}
