import SceneKit
import simd

final class Atlantis {
    static let shieldCapacity = 480
    static let hullCapacity = 340
    static let shieldRadius: Float = 625
    static let attackRange: Float = 240
    static let droneVolleySize = 30
    static let droneLaunchInterval: Float = 0.05
    static let droneVolleyPause: Float = 10
    static let towerTip: Float = 190
    static let revealDelay: Float = 0.48
    static let assaultThreshold = shieldCapacity*18/100

    let node = SCNNode()
    let city = SCNNode()
    let position: V3
    let attackingSide: Int
    var dronePort: V3 { position+V3(0,Self.towerTip+2,0) }
    let arrivalTime: Float
    let shield: SCNNode
    private let shieldMaterial: SCNMaterial
    private var hullSections: [AtlantisHullSection] = []
    var shieldPoints = Atlantis.shieldCapacity
    var hullPoints = Atlantis.hullCapacity
    var intact: Bool { hullPoints>0 }
    var destroyedAt: Float?
    var nextDroneTime: Float
    var droneVolley: AncientDroneVolley?
    var nextExplosion = 0
    var impactStrength: Float = 0
    var drones: [AncientDrone] = []
    var assault: AtlantisAssault?

    init(position: V3, time: Float, seed: UInt64, attackingSide: Int) {
        self.position = position
        self.attackingSide = attackingSide
        arrivalTime = time
        nextDroneTime = time+3
        node.name = "atlantis"
        node.simdPosition = position
        node.addChildNode(city)

        let field = material(color(0.14,0.62,1,0.12))
        field.lightingModel = .constant
        field.blendMode = .add
        field.writesToDepthBuffer = false
        field.setValue(SCNVector3(0,1,0),forKey:"impactDirection")
        field.setValue(Float(0),forKey:"impactStrength")
        field.setValue(Float(1),forKey:"integrity")
        field.shaderModifiers = [.fragment:"""
        #pragma arguments
        float3 impactDirection;
        float impactStrength;
        float integrity;
        #pragma transparent
        #pragma body
        float3 normal = normalize(_surface.normal);
        float facing = abs(dot(normal, normalize(-_surface.position)));
        float3 radial = normalize((scn_node.inverseModelViewTransform * float4(_surface.position,1.0)).xyz);
        float rim = pow(1.0-facing, 3.4);
        float waves = 0.5 + 0.5*sin(radial.y*43.0 + sin(radial.x*15.0 + scn_frame.time)*1.4);
        float pulse = exp(-length(radial-impactDirection)*13.0)*impactStrength;
        float alpha = 0.018 + rim*0.30 + waves*rim*0.06 + pulse*0.57;
        float3 blue = mix(float3(0.25,0.60,1.0), float3(0.10,0.71,1.0), integrity);
        _output.color = float4((blue + pulse*float3(0.7,0.8,0.6))*alpha, alpha);
        """]
        shieldMaterial = field
        let sphere = SCNSphere(radius:CGFloat(Self.shieldRadius))
        sphere.segmentCount = 96
        shield = SCNNode(geometry:sphere)
        sphere.materials = [field]
        shield.renderingOrder = 15
        node.addChildNode(shield)
        buildCity(seed:seed)
    }

