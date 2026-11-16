import AppKit
import SceneKit
import simd

func ringworld(seed: UInt64, towardCamera: V3, sun: V3) -> SCNNode {
    var random = Random(state:seed ^ 0x5249_4E47)
    let offset = random.range(0,80)
    let inner = landmarkMaterial(color(0.36,0.53,0.42),sun:sun,declarations:planetNoise,surface:"""
        float a = atan2(p.z,p.x);
        float strip = p.y*6.4;
        float3 ground = float3(cos(a)*11.0,sin(a)*11.0,strip*2.1)+\(offset);
        float continent = planetFBM(ground);
        float hills = planetNoise(ground*5.4);
        float land = smoothstep(0.46,0.518,continent);
        float3 water = mix(float3(0.016,0.075,0.15),float3(0.07,0.35,0.34),smoothstep(0.31,0.49,continent));
        float3 soil = mix(float3(0.12,0.26,0.16),float3(0.56,0.50,0.32),smoothstep(0.48,0.75,continent+hills*0.11));
        float clouds = smoothstep(0.57,0.74,planetFBM(ground*2.4+float3(1.9,5.1,8.7)));
        albedo = mix(mix(water,soil,land),float3(0.63,0.72,0.72),clouds*0.59);
        float rails = smoothstep(0.88,0.96,abs(strip));
        albedo = mix(albedo,float3(0.32,0.40,0.46),rails);
        lamps += float3(0.036,0.085,0.096)*(0.5+0.5*land);
        """)
    let shell = landmarkMaterial(color(0.24,0.28,0.33),sun:sun,declarations:planetNoise,surface:"""
        float a = atan2(p.z,p.x)*44.0;
        float axial = p.y*28.0 + fmod(floor(a),2.0)*0.5;
        float2 uv = float2(a,axial);
        float2 f = fract(uv);
        float panel = planetHash(float3(floor(uv),2.1));
        albedo *= (0.61+panel*0.54)*(0.70+0.30*smoothstep(0.04,0.12,min(f.x,f.y)));
        float windows = step(0.81,panel)*smoothstep(0.78,0.90,f.y)*step(0.33,f.x)*step(f.x,0.68);
        lamps += float3(0.22,0.37,0.49)*windows;
        """)
    let rim = landmarkMaterial(color(0.42,0.48,0.56),sun:sun,surface:"""
        float angle = atan2(p.z,p.x);
        float seam = step(0.94,fract(angle*57.3));
        albedo *= 1.0-0.48*seam;
        float rail = exp(-abs(length(p.xz)-2.624)*265.0);
        lamps += (1.0-seam)*rail*float3(0.32,0.60,0.84);
        """)
    let root = SCNNode()
    let band = SCNNode()
    let inside: Float = 2.59, outside: Float = 2.67, width: Float = 0.147
    for (radius,skin) in [(inside,inner),(outside,shell)] {
        band.addChildNode(landmarkMesh(rows:8,columns:256,skin:skin,flip:radius == inside) { t,a in
            V3(cos(a)*radius,(2*t-1)*width,sin(a)*radius)
        })
    }
    for sign: Float in [-1,1] {
        band.addChildNode(landmarkMesh(rows:4,columns:256,skin:rim,flip:sign>0) { t,a in
            let r = inside+(outside-inside)*t
            return V3(cos(a)*r,sign*width,sin(a)*r)
        })
    }
    let supports = SCNNode()
    for i in 0..<90 {
        let a = Float(i)*tau/90
        let beam = box(V3(0.022,0.35,0.067),shell,V3(cos(a)*2.65,0,sin(a)*2.65),chamfer:0.007)
        beam.simdEulerAngles.y = -a
        supports.addChildNode(beam)
    }
    band.addChildNode(supports.flattenedClone())
    band.simdEulerAngles = V3(0.41,0,random.range(-0.44,-0.27))
    root.simdOrientation = simd_quatf(from:V3(0,0,1),to:towardCamera)
    root.addChildNode(band)
    return root
}

final class BlackHoleBackdrop {
    let node: SCNNode
    private let effect: SCNMaterial

