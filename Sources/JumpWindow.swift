import AppKit
import SceneKit
import simd

// The dark disk is the visual aperture; travelling craft also have their own
// clipping planes. Blue eddies need no image textures or particle nodes.
private let jumpWindowFragment = """
#pragma arguments
float jumpTime;
#pragma transparent
#pragma body
float2 p = (_surface.diffuseTexcoord-float2(0.5))*2.0;
float r = length(p);
if (r > 1.0) { discard_fragment(); }
float a = atan2(p.y,p.x);
float warp = a+r*9.0-jumpTime*1.8;
// Integer angular harmonics meet seamlessly across atan2's branch cut.
float eddies = sin(a*7.0+r*17.0-jumpTime*2.0)*0.46
             + sin(a*11.0-r*23.0+jumpTime)*0.24
             + sin(a*17.0+r*31.0)*0.15;
float spiral = pow(0.5+0.5*sin(warp*5.0+eddies*2.3),3.0);
float rim = exp(-pow((r-0.79-eddies*0.035)*9.0,2.0));
float core = smoothstep(0.13,0.8,r);
float blue = (0.12+spiral*0.85)*core*rim;
float halo = exp(-pow((r-0.86)*12.0,2.0));
float3 ink = float3(0.001,0.002,0.008);
float3 light = float3(0.025,0.20,1.5)*blue+float3(0.02,0.12,0.6)*halo;
float alpha = 1.0-smoothstep(0.89,1.0,r);
_output.color = float4(ink+light,alpha);
"""

final class JumpWindow {
    let node: SCNNode
    let material: SCNMaterial
    let radius: Float
    var openness: Float = 0
    init(radius: Float, forward: V3) {
        self.radius = radius
        material = SCNMaterial(); material.lightingModel = .constant
        material.diffuse.contents = NSColor.white; material.isDoubleSided = true
        material.readsFromDepthBuffer = true; material.writesToDepthBuffer = true
        material.shaderModifiers = [.fragment:jumpWindowFragment]
        material.setValue(Float(0),forKey:"jumpTime")
        let disk = SCNPlane(width:CGFloat(radius*2),height:CGFloat(radius*2)); disk.materials = [material]
        node = SCNNode(geometry:disk)
        node.simdOrientation = simd_quatf(from:V3(0,0,1),to:forward)
        node.isHidden = true
    }
    func update(time: Float, position: V3, openness: Float) {
        self.openness = min(1,max(0,openness))
        node.simdPosition = position; node.isHidden = self.openness<0.001
        let eased = self.openness*self.openness*(3-2*self.openness)
        node.simdScale = V3(repeating:max(0.0001,eased))
        material.setValue(time,forKey:"jumpTime")
    }
}

extension Dogfight {
    func updateJumpWindow(_ ship: Carrier, age: Float) -> V3 {
        guard let window = ship.jumpWindow else { return ship.origin }
        if ship.faction == .earth {
            // Jump point exists for over a second before the first fighter exits.
            let open = min(age/1.0,(ship.departureAge+0.7-age)/0.7)
            window.update(time:time,position:ship.origin,openness:open)
            ship.node.isHidden = true
            if age>=ship.departureAge && !ship.departing {
                ship.departing = true; carrierDepartures += 1
                director.requestCarrierDeparture(ship,in:self)
            }
            return ship.origin
        }
        let radius = ship.worldRadius
        let departureOpening = ship.departureAge-0.65
        var position = ship.origin
        if age<2.4 {
            let travel = max(0,min(1,(age-0.85)/1.25))
            position -= ship.forward*(radius*2.6*(1-travel))
            ship.node.isHidden = age<0.85
            let open = min(age/0.85,(2.4-age)/0.3)
            let portal = ship.origin-ship.forward*radius*0.75
            window.update(time:time,position:portal,openness:open)
            if age<ship.arrivalDuration { ship.jumpClipper?.setPlane(origin:portal,normal:ship.forward) }
            else { ship.jumpClipper?.clear() }
        } else if age<departureOpening {
            ship.jumpClipper?.clear()
            ship.node.isHidden = false
            window.update(time:time,position:ship.origin,openness:0)
        } else {
            let t = max(0,min(1,(age-ship.departureAge)/2.0))
            position += ship.forward*radius*3.0*t*t
            ship.node.isHidden = t>=1
            let open = min((age-departureOpening)/0.65,(ship.departureAge+2.6-age)/0.6)
            let portal = ship.origin+ship.forward*radius*1.6
            window.update(time:time,position:portal,openness:open)
            // Invert the plane on exit: crossed geometry is now in hyperspace.
            ship.jumpClipper?.setPlane(origin:portal,normal:-ship.forward)
            if age>=ship.departureAge && !ship.departing {
                ship.departing = true; carrierDepartures += 1
                director.requestCarrierDeparture(ship,in:self)
            }
        }
        return position
    }
}