    private func buildCity(seed: UInt64) {
        var rng = Random(state:seed ^ 0xA71A_A715)
        let foundation = material(color(0.22,0.35,0.42),metal:0.38)
        let ceramic = material(color(0.56,0.66,0.65),metal:0.26)
        let ribs = material(color(0.29,0.43,0.50),metal:0.48)
        let glass = material(color(0.08,0.27,0.38),metal:0.48)
        let light = material(color(0.27,0.82,1),emission:color(0.28,1.4,2.1))
        let warm = material(color(0.83,0.7,0.42),emission:color(0.95,0.58,0.21))

        func platform(radius: CGFloat, height: CGFloat, at position: V3, material: SCNMaterial) -> SCNNode {
            let geometry = SCNCylinder(radius:radius,height:height)
            geometry.radialSegmentCount = 6
            let part = SCNNode(geometry:geometry)
            geometry.materials = [material]
            part.simdPosition = position
            return part
        }

        func tower(on parent: SCNNode, x: Float, z: Float, width: Float, height: Float) {
            let base: Float = 5
            parent.addChildNode(box(V3(width,height,width*0.78),ceramic,V3(x,base+height/2,z),chamfer:CGFloat(width*0.09)))
            parent.addChildNode(box(V3(width*0.68,height*0.24,width*0.56),ribs,V3(x,base+height*1.07,z),chamfer:CGFloat(width*0.07)))
            parent.addChildNode(box(V3(width*0.42,height*0.73,width*0.82),glass,V3(x,base+height*0.53,z)))
            for i in 0..<5 {
                let y = base+height*(0.18+Float(i)*0.15)
                parent.addChildNode(box(V3(width*0.53,0.85,width*0.84),i%3==0 ? warm : light,V3(x,y,z)))
            }
        }

        hullSections = [
            AtlantisHullSection(center:V3(0,15,0),axes:V3(174,91,174)),
            AtlantisHullSection(center:V3(0,128,0),axes:V3(33,65,33))
        ]
        let hub = SCNNode()
        hub.name = "atlantis.hub"
        city.addChildNode(hub)
        hub.addChildNode(platform(radius:171,height:30,at:V3(0,-19,0),material:foundation))
        hub.addChildNode(platform(radius:146,height:15,at:V3(0,0,0),material:ribs))
        hub.addChildNode(platform(radius:114,height:5,at:V3(0,10,0),material:ceramic))
        hub.addChildNode(platform(radius:95,height:10,at:V3(0,-39,0),material:light))
        tower(on:hub,x:0,z:0,width:43,height:148)
        hub.addChildNode(segment(V3(0,165,0),V3(0,Self.towerTip,0),radius:2.4,mat:light))
        for i in 0..<12 {
            let a = Float(i)*tau/12
            let r = i%2 == 0 ? 72 as Float : 110
            tower(on:hub,x:sin(a)*r,z:cos(a)*r,width:rng.range(16,28),height:rng.range(37,91))
        }

        for armIndex in 0..<6 {
            let arm = SCNNode()
            arm.name = "atlantis.pier"
            arm.simdEulerAngles.y = Float(armIndex)*tau/6
            city.addChildNode(arm)
            let reach: Float = armIndex%3 == 0 ? 518 : 470
            let orientation = arm.simdOrientation
            let center = orientation.act(V3(0,9,-(reach+104)/2))
            hullSections.append(AtlantisHullSection(center:center,axes:V3(66,57,(reach-104)*0.53),orientation:orientation))
            let deck = armoredLoft([(-reach,25,7,-13),(-reach+43,61,10,-12),(-282,56,12,-12),(-150,61,14,-10),(-103,54,13,-9)],mat:foundation)
            arm.addChildNode(deck)
            arm.addChildNode(box(V3(70,5,reach-161),ceramic,V3(0,2.8,-(reach+145)/2),chamfer:1.4))
            arm.addChildNode(platform(radius:53,height:12,at:V3(0,0,-reach+62),material:ribs))
            for side: Float in [-1,1] {
                arm.addChildNode(segment(V3(side*35,6,-151),V3(side*35,6,-reach+47),radius:1.2,mat:light))
                arm.addChildNode(segment(V3(side*28,-28,-162),V3(side*20,-22,-reach+48),radius:3,mat:ribs))
                for row in 0..<5 {
                    let z = -175-Float(row)*49
                    tower(on:arm,x:side*rng.range(19,36),z:z,width:rng.range(12,21),height:rng.range(21,60))
                }
            }
            arm.addChildNode(platform(radius:16,height:1,at:V3(0,7,-reach+58),material:warm))
        }
    }

    func impact(from: V3, to: V3, padding: Float = 0) -> Float? {
        if shieldPoints>0 {
            return sphereImpact(from:from,to:to,center:position,radius:Self.shieldRadius+padding)
        }
        return hullImpact(from:from,to:to,padding:padding)
    }

    func hullImpact(from: V3, to: V3, padding: Float = 0) -> Float? {
        var earliest: Float?
        for section in hullSections {
            let axes = section.axes+V3(repeating:padding)
            let start = section.local(from-position)/axes
            let end = section.local(to-position)/axes
            if let hit = sphereImpact(from:start,to:end,center:.zero,radius:1), hit<(earliest ?? 2) {
                earliest = hit
            }
        }
        return earliest
    }

    func distanceToSurface(from point: V3) -> Float {
        let offset = point-position
        if shieldPoints>0 { return simd_length(offset)-Self.shieldRadius }
        return nearestHull(to:offset).distance(to:offset)
    }

    private func nearestHull(to offset: V3) -> AtlantisHullSection {
        var closest = hullSections[0]
        var distance = closest.distance(to:offset)
        for section in hullSections.dropFirst() {
            let other = section.distance(to:offset)
            if other<distance {
                closest = section
                distance = other
            }
        }
        return closest
    }

