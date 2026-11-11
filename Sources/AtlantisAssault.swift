import SceneKit
import simd

struct CapitalDronePath {
    static let passes = 3
    private static let speed: Float = 1520

    private struct Leg {
        let start: V3
        let controlA: V3
        let controlB: V3
        let end: V3
        let duration: Float
        let penetration: Int?
        var arch = V3.zero

        func point(_ t: Float) -> V3 {
            let a = mix(start,controlA,t)
            let b = mix(controlA,controlB,t)
            let c = mix(controlB,end,t)
            let bow = 4*t*(1-t)
            return mix(mix(a,b,t),mix(b,c,t),t)+arch*bow*bow
        }
    }

    private let legs: [Leg]
    let duration: Float

    init(origin: V3, ship: Carrier, lane: Int) {
        let up = V3(0,1,0)
        let right = unit(simd_cross(ship.forward,up))
        let across = unit(right+ship.forward*0.28)
        let laneOffset = Float(lane)-1.5
        // The crossing points lie inside the central hull on every model.
        // The turnarounds extend beyond the wing tips and alternate above/below.
        let core = ship.origin+ship.forward*laneOffset*45
        let span = ship.worldRadius*1.08+115
        let first = core-across*span-up*13
        let firstTime = simd_distance(origin,first)/Self.speed+0.34
        var route = [Leg(start:origin,controlA:origin+up*440,controlB:first-across*470,
                         end:first,duration:firstTime,penetration:nil)]
        for pass in 0..<Self.passes {
            let sign: Float = pass%2 == 0 ? 1 : -1
            let direction = across*sign
            let center = core+up*(Float(pass-1)*13)
            let entry = center-direction*span
            let exit = center+direction*span
            route.append(Leg(start:entry,controlA:mix(entry,exit,1/3),controlB:mix(entry,exit,2/3),
                             end:exit,duration:2*span/Self.speed,penetration:pass))
            if pass+1<Self.passes {
                let next = exit+up*13
                let arch = up*sign*(300+laneOffset*68)
                let extensionVector = direction*(300+laneOffset*55)
                route.append(Leg(start:exit,controlA:exit+extensionVector,
                                 controlB:next+extensionVector,end:next,
                                 duration:0.78+Float(lane)*0.055,penetration:nil,arch:arch*0.66))
            }
        }
        legs = route
        duration = route.reduce(0) { $0+$1.duration }
    }

    func sample(at age: Float) -> (position: V3, penetration: Int?) {
        var remaining = age
        for leg in legs {
            if remaining<leg.duration {
                let t = max(0,remaining/leg.duration)
                return (leg.point(t),t>=0.5 ? leg.penetration : nil)
            }
            remaining -= leg.duration
        }
        return (legs.last!.end,nil)
    }
}

final class CapitalDrone {
    let node = AncientDrone.makeNode(scale:3.8)
    let path: CapitalDronePath
    let launchTime: Float
    var lastPenetration = -1

    init(path: CapitalDronePath, launchTime: Float) {
        self.path = path; self.launchTime = launchTime
    }
}

final class AtlantisAssault {
    static let droneCount = 108
    static let launchInterval: Float = 0.024
    static let hullCapacity = 238
    static let wreckDuration: Float = 2.8

    let ship: Carrier
    let muzzles: [SCNNode]
    let paths: [CapitalDronePath]
    var nextVolley: Float
    var counterstrikeStart: Float?
    var launched = 0
    var drones: [CapitalDrone] = []
    var penetrations = Array(repeating:0,count:CapitalDronePath.passes)
    var hullPoints = hullCapacity
    var destroyedAt: Float?
    var nextExplosion = 0
    var finished = false

    init(ship: Carrier, port: V3) {
        self.ship = ship
        nextVolley = ship.start+max(1.63,ship.arrivalDuration+0.34)
        paths = (0..<4).map { CapitalDronePath(origin:port,ship:ship,lane:$0) }
        let mount: V3
        switch ship.faction {
        case .rebel: mount = V3(18,17,-47)
        case .empire: mount = V3(11,10,-51)
        case .colonial: mount = V3(15,11,-82)
        case .cylon: mount = V3(9,18,-21)
        case .earth: mount = V3(15,13,-106)
        case .shadow: mount = V3(18,12,-30)
        case .tauri: mount = V3(12,9,-86)
        case .goauld: mount = V3(29,-18,-66)
        case .wraith: mount = V3(16,12,-96)
        }
        let turret = material(color(0.28,0.34,0.38),metal:0.66)
        muzzles = [-1 as Float,1].map { side in
            let base = SCNNode()
            base.simdPosition = V3(side*mount.x,mount.y,mount.z)
            ship.node.addChildNode(base)
            base.addChildNode(box(V3(5.8,4,6),turret,chamfer:0.7))
            base.addChildNode(cylinder(1.15,10,turret,V3(0,0,-5)))
            let muzzle = SCNNode()
            muzzle.simdPosition = V3(0,0,-10.5)
            base.addChildNode(muzzle)
            return muzzle
        }
    }

    func removeNodes() {
        ship.node.isHidden = true
        ship.node.removeFromParentNode()
        ship.warp.removeFromParentNode()
        for drone in drones { drone.node.removeFromParentNode() }
        drones.removeAll()
        finished = true
    }
}

