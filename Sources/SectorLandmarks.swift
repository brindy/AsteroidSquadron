import AppKit
import SceneKit
import simd

enum SectorLandmark: String, CaseIterable {
    case planet, shatteredMoon = "moon", babylon5 = "babylon5", deathStar = "deathstar"
    case ringworld, blackHole = "blackhole", graveyard

    var title: String {
        switch self {
        case .planet: return "PLANETARY ORBIT"
        case .shatteredMoon: return "SHATTERED MOON"
        case .babylon5: return "BABYLON 5"
        case .deathStar: return "DEATH STAR"
        case .ringworld: return "RINGWORLD"
        case .blackHole: return "BLACK HOLE"
        case .graveyard: return "FLEET GRAVEYARD"
        }
    }
}

struct SectorBackdrops {
    private var random: Random
    private var remaining: [SectorLandmark] = []
    private var last: SectorLandmark?

    init(seed: UInt64) { random = Random(state:seed ^ 0x5345_4354_4F52_5353) }

    mutating func next(preferred: SectorLandmark? = nil) -> (kind: SectorLandmark, waves: Int) {
        if remaining.isEmpty { remaining = SectorLandmark.allCases }
        let candidates = remaining.indices.filter { remaining[$0] != last }
        let index = preferred.flatMap { remaining.firstIndex(of:$0) } ?? candidates[random.index(candidates.count)]
        let kind = remaining.remove(at:index)
        last = kind
        return (kind,10+random.index(11))
    }
}

// The landmarks sit well beyond the arena fog. Shade them in local space so the
// same directional key lights them as the fighters without losing their silhouettes.
func landmarkMaterial(_ base: NSColor, sun: V3, declarations: String = "", surface: String = "") -> SCNMaterial {
    let mat = material(base)
    mat.lightingModel = .constant
    mat.shaderModifiers = [.fragment:"""
    #pragma arguments
    float3 landmarkSun;
    #pragma declaration
    \(declarations)
    #pragma body
    float3 p = (scn_node.inverseModelViewTransform*float4(_surface.position,1)).xyz;
    float3 n = normalize((float4(_surface.normal,0)*scn_node.modelViewTransform).xyz);
    float3 sun = normalize((scn_node.inverseModelTransform*float4(landmarkSun,0)).xyz);
    float3 albedo = _surface.diffuse.rgb;
    float3 lamps = float3(0);
    \(surface)
    float day = max(0.0,dot(n,sun));
    float fill = max(0.0,dot(n,normalize(float3(0.4,-0.23,0.8))));
    float3 lighting = float3(0.10,0.13,0.19)+float3(1.08,0.99,0.85)*pow(day,0.85)+float3(0.06,0.12,0.22)*fill;
    _output.color = float4(albedo*lighting+lamps,1);
    """]
    mat.setValue(SCNVector3(sun),forKey:"landmarkSun")
    return mat
}

func landmarkMesh(rows: Int, columns: Int, skin: SCNMaterial, flip: Bool = false,
                          point: (Float,Float) -> V3) -> SCNNode {
    let stride = columns+1
    var vertices = [V3](), normals = [SCNVector3](), indices = [Int32]()
    for row in 0...rows {
        for column in 0...columns { vertices.append(point(Float(row)/Float(rows),Float(column)*tau/Float(columns))) }
    }
    let sign: Float = flip ? -1 : 1
    for row in 0...rows {
        for column in 0...columns {
            let left = (column+columns-1)%columns, right = (column+1)%columns
            let vertical = vertices[min(rows,row+1)*stride+column]-vertices[max(0,row-1)*stride+column]
            let around = vertices[row*stride+right]-vertices[row*stride+left]
            let normal = simd_cross(vertical,around)*sign
            let safe = simd_length_squared(normal)>1e-15 ? simd_normalize(normal) : unit(vertices[row*stride+column])
            normals.append(SCNVector3(safe))
            if row<rows && column<columns {
                let a = Int32(row*stride+column), b = a+1, c = a+Int32(stride), d = c+1
                indices += flip ? [a,b,c,b,d,c] : [a,c,b,b,c,d]
            }
        }
    }
    let geometry = SCNGeometry(sources:[SCNGeometrySource(vertices:vertices.map(SCNVector3.init)),SCNGeometrySource(normals:normals)],
                               elements:[SCNGeometryElement(indices:indices,primitiveType:.triangles)])
    return node(geometry,skin)
}