    func aimPoint(for fighter: Fighter) -> V3 {
        let offset = fighter.position-position
        if shieldPoints==0 {
            let section = nearestHull(to:offset)
            return position+section.center+V3(0,Float(fighter.pair%3-1)*12,0)
        }
        let right = unit(simd_cross(unit(offset),V3(0,1,0)))
        let across = Float(fighter.pair%3-1)*70
        let height = Float(fighter.pair/3)*45+Float(fighter.side)*32-40
        return position+right*across+V3(0,height,0)
    }

    func hitShield(at point: V3, damage: Int) {
        shieldPoints = max(0,shieldPoints-damage)
        impactStrength = 1
        shieldMaterial.setValue(SCNVector3(unit(point-position)),forKey:"impactDirection")
        shieldMaterial.setValue(Float(shieldPoints)/Float(Self.shieldCapacity),forKey:"integrity")
        shield.isHidden = shieldPoints==0
    }

    func updateShield(_ dt: Float) {
        impactStrength *= exp(-dt*6)
        shieldMaterial.setValue(impactStrength,forKey:"impactStrength")
    }
}

private struct AtlantisHullSection {
    let center: V3
    let axes: V3
    var orientation = simd_quatf(angle:0,axis:V3(0,1,0))

    func local(_ point: V3) -> V3 {
        orientation.inverse.act(point-center)
    }

    func distance(to point: V3) -> Float {
        let offset = local(point)
        return simd_length(offset)-1/simd_length(unit(offset)/axes)
    }
}

struct AncientDronePath {
    static let speed: Float = 235
    let origin: V3
    let rise: V3
    let turn: V3
    let exit: V3
    let direction: V3
    let duration: Float

    init(origin: V3, target: V3) {
        self.origin = origin
        direction = unit(target-origin)
        let distance = min(380,max(100,simd_distance(origin,target)*0.58))
        duration = max(0.65,distance/Self.speed)
        rise = origin+V3(0,min(85,distance*0.3),0)
        exit = origin+direction*distance
        // Match the coast speed at the end of the curve.
        turn = exit-direction*(Self.speed*duration/3)
    }

    func point(at age: Float) -> V3 {
        if age>=duration { return exit+direction*(age-duration)*Self.speed }
        let t = age/duration
        let a = mix(origin,rise,t)
        let b = mix(rise,turn,t)
        let c = mix(turn,exit,t)
        return mix(mix(a,b,t),mix(b,c,t),t)
    }
}

struct AncientDroneVolley {
    let path: AncientDronePath
    var remaining = Atlantis.droneVolleySize
}

final class AncientDrone {
    private static let glow = material(color(1,0.72,0.25),emission:color(3.4,1.7,0.20))
    private static let trail: SCNMaterial = {
        let material = material(color(0.94,0.4,0.06,0.5),emission:color(1.7,0.54,0.05))
        material.blendMode = .add
        material.writesToDepthBuffer = false
        return material
    }()

    let node: SCNNode
    let path: AncientDronePath
    var position: V3
    var age: Float = 0

    init(path: AncientDronePath) {
        self.path = path
        position = path.origin
        node = Self.makeNode()
        node.simdPosition = position
        node.simdOrientation = simd_quatf(from:V3(0,0,-1),to:V3(0,1,0))
    }

    static func makeNode(scale: Float = 1) -> SCNNode {
        let node = SCNNode()
        node.addChildNode(cylinder(1.05,4.8,Self.glow))
        node.addChildNode(segment(V3(0,0,2),V3(0,0,22),radius:0.42,mat:Self.trail))
        node.simdScale = V3(repeating:scale)
        return node
    }
}

extension Dogfight {
    var atlantisSiegeActive: Bool { atlantis?.intact == true }
    var fleetTruce: Bool { atlantisAttackingSide != nil }

    private func startAtlantisSiege(attackingSide: Int) {
        // Stage off to one side of the planet-facing gap so later fighter
        // deployments can still use the lanes on either side of the sightline.
        let towardPlanet = unit(V3(planetPosition.x,0,planetPosition.z))
        let angle = rng.range(0.99,1.13)
        let direction = simd_quatf(angle:angle,axis:V3(0,1,0)).act(towardPlanet)
        let station = direction*2850+V3(0,530,0)
        let clearance = Atlantis.shieldRadius+160
        let arrival = (0...5).map { station+V3(0,Float($0)*320,0) }.first { point in
            fighters.allSatisfy { !$0.active || simd_distance($0.position,point)>clearance }
        } ?? station+V3(0,1920,0)
        let city = Atlantis(position:arrival,time:time,seed:seed &+ UInt64(encountersCompleted),attackingSide:attackingSide)
        atlantis = city
        city.node.opacity = 0
        scene.rootNode.addChildNode(city.node)
        for shot in lasers { shot.node.removeFromParentNode() }
        lasers.removeAll(keepingCapacity:true)
        for fighter in fighters {
            fighter.attackTarget = nil
            fighter.breakUntil = -1
            fighter.pivotUntil = -100
            fighter.atlantisEgress = nil
            fighter.patrolRoute.removeAll(keepingCapacity:true)
        }
        if automatic { director.begin(.atlantisArrival,in:self) }
    }

