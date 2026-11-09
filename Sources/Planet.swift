import AppKit
import SceneKit
import simd

enum PlanetBiome: Int, CaseIterable {
    case temperate, saltDesert, ice, rust
    var slug: String { ["temperate","salt-desert","ice","rust"][rawValue] }
    var title: String { ["TEMPERATE WORLD","SALT DESERT","ICE WORLD","RUST WORLD"][rawValue] }
}

// Noise is evaluated on the sphere itself: no image downloads, UV seam, or polar stretch.
private let planetNoise = """
float planetHash(float3 p) {
    p = fract(p*0.1031);
    p += dot(p,p.yzx+33.33);
    return fract((p.x+p.y)*p.z);
}
float planetNoise(float3 p) {
    float3 i = floor(p), f = fract(p);
    f = f*f*(3.0-2.0*f);
    return mix(mix(mix(planetHash(i),planetHash(i+float3(1,0,0)),f.x),
                   mix(planetHash(i+float3(0,1,0)),planetHash(i+float3(1,1,0)),f.x),f.y),
               mix(mix(planetHash(i+float3(0,0,1)),planetHash(i+float3(1,0,1)),f.x),
                   mix(planetHash(i+float3(0,1,1)),planetHash(i+float3(1,1,1)),f.x),f.y),f.z);
}
float planetFBM(float3 p) {
    float result = 0.0, amplitude = 0.508;
    for (int octave=0; octave<6; octave++) {
        result += planetNoise(p)*amplitude;
        p = float3(dot(p,float3(0,0.8,0.6)),dot(p,float3(-0.8,0.36,-0.48)),dot(p,float3(-0.6,-0.48,0.64)))*2.03+float3(7.1,3.4,1.7);
        amplitude *= 0.5;
    }
    return result;
}
float planetClouds(float3 p,float seed,float time) {
    // Differential latitude winds shear the domain into curling weather bands.
    float angle = sin(p.y*6.0)*0.34+time*0.0015;
    p.xz = float2(p.x*cos(angle)-p.z*sin(angle),p.x*sin(angle)+p.z*cos(angle));
    float3 offset = float3(seed,seed*0.37,seed*0.71);
    float3 warp = float3(planetNoise(p*3.8+offset),planetNoise(p*3.8+offset+17.2),planetNoise(p*3.8+offset-6.4));
    float weather = planetFBM(p*6.5+offset+warp*1.8);
    float wisps = planetNoise(p*70.0+offset)*0.045;
    return smoothstep(0.49,0.68,weather+wisps);
}
float planetCloudAmount(float biome) {
    return biome<0.5 ? 1.0 : (biome<1.5 ? 0.18 : (biome<2.5 ? 0.48 : 0.12));
}
"""

