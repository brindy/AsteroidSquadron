import AppKit
import SceneKit
import simd

private func hyperspaceGlow(_ body: String) -> SCNMaterial {
    let glow = SCNMaterial()
    glow.lightingModel = .constant
    glow.diffuse.contents = NSColor.white
    glow.blendMode = .add
    glow.writesToDepthBuffer = false
    glow.isDoubleSided = true
    glow.shaderModifiers = [.fragment:body]
    return glow
}

private let streakGlow = hyperspaceGlow("""
#pragma transparent
#pragma body
float3 p = (scn_node.inverseModelViewTransform*float4(_surface.position,1.0)).xyz;
float edge = smoothstep(0.0,0.055,1.0-abs(p.y));
float radial = p.x*p.x;
float core = exp(-radial*85.0)*1.6;
float halo = exp(-radial*7.5)*0.65;
float3 light = float3(0.87,0.94,1.0)*core+float3(0.15,0.45,1.0)*halo;
_output.color = float4(light*edge*_surface.diffuse.a,min(1.0,core+halo)*edge*_surface.diffuse.a);
""")

private let pointGlow = hyperspaceGlow("""
#pragma transparent
#pragma body
float2 p = (scn_node.inverseModelViewTransform*float4(_surface.position,1.0)).xy;
float r = dot(p,p);
float core = exp(-r*70.0)*3.2;
float halo = exp(-r*8.5)*0.82;
float rays = exp(-abs(p.x)*54.0-abs(p.y)*5.8)+exp(-abs(p.y)*54.0-abs(p.x)*5.8);
float edge = 1.0-smoothstep(0.65,1.0,r);
float3 light = float3(0.89,0.96,1.0)*(core+0.48*rays)+float3(0.19,0.47,1.0)*halo;
_output.color = float4(light*edge*_surface.diffuse.a,min(1.0,core+halo+rays)*edge*_surface.diffuse.a);
""")

final class HyperspaceTrail: SCNNode {
    let streak = SCNNode()
    let point: SCNNode

    override init() {
        let light = SCNNode(geometry:SCNPlane(width:2,height:2))
        light.geometry?.materials = [pointGlow]
        light.constraints = [SCNBillboardConstraint()]
        light.renderingOrder = 4
        point = light
        super.init()
        name = "hyperspace.trail"
        // Crossed ribbons keep the thin line readable from either side of the route.
        let plane = SCNPlane(width:2,height:2)
        plane.materials = [streakGlow]
        for angle: Float in [0,.pi/2] {
            let ribbon = SCNNode(geometry:plane)
            ribbon.simdEulerAngles.y = angle
            ribbon.renderingOrder = 3
            streak.addChildNode(ribbon)
        }
        addChildNode(streak)
        addChildNode(point)
        isHidden = true
    }

    required init?(coder: NSCoder) { fatalError("Hyperspace trails are generated at runtime") }

    func show(from start: V3, to end: V3, lightAt light: V3, width: Float, opacity: Float, pointOpacity: Float) {
        isHidden = opacity<0.01 && pointOpacity<0.01
        guard !isHidden else { return }
        let length = simd_distance(start,end)
        streak.isHidden = length<0.5 || opacity<0.01
        if !streak.isHidden {
            streak.simdPosition = (start+end)*0.5
            streak.simdOrientation = simd_quatf(from:V3(0,1,0),to:unit(end-start))
            streak.simdScale = V3(width,length*0.5,width)
            streak.opacity = CGFloat(opacity)
        }
        point.simdPosition = light
        point.simdScale = V3(repeating:width*2.6)
        point.opacity = CGFloat(pointOpacity)
    }

    func arrive(distant: V3, stern: V3, progress: Float, width: Float) {
        let reach = hyperspaceRamp(progress,from:0.15,to:0.62)
        let catchUp = hyperspaceRamp(progress,from:0.69,to:0.96)
        let start = mix(distant,stern,catchUp)
        let end = mix(distant,stern,reach)
        let brightness = 1-hyperspaceRamp(progress,from:0.88,to:1)
        let sparkle = hyperspaceRamp(progress,from:0.025,to:0.14)*brightness
        show(from:start,to:end,lightAt:start,width:width,
             opacity:brightness*hyperspaceRamp(progress,from:0.15,to:0.24),pointOpacity:sparkle)
    }
}

func hyperspaceRamp(_ value: Float, from start: Float, to end: Float) -> Float {
    let t = min(1,max(0,(value-start)/(end-start)))
    return t*t*(3-2*t)
}