    func atlantisDestination(for fighter: Fighter, city: Atlantis, speed: inout Float) -> V3 {
        let distance = city.distanceToSurface(from:fighter.position)
        speed = min(speed,88+max(0,distance-260)*0.20)
        if let exit = fighter.atlantisEgress {
            if simd_distance(fighter.position,exit)>75 { return exit }
            fighter.atlantisEgress = nil
        }
        let outward = unit(fighter.position-city.position)
        if distance<105 {
            let side: Float = (fighter.pair+fighter.side)%2 == 0 ? 1 : -1
            let lateral = unit(simd_cross(outward,V3(0,1,0)))
            let exit = fighter.position+outward*285+lateral*side*225+V3(0,side*75,0)
            fighter.atlantisEgress = exit
            return exit
        }

        return city.aimPoint(for:fighter)
    }

    func hitAtlantis(_ city: Atlantis, at point: V3, damage: Int = 1) {
        if city.shieldPoints>0 {
            city.hitShield(at:point,damage:damage)
            if city.shieldPoints==0 {
                jumpPulse(at:city.position,radius:Atlantis.shieldRadius*1.35)
                if automatic && city.assault?.finished != false { director.begin(.atlantisBreach,in:self) }
            }
            return
        }
        city.hullPoints -= min(3,damage)
        if city.hullPoints<=0 {
            city.destroyedAt = time
            returningFromAtlantis = true
            creditEncounter(survivingSides:[city.attackingSide],replenish:false)
            if nextAtlantisEncounter != nil { nextAtlantisEncounter = encountersCompleted+10 }
            for drone in city.drones { drone.node.removeFromParentNode() }
            city.drones.removeAll()
            city.droneVolley = nil
            if let assault = city.assault {
                for index in assault.ship.squadron where fighters[index].state == .arriving {
                    fighters[index].state = .destroyed
                }
                assault.removeNodes()
            }
            for fighter in fighters {
                fighter.patrolRoute.removeAll(keepingCapacity:true)
                fighter.atlantisEgress = nil
                fighter.breakUntil = -1
            }
            if automatic { director.begin(.atlantisDestruction,in:self) }
        }
    }

    func resolveAtlantisCollision(_ fighter: Fighter, from start: V3) {
        guard let city = atlantis, city.intact,
              let impact = city.impact(from:start,to:fighter.position,padding:fighter.faction.collisionRadius) else { return }
        fighter.position = mix(start,fighter.position,impact)
        fighter.node.simdPosition = fighter.position
        destroy(fighter)
    }

    func updateAtlantis(_ dt: Float, starts: [V3], wasActive: [Bool]) {
        if let side = atlantisAttackingSide, atlantis == nil, !returningFromAtlantis,
           carriers.isEmpty, arrivingCount==0, time>=nextArrivalTime {
            if atlantisTopUpPending || sideCount(side)==0 {
                atlantisTopUpPending = false
                let reserves = atlantisReinforcements(for:side)
                deploySquadron(reserves,side:side)
                if !reserves.isEmpty { return }
            }
            if sideCount(side)>0 && sideCount(1-side)==0 { startAtlantisSiege(attackingSide:side) }
        }
        if let city = atlantis {
            if let destroyedAt = city.destroyedAt {
                updateAtlantisDestruction(city,age:time-destroyedAt,dt:dt)
            } else {
                let arrivalAge = time-city.arrivalTime-Atlantis.revealDelay
                if arrivalAge>=0 && arrivalAge<dt {
                    jumpPulse(at:city.position,radius:Atlantis.shieldRadius*1.5)
                }
                city.node.opacity = CGFloat(min(1,max(0,arrivalAge/0.23)))
                city.updateShield(dt)
                if dt>0 {
                    updateAtlantisAssault(city,dt:dt)
                    updateAncientDrones(city,dt:dt,starts:starts,wasActive:wasActive)
                }
            }
        }
        guard returningFromAtlantis, let side = atlantisAttackingSide, atlantis == nil, arrivingCount==0,
              fighters.allSatisfy({!$0.active || simd_length_squared($0.position)<1200*1200}) else { return }
        let regroupUntil = atlantisRegroupUntil ?? (time+6)
        atlantisRegroupUntil = regroupUntil
        guard time>=regroupUntil else { return }
        returningFromAtlantis = false
        atlantisRegroupUntil = nil
        atlantisAttackingSide = nil
        refillVeteranSquadron(side:side)
        queueFactionReplacement(for:1-side)
    }