private func spherical(_ polar: Float, _ azimuth: Float) -> V3 {
    V3(sin(polar)*cos(azimuth),cos(polar),sin(polar)*sin(azimuth))
}

func shatteredMoon(seed: UInt64, towardCamera: V3, sun: V3) -> SCNNode {
    let root = SCNNode(), fragments = SCNNode()
    var rng = Random(state:seed ^ 0x4D4F_4F4E)
    let phase = rng.range(-1,1)
    let spinAxis = unit(towardCamera*0.68+V3(-towardCamera.z*0.62,1.02,towardCamera.x*0.62))
    root.simdOrientation = simd_quatf(from:V3(0,1,0),to:spinAxis)
    root.addChildNode(fragments)
    let crust = landmarkMaterial(color(0.39,0.37,0.36),sun:sun,declarations:planetNoise,surface:"""
        float3 q = normalize(p)+\(phase);
        float regolith = planetFBM(q*13.0);
        float basalt = smoothstep(0.34,0.68,planetFBM(q*3.9));
        albedo *= (0.55+regolith*0.92)*(0.58+basalt*0.52);
        """)
    let mantle = landmarkMaterial(color(0.36,0.26,0.21),sun:sun,declarations:planetNoise,surface:"""
        float plate = planetNoise(p*13.0+12.0);
        float grain = planetFBM(p*22.0);
        float strata = sin((length(p)*12.0+plate*0.45)*6.28318);
        float faults = smoothstep(0.33,0.65,grain+strata*0.1);
        albedo *= (0.42+faults*0.79)*(0.65+plate*0.65);
        albedo += float3(0.07,0.032,0.012)*faults;
        """)
    let craters = (0..<60).map { index in
        (axis:unit(rng.vector(1)),width:index<11 ? rng.range(0.06,0.24) : rng.range(0.024,0.078))
    }
    func seam(_ a: Float) -> Float {
        1.13+sin(a*2+phase)*0.16+cos(a*5+phase)*0.081+sin(a*11)*0.041+cos(a*21)*0.018
    }
    func outer(_ polar: Float, _ a: Float) -> V3 {
        let direction = spherical(polar,a)
        var elevation = sin(direction.x*31)*cos(direction.z*27+direction.y*19)*0.003
        for crater in craters {
            let d = simd_length_squared(direction-crater.axis)/(crater.width*crater.width)
            if d<1.48 {
                let rim = max(0,1-abs(sqrt(d)-0.89)*5.4)
                let bowl = max(0,1-d*1.20)
                elevation += crater.width*(rim*0.09-bowl*0.19)
            }
        }
        return direction*(1+elevation)
    }
    let body = landmarkMesh(rows:68,columns:144,skin:crust,flip:true) { t,a in
        outer(seam(a)+(.pi-seam(a))*t,a)
    }
    fragments.addChildNode(body)
    let cap = SCNNode()
    cap.addChildNode(landmarkMesh(rows:44,columns:144,skin:crust,flip:true) { t,a in outer(t*seam(a),a) })
    for chunk in [fragments,cap] {
        let top = chunk === fragments
        chunk.addChildNode(landmarkMesh(rows:18,columns:144,skin:mantle,flip:top) { t,a in
            let edge = outer(seam(a),a)
            let ridges = (sin(a*7+t*13+phase)*0.08+sin(a*19-t*17)*0.033)*sin(t*Float.pi)
            let y = mixScalar(0.32,edge.y,t)+ridges
            return V3(edge.x*t,y,edge.z*t)
        })
    }
    cap.simdPosition = V3(0.24,0.51,-0.28)
    cap.simdEulerAngles = V3(0.13,0,-0.23)
    fragments.addChildNode(cap)

    // A bridge of successively smaller boulders leads from the fracture toward the belt.
    let ejecta = SCNNode()
    let shardMeshes = (0..<4).map { i in asteroidGeometry(seed:seed &+ UInt64(i)*271,lunar:true) }
    for index in 0..<39 {
        let travel = rng.range(0.13,1.0)
        let spray = unit(rng.vector(1))
        let radius = rng.range(0.014,0.083)*(1-travel*0.62)
        let shard = SCNNode(geometry:shardMeshes[index%shardMeshes.count])
        shard.simdPosition = V3(0.21,0.58,-0.18)+V3(1.22,0.84,0.28)*travel+spray*(0.19+travel*0.38)
        shard.simdScale = V3(radius*1.2,radius*0.68,radius)
        shard.simdEulerAngles = rng.vector(.pi)
        // Reuse the asteroid mesh with the distant landmark lighting.
        let geometry = shard.geometry!.copy() as! SCNGeometry
        geometry.materials = [index%4 == 0 ? mantle : crust]
        geometry.levelsOfDetail = []
        shard.geometry = geometry
        ejecta.addChildNode(shard)
    }
    fragments.addChildNode(ejecta.flattenedClone())
    return root
}

