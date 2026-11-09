import AppKit
import SceneKit
import simd

// Reuse the tested volume noise, with a cooling fuel cloud rather than a solid sphere.
private let blastNoise = String(nebulaFragment.components(separatedBy:"#pragma declaration")[1].components(separatedBy:"#pragma transparent")[0])
private let blastFragment = """
#pragma arguments
float blastAge;
float blastSeed;
#pragma declaration
""" + blastNoise + """
#pragma transparent
#pragma body
float3 eye = (scn_node.inverseModelViewTransform*float4(0,0,0,1)).xyz;
float3 ray = normalize((scn_node.inverseModelViewTransform*float4(normalize(_surface.position),0)).xyz);
float b = dot(eye,ray), disc = b*b-dot(eye,eye)+1.0;
if (disc <= 0.0) { discard_fragment(); }
float lo = max(0.0,-b-sqrt(disc)), hi = -b+sqrt(disc), ds = (hi-lo)/24.0;
float opacity = 0.0;
float3 radiance = float3(0);
float lifeFade = 1.0-smoothstep(2.4,4.5,blastAge);
for (int i=0; i<24; i++) {
    float3 p = eye+ray*(lo+(float(i)+0.5)*ds);
    float3 swirl = p*4.5+float3(blastAge*0.5,-blastAge*0.7,blastSeed);
    float noise = gasDensity(swirl);
    float radius = length(p);
    float edge = 1.0-smoothstep(0.48+noise*0.28,0.96,radius);
    float density = max(0.0,noise-0.25)*edge*9.0*lifeFade;
    float heat = exp(-blastAge*1.8)*(1.0-radius*0.75)*(0.65+noise*0.7);
    float3 flame = mix(float3(0.48,0.035,0.004),float3(3.0,0.65,0.055),smoothstep(0.06,0.65,heat));
    flame = mix(flame,float3(5.0,3.4,1.6),smoothstep(0.65,1.05,heat));
    float lighting = 0.55+0.45*smoothstep(-0.9,0.9,p.y-p.x*0.3);
    float3 soot = float3(0.065,0.075,0.087)*lighting;
    float3 tint = soot+flame*smoothstep(0.03,0.35,heat);
    float alpha = 1.0-exp(-density*ds);
    radiance += (1.0-opacity)*alpha*tint;
    opacity += (1.0-opacity)*alpha;
}
_output.color = float4(radiance,opacity);
"""

final class ExplosionVolume {
    let node: SCNNode
    let material: SCNMaterial
    let origin: V3
    let velocity: V3
    let shape: V3
    var age: Float = 0
    init(at position: V3, velocity: V3, shape: V3, seed: Float) {
        origin = position; self.velocity = velocity; self.shape = shape
        material = SCNMaterial(); material.lightingModel = .constant
        material.diffuse.contents = NSColor.white
        material.writesToDepthBuffer = false; material.readsFromDepthBuffer = true
        material.shaderModifiers = [.fragment:blastFragment]
        material.setValue(Float(0),forKey:"blastAge"); material.setValue(seed,forKey:"blastSeed")
        let g = SCNSphere(radius:1); g.segmentCount = 24; g.materials = [material]
        node = SCNNode(geometry:g); node.simdPosition = position
        node.renderingOrder = 60
    }
    func update(dt: Float, camera: V3) {
        age += dt
        let size = 1.5+9*(1-exp(-age*2))+age*2.0
        node.simdScale = shape*size
        node.simdPosition = origin+velocity*age*0.18
        material.setValue(age,forKey:"blastAge")
        let eye = (camera-node.simdPosition)/node.simdScale
        material.cullMode = simd_length_squared(eye)<1 ? .front : .back
    }
}

private func flashMaterial() -> SCNMaterial {
    let size = 64
    let bitmap = NSBitmapImageRep(bitmapDataPlanes:nil,pixelsWide:size,pixelsHigh:size,bitsPerSample:8,samplesPerPixel:4,hasAlpha:true,isPlanar:false,colorSpaceName:.deviceRGB,bytesPerRow:size*4,bitsPerPixel:32)!
    let data = bitmap.bitmapData!
    for y in 0..<size { for x in 0..<size {
        let dx = Float(x-32)/32, dy = Float(y-32)/32
        let r = sqrt(dx*dx+dy*dy), a = pow(max(0,1-r),3)
        let i = (y*size+x)*4
        // NSBitmapImageRep stores premultiplied color; transparent texels must not
        // contain full-intensity RGB or HDR filtering produces colored fringes.
        data[i] = UInt8(a*255); data[i+1] = UInt8(a*220); data[i+2] = UInt8(a*165); data[i+3] = UInt8(a*255)
    } }
    let image = NSImage(size:NSSize(width:size,height:size)); image.addRepresentation(bitmap)
    let m = SCNMaterial(); m.lightingModel = .constant
    m.diffuse.contents = image; m.emission.contents = image; m.emission.intensity = 2
    m.blendMode = .add; m.writesToDepthBuffer = false
    return m
}