private let surfaceFragment = """
#pragma arguments
float planetSeed;
float seaLevel;
float planetTime;
float planetBiome;
float3 planetSun;
#pragma declaration
""" + "\n" + planetNoise + "\n" + """
#pragma body
float3 point = (scn_node.inverseModelViewTransform*float4(_surface.position,1)).xyz;
float3 p = normalize(point);
float3 eye = (scn_node.inverseModelViewTransform*float4(0,0,0,1)).xyz;
float3 view = normalize(eye-point);
float3 sun = normalize((scn_node.inverseModelTransform*float4(planetSun,0)).xyz);
float3 offset = float3(planetSeed,planetSeed*0.37,planetSeed*0.71);
float3 warp = float3(planetNoise(p*2.7+offset),planetNoise(p*2.7+offset+9.3),planetNoise(p*2.7+offset-7.2))-0.5;
float continent = planetFBM(p*2.1+offset+warp*0.95);
float elevation = max(0.0,continent-seaLevel);
float land = smoothstep(seaLevel-0.004,seaLevel+0.008,continent);
float detail = planetFBM(p*23.0+offset);
float ridge = pow(1.0-abs(2.0*detail-1.0),4.0);
float mountain = smoothstep(0.035,0.17,elevation)*ridge;
float latitude = abs(p.y);
float moisture = planetFBM(p*4.3+offset+31.4);
float3 grass = float3(0.27,0.31,0.12), forest = float3(0.075,0.17,0.065), sand = float3(0.57,0.42,0.24);
float3 rock = float3(0.34,0.32,0.29), snow = float3(0.83,0.86,0.85);
float3 deep = float3(0.008,0.033,0.095), shallow = float3(0.013,0.12,0.19), shore = float3(0.035,0.29,0.30);
float wetness = 1.0, polarCoverage = 1.0;
if (planetBiome>0.5 && planetBiome<1.5) {
    // Low basins are dune sand; the former green highlands become white salt/chalk.
    grass = float3(0.84,0.82,0.72); forest = float3(0.94,0.92,0.84); sand = float3(0.94,0.86,0.66);
    rock = float3(0.62,0.57,0.47); snow = float3(0.94,0.93,0.88);
    deep = float3(0.44,0.24,0.085); shallow = float3(0.77,0.55,0.25); shore = float3(0.92,0.76,0.44);
    wetness = 0.0; polarCoverage = 0.12;
} else if (planetBiome>1.5 && planetBiome<2.5) {
    grass = float3(0.76,0.84,0.86); forest = float3(0.88,0.91,0.92); sand = float3(0.61,0.73,0.77);
    rock = float3(0.38,0.48,0.55); snow = float3(0.94,0.96,0.97);
    deep = float3(0.055,0.15,0.24); shallow = float3(0.29,0.52,0.60); shore = float3(0.64,0.80,0.84);
    wetness = 0.12;
} else if (planetBiome>2.5) {
    grass = float3(0.58,0.28,0.13); forest = float3(0.71,0.42,0.22); sand = float3(0.77,0.51,0.28);
    rock = float3(0.25,0.18,0.15); snow = float3(0.80,0.71,0.58);
    deep = float3(0.19,0.055,0.025); shallow = float3(0.42,0.17,0.065); shore = float3(0.61,0.33,0.14);
    wetness = 0.0; polarCoverage = 0.25;
}
float3 landColor = mix(grass,forest,smoothstep(0.36,0.62,moisture));
float desert = smoothstep(0.04,0.2,latitude)*(1.0-smoothstep(0.43,0.62,latitude))*(1.0-smoothstep(0.4,0.57,moisture));
landColor = mix(landColor,sand,desert*0.9);
landColor = mix(landColor,rock,mountain);
landColor *= 0.82+detail*0.4;
float ice = smoothstep(0.78,0.91,latitude+elevation*0.65+(detail-0.5)*0.1)*polarCoverage;
float alpine = smoothstep(0.18,0.28,elevation+latitude*0.06)*mountain;
landColor = mix(landColor,snow,alpine);
float shelf = smoothstep(seaLevel-0.12,seaLevel,continent);
float3 ocean = mix(deep,shallow,shelf);
ocean = mix(ocean,shore,smoothstep(seaLevel-0.018,seaLevel,continent)*0.75);
float3 albedo = mix(ocean,landColor,land);
albedo = mix(albedo,snow,ice);
// Screen derivatives give the terrain a normal without changing the planet silhouette.
float relief = elevation*1.8+detail*0.025*land;
float3 tx = dfdx(p), ty = dfdy(p), rx = cross(ty,p), ry = cross(p,tx);
float determinant = dot(tx,rx);
float3 gradient = (rx*dfdx(relief)+ry*dfdy(relief))/(abs(determinant)>0.0000001 ? determinant : 0.0000001);
gradient *= min(1.0,4.0/max(0.001,length(gradient)));
float3 normal = normalize(p-gradient*0.045*land);
float day = max(0.0,dot(normal,sun));
float clouds = planetClouds(normalize(p+sun*0.008),planetSeed,planetTime)*planetCloudAmount(planetBiome);
float3 lighting = float3(0.012,0.019,0.032)+float3(1.0,0.96,0.87)*pow(day,0.85)*1.23;
float3 result = albedo*lighting*(1.0-clouds*0.22);
float glint = pow(max(0.0,dot(normal,normalize(sun+view))),180.0)*day*(1.0-land)*(1.0-ice)*wetness;
result += float3(1.0,0.94,0.8)*glint*0.8;
_output.color = float4(result,1);
"""

private let cloudFragment = """
#pragma arguments
float planetSeed;
float planetTime;
float planetBiome;
float3 planetSun;
#pragma declaration
""" + "\n" + planetNoise + "\n" + """
#pragma transparent
#pragma body
float3 p = normalize((scn_node.inverseModelViewTransform*float4(_surface.position,1)).xyz);
float density = planetClouds(p,planetSeed,planetTime)*planetCloudAmount(planetBiome);
float3 sun = normalize((scn_node.inverseModelTransform*float4(planetSun,0)).xyz);
float day = max(0.0,dot(p,sun));
float edge = planetClouds(normalize(p+sun*0.018),planetSeed,planetTime);
float lighting = (0.7+0.3*clamp(density-edge+0.5,0.0,1.0))*pow(day,0.72);
float3 tint = float3(0.025,0.035,0.055)+float3(1.0,0.98,0.94)*lighting*1.18;
_output.color = float4(tint*density*0.92,density*0.92);
"""