    private func updateAtlantisDestruction(_ city: Atlantis, age: Float, dt: Float) {
        let times: [Float] = [0,0.4,0.85,1.3,1.75,2.2,2.7]
        if city.nextExplosion<times.count, age>=times[city.nextExplosion] {
            let index = city.nextExplosion
            let angle = Float(index)*tau/6
            let offset = index==0 ? V3(0,80,0) : V3(sin(angle)*315,18,cos(angle)*315)
            burst(at:city.position+offset,count:20,big:true,scale:index==0 ? 13 : 8)
            city.nextExplosion += 1
        }
        if age>0.55 {
            for (i,part) in city.city.childNodes.enumerated() {
                let angle = Float(i-1)*tau/6
                let drift = i==0 ? V3(0,-22,0) : V3(-sin(angle)*46,-11,-cos(angle)*46)
                part.simdPosition += drift*dt
                part.simdEulerAngles.z += (i%2==0 ? 0.07 : -0.07)*dt
            }
        }
        city.city.opacity = CGFloat(max(0,min(1,(5.1-age)/2)))
        if age>=5.1 {
            city.node.removeFromParentNode()
            atlantis = nil
        }
    }

    private func launchAncientDroneIfReady(_ city: Atlantis) {
        guard time>=city.nextDroneTime else { return }
        if city.droneVolley == nil {
            guard city.assault?.finished != false else { return }
            let targets = fighters.indices.filter { fighters[$0].active && city.distanceToSurface(from:fighters[$0].position)<355 }
            guard !targets.isEmpty else { return }
            let index = targets[rng.index(targets.count)]
            let fighter = fighters[index]
            let target = interceptPoint(from:city.dronePort,velocity:.zero,target:fighter.position,
                                        targetVelocity:fighter.velocity,speed:AncientDronePath.speed)
            city.droneVolley = AncientDroneVolley(path:AncientDronePath(origin:city.dronePort,target:target))
            city.nextDroneTime = time
            director.requestAtlantisVolley(index,in:self)
        }
        guard var volley = city.droneVolley else { return }
        // Every drone traces the lead drone's curve at its own launch offset.
        let drone = AncientDrone(path:volley.path)
        city.drones.append(drone)
        city.node.addChildNode(drone.node)
        drone.node.simdPosition = volley.path.origin-city.position

        volley.remaining -= 1
        if volley.remaining>0 {
            city.droneVolley = volley
            city.nextDroneTime += Atlantis.droneLaunchInterval
        } else {
            city.droneVolley = nil
            city.nextDroneTime = time+Atlantis.droneVolleyPause
        }
    }

    private func updateAncientDrones(_ city: Atlantis, dt: Float, starts: [V3], wasActive: [Bool]) {
        launchAncientDroneIfReady(city)
        for i in city.drones.indices.reversed() {
            let drone = city.drones[i]
            drone.age += dt
            let from = drone.position
            drone.position = drone.path.point(at:drone.age)
            drone.node.simdPosition = drone.position-city.position
            drone.node.simdOrientation = simd_quatf(from:V3(0,0,-1),to:unit(drone.position-from))
            var fraction: Float = 2
            var victim: Fighter?
            for j in fighters.indices where fighters[j].active {
                let fighter = fighters[j]
                let start = wasActive[j] ? starts[j] : fighter.position
                if let hit = sphereImpact(from:from-start,to:drone.position-fighter.position,center:.zero,radius:fighter.faction.collisionRadius+2), hit<fraction {
                    fraction = hit
                    victim = fighter
                }
            }
            if let victim {
                burst(at:mix(from,drone.position,fraction),count:11,big:false)
                victim.hitPoints -= 2
                if victim.hitPoints<=0 { destroy(victim) }
            }
            if fraction<=1 || drone.age>=6 {
                drone.node.removeFromParentNode()
                city.drones.remove(at:i)
            }
        }
    }
}
