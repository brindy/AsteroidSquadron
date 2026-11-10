import SceneKit
import simd

// The aperture's depth buffer cannot hide a hull that projects outside the
// disk, or a hull seen from behind. Clip the travelling craft itself in world
// space so every camera sees only the part that has crossed into normal space.
private let jumpClipFragment = """
#pragma arguments
float jumpClipEnabled;
float4 jumpClipPlane;
#pragma body
if (jumpClipEnabled > 0.5) {
    float3 worldPosition = (scn_frame.inverseViewTransform * float4(_surface.position,1.0)).xyz;
    if (dot(float4(worldPosition,1.0),jumpClipPlane) < 0.0) { discard_fragment(); }
}
"""

final class JumpClipper {
    let materials: [SCNMaterial]
    private(set) var plane: SIMD4<Float>?

    init(root: SCNNode) {
        var unique = [ObjectIdentifier:SCNMaterial]()
        func collect(_ n: SCNNode) {
            for m in n.geometry?.materials ?? [] { unique[ObjectIdentifier(m)] = m }
        }
        collect(root); root.enumerateChildNodes { child,_ in collect(child) }
        materials = Array(unique.values)
        for m in materials {
            // Babylon models use surface modifiers for their organic skin;
            // retain those while adding the independent fragment clipping stage.
            var modifiers = m.shaderModifiers ?? [:]
            modifiers[.fragment] = jumpClipFragment
            m.shaderModifiers = modifiers
            m.setValue(Float(0),forKey:"jumpClipEnabled")
            m.setValue(SCNVector4(0,0,0,0),forKey:"jumpClipPlane")
        }
    }
    func setPlane(origin: V3, normal: V3) {
        let n = unit(normal), value = SIMD4<Float>(n.x,n.y,n.z,-simd_dot(n,origin))
        guard plane != value else { return }
        plane = value
        for m in materials {
            m.setValue(SCNVector4(value.x,value.y,value.z,value.w),forKey:"jumpClipPlane")
            m.setValue(Float(1),forKey:"jumpClipEnabled")
        }
    }
    func clear() {
        guard plane != nil else { return }
        plane = nil
        for m in materials { m.setValue(Float(0),forKey:"jumpClipEnabled") }
    }
}

extension Dogfight {
    func updateFighterJumpClipping() {
        for f in fighters {
            guard let clipper = f.jumpClipper else { continue }
            // A one-shot transit: after clearing the aperture, flying back past
            // the old location must never reactivate clipping at a closed gate.
            if !f.active || f.entry != .jumpWindow || simd_dot(f.position-f.entryPosition,f.entryForward)>=f.faction.collisionRadius+1 {
                clipper.clear()
            }
        }
    }
}
