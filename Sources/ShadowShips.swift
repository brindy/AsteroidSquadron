import SceneKit
import simd

enum ShadowCarrier {
    static let bayX: Float = 22
    static let bayY: Float = -29
    static let bayMouth: Float = -53

    static func launchPort(side: Float) -> V3 {
        V3(side*bayX,bayY,bayMouth+0.7)
    }
}

private func shadowSkin(cellsPerUnit: Float) -> SCNMaterial {
    let skin = material(color(0.105,0.097,0.119),metal:0.59)
    skin.shaderModifiers = [.surface:"""
    #pragma declaration
    float2 shadowHash(float2 p) {
        float3 q = fract(p.xyx*float3(0.1031,0.1030,0.0973));
        q += dot(q,q.yzx+33.33);
        return fract((q.xx+q.yz)*q.zy);
    }
    #pragma body
    float3 p = (scn_node.inverseModelViewTransform*float4(_surface.position,1.0)).xyz;
    float2 cells = float2(p.x+p.y*0.68,p.z-p.y*0.52)*\(cellsPerUnit);
    float2 tile = floor(cells);
    float nearest = 10.0;
    float second = 10.0;
    for (int row=-1; row<=1; ++row) {
        for (int col=-1; col<=1; ++col) {
            float2 offset = float2(col,row);
            float2 samplePoint = offset+0.18+0.64*shadowHash(tile+offset)-fract(cells);
            float distance = dot(samplePoint,samplePoint);
            second = min(second,max(nearest,distance));
            nearest = min(nearest,distance);
        }
    }
    float grain = max(length(dfdx(cells)),length(dfdy(cells)));
    float detail = 1.0-smoothstep(0.35,1.4,grain);
    float seam = smoothstep(0.032,0.14,second-nearest);
    float grainTone = sin(p.x*1.7+p.z*0.7)*sin(p.z*1.1-p.y*1.92);
    _surface.diffuse.rgb *= mix(0.79,0.54+0.53*seam,detail)*(0.94+grainTone*0.075);
    _surface.roughness = mix(0.45,mix(0.60,0.30,seam),detail);
    """]
    return skin
}

// Both halves share their equator to keep the highlights continuous.
private func shadowCarapace(_ outline: [(Float,Float)], extent: V3, skin: SCNMaterial) -> SCNNode {
    let sectors = 96, belts = 12
    var vertices: [V3] = [V3(0,extent.y,0),V3(0,-extent.y*0.78,0)]
    let direction = (0..<sectors).map { index -> (Float,Float,Float) in
        let angle = Float(index)*360/Float(sectors)
        let mirror = min(angle,360-angle)
        let (a,b) = zip(outline,outline.dropFirst()).first { mirror <= $0.1.0 }
            ?? (outline[outline.count-2],outline[outline.count-1])
        let t = (mirror-a.0)/(b.0-a.0)
        let blend = t*t*(3-2*t)
        let radius = a.1+(b.1-a.1)*blend
        let radians = angle*Float.pi/180
        return (sin(radians),cos(radians),radius)
    }
    for surface in 0...1 {
        let verticalScale: Float = surface == 0 ? 1 : -0.78
        let lastBelt = surface == 0 ? belts : belts-1
        for belt in 1...lastBelt {
            let fraction = sin(Float(belt)/Float(belts)*Float.pi/2)
            for (x,z,radius) in direction {
                let camber = extent.y*fraction*fraction*(0.27*x*x-0.11*z)
                let lobe = 1+0.17*sin(fraction*(x*x*2.4-z*2.1))
                let height = camber+extent.y*verticalScale*sqrt(max(0,1-fraction*fraction))*lobe
                vertices.append(V3(extent.x*x*radius*fraction,height,-extent.z*z*radius*fraction))
            }
        }
    }
    var indices: [Int32] = []
    var normals = Array(repeating:V3.zero,count:vertices.count)
    func triangle(_ a: Int, _ b: Int, _ c: Int) {
        let normal = simd_cross(vertices[b]-vertices[a],vertices[c]-vertices[a])
        normals[a] += normal; normals[b] += normal; normals[c] += normal
        indices += [Int32(a),Int32(b),Int32(c)]
    }
    func index(_ surface: Int, _ belt: Int, _ spoke: Int) -> Int {
        let offset = surface == 1 && belt < belts ? belts*sectors : 0
        return 2+offset+(belt-1)*sectors+spoke%sectors
    }
    for surface in 0...1 {
        func wound(_ a: Int, _ b: Int, _ c: Int) {
            if surface == 0 { triangle(a,b,c) } else { triangle(a,c,b) }
        }
        for spoke in 0..<sectors {
            wound(surface,index(surface,1,spoke+1),index(surface,1,spoke))
            for belt in 1..<belts {
                let a = index(surface,belt,spoke), b = index(surface,belt,spoke+1)
                let c = index(surface,belt+1,spoke), d = index(surface,belt+1,spoke+1)
                wound(a,b,c); wound(b,d,c)
            }
        }
    }
    let geometry = SCNGeometry(
        sources:[SCNGeometrySource(vertices:vertices.map(SCNVector3.init)),
                 SCNGeometrySource(normals:normals.map { SCNVector3(unit($0)) })],
        elements:[SCNGeometryElement(indices:indices,primitiveType:.triangles)])
    return node(geometry,skin)
}