    init(towardCamera: V3, sky: Any?) {
        let lens = material(.white)
        lens.lightingModel = .constant
        lens.blendMode = .alpha
        lens.writesToDepthBuffer = false
        lens.shaderModifiers = [.fragment:"""
        #pragma transparent
        #pragma arguments
        texture2d<float> distantSky;
        float diskTime;
        #pragma declaration
        constexpr sampler skySampler (coord::normalized, s_address::repeat, t_address::clamp_to_edge, filter::linear);
        #pragma body
        float3 p = (scn_node.inverseModelViewTransform*float4(_surface.position,1)).xyz;
        float3 eye = (scn_node.inverseModelViewTransform*float4(0,0,0,1)).xyz;
        float3 ray = normalize(p-eye);
        float3 nearest = eye-ray*dot(eye,ray);
        float b = length(nearest);
        float3 sight = normalize(eye);
        float3 right = normalize(cross(float3(0,1,0),sight));
        float3 up = cross(sight,right);
        float x = dot(nearest,right), y = dot(nearest,up);
        float shadow = 1.0-smoothstep(0.410,0.425,b);

        // Approximate light bending with a radial deflection that falls off into
        // the same procedural sky, rather than drawing a fixed ring of stars.
        float warp = 1.0-smoothstep(0.72,1.40,b);
        float angle = 0.047*warp/max(0.31,b);
        float3 backgroundRay = normalize(ray - nearest*angle/max(0.001,b));
        float3 world = normalize((scn_node.modelTransform*float4(backgroundRay,0)).xyz);
        float2 uv = float2(atan2(world.x,world.z)/6.283185+0.5,asin(clamp(world.y,-1.0,1.0))/3.141593+0.5);
        float3 stars = distantSky.sample(skySampler,uv).rgb*0.83;

        // A tilted, thin near disk crosses the shadow. Its far side is imaged
        // in curved arcs above and below, with the approaching gas brighter.
        float lean = 0.10 + 0.32*sight.y;
        float diskY = y-0.105*x;
        float nearY = diskY+lean*0.23;
        float radius = sqrt(x*x+nearY*nearY*19.0);
        float radialWindow = smoothstep(0.47,0.54,radius)*(1.0-smoothstep(0.87,1.28,radius));
        float threads = 0.56+0.44*sin(65.0*radius+2.2*sin(x*11.0-nearY*14.0+diskTime*0.45));
        float inFront = mix(1.0,1.0-smoothstep(-0.03,0.035,diskY),shadow);
        float sheet = exp(-abs(nearY)*10.0)*radialWindow*(0.35+threads*0.65)*inFront;
        float bentY = diskY*(diskY>0.0 ? 0.79 : 1.44);
        float bend = sqrt(x*x+bentY*bentY);
        float fold = exp(-abs(bend-0.445)*35.0)*smoothstep(0.417,0.454,b)*(0.28+0.72*smoothstep(0.015,0.18,abs(diskY)));
        float rim = exp(-abs(b-0.422)*225.0);
        float heat = smoothstep(-0.62,0.68,x);
        float3 tint = mix(float3(0.75,0.15,0.038),float3(1.6,0.73,0.31),heat);
        float3 light = tint*(sheet*1.47+fold*(0.45+0.43*heat)) + float3(1.0,0.64,0.38)*rim*0.56;
        float cover = max(shadow,warp*0.79);
        float alpha = max(cover,min(0.90,length(light)));
        _output.color = float4(mix(stars*warp,float3(0.0004,0.0006,0.0011),shadow)+light,alpha);
        """]
        let skyTexture = SCNMaterialProperty(contents:sky ?? NSColor.black)
        skyTexture.wrapS = .repeat
        skyTexture.wrapT = .clamp
        lens.setValue(skyTexture,forKey:"distantSky")
        lens.setValue(Float.zero,forKey:"diskTime")
        let geometry = SCNSphere(radius:1.46); geometry.segmentCount = 92
        node = SCNNode(geometry:geometry); geometry.materials = [lens]
        node.simdOrientation = simd_quatf(from:V3(0,0,1),to:towardCamera)
            * simd_quatf(angle:0.20,axis:V3(0,0,1))
        node.renderingOrder = 2
        effect = lens
    }

    func update(time: Float) { effect.setValue(time,forKey:"diskTime") }
}