private let atmosphereFragment = """
#pragma arguments
float3 planetSun;
float planetBiome;
#pragma transparent
#pragma body
float3 point = (scn_node.inverseModelViewTransform*float4(_surface.position,1)).xyz;
float3 eye = (scn_node.inverseModelViewTransform*float4(0,0,0,1)).xyz;
float3 ray = normalize(point-eye);
float3 sun = normalize((scn_node.inverseModelTransform*float4(planetSun,0)).xyz);
float b = dot(eye,ray), ee = dot(eye,eye);
float disc = b*b-ee+1.04*1.04;
if (disc<=0.0) { discard_fragment(); }
float lo = max(0.0,-b-sqrt(disc)), hi = -b+sqrt(disc);
float ground = b*b-ee+1.0;
if (ground>0.0) { hi = min(hi,-b-sqrt(ground)); }
if (hi<=lo) { discard_fragment(); }
float ds = (hi-lo)/12.0;
float3 beta = float3(0.12,0.30,0.70)*2.0;
if (planetBiome>0.5 && planetBiome<1.5) { beta = float3(0.42,0.28,0.13)*1.3; }
else if (planetBiome>1.5 && planetBiome<2.5) { beta = float3(0.18,0.40,0.62)*2.0; }
else if (planetBiome>2.5) { beta = float3(0.55,0.24,0.09)*1.3; }
float3 transmittance = float3(1), scatter = float3(0);
float mu = dot(ray,sun), phase = 0.7*(1.0+mu*mu);
for (int sample=0; sample<12; sample++) {
    float3 p = eye+ray*(lo+(float(sample)+0.5)*ds);
    float height = max(0.0,(length(p)-1.0)/0.04);
    float density = exp(-height*5.5);
    float daylight = smoothstep(-0.10,0.18,dot(normalize(p),sun));
    float sunB = dot(p,sun), shadow = sunB*sunB-dot(p,p)+1.0;
    if (shadow>0.0 && -sunB-sqrt(shadow)>0.0) { daylight *= 0.05; }
    float3 extinction = exp(-beta*density*ds*6.0);
    scatter += transmittance*(1.0-extinction)*daylight*phase;
    transmittance *= extinction;
}
float alpha = clamp(1.0-dot(transmittance,float3(0.2126,0.7152,0.0722)),0.0,0.92);
// SceneKit's transparent shader modifiers require premultiplied radiance.
_output.color = float4(scatter,alpha);
"""

final class ProceduralPlanet {
    let node = SCNNode()
    let surface: SCNNode
    let clouds: SCNNode
    let atmosphere: SCNNode
    let seed: UInt64
    let noiseSeed: Float
    let seaLevel: Float
    private(set) var biome: PlanetBiome
    var sunDirection: V3
    private let orientation: simd_quatf

    init(seed: UInt64, radius: Float, sun: V3, biome requestedBiome: PlanetBiome? = nil) {
        self.seed = seed; sunDirection = unit(sun)
        var random = Random(state:seed ^ 0x50_AA_7E)
        noiseSeed = random.range(3,97); seaLevel = random.range(0.46,0.53)
        orientation = simd_quatf(angle:random.range(0,tau),axis:V3(0,1,0))*simd_quatf(angle:random.range(0.18,0.47),axis:V3(0,0,1))
        biome = requestedBiome ?? PlanetBiome.allCases[random.index(PlanetBiome.allCases.count)]
        func layer(_ radius: CGFloat, _ fragment: String, name: String, transparent: Bool) -> SCNNode {
            let material = SCNMaterial(); material.lightingModel = .constant
            material.diffuse.contents = NSColor.white
            material.shaderModifiers = [.fragment:fragment]
            material.writesToDepthBuffer = !transparent; material.readsFromDepthBuffer = true
            if transparent { material.blendMode = .alpha }
            let geometry = SCNSphere(radius:radius); geometry.segmentCount = 128
            let result = SCNNode(geometry:geometry); result.name = name
            geometry.materials = [material]
            return result
        }
        surface = layer(1,surfaceFragment,name:"planet.surface",transparent:false)
        clouds = layer(1.008,cloudFragment,name:"planet.clouds",transparent:true)
        atmosphere = layer(1.04,atmosphereFragment,name:"planet.atmosphere",transparent:true)
        clouds.renderingOrder = 5; atmosphere.renderingOrder = 10
        node.name = "procedural.planet"; node.simdScale = V3(repeating:radius)
        for child in [surface,clouds,atmosphere] { node.addChildNode(child) }
        for child in [surface,clouds] {
            let material = child.geometry!.firstMaterial!
            material.setValue(noiseSeed,forKey:"planetSeed")
            material.setValue(Float(0),forKey:"planetTime")
        }
        surface.geometry!.firstMaterial!.setValue(seaLevel,forKey:"seaLevel")
        setBiome(biome)
        update(time:0)
    }

    func setBiome(_ value: PlanetBiome) {
        biome = value
        for child in [surface,clouds,atmosphere] { child.geometry!.firstMaterial!.setValue(Float(value.rawValue),forKey:"planetBiome") }
    }

    func update(time: Float) {
        let rotation = orientation*simd_quatf(angle:time*0.003,axis:V3(0,1,0))
        for child in [surface,clouds,atmosphere] {
            child.simdOrientation = rotation
            child.geometry!.firstMaterial!.setValue(SCNVector3(sunDirection),forKey:"planetSun")
        }
        for child in [surface,clouds] { child.geometry!.firstMaterial!.setValue(time,forKey:"planetTime") }
    }
}
