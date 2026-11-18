import AppKit
import SceneKit
import simd

enum CapitalJump {
    static let entryOpens: Float = 0.85
    static let arrivalDuration: Float = 2.1
    static let arrivalClosed: Float = 2.4
    static let exitOpeningDuration: Float = 0.65
    static let exitTravelDuration: Float = 2
    static let exitClosingDuration: Float = 0.6

    static func shadowDepartureAge(after launch: Float) -> Float {
        max(launch+0.18,arrivalClosed+0.10+exitOpeningDuration)
    }
}

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
    func emergeThroughJumpWindow(_ ship: Carrier, age: Float, window: JumpWindow) -> V3 {
        let radius = ship.worldRadius
        let travel = max(0,min(1,(age-CapitalJump.entryOpens)/(CapitalJump.arrivalDuration-CapitalJump.entryOpens)))
        let position = ship.origin-ship.forward*(radius*2.6*(1-travel))
        ship.node.isHidden = age<CapitalJump.entryOpens
        let portal = ship.arrivalGatePosition
        let closing = (CapitalJump.arrivalClosed-age)/(CapitalJump.arrivalClosed-CapitalJump.arrivalDuration)
        window.update(time:time,position:portal,openness:min(age/CapitalJump.entryOpens,closing))
        if age<ship.arrivalDuration { ship.jumpClipper?.setPlane(origin:portal,normal:ship.forward) }
        else { ship.jumpClipper?.clear() }
        return position
    }

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
        let departureOpening = ship.departureAge-CapitalJump.exitOpeningDuration
        var position = ship.origin
        if age<CapitalJump.arrivalClosed {
            return emergeThroughJumpWindow(ship,age:age,window:window)
        } else if age<departureOpening {
            ship.jumpClipper?.clear()
            ship.node.isHidden = false
            window.update(time:time,position:ship.origin,openness:0)
        } else {
            let t = max(0,min(1,(age-ship.departureAge)/CapitalJump.exitTravelDuration))
            position += ship.forward*radius*3.0*t*t
            ship.node.isHidden = t>=1
            let open = min((age-departureOpening)/CapitalJump.exitOpeningDuration,
                           (ship.departureAge+ship.departureDuration-age)/CapitalJump.exitClosingDuration)
            let portal = ship.departureGatePosition
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
