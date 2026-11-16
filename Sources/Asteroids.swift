import SceneKit
import simd

private struct AsteroidMesh {
    var directions: [V3]
    var faces: [SIMD3<Int32>]

    init() {
        let t: Float = (1+sqrt(5))/2
        directions = [
            V3(-1,t,0), V3(1,t,0), V3(-1,-t,0), V3(1,-t,0),
            V3(0,-1,t), V3(0,1,t), V3(0,-1,-t), V3(0,1,-t),
            V3(t,0,-1), V3(t,0,1), V3(-t,0,-1), V3(-t,0,1)
        ].map(simd_normalize)
        faces = [
            SIMD3(0,11,5), SIMD3(0,5,1), SIMD3(0,1,7), SIMD3(0,7,10), SIMD3(0,10,11),
            SIMD3(1,5,9), SIMD3(5,11,4), SIMD3(11,10,2), SIMD3(10,7,6), SIMD3(7,1,8),
            SIMD3(3,9,4), SIMD3(3,4,2), SIMD3(3,2,6), SIMD3(3,6,8), SIMD3(3,8,9),
            SIMD3(4,9,5), SIMD3(2,4,11), SIMD3(6,2,10), SIMD3(8,6,7), SIMD3(9,8,1)
        ]
    }

    mutating func subdivide() {
        var midpoints: [SIMD2<Int32>:Int32] = [:]
        func midpoint(_ a: Int32, _ b: Int32) -> Int32 {
            let edge = SIMD2(min(a,b),max(a,b))
            if let index = midpoints[edge] { return index }
            let index = Int32(directions.count)
            directions.append(simd_normalize(directions[Int(a)]+directions[Int(b)]))
            midpoints[edge] = index
            return index
        }
        var refined: [SIMD3<Int32>] = []
        refined.reserveCapacity(faces.count*4)
        for face in faces {
            let a = face.x, b = face.y, c = face.z
            let ab = midpoint(a,b), bc = midpoint(b,c), ca = midpoint(c,a)
            refined += [SIMD3(a,ab,ca), SIMD3(b,bc,ab), SIMD3(c,ca,bc), SIMD3(ab,bc,ca)]
        }
        faces = refined
    }

    func geometry(shape: AsteroidShape, material: SCNMaterial) -> SCNGeometry {
        let vertices = directions.map { $0*shape.radius(at:$0) }
        var normals = Array(repeating:V3.zero,count:vertices.count)
        var indices: [Int32] = []
        indices.reserveCapacity(faces.count*3)
        for face in faces {
            let a = Int(face.x), b = Int(face.y), c = Int(face.z)
            let normal = simd_cross(vertices[b]-vertices[a],vertices[c]-vertices[a])
            normals[a] += normal
            normals[b] += normal
            normals[c] += normal
            indices += [face.x,face.y,face.z]
        }
        let geometry = SCNGeometry(
            sources:[SCNGeometrySource(vertices:vertices.map(SCNVector3.init)),
                     SCNGeometrySource(normals:normals.map { SCNVector3(simd_normalize($0)) })],
            elements:[SCNGeometryElement(indices:indices,primitiveType:.triangles)]
        )
        geometry.materials = [material]
        return geometry
    }
}

private struct AsteroidShape {
    private let offset: V3
    private let axis: V3
    private let craters: [(direction: V3, width: Float, depth: Float)]

    init(random: inout Random) {
        offset = random.vector(30)
        axis = unit(random.vector(1))
        let largeCrater = (unit(random.vector(1)),random.range(0.38,0.58),random.range(0.13,0.24))
        craters = [largeCrater]+(0..<6).map { _ in
            let direction = unit(random.vector(1))
            let width = random.range(0.13,0.32)
            return (direction,width,width*random.range(0.19,0.38))
        }
    }

    func radius(at direction: V3) -> Float {
        let broad = noise(direction*1.65+offset)-0.5
        let blocks = noise(direction*4.7+offset)-0.5
        let scree = noise(direction*12+offset)-0.5
        let elongation = abs(simd_dot(direction,axis))
        var radius = 0.94+0.5*broad+0.21*blocks+0.078*scree+0.14*elongation*elongation
        for crater in craters {
            let distanceSquared = 2-2*simd_dot(direction,crater.direction)
            let t = distanceSquared/(crater.width*crater.width)
            let bowl = max(0,1-t)
            let lip = max(0,1-abs(t-0.92)*2.4)
            radius += crater.depth*(0.22*lip*lip-bowl*bowl)
        }
        // Match the existing spherical clearance used by collision and camera checks.
        return min(1.245,max(0.56,radius))
    }

