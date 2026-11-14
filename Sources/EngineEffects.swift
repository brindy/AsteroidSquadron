import AppKit
import SceneKit
import simd

// Sample a tapered, emissive plume in nozzle space so the halo stays soft from
// the side and directly behind the ship. Each nozzle needs only one draw call.
private let exhaustFragment = """
#pragma arguments
float3 exhaustTint;
#pragma transparent
#pragma body
float3 eye = (scn_node.inverseModelViewTransform * float4(0,0,0,1)).xyz;
float3 point = (scn_node.inverseModelViewTransform * float4(_surface.position,1)).xyz;
float3 ray = normalize(point-eye);
float b = dot(eye,ray);
float disc = b*b-dot(eye,eye)+1.0;
if (disc <= 0.0) { discard_fragment(); }
float start = max(0.0,-b-sqrt(disc));
float step = (-b+sqrt(disc)-start)/8.0;
float core = 0.0, halo = 0.0;
for (int i=0; i<8; i++) {
    float3 p = eye+ray*(start+(float(i)+0.5)*step);
    float t = p.z*0.5+0.5;
    float falloff = (1.0-smoothstep(0.03,1.0,t))*smoothstep(0.0,0.08,t);
    float width = mix(0.24,0.64,smoothstep(0.0,0.26,t))*(1.0-0.76*t);
    float r = dot(p.xy,p.xy)/(width*width);
    float bands = 0.82+0.18*cos(t*35.0);
    float edge = 1.0-smoothstep(0.72,1.0,dot(p,p));
    core += exp(-r*5.7)*falloff*bands*edge*step;
    halo += exp(-r*1.05)*falloff*edge*step;
}
float3 light = mix(exhaustTint,float3(1.0,0.94,0.86),0.72)*core*6.0 + exhaustTint*halo*2.5;
_output.color = float4(light*_surface.diffuse.a,min(1.0,(core+halo)*3.0)*_surface.diffuse.a);
"""

final class EngineNozzle: SCNNode {
    private static let volume = {
        let sphere = SCNSphere(radius:1)
        sphere.segmentCount = 16
        return sphere
    }()

    let radius: Float
    private let plume: SCNNode

    init(at position: V3, radius: Float, tint: V3) {
        self.radius = radius
        let glow = SCNMaterial()
        glow.lightingModel = .constant
        glow.diffuse.contents = NSColor.white
        glow.blendMode = .add
        glow.writesToDepthBuffer = false
        glow.shaderModifiers = [.fragment:exhaustFragment]
        glow.setValue(SCNVector3(tint),forKey:"exhaustTint")
        let geometry = Self.volume.copy() as! SCNGeometry
        geometry.materials = [glow]
        plume = SCNNode(geometry:geometry)
        plume.renderingOrder = 2
        super.init()
        name = "engine.nozzle"
        simdPosition = position
        addChildNode(plume)
        update(power:0.45,pulse:0.9)
    }

    required init?(coder: NSCoder) { fatalError("Engine nozzles are generated at runtime") }

    func update(power: Float, pulse: Float) {
        let length = radius*(2.3+12*power)*pulse
        let width = radius*(2.55+0.85*power)
        plume.simdPosition.z = length*0.48
        plume.simdScale = V3(width,width,length*0.5)
        plume.opacity = CGFloat(0.13+0.87*power)
    }
}

final class FighterEngines {
    let nozzles: [EngineNozzle]
    private var power: Float = 0.45
    private var lastHull = Fighter.fullHull
    private var ventUntil: Float = 0
    private var nextPuff: Float = 0

    init(model: SCNNode) {
        var nozzles: [EngineNozzle] = []
        model.enumerateChildNodes { child,_ in
            if let nozzle = child as? EngineNozzle { nozzles.append(nozzle) }
        }
        self.nozzles = nozzles
    }

    func update(_ fighter: Fighter, thrust: Float, time: Float, dt: Float, trail: EngineSmoke) {
        guard !nozzles.isEmpty else { return }
        power += (thrust-power)*(1-exp(-dt*8))
        if fighter.hitPoints < lastHull {
            ventUntil = time+0.9
            nextPuff = time
        }
        lastHull = fighter.hitPoints
        let damaged = fighter.hitPoints < Fighter.fullHull
        let venting = damaged && (time<ventUntil || fighter.hitPoints<=4)
        let damagedIndex = (fighter.pair*3+fighter.side+(fighter.trailing ? 1 : 0))%nozzles.count
        let phase = time*19+Float(fighter.pair*11+fighter.side*5)
        for (index,nozzle) in nozzles.enumerated() {
            let beat = phase+Float(index)*2.17
            let pulse = 0.91+0.07*sin(beat)+0.04*sin(beat*1.83)
            let flicker = venting && index == damagedIndex ? 0.28+0.48*pow(0.5+0.5*sin(beat*1.7),2) : 1
            nozzle.update(power:power*flicker,pulse:pulse)
        }

        guard dt>0, fighter.active, fighter.jumpClipper?.plane == nil, venting, time>=nextPuff else { return }
        let severity = Float(Fighter.fullHull-fighter.hitPoints)/Float(Fighter.fullHull-1)
        nextPuff = time+0.115-0.056*severity
        let transform = nozzles[damagedIndex].simdWorldTransform
        let rear = unit(transform.columns.2.xyz)
        trail.emit(at:transform.columns.3.xyz,velocity:fighter.velocity*0.76+rear*(6+5*severity),severity:severity)
    }
}