private func mixScalar(_ a: Float, _ b: Float, _ t: Float) -> Float { a+(b-a)*t }
private func smooth(_ a: Float, _ b: Float, _ x: Float) -> Float {
    let t = max(0,min(1,(x-a)/(b-a)))
    return t*t*(3-2*t)
}

func deathStar(towardCamera: V3, sun: V3) -> SCNNode {
    let dishAxis = unit(V3(-0.42,0.42,0.81))
    let dishBasis = simd_quatf(from:V3(0,1,0),to:dishAxis)
    let skin = landmarkMaterial(color(0.45,0.48,0.52),sun:sun,declarations:"""
        \(planetNoise)
        float panelGrid(float2 uv) {
            float2 f = fract(uv);
            float2 edge = min(f,1.0-f);
            return smoothstep(0.016,0.062,min(edge.x,edge.y));
        }
        """,surface:"""
        float3 dir = normalize(p);
        float azimuth = atan2(dir.x,dir.z)/6.283185;
        float latitude = asin(clamp(dir.y,-1.0,1.0))/3.141593;
        float2 blocks = float2(azimuth*116.0,latitude*54.0);
        blocks.x += 0.44*fmod(abs(floor(blocks.y)),2.0);
        float plate = planetHash(float3(floor(blocks),1.2));
        float variation = planetNoise(dir*23.0)*0.20+plate*0.30;
        albedo *= (0.70+variation)*(0.77+0.23*panelGrid(blocks));
        float localWindows = planetHash(float3(floor(blocks*5.0),2.3));
        float windows = smoothstep(0.95,0.98,localWindows)*panelGrid(blocks*float2(5.0,9.0));
        lamps += float3(0.17,0.24,0.32)*windows*0.45;
        float trench = 1.0-smoothstep(0.018,0.025,abs(dir.y));
        albedo *= mix(1.0,0.18+0.13*step(0.77,fract(azimuth*208.0)),trench);
        lamps += trench*step(0.93,fract(azimuth*326.0))*float3(0.18,0.22,0.25);
        float3 axis = normalize(float3(-0.42,0.42,0.81));
        float theta = acos(clamp(dot(dir,axis),-1.0,1.0));
        float bowl = 1.0-smoothstep(0.235,0.250,theta);
        float3 across = normalize(cross(axis,float3(0,1,0)));
        float3 radial = cross(axis,across);
        float spoke = atan2(dot(dir,across),dot(dir,radial));
        float rings = pow(0.5+0.5*cos(theta*223.0),12.0);
        float ribs = pow(0.5+0.5*cos(spoke*32.0),18.0)*smoothstep(0.035,0.13,theta);
        float3 dish = float3(0.28,0.30,0.34)*(0.82+rings*0.30+ribs*0.40);
        albedo = mix(albedo,dish,bowl);
        albedo *= 1.0+0.48*(1.0-smoothstep(0.002,0.008,abs(theta-0.251)));
        lamps = mix(lamps,float3(0.12,0.22,0.18)*rings*0.18,bowl);
        """)
    let sphere = landmarkMesh(rows:180,columns:180,skin:skin,flip:true) { t,a in
        let theta = max(0.0001,min(Float.pi-0.0001,t*Float.pi))
        let direction = dishBasis.act(spherical(theta,a))
        let bowl: Float = 0.106*(1-smooth(0,0.242,theta))
        let lip: Float = 0.006*(1-smooth(0,0.010,abs(theta-0.252)))
        let trench: Float = 0.014*(1-smooth(0.015,0.03,abs(direction.y)))
        return direction*(1-bowl+lip-trench)
    }
    let root = SCNNode(); root.addChildNode(sphere)
    let emitter = SCNSphere(radius:0.021); emitter.segmentCount = 16
    sphere.addChildNode(node(emitter,skin,dishAxis*0.904))
    root.simdOrientation = simd_quatf(from:V3(0,0,1),to:towardCamera)
    return root
}