    private func noise(_ point: V3) -> Float {
        let base = V3(floor(point.x),floor(point.y),floor(point.z))
        let cell = SIMD3<Int32>(base)
        let f = point-base
        let t = f*f*(3-2*f)
        func hash(_ x: Int32, _ y: Int32, _ z: Int32) -> Float {
            var n = UInt32(bitPattern:cell.x+x) &* 0x8DA6B343
            n ^= UInt32(bitPattern:cell.y+y) &* 0xD8163841
            n ^= UInt32(bitPattern:cell.z+z) &* 0xCB1AB31F
            n = (n ^ (n >> 16)) &* 0x7FEB352D
            return Float((n ^ (n >> 15)) & 0xFFFF)/65535
        }
        func row(_ y: Int32, _ z: Int32) -> Float {
            let left = hash(0,y,z)
            return left+(hash(1,y,z)-left)*t.x
        }
        let front = row(0,0)+(row(1,0)-row(0,0))*t.y
        let back = row(0,1)+(row(1,1)-row(0,1))*t.y
        return front+(back-front)*t.z
    }
}

private let asteroidSurface = """
#pragma arguments
float3 stoneOffset;
float stoneDetail;
#pragma declaration
float stoneHash(float3 p) {
    p = fract(p * 0.1031);
    p += dot(p,p.yzx + 33.33);
    return fract((p.x + p.y) * p.z);
}
float4 stoneNoise(float3 p) {
    float3 cell = floor(p), f = fract(p);
    float3 u = f*f*(3.0-2.0*f);
    float4 left = float4(stoneHash(cell),stoneHash(cell+float3(0,1,0)),
                        stoneHash(cell+float3(0,0,1)),stoneHash(cell+float3(0,1,1)));
    float4 right = float4(stoneHash(cell+float3(1,0,0)),stoneHash(cell+float3(1,1,0)),
                         stoneHash(cell+float3(1,0,1)),stoneHash(cell+float3(1,1,1)));
    float4 rows = mix(left,right,u.x);
    float2 slices = mix(rows.xz,rows.yw,u.y);
    float4 slope = right-left;
    float3 gradient = float3(mix(mix(slope.x,slope.y,u.y),mix(slope.z,slope.w,u.y),u.z),
                             mix(rows.y-rows.x,rows.w-rows.z,u.z),slices.y-slices.x);
    return float4(gradient*6.0*f*(1.0-f),mix(slices.x,slices.y,u.z));
}
#pragma body
float3 p = (scn_node.inverseModelViewTransform*float4(_surface.position,1.0)).xyz;
float3 q = p+stoneOffset;
float strata = stoneNoise(q*5.5).w;
float4 chipField = stoneNoise(q*17.0+float3(4.0,2.0,1.0));
float chips = chipField.w;
float recess = 1.0-smoothstep(0.16,0.46,chips);
float tone = mix(0.53,1.22,smoothstep(0.16,0.85,strata))*(0.84+0.33*chips);
_surface.diffuse.rgb *= tone*(1.0-0.24*recess);
_surface.diffuse.rgb += float3(0.071,0.034,0.012)*smoothstep(0.48,0.84,strata);
_surface.roughness = 0.79+0.2*recess;
if (stoneDetail>0.5) {
    float footprint = max(length(dfdx(p)),length(dfdy(p)));
    float fade = 1.0-smoothstep(0.007,0.026,footprint);
    float4 fine = stoneNoise(q*54.0+9.0);
    _surface.diffuse.rgb *= 1.0+(fine.w-0.5)*0.27*fade;
    float3 localGradient = chipField.xyz*0.26+fine.xyz*0.15*fade;
    float3 gradient = (float4(localGradient,0)*scn_node.inverseModelViewTransform).xyz;
    float3 n = normalize(_surface.normal);
    gradient *= length(scn_node.modelViewTransform[0].xyz);
    _surface.normal = normalize(n-(gradient-n*dot(n,gradient)));
}
"""

func asteroidGeometry(seed: UInt64, lunar: Bool = false) -> SCNGeometry {
    var random = Random(state:seed)
    let shape = AsteroidShape(random:&random)
    let tint = CGFloat(random.range(0.24,0.42))
    let warmth = CGFloat(random.range(0,1))
    let base = lunar ? color(tint*0.97,tint*1.10,tint*1.21) : color(tint+0.03*warmth,tint*(0.94-0.14*warmth),tint*(0.91-0.24*warmth))
    let stone = material(base)
    stone.roughness.contents = 0.9
    stone.shaderModifiers = [.surface:asteroidSurface]
    stone.setValue(SCNVector3(random.vector(21)),forKey:"stoneOffset")
    stone.setValue(Float(1),forKey:"stoneDetail")
    let distantStone = stone.copy() as! SCNMaterial
    distantStone.setValue(stone.value(forKey:"stoneOffset"),forKey:"stoneOffset")
    distantStone.setValue(Float(0),forKey:"stoneDetail")

    var mesh = AsteroidMesh()
    mesh.subdivide()
    mesh.subdivide()
    let distant = mesh.geometry(shape:shape,material:distantStone)
    mesh.subdivide()
    let medium = mesh.geometry(shape:shape,material:stone)
    mesh.subdivide()
    let close = mesh.geometry(shape:shape,material:stone)
    close.levelsOfDetail = [
        SCNLevelOfDetail(geometry:medium,screenSpaceRadius:86),
        SCNLevelOfDetail(geometry:distant,screenSpaceRadius:25)
    ]
    return close
}