private func shadowSpine(_ points: [V3], radius: Float, flattening: Float, skin: SCNMaterial) -> SCNNode {
    let rings = 30, sides = 12
    var vertices: [SCNVector3] = [], normals: [SCNVector3] = [], indices: [Int32] = []
    func curve(_ t: Float) -> V3 {
        let u = 1-t
        let a = points[0]*u*u*u, b = points[1]*3*u*u*t
        let c = points[2]*3*u*t*t, d = points[3]*t*t*t
        return a+b+c+d
    }
    for ring in 0...rings {
        let t = Float(ring)/Float(rings), center = curve(t)
        let tangent = unit(curve(min(1,t+0.002))-curve(max(0,t-0.002)))
        let side = unit(simd_cross(tangent,V3(0,1,0)))
        let up = unit(simd_cross(side,tangent))
        let width = max(0.035,radius*pow(1-t,1.12))
        let height = width*flattening
        for spoke in 0..<sides {
            let angle = Float(spoke)*tau/Float(sides)
            let x = cos(angle), y = sin(angle)
            vertices.append(SCNVector3(center+side*(width*x)+up*(height*y)))
            normals.append(SCNVector3(unit(side*x+up*(y/flattening))))
        }
    }
    for ring in 0..<rings {
        for spoke in 0..<sides {
            let a = Int32(ring*sides+spoke), b = Int32(ring*sides+(spoke+1)%sides)
            let c = a+Int32(sides), d = b+Int32(sides)
            indices += [a,c,b,b,c,d]
        }
    }
    for spoke in 1..<(sides-1) {
        indices += [0,Int32(spoke),Int32(spoke+1)]
        let cap = Int32(rings*sides)
        indices += [cap,cap+Int32(spoke+1),cap+Int32(spoke)]
    }
    let geometry = SCNGeometry(
        sources:[SCNGeometrySource(vertices:vertices),SCNGeometrySource(normals:normals)],
        elements:[SCNGeometryElement(indices:indices,primitiveType:.triangles)])
    return node(geometry,skin)
}

func shadowFighter() -> SCNNode {
    let root = SCNNode()
    let shell = shadowSkin(cellsPerUnit:3.9)
    let outline: [(Float,Float)] = [(0,0.92),(25,0.95),(50,0.99),(78,1.10),(96,1.05),
        (120,0.92),(146,0.82),(165,0.92),(180,1.04)]
    root.addChildNode(shadowCarapace(outline,extent:V3(2.45,2.05,3.62),skin:shell))

    // Roots start inside the rounded body. Separate dorsal and ventral growths
    // give the fighter a silhouette from the side as well as from above.
    let spines: [([V3],Float,Float)] = [
        ([V3(1.26,0.35,-1.42),V3(2.96,0.63,-0.31),V3(4.65,1.41,0.96),V3(6.08,1.63,2.42)],0.89,0.88),
        ([V3(1.10,0.52,0.91),V3(2.24,1.02,2.52),V3(3.52,1.92,4.49),V3(4.05,2.55,5.91)],0.77,0.92),
        ([V3(0.98,-0.81,0.43),V3(2.48,-1.22,1.53),V3(4.18,-2.41,3.02),V3(5.26,-3.24,4.31)],0.72,0.94),
        ([V3(0.83,0.31,-2.08),V3(1.72,0.86,-2.52),V3(2.38,1.87,-2.62),V3(3.52,2.79,-2.15)],0.57,0.85),
        ([V3(0.51,1.27,0.66),V3(0.79,2.48,1.93),V3(1.16,3.23,3.52),V3(1.72,3.68,5.03)],0.61,0.90)
    ]
    for side: Float in [-1,1] {
        for (path,radius,flattening) in spines {
            let curve = path.map { V3(side*$0.x,$0.y,$0.z) }
            root.addChildNode(shadowSpine(curve,radius:radius,flattening:flattening,skin:shell))
        }
    }
    let dark = material(color(0.036,0.019,0.052),metal:0.62)
    let glow = material(color(0.24,0.08,0.35),emission:color(0.25,0.041,0.45))
    root.addChildNode(cylinder(0.26,0.42,dark,V3(0,0.18,3.69)))
    root.addChildNode(cylinder(0.15,0.12,glow,V3(0,0.18,3.91)))
    root.addChildNode(EngineNozzle(at:V3(0,0.18,3.98),radius:0.16,tint:V3(0.47,0.17,0.75)))
    for side: Float in [-1,1] {
        let vent = node(SCNSphere(radius:1),dark,V3(side*0.66,-0.27,-3.12))
        vent.simdScale = V3(0.20,0.16,0.32)
        root.addChildNode(vent)
        addMuzzle(to:root,at:V3(side*0.66,-0.27,-3.46),name:"\(side)")
    }
    return root
}