func wreckedHull(seed: UInt64, sun: V3? = nil) -> SCNNode {
    var random = Random(state:seed ^ 0x4855_4C4B)
    func skin(_ base: NSColor) -> SCNMaterial {
        if let sun {
            return landmarkMaterial(base,sun:sun,declarations:planetNoise,surface:"""
                float corrosion = planetFBM(p*21.0);
                albedo *= 0.57+0.66*corrosion;
                albedo += float3(0.088,0.035,0.014)*smoothstep(0.48,0.70,corrosion);
                """)
        }
        return material(base,metal:0.39)
    }
    let hull = skin(color(0.37,0.39,0.40)), plate = skin(color(0.45,0.44,0.40))
    let steel = skin(color(0.23,0.26,0.29)), torn = skin(color(0.23,0.123,0.084))
    let hollow = skin(color(0.065,0.072,0.088))
    let root = SCNNode(); root.name = "wreck.hull"
    let shell = SCNNode(), frames = SCNNode()
    let broad = random.range(0.31,0.62)
    let height = random.range(0.113,0.19)
    let rupture: Float = random.range(-0.20,0.0)
    let aft: Float = 0.70
    // Armour panels end at varying cuts, leaving the underlying rib cage exposed.
    for i in 0..<7 {
        let step = Float(i)*0.119
        let span = broad*(1-step*0.39)
        let z = aft-step
        for side: Float in [-1,1] {
            let tear = step>0.50 ? random.range(-0.04,0.10) : 0
            let x0 = side*span*(step>0.56 ? 0.33 : 0.16)
            let x1 = side*span
            let deck = [V3(x0,height,z-0.091),V3(x1,height*0.48,z-0.065-tear),V3(x1,height*0.50,z+0.03),V3(x0,height,z+0.037)]
            let shellPoints = deck+deck.map { $0-V3(0,0.026,0) }
            shell.addChildNode(hullMesh(shellPoints,faces:[[0,1,2,3],[4,5,6,7],[0,1,5,4],[1,2,6,5],[2,3,7,6],[3,0,4,7]],mat:i%3 == 0 ? plate : hull))
            let belly = box(V3(span*0.78,0.04,0.084),steel,V3(side*span*0.49,-height*0.66,z),chamfer:0.012)
            shell.addChildNode(belly)
        }
    }
    shell.addChildNode(box(V3(broad*1.06,height*0.82,0.48),hollow,V3(0,0,0.44),chamfer:0.032))
    let bridgeX = random.range(-0.11,0.11)
    let bridgeZ = random.range(0.28,0.47)
    let bridge = box(V3(broad*0.62,0.15,0.28),hull,V3(bridgeX,height+0.016,bridgeZ),chamfer:0.027)
    shell.addChildNode(bridge)
    shell.addChildNode(box(V3(broad*0.46,0.061,0.18),plate,V3(bridgeX,height+0.106,bridgeZ),chamfer:0.013))
    let engines = 2+random.index(3)
    for i in 0..<engines {
        let x = (Float(i)/Float(engines-1)-0.5)*broad*1.43
        let radius: CGFloat = engines == 4 ? 0.069 : 0.086
        shell.addChildNode(cylinder(radius,0.12,steel,V3(x,0,0.77)))
        shell.addChildNode(cylinder(radius*0.70,0.018,hollow,V3(x,0,0.833)))
    }
    for i in 0..<5 {
        let z = rupture-Float(i)*0.087
        let span = broad*(0.82-Float(i)*0.075)
        let y = height*(0.78-Float(i)*0.08)
        let crossbar = box(V3(span*1.8,0.027,0.032),torn,V3(random.range(-0.041,0.041),y,z))
        crossbar.simdEulerAngles.z = random.range(-0.19,0.19)
        frames.addChildNode(crossbar)
        for side: Float in [-1,1] {
            let beam = segment(V3(side*span*0.89,y,z),V3(side*span*0.7,-y*0.81,z+0.028),radius:0.014,mat:steel)
            frames.addChildNode(beam)
        }
    }
    for x: Float in [-0.11,0,0.13] {
        frames.addChildNode(segment(V3(x,-0.02,0.26),V3(x*1.4,random.range(-0.11,0.05),rupture-random.range(0.32,0.48)),radius:0.018,mat:torn))
    }
    root.addChildNode(shell.flattenedClone()); root.addChildNode(frames.flattenedClone())
    return root
}

func fleetGraveyard(seed: UInt64, towardCamera: V3, sun: V3) -> SCNNode {
    var random = Random(state:seed ^ 0x4752_4156_45)
    let root = SCNNode()
    let lead = wreckedHull(seed:seed,sun:sun)
    lead.simdEulerAngles = V3(-0.43,0.82,0.70)
    lead.simdScale = V3(repeating:1.28)
    root.addChildNode(lead)
    for i in 0..<14 {
        let a = Float(i)*tau/14+random.range(-0.2,0.2)
        let spread = random.range(i<7 ? 0.77 : 1.32,i<7 ? 1.43 : 2.07)
        let piece = wreckedHull(seed:seed &+ UInt64(i+1)*323,sun:sun)
        piece.simdPosition = V3(cos(a)*spread,sin(a)*spread*0.66,random.range(-0.75,0.75))
        piece.simdScale = V3(repeating:random.range(0.16,0.47))
        piece.simdEulerAngles = random.vector(.pi)
        root.addChildNode(piece)
    }
    root.simdOrientation = simd_quatf(from:V3(0,0,1),to:towardCamera)
    return root
}
