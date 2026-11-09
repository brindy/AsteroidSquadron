import AppKit
import SceneKit
import simd

// A ray-marched density field inside an ellipsoid, rather than a textured sky plane.
// Twenty samples and three noise octaves keep this practical at the default 30 fps.
let nebulaFragment = """
#pragma arguments
float cloudTime;
float cloudSeed;
float3 cloudTint;
#pragma declaration
float gasHash(float3 p) {
    p = fract(p * 0.1031);
    p += dot(p, p.yzx + 33.33);
    return fract((p.x + p.y) * p.z);
}
float gasNoise(float3 p) {
    float3 i = floor(p), f = fract(p);
    f = f*f*(3.0-2.0*f);
    return mix(mix(mix(gasHash(i),gasHash(i+float3(1,0,0)),f.x),
                   mix(gasHash(i+float3(0,1,0)),gasHash(i+float3(1,1,0)),f.x),f.y),
               mix(mix(gasHash(i+float3(0,0,1)),gasHash(i+float3(1,0,1)),f.x),
                   mix(gasHash(i+float3(0,1,1)),gasHash(i+float3(1,1,1)),f.x),f.y),f.z);
}
float gasDensity(float3 p) {
    return gasNoise(p)*0.57 + gasNoise(p*2.07+7.3)*0.29 + gasNoise(p*4.13-3.1)*0.14;
}
#pragma transparent
#pragma body
float3 eye = (scn_node.inverseModelViewTransform * float4(0,0,0,1)).xyz;
float3 ray = normalize((scn_node.inverseModelViewTransform * float4(normalize(_surface.position),0)).xyz);
float b = dot(eye,ray);
float disc = b*b-dot(eye,eye)+1.0;
if (disc <= 0.0) { discard_fragment(); }
float nearT = max(0.0,-b-sqrt(disc)), farT = -b+sqrt(disc);
float stepSize = (farT-nearT)/20.0;
float opacity = 0.0;
float3 accumulated = float3(0);
float3 drift = float3(cloudTime*0.014,cloudTime*0.008,cloudSeed);
for (int sample = 0; sample < 20; sample++) {
    float3 p = eye + ray * (nearT + (float(sample)+0.5)*stepSize);
    float edge = 1.0-smoothstep(0.25,1.0,length(p));
    float noise = gasDensity(p*3.8+drift);
    float density = max(0.0,noise-0.30)*edge*2.6;
    float alpha = 1.0-exp(-density*stepSize*1.25);
    float lighting = 0.48 + 0.52*smoothstep(-0.8,0.8,p.y+p.x*0.35);
    float3 tint = cloudTint*(lighting+noise*0.5);
    accumulated += (1.0-opacity)*alpha*tint;
    opacity += (1.0-opacity)*alpha;
}
_output.color = float4(accumulated,opacity);
"""

struct GasCloud {
    let node: SCNNode
    let material: SCNMaterial

    init(position: V3, scale: V3, tint: NSColor, seed: Float) {
        let sphere = SCNSphere(radius:1)
        sphere.segmentCount = 28
        material = SCNMaterial()
        material.lightingModel = .constant
        material.diffuse.contents = NSColor.white
        material.writesToDepthBuffer = false
        material.readsFromDepthBuffer = true
        material.shaderModifiers = [.fragment:nebulaFragment]
        material.setValue(Float(0),forKey:"cloudTime")
        material.setValue(seed,forKey:"cloudSeed")
        material.setValue(SCNVector3(tint.redComponent,tint.greenComponent,tint.blueComponent),forKey:"cloudTint")
        sphere.materials = [material]
        node = SCNNode(geometry:sphere)
        node.simdPosition = position
        node.simdScale = scale
        node.renderingOrder = 50
    }

    func update(time: Float, camera: V3) {
        material.setValue(time,forKey:"cloudTime")
        // Draw the exit surface while inside the volume, the entry surface outside.
        let localEye = (camera-node.simdPosition)/node.simdScale
        material.cullMode = simd_length_squared(localEye)<1 ? .front : .back
    }
}