extension Dogfight {
    func burst(at p: V3, count: Int, big: Bool, velocity: V3 = .zero) {
        let debris = material(color(0.25,0.29,0.3),metal:0.8)
        let hotEdge = material(color(0.16,0.13,0.1),emission:color(0.7,0.12,0.01),metal:0.6)
        let ember = material(color(1,0.5,0.12),emission:color(3,0.8,0.09))
        let impact = material(color(1,0.8,0.35),emission:color(3,1.6,0.4))
        for i in 0..<count {
            let isDebris = big && i<14
            let duration = rng.range(isDebris ? 2.4 : 0.15,isDebris ? 5 : (big ? 1.4 : 0.5))
            let size = isDebris ? rng.range(0.35,1.0) : rng.range(0.045,0.13)
            let g: SCNGeometry
            if isDebris {
                g = SCNBox(width:CGFloat(rng.range(0.2,0.7)),height:0.07,length:CGFloat(rng.range(0.8,2.1)),chamferRadius:0.015)
            } else {
                let capsule = SCNCapsule(capRadius:0.35,height:2.8); capsule.radialSegmentCount = 5; capsule.capSegmentCount = 2
                g = capsule
            }
            let impulse = unit(rng.vector(1))*rng.range(big ? 7 : 5,big ? 40 : 16)
            let v = velocity*0.5+impulse
            let n = node(g,isDebris ? (i%4 == 0 ? hotEdge : debris) : (big ? ember : impact),p)
            n.simdScale = V3(repeating:size)
            n.simdOrientation = isDebris ? simd_quatf(angle:rng.range(0,tau),axis:unit(rng.vector(1))) : simd_quatf(from:V3(0,1,0),to:unit(v))
            scene.rootNode.addChildNode(n)
            sparks.append(Spark(node:n,position:p,velocity:v,life:duration,duration:duration,scale:size,spin:rng.vector(3),kind:isDebris ? .debris : (big ? .ember : .impact)))
        }
        if big {
            let blast = ExplosionVolume(at:p,velocity:velocity,shape:V3(rng.range(0.9,1.2),rng.range(0.8,1.1),rng.range(0.9,1.2)),seed:rng.range(0,100))
            blasts.append(blast); scene.rootNode.addChildNode(blast.node)
            let flash = node(SCNPlane(width:20,height:20),flashMaterial(),p)
            flash.constraints = [SCNBillboardConstraint()]
            scene.rootNode.addChildNode(flash)
            effects.append(Transient(node:flash,kind:.flash,life:0.18,duration:0.18))
            let light = SCNNode(); light.light = SCNLight(); light.light!.type = .omni
            light.light!.color = color(1,0.65,0.3); light.light!.intensity = 5000
            light.light!.attenuationEndDistance = 120; light.simdPosition = p
            scene.rootNode.addChildNode(light)
            effects.append(Transient(node:light,kind:.light,life:0.6,duration:0.6))
            let distance = simd_distance(cameraPosition,p)
            if distance<120 { director.shake = max(director.shake,1-distance/120) }
        }
    }
    func updateBlasts(_ dt: Float) {
        for i in blasts.indices.reversed() {
            blasts[i].update(dt:dt,camera:cameraPosition)
            if blasts[i].age>4.5 { blasts[i].node.removeFromParentNode(); blasts.remove(at:i) }
        }
    }
    func updateEffects(_ dt: Float) {
        for i in effects.indices.reversed() {
            effects[i].life -= dt
            let t = max(0,effects[i].life/effects[i].duration), age = 1-t
            let n = effects[i].node
            switch effects[i].kind {
            case .flash: n.opacity = CGFloat(t*t); n.simdScale = V3(repeating:0.6+age*1.4)
            case .light: n.light?.intensity = CGFloat(5000*exp(-age*8))
            case .arrival: n.simdScale = V3(repeating:0.3+t*3); n.opacity = CGFloat(t)
            }
            if effects[i].life<=0 { n.removeFromParentNode(); effects.remove(at:i) }
        }
    }
    func updateSparks(_ dt: Float) {
        for i in sparks.indices.reversed() {
            sparks[i].life -= dt; sparks[i].position += sparks[i].velocity*dt
            let n = sparks[i].node, t = max(0,sparks[i].life/sparks[i].duration)
            n.simdPosition = sparks[i].position
            if sparks[i].kind == .debris {
                n.simdEulerAngles += sparks[i].spin*dt
                n.opacity = CGFloat(min(1,t*4))
            } else {
                n.opacity = CGFloat(t*t); n.simdScale = V3(repeating:sparks[i].scale*(0.2+t*0.8))
            }
            if sparks[i].life<=0 { n.removeFromParentNode(); sparks.remove(at:i) }
        }
    }
}