final class BabylonStation {
    let node = SCNNode()
    private let habitat = SCNNode()

    init(towardCamera: V3, sun: V3) {
        let plating = """
        \(planetNoise)
        """
        let panels = """
        float azimuth = atan2(p.y,p.x);
        float2 cells = float2(azimuth*8.0,p.z*61.0);
        float2 f = fract(cells);
        float id = planetHash(float3(floor(cells),3.1));
        float edge = min(min(f.x,1.0-f.x),min(f.y,1.0-f.y));
        albedo *= (0.76+id*0.37)*(0.63+0.37*smoothstep(0.018,0.09,edge));
        float strips = smoothstep(0.74,0.96,id)*step(0.81,f.y)*step(0.18,f.x)*step(f.x,0.78);
        lamps += float3(0.54,0.71,0.78)*strips;
        """
        let blue = landmarkMaterial(color(0.17,0.33,0.51),sun:sun,declarations:plating,surface:panels)
        let silver = landmarkMaterial(color(0.52,0.57,0.59),sun:sun,declarations:plating,surface:panels)
        let copper = landmarkMaterial(color(0.54,0.33,0.23),sun:sun,declarations:plating,surface:panels)
        let structural = landmarkMaterial(color(0.21,0.25,0.29),sun:sun)
        let dark = landmarkMaterial(color(0.058,0.077,0.10),sun:sun)
        let windows = landmarkMaterial(color(0.40,0.59,0.67),sun:sun,surface:"lamps += float3(0.43,0.57,0.66);")
        let runningLights = landmarkMaterial(color(0.5,0.20,0.08),sun:sun,surface:"lamps += float3(0.84,0.29,0.12);")

        func ring(_ z: Float, _ radius: Float) -> [V3] {
            (0..<40).map { i in
                let a = Float(i)*tau/40
                return V3(cos(a)*radius,-sin(a)*radius,z)
            }
        }
        func tube(_ outline: [(Float,Float)], _ skin: SCNMaterial, inward: Bool = false) -> SCNNode {
            armoredSleeve(outline.map { ring($0.0,$0.1) },material:skin,inward:inward)
        }
        let frame = SCNNode()
        frame.addChildNode(tube([(-1.52,0.126),(-1.43,0.16),(-1.16,0.20),(-0.94,0.265),(-0.74,0.25)],blue))
        // The blue nose sleeves down to a dark docking throat.
        frame.addChildNode(tube([(-1.53,0.093),(-1.52,0.126)],silver))
        frame.addChildNode(tube([(-1.53,0.093),(-1.31,0.083)],structural,inward:true))
        frame.addChildNode(cylinder(0.086,0.03,dark,V3(0,0,-1.29)))
        for index in 0..<5 {
            let x = Float(index-2)*0.025
            frame.addChildNode(box(V3(0.010,0.007,0.17),windows,V3(x,-0.052,-1.41)))
        }
        frame.addChildNode(tube([(-0.84,0.151),(0.9,0.155),(1.18,0.103),(1.55,0.047)],structural))
        frame.addChildNode(cylinder(0.049,0.14,silver,V3(0,0,1.53)))

        habitat.addChildNode(tube([(-0.83,0.212),(-0.67,0.294),(-0.47,0.309),(0.08,0.275),(0.35,0.211),(0.61,0.168)],silver))
        let collars: [(Float,Float,Float,SCNMaterial)] = [
            (-0.69,0.294,0.065,blue),(-0.52,0.312,0.060,blue),(-0.31,0.305,0.11,copper),
            (-0.11,0.298,0.07,blue),(0.08,0.280,0.05,copper),(0.31,0.226,0.08,blue),
            (0.49,0.195,0.06,copper),(0.74,0.179,0.047,silver),(1.02,0.147,0.065,copper)
        ]
        for (z,radius,length,skin) in collars {
            habitat.addChildNode(tube([(z-length/2,radius),(z+length/2,radius)],skin))
        }
        for i in 0..<10 {
            let a = Float(i)*tau/10
            let side = V3(cos(a),sin(a),0)
            let truss = segment(side*0.277+V3(0,0,-0.55),side*0.217+V3(0,0,0.37),radius:0.018,mat:structural)
            habitat.addChildNode(truss)
            for z: Float in [-0.49,-0.23,-0.02,0.16] {
                habitat.addChildNode(box(V3(0.028,0.027,0.035),windows,side*(0.310-max(0,z+0.1)*0.15)+V3(0,0,z)))
            }
        }

        for i in 0..<4 {
            let rib = SCNNode(); rib.simdEulerAngles.z = 0.38+Float(i)*tau/4
            rib.addChildNode(hullMesh([V3(0.12,-0.014,0.40),V3(0.47,-0.014,0.76),V3(0.56,-0.014,1.26),V3(0.12,-0.014,1.07),
                                       V3(0.12,0.014,0.40),V3(0.47,0.014,0.76),V3(0.56,0.014,1.26),V3(0.12,0.014,1.07)],
                                       faces:[[0,1,2,3],[4,5,6,7],[0,1,5,4],[1,2,6,5],[2,3,7,6],[3,0,4,7]],mat:structural))
            for strip in 0..<7 {
                let x = 0.23+Float(strip)*0.038
                let z = 0.82+Float(strip)*0.031
                let panel = box(V3(0.033,0.032,0.33),blue,V3(x,0,z))
                rib.addChildNode(panel)
            }
            rib.addChildNode(segment(V3(0.19,0,0.53),V3(0.55,0,1.23),radius:0.012,mat:silver))
            rib.addChildNode(box(V3(0.022,0.022,0.026),runningLights,V3(0.55,0,1.23)))
            frame.addChildNode(rib)
        }
        let command = box(V3(0.14,0.12,0.29),blue,V3(0,0.245,-1.08),chamfer:0.03)
        frame.addChildNode(command)
        frame.addChildNode(box(V3(0.11,0.023,0.028),windows,V3(0,0.258,-1.23)))
        for x: Float in [-0.075,0,0.075] {
            frame.addChildNode(segment(V3(x,0.29,-1.02),V3(x,0.44+abs(x)*0.4,-0.98),radius:0.009,mat:silver))
        }
        node.addChildNode(frame.flattenedClone())
        let spinningHull = habitat.flattenedClone()
        habitat.childNodes.forEach { $0.removeFromParentNode() }
        habitat.addChildNode(spinningHull)
        node.addChildNode(habitat)
        let heading = simd_quatf(from:V3(0,0,-1),to:towardCamera)
        node.simdOrientation = heading*simd_quatf(angle:0.94,axis:V3(0,1,0))*simd_quatf(angle:0.34,axis:V3(1,0,0))
    }

    func update(time: Float) { habitat.simdEulerAngles.z = time*0.035 }
}