private func shadowBay(skin: SCNMaterial, dark: SCNMaterial, lip: SCNMaterial, lights: SCNMaterial) -> SCNNode {
    func rim(_ z: Float, width: Float, roof: Float, floor: Float) -> [V3] {
        (0..<24).map { index in
            let angle = Float(index)*tau/24, vertical = cos(angle)
            return V3(sin(angle)*width,vertical*(vertical>=0 ? roof : floor),z)
        }
    }
    let root = SCNNode()
    let shell = [rim(0,width:12.4,roof:8.3,floor:7.0),rim(8,width:15.0,roof:12.2,floor:7.8),
                 rim(22,width:15.5,roof:16.8,floor:8.6),rim(33,width:12.0,roof:16.5,floor:7.6)]
    let liner = [rim(0,width:10.7,roof:5.6,floor:5.35),rim(9,width:11.1,roof:5.9,floor:5.5),
                 rim(29,width:10.9,roof:5.9,floor:5.5)]
    root.addChildNode(armoredSleeve(shell,material:skin))
    root.addChildNode(armoredSleeve(liner,material:dark,inward:true))
    let bevel = rim(-0.24,width:11.3,roof:6.25,floor:5.92)
    root.addChildNode(armoredSleeve([liner[0],bevel],material:lip))
    root.addChildNode(armoredSleeve([bevel,shell[0]],material:skin))
    let back = shell[shell.count-1]
    root.addChildNode(hullMesh(Array(back.reversed()),faces:[Array(back.indices)],mat:skin))
    root.addChildNode(box(V3(20,11.2,0.8),dark,V3(0,0.1,29),chamfer:0.8))
    let lamps = SCNNode()
    for z: Float in [1.6,7.3,13,18.7,24.4] {
        for side: Float in [-1,1] {
            lamps.addChildNode(box(V3(0.77,0.17,2.3),lights,V3(side*5.5,-4.53,z),chamfer:0.08))
        }
    }
    root.addChildNode(lamps.flattenedClone())
    return root
}

func shadowCapital() -> SCNNode {
    let root = SCNNode()
    let armor = shadowSkin(cellsPerUnit:0.46)
    let dark = material(color(0.043,0.027,0.059),metal:0.43)
    let lip = material(color(0.18,0.105,0.23),emission:color(0.16,0.056,0.25),metal:0.54)
    let lights = material(color(0.34,0.12,0.54),emission:color(0.40,0.10,0.72))
    let hull: [(Float,Float)] = [(0,1.02),(25,0.99),(47.5,1.0),(75,1.08),(95,1.04),
                                 (115,0.98),(132.5,0.91),(155,0.90),(180,0.94)]
    root.addChildNode(shadowCarapace(hull,extent:V3(43,18,64),skin:armor))
    for side: Float in [-1,1] {
        // Each shoulder opens into a different direction in pitch and sweep.
        // The shorter spines break up the gaps between the main arms.
        let arms: [([V3],Float)] = [
            ([V3(17,2,-39),V3(56,9,-22),V3(111,39,-71),V3(139,57,-145)],16.2),
            ([V3(21,3,-13),V3(70,16,1),V3(126,12,-46),V3(155,23,-111)],17.3),
            ([V3(22,-1,14),V3(69,-2,27),V3(126,-21,-16),V3(149,-28,-62)],17.7),
            ([V3(18,-2,40),V3(61,2,50),V3(106,-26,11),V3(128,-64,-22)],15.6),
            ([V3(29,-7,-24),V3(45,-11,-15),V3(62,-28,-39),V3(85,-49,-103)],8.6),
            ([V3(30,-9,11),V3(55,-21,11),V3(74,-54,-7),V3(90,-67,-51)],8.4),
            ([V3(24,6,35),V3(41,14,46),V3(62,35,59),V3(90,45,68)],8.2)
        ]
        for (path,radius) in arms {
            let curve = path.map { V3(side*$0.x,$0.y,$0.z) }
            root.addChildNode(shadowSpine(curve,radius:radius,flattening:0.86,skin:armor))
        }
        for z: Float in [-40,-13,15,39] {
            let fold = [V3(side*11,12,z),V3(side*29,20,z+5),
                        V3(side*51,17,z+7),V3(side*68,10,z+9)]
            root.addChildNode(shadowSpine(fold,radius:7.3,flattening:0.67,skin:armor))
        }
        let bay = shadowBay(skin:armor,dark:dark,lip:lip,lights:lights)
        bay.name = side<0 ? "port Shadow launch bay" : "starboard Shadow launch bay"
        bay.simdPosition = V3(side*ShadowCarrier.bayX,ShadowCarrier.bayY,ShadowCarrier.bayMouth)
        root.addChildNode(bay)
    }
    return root
}