// Escaping propellant and soot are world-space billboards. They continue to
// drift and fade after the ship turns, jumps or is destroyed.
final class EngineSmoke {
    static let capacity = 144
    let node = SCNNode()
    private(set) var puffs: [Puff] = []
    private var available: [SCNNode] = []
    private var random: Random

    struct Puff {
        let sprite: SCNNode
        let origin: V3
        let velocity: V3
        let duration: Float
        let expansion: Float
        let opacity: Float
        var age: Float = 0
    }

    init(seed: UInt64) {
        random = Random(state:seed ^ 0x534D_4F4B_45)
        node.name = "engine.smoke"
    }

    func emit(at position: V3, velocity: V3, severity: Float) {
        let sprite: SCNNode
        if puffs.count == Self.capacity {
            sprite = puffs.removeFirst().sprite
        } else {
            sprite = available.popLast() ?? makeSprite()
            node.addChildNode(sprite)
        }
        sprite.simdPosition = position
        sprite.simdScale = V3(repeating:0.6)
        sprite.opacity = 0
        puffs.append(Puff(sprite:sprite,origin:position,velocity:velocity+random.vector(2.2+severity*2.5),
                          duration:random.range(0.72,1.12)+severity*0.64,
                          expansion:random.range(2.8,4.5)+severity*2.7,opacity:0.4+severity*0.37))
    }

    func update(dt: Float) {
        guard dt>0 else { return }
        for i in puffs.indices.reversed() {
            puffs[i].age += dt
            let puff = puffs[i]
            if puff.age>=puff.duration {
                puff.sprite.removeFromParentNode()
                available.append(puff.sprite)
                puffs.remove(at:i)
                continue
            }
            let life = puff.age/puff.duration
            puff.sprite.simdPosition = puff.origin+puff.velocity*puff.age
            puff.sprite.simdScale = V3(repeating:0.65+puff.expansion*sqrt(life))
            puff.sprite.opacity = CGFloat(puff.opacity*min(1,life*17)*(1-life)*(1-life))
        }
    }

    private func makeSprite() -> SCNNode {
        let sprite = SCNNode()
        sprite.constraints = [SCNBillboardConstraint()]
        let cloud = SCNNode(geometry:Self.smokeCards[random.index(Self.smokeCards.count)])
        cloud.simdEulerAngles.z = random.range(0,tau)
        cloud.renderingOrder = 32
        sprite.addChildNode(cloud)
        return sprite
    }

    private static let smokeCards: [SCNPlane] = (0..<4).map { variant in
        let size = 64
        let bitmap = NSBitmapImageRep(bitmapDataPlanes:nil,pixelsWide:size,pixelsHigh:size,bitsPerSample:8,
                                      samplesPerPixel:4,hasAlpha:true,isPlanar:false,colorSpaceName:.deviceRGB,
                                      bytesPerRow:size*4,bitsPerPixel:32)!
        let bytes = bitmap.bitmapData!
        var random = Random(state:34+UInt64(variant))
        let lobes = (0..<10).map { _ in
            (x:random.range(-0.56,0.56),y:random.range(-0.56,0.56),width:random.range(7,29))
        }
        for y in 0..<size {
            for x in 0..<size {
                let u = (Float(x)+0.5)*2/Float(size)-1
                let v = (Float(y)+0.5)*2/Float(size)-1
                let edge = max(0,1-u*u-v*v)
                let density = lobes.reduce(Float(0)) { sum,lobe in
                    let dx = u-lobe.x, dy = v-lobe.y
                    return sum+exp(-(dx*dx+dy*dy)*lobe.width)
                }
                let detail = 0.85+0.15*sin(u*34+sin(v*29)*1.8)*sin(v*28-u*5)
                let alpha = min(1,density*edge*edge*1.15*detail)
                let light = min(1,0.58+v*0.23+density*0.1)
                let offset = (y*size+x)*4
                bytes[offset] = UInt8(alpha*light*145)
                bytes[offset+1] = UInt8(alpha*light*147)
                bytes[offset+2] = UInt8(alpha*light*152)
                bytes[offset+3] = UInt8(alpha*255)
            }
        }
        let image = NSImage(size:NSSize(width:size,height:size))
        image.addRepresentation(bitmap)
        let soot = SCNMaterial()
        soot.lightingModel = .constant
        soot.diffuse.contents = image
        soot.writesToDepthBuffer = false
        let card = SCNPlane(width:2,height:2)
        card.materials = [soot]
        return card
    }
}

extension Dogfight {
    func updateEngines(_ dt: Float) {
        engineSmoke.update(dt:dt)
        for fighter in fighters where fighter.state != .destroyed && !fighter.node.isHidden {
            let power: Float
            if fighter.spin != nil { power = 0.21 }
            else if fighter.faction == .earth && time<fighter.pivotUntil { power = 0.08 }
            else if fighter.state == .arriving || time<fighter.entryTime+fighter.formationHold { power = 0.87 }
            else { power = fighter.driveThrust }
            fighter.engines.update(fighter,thrust:power,time:time,dt:dt,trail:engineSmoke)
        }
    }
}