extension Dogfight {
    func updateAtlantisAssault(_ city: Atlantis, dt: Float) {
        if city.assault == nil && city.shieldPoints<=Atlantis.assaultThreshold {
            let activeSides = sideFactions.indices.filter { sideCount($0)>0 }
            let sides = activeSides.isEmpty ? Array(sideFactions.indices) : activeSides
            let side = sides[rng.index(sides.count)]
            let radial = unit(V3(city.position.x,0,city.position.z))
            let lateral = unit(simd_cross(radial,V3(0,1,0)))
            let outward = unit(radial*0.62+lateral*0.78)
            let ship = Carrier(faction:sideFactions[side],side:side,origin:city.position+outward*1850,
                               forward:-outward,start:time,squadron:[])
            city.assault = AtlantisAssault(ship:ship,port:city.dronePort)
            scene.rootNode.addChildNode(ship.node)
            scene.rootNode.addChildNode(ship.warp)
            if automatic { director.begin(.atlantisCapitalArrival,in:self) }
        }
        guard let assault = city.assault, !assault.finished else { return }
        let ship = assault.ship
        if let destroyedAt = assault.destroyedAt {
            updateAssaultWreck(assault,age:time-destroyedAt,dt:dt)
            if assault.finished { return }
        } else {
            let age = time-ship.start
            if let window = ship.jumpWindow, age<2.4 {
                ship.node.simdPosition = emergeThroughJumpWindow(ship,age:age,window:window)
            } else if !ship.faction.usesBlinkFTL && ship.jumpWindow == nil && age<ship.arrivalDuration {
                ship.node.simdPosition = capitalHyperspaceEntry(ship,age:age)
            } else {
                ship.node.simdPosition = ship.origin
                ship.warp.isHidden = true
                ship.node.isHidden = age<ship.arrivalDuration
                if ship.faction.usesBlinkFTL && !ship.node.isHidden { blinkCapitalIn(ship) }
            }
            if time>=assault.nextVolley {
                fireCapitalVolley(assault,at:city)
                if assault.counterstrikeStart == nil {
                    assault.counterstrikeStart = time+0.86
                    if automatic { director.begin(.atlantisBombardment,in:self) }
                }
                assault.nextVolley = time+0.64
            }
        }
        guard let start = assault.counterstrikeStart, time>=start else { return }
        if assault.launched == 0 && automatic { director.begin(.atlantisCounterstrike,in:self) }
        while assault.launched<AtlantisAssault.droneCount {
            let launchTime = start+Float(assault.launched)*AtlantisAssault.launchInterval
            if time<launchTime { break }
            let drone = CapitalDrone(path:assault.paths[assault.launched%assault.paths.count],launchTime:launchTime)
            city.node.addChildNode(drone.node)
            assault.drones.append(drone)
            assault.launched += 1
        }
        for i in assault.drones.indices.reversed() {
            let drone = assault.drones[i]
            let age = time-drone.launchTime
            let sample = drone.path.sample(at:age)
            let direction = unit(drone.path.sample(at:age+dt).position-sample.position)
            drone.node.simdPosition = sample.position-city.position
            drone.node.simdOrientation = simd_quatf(from:V3(0,0,-1),to:direction)
            if let pass = sample.penetration, drone.lastPenetration<pass {
                drone.lastPenetration = pass
                assault.penetrations[pass] += 1
                if assault.destroyedAt == nil {
                    assault.hullPoints -= 1
                    if assault.penetrations[pass]%7 == 1 {
                        burst(at:sample.position,count:7,big:false,scale:13)
                    }
                    if assault.hullPoints==0 {
                        assault.destroyedAt = time
                        if automatic { director.begin(.atlantisCapitalDestroyed,in:self) }
                    }
                }
            }
            if age>=drone.path.duration {
                drone.node.removeFromParentNode()
                assault.drones.remove(at:i)
            }
        }
    }

    private func fireCapitalVolley(_ assault: AtlantisAssault, at city: Atlantis) {
        let ship = assault.ship
        for muzzle in assault.muzzles {
            let turret = muzzle.parent!
            turret.look(at:SCNVector3(city.position),up:SCNVector3(0,1,0),localFront:SCNVector3(0,0,-1))
            let transform = muzzle.simdWorldTransform
            let origin = transform.columns.3.xyz
            let forward = unit(-transform.columns.2.xyz)
            let length: Float = 54
            let bolt = SCNNode()
            bolt.addChildNode(box(V3(2.4,2.4,length),projectileMaterials[ship.faction]!,V3(0,0,-length/2)))
            bolt.simdPosition = origin
            bolt.simdOrientation = simd_quatf(from:V3(0,0,-1),to:forward)
            scene.rootNode.addChildNode(bolt)
            lasers.append(Laser(node:bolt,position:origin,velocity:forward*1450,life:2.1,sourceSide:ship.side,
                                generations:[],launchOrigin:origin,launchForward:forward,inheritedVelocity:.zero,
                                length:length,targetsAtlantis:true,atlantisDamage:7))
        }
    }

    private func updateAssaultWreck(_ assault: AtlantisAssault, age: Float, dt: Float) {
        let ship = assault.ship
        let beats: [Float] = [0,0.22,0.46,0.79,1.14,1.51]
        if assault.nextExplosion<beats.count && age>=beats[assault.nextExplosion] {
            let index = assault.nextExplosion
            let centerHeight: Float = ship.faction == .goauld ? 46 : 28
            let offset = [V3(0,centerHeight,-5),V3(24,13,-54),V3(-20,16,46),
                          V3(0,19,-32),V3(0,-10,24),V3(-8,centerHeight,0)][index]
            let position = ship.node.simdConvertPosition(offset,to:nil)
            burst(at:position,count:27,big:true,velocity:ship.forward*32,scale:index==0 || index==5 ? 31 : 18)
            assault.nextExplosion += 1
        }
        ship.node.simdPosition += (ship.forward*32+V3(0,-25,0))*dt
        ship.node.simdEulerAngles.z += 0.12*dt
        ship.node.opacity = CGFloat(max(0,min(1,(AtlantisAssault.wreckDuration-age)/1.4)))
        if age>=AtlantisAssault.wreckDuration { assault.removeNodes() }
    }
}
