import SceneKit
import simd

struct ArrivalFlight {
    let indices: [Int]
    let origin: V3
    let forward: V3
    let start: Float
}

struct AtlantisLookout {
    let index: Int
    let generation: Int
    let position: V3
    let slide: V3
    let launchFocus: V3?
}

final class CinematicDirector {
    static let atlantisWideDuration: Float = 3.4

    enum Event {
        case none, formation, carrierArrival, carrierDeparture, handoff, spin, attack, explosion
        case atlantisArrival, atlantisAttack, atlantisDefense, atlantisBreach, atlantisDestruction
        case atlantisCapitalArrival, atlantisBombardment, atlantisCounterstrike, atlantisCapitalDestroyed
    }
    var event: Event = .none
    var eventAge: Float = 0
    var arrivalFlight: ArrivalFlight?
    var featuredCarrier: Carrier?
    var coveredFlight: Float = -100
    var shotLength: Float = 7
    var velocity = V3.zero
    var lookVelocity = V3.zero
    var heading = V3(0,0,-1)
    var side: Float = 1
    var flybyAnchor = V3.zero
    var overviewSubject: Int?
    var overviewDirection = V3.zero
    var overviewReviewAt: Float = 0
    var nextHighlightTime: Float = 10
    var nextCriticalCheck: Float = 0
    var engagementTarget: Int?
    var explosionOrigin = V3.zero
    var explosionVelocity = V3.zero
    var explosionCamera = V3.zero
    var attackCuts = 0
    var explosionCuts = 0
    var shake: Float = 0
    var rng: Random
    var formationCuts = 0
    var carrierCuts = 0
    var carrierLaunchCuts = 0
    var carrierLaunchShot = false
    var carrierDollyDistance: Float = 0
    var handoffIncoming: [(index: Int,generation: Int)] = []
    var handoffExisting: [(index: Int,generation: Int)] = []
    var handoffAnchor: Int?
    var handoffSide: Float = 10
    var handoffHeight: Float = 7
    var handoffCuts = 0
    var dangerCuts = 0
    var normalCuts = 0
    var hardCuts = 0
    var lastDangerTime: Float = -20
    var atlantisLookout: AtlantisLookout?
    private var nextAtlantisPier = false
    private var favorAtlantisLookout = true
    var caption: String?
    var detail: String?
    init(seed: UInt64) { rng = Random(state:seed ^ 0xC1AE_AA77) }

    func begin(_ newEvent: Event, in b: Dogfight) {
        event = newEvent; eventAge = 0; b.cut = true; b.wreckHold = 0
        switch newEvent {
        case .formation: caption = "SQUADRON INBOUND"; detail = "X-WING FORMATION / HYPERSPACE INSERTION"; formationCuts += 1
        case .carrierArrival:
            carrierLaunchShot = false
            carrierDollyDistance = 0
            caption = featuredCarrier?.faction.carrierName ?? "CAPITAL SHIP INBOUND"
            detail = featuredCarrier?.faction.usesJumpWindow == true ? "JUMP POINT OPENING / SQUADRON DEPLOYMENT" : (featuredCarrier?.faction.usesBlinkFTL == true ? "FTL BLINK / SQUADRON DEPLOYMENT" : "HYPERSPACE ARRIVAL / HANGAR DEPLOYMENT")
            carrierCuts += 1
        case .carrierDeparture:
            caption = featuredCarrier?.faction == .earth ? "JUMP POINT CLOSING" : (featuredCarrier?.faction.usesBlinkFTL == true ? "FTL JUMP" : "JUMP TO HYPERSPACE")
            detail = featuredCarrier?.faction == .earth ? "SQUADRON CLEAR / JUMP POINT COLLAPSE" : "CAPITAL SHIP DEPARTURE"
        case .handoff:
            featuredCarrier = nil
            caption = "SQUADRON APPROACHING"; detail = "FROM THE BATTLE / INCOMING SQUADRON TRACKING"; handoffCuts += 1
        case .spin:
            caption = "LOSS OF CONTROL"
            detail = b.fighters[b.followedIndex].spin?.cause == .ship ? "SHIP COLLISION / RECOVERY TRACKING" : "ASTEROID STRIKE / RECOVERY TRACKING"
            dangerCuts += 1
        case .attack:
            caption = "HOT PURSUIT"; detail = "CRITICAL ATTACK RUN / TARGET UNDER FIRE"; attackCuts += 1
        case .explosion:
            caption = "FIGHTER DESTROYED"; detail = "COMBAT LOSS / EXPLOSION TRACKING"; explosionCuts += 1
        case .atlantisArrival:
            favorAtlantisLookout = true
            nextAtlantisPier = false
            caption = "ATLANTIS ARRIVES"; detail = "CITY SHIP / SQUADRONS DIVERTING"
        case .atlantisAttack:
            favorAtlantisLookout = true
            caption = "ATTACK RUN"; detail = "ATLANTIS / ANCIENT DRONE DEFENSE"
        case .atlantisDefense:
            favorAtlantisLookout = false
            caption = "ATLANTIS DEFENSE"; detail = "TRACKING INCOMING FIGHTERS"
        case .atlantisBreach:
            caption = "SHIELD COLLAPSE"; detail = "ATLANTIS HULL EXPOSED"
        case .atlantisCapitalArrival:
            caption = b.atlantis?.assault?.ship.faction.siegeCapitalName
            detail = "CAPITAL SHIP INBOUND / ATLANTIS UNDER SIEGE"
        case .atlantisBombardment:
            caption = "CAPITAL BOMBARDMENT"; detail = "HEAVY BATTERIES FIRING ON ATLANTIS"
        case .atlantisCounterstrike:
            caption = "ANCIENT DRONE COUNTERSTRIKE"; detail = "SWARM LAUNCHING FROM THE CENTRAL TOWER"
        case .atlantisCapitalDestroyed:
            caption = "CAPITAL SHIP DESTROYED"; detail = b.atlantis?.assault?.ship.faction.siegeCapitalName
        case .atlantisDestruction:
            caption = "ATLANTIS DESTROYED"; detail = "SURVIVORS RETURNING TO THE BELT"
        case .none:
            caption = nil; detail = nil; featuredCarrier = nil
            atlantisLookout = nil
            handoffIncoming.removeAll(); handoffExisting.removeAll(); handoffAnchor = nil
        }
        b.cameraChanged?()
    }
    func requestCarrierArrival(_ ship: Carrier, in b: Dogfight) {
        if b.automatic && b.atlantis?.assault?.finished != false {
            rememberIncomingSquadron(ship,in:b)
            featuredCarrier = ship; begin(.carrierArrival,in:b)
        }
    }
    func requestCarrierDeparture(_ ship: Carrier, in b: Dogfight) {
        guard b.automatic, b.atlantis?.assault?.finished != false else { return }
        // Keep the arrival camera and its shot clock through the same departure beat.
        if featuredCarrier === ship && event == .carrierArrival {
            caption = ship.faction == .earth ? "JUMP POINT CLOSING" : (ship.faction.usesBlinkFTL ? "FTL JUMP" : "JUMP TO HYPERSPACE")
            detail = ship.faction == .earth ? "SQUADRON CLEAR / JUMP POINT COLLAPSE" : "SQUADRON DEPLOYED / CAPITAL SHIP DEPARTURE"
            b.cameraChanged?()
        } else {
            if handoffIncoming.isEmpty { rememberIncomingSquadron(ship,in:b) }
            featuredCarrier = ship; begin(.carrierDeparture,in:b)
        }
    }
    func requestSpin(_ index: Int, in b: Dogfight) {
        guard b.automatic, event == .none, b.cameraIndex == 2, b.time>=nextHighlightTime, b.time-lastDangerTime>8, b.cameraAge>8 else { return }
        lastDangerTime = b.time; b.followedIndex = index; heading = b.fighters[index].forward; begin(.spin,in:b)
    }
    func requestExplosion(_ fighter: Fighter, in b: Dogfight) {
        guard b.automatic else { return }
        let alreadyFollowing = (event == .attack && (engagementTarget.flatMap { b.fighters[$0] } === fighter || b.fighters[b.followedIndex] === fighter)) || (event == .spin && b.fighters[b.followedIndex] === fighter)
        let important = fighter.hitPoints<=2 || b.sideCount(fighter.side)<=2 || fighter.spin != nil
        guard alreadyFollowing || (event == .none && b.cameraIndex == 2 && b.time>=nextHighlightTime && b.cameraAge>8 && important) else { return }
        explosionOrigin = fighter.position; explosionVelocity = fighter.velocity
        explosionCamera = alreadyFollowing ? b.cameraPosition : fighter.position+unit(b.cameraPosition-fighter.position)*43+V3(0,8,0)
        let pendingCut = b.cut
        begin(.explosion,in:b)
        if alreadyFollowing { b.cut = pendingCut }
    }
    func requestAtlantisAttack(_ index: Int, in b: Dogfight) {
        guard b.automatic, event == .none, b.cameraIndex == 2, let city = b.atlantis,
              b.time>=nextHighlightTime, b.cameraAge>=2.4 else { return }
        if favorAtlantisLookout {
            startAtlantisLookout(index,city:city,in:b,fromPier:nextAtlantisPier)
        } else {
            b.followedIndex = index
            heading = b.fighters[index].forward
            begin(.atlantisAttack,in:b)
        }
    }

    func requestAtlantisVolley(_ index: Int, in b: Dogfight) {
        guard b.automatic, let city = b.atlantis,
              (event == .none && b.cameraAge>=1.8) || (event == .atlantisDefense && eventAge>=2.4) else { return }
        startAtlantisLookout(index,city:city,in:b,fromPier:false,volley:true)
    }

    private func startAtlantisLookout(_ index: Int, city: Atlantis, in b: Dogfight, fromPier: Bool, volley: Bool = false) {
        let fighter = b.fighters[index]
        let offset = fighter.position-city.position
        let outward = unit(V3(offset.x,0,offset.z))
        let right = unit(simd_cross(outward,V3(0,1,0)))
        var position: V3
        let launchFocus: V3?
        if volley, let path = city.droneVolley?.path {
            position = city.dronePort-outward*128+right*88+V3(0,30,0)
            launchFocus = mix(path.origin,path.exit,0.46)+V3(0,35,0)
        } else if fromPier {
            let step = tau/6
            let angle = (atan2(-outward.x,-outward.z)/step).rounded()*step
            let pier = V3(-sin(angle),0,-cos(angle))
            position = city.position+pier*380+V3(0,63,0)+right*86
            launchFocus = nil
        } else {
            position = city.dronePort-outward*31+right*64+V3(0,21,0)
            launchFocus = nil
        }
        if launchFocus == nil, city.hullImpact(from:position,to:fighter.position,padding:5) != nil {
            position.y += 64
        }
        atlantisLookout = AtlantisLookout(index:index,generation:fighter.generation,position:position,
                                         slide:right*(fromPier ? 17 : 25)+outward*12,
                                         launchFocus:launchFocus)
        nextAtlantisPier = !fromPier
        begin(.atlantisDefense,in:b)
        caption = volley ? "ANCIENT DRONES LAUNCH" : (fromPier ? "OUTER PIER" : "CENTRAL TOWER")
        b.cameraChanged?()
    }

    private func considerAtlantisCoverage(in b: Dogfight) {
        guard b.automatic, event == .none, b.cameraIndex == 2,
              b.cameraAge>=Self.atlantisWideDuration, let city = b.atlantis, city.intact else { return }
        let live = b.fighters.indices.filter { b.fighters[$0].active && b.fighters[$0].spin == nil }
        let inbound = live.filter { b.fighters[$0].atlantisEgress == nil }
        let candidates = inbound.isEmpty ? live : inbound
        guard let index = candidates.min(by: {
            simd_distance_squared(b.fighters[$0].position,city.position)<simd_distance_squared(b.fighters[$1].position,city.position)
        }) else { return }
        let fighter = b.fighters[index]
        if city.distanceToSurface(from:fighter.position)<430 {
            startAtlantisLookout(index,city:city,in:b,fromPier:nextAtlantisPier)
        } else {
            // Follow the flight in while the attackers are still too distant
            // to read from the city itself.
            b.followedIndex = index
            heading = fighter.forward
            begin(.atlantisAttack,in:b)
        }
    }

    func atlantisFrame(_ city: Atlantis, in b: Dogfight, progress: Float = 0) -> (position: V3, look: V3, fov: Float) {
        let outward = unit(V3(-city.position.x,0,-city.position.z))
        let right = unit(simd_cross(outward,V3(0,1,0)))
        let direction = unit(outward+right*(0.55+progress*0.38)+V3(0,0.68,0))
        let distance = (1680+progress*130)/max(0.72,min(1,b.viewportAspect))
        return (city.position+direction*distance,city.position+V3(0,30,0),52)
    }

    func considerCriticalMoment(in b: Dogfight) {
        guard !b.fleetTruce else { return }
        guard b.automatic, event == .none, b.cameraIndex == 2, b.cameraAge>8, b.time>=nextHighlightTime, b.time>=nextCriticalCheck else { return }
        nextCriticalCheck = b.time+0.2
        for i in b.fighters.indices where b.fighters[i].active && b.fighters[i].spin == nil {
            let f = b.fighters[i]
            guard f.burstShotsLeft>0, let target = f.attackTarget, b.fighters[target].active else { continue }
            let enemy = b.fighters[target], distance = simd_distance(f.position,enemy.position)
            let important = enemy.hitPoints<=3 || b.sideCount(enemy.side)<=2
            if important && distance<145 && simd_dot(unit(enemy.position-f.position),f.forward)>0.95 {
                b.followedIndex = i; engagementTarget = target; heading = f.forward
                begin(.attack,in:b); return
            }
        }
        for i in b.fighters.indices where b.fighters[i].active && b.fighters[i].spin == nil {
            let f = b.fighters[i]
            guard simd_length(f.velocity)>65 else { continue }
            let threatened = b.rocks.contains { sphereImpact(from:f.position,to:f.position+f.velocity*0.7,center:$0.position,radius:$0.radius+f.faction.collisionRadius+2) != nil }
            if threatened {
                requestSpin(i,in:b)
                if event == .spin { caption = "EVASIVE ACTION"; detail = "ASTEROID CLOSE PASS"; b.cameraChanged?() }
                return
            }
        }
    }
    func endEvent(in b: Dogfight, follow index: Int? = nil) {
        begin(.none,in:b)
        b.cameraIndex = 2; b.cameraAge = 0
        nextHighlightTime = b.time+(b.atlantisSiegeActive ? 2.4 : 10)
        if let index, b.fighters[index].active { b.followedIndex = index } else { b.selectCameraSubject() }
        prepareShot(in:b); b.cameraChanged?()
    }
    func prepareShot(in b: Dogfight) {
        overviewSubject = nil
        overviewDirection = .zero
        overviewReviewAt = 0
        shotLength = b.cameraIndex == 4 ? 4.8 : (b.cameraIndex == 2 ? 5.5 : rng.range(6.5,9.5))
        if let f = b.cameraSubject() {
            heading = f.forward
            let right = unit(simd_cross(heading,V3(0,1,0)))
            flybyAnchor = f.position+f.velocity*1.4+right*side*22+V3(0,7,0)
        }
        velocity = .zero; lookVelocity = .zero; normalCuts += 1
    }
    func battlefieldFrame(in b: Dogfight) -> (position: V3, look: V3, fov: Float) {
        let live = b.fighters.indices.filter { b.fighters[$0].active }
        guard !live.isEmpty else {
            return (b.arenaRotation.act(V3(250,160,250)),.zero,49)
        }
        if overviewSubject == nil || !b.fighters[overviewSubject!].active || b.time>=overviewReviewAt {
            let old = overviewSubject
            overviewReviewAt = b.time+2
            // Prefer a busy engagement. Widely separated inbound squadrons are
            // separate subjects, rather than endpoints of a mostly empty panorama.
            func score(_ index: Int) -> Float {
                    let f = b.fighters[index]
                    return live.reduce(Float(0)) { total,j in
                        let other = b.fighters[j], distance = simd_distance(f.position,other.position)
                        let weight = max(0,1-distance/420)
                        return total+weight*(f.side == other.side ? 1 : 3)
                    }
            }
            let best = live.max { score($0)<score($1) }!
            if old == nil || !b.fighters[old!].active || score(best)>score(old!)*1.4+0.5 { overviewSubject = best }
            if let old, overviewSubject != old, simd_distance(b.fighters[old].position,b.fighters[overviewSubject!].position)>350 {
                overviewDirection = .zero; b.cut = true
            }
        }
        let anchor = b.fighters[overviewSubject!]
        // Frame the connected furball, including wingmen on its edges. A distant
        // inbound squadron is not allowed to stretch the view across empty space.
        var members = Set([overviewSubject!]), changed = true
        while changed {
            changed = false
            for i in live where !members.contains(i) && simd_distance(b.fighters[i].position,anchor.position)<650 {
                if members.contains(where:{simd_distance(b.fighters[$0].position,b.fighters[i].position)<240}) { members.insert(i); changed = true }
            }
        }
        let group = live.filter { members.contains($0) }.map { b.fighters[$0] }
        let center = group.reduce(V3.zero) { $0+$1.position }/Float(group.count)
        let radius = group.map { simd_distance($0.position,center)+$0.faction.collisionRadius }.max() ?? 20
        let fov: Float = 49
        let distance = max(85,radius/sin(fov*Float.pi/360)*1.12)
        if simd_length_squared(overviewDirection)<0.1 {
            var best = -Float.infinity
            // Establish from an open side of the asteroid cluster so the hulls
            // are readable instead of hidden behind a foreground boulder.
            let planetDirection = unit(V3(center.x-b.planetPosition.x,0,center.z-b.planetPosition.z))
            let count = b.automatic ? 19 : 16
            for step in 0..<count {
                let a = b.time*0.026+Float(step%8)*tau/8
                let elevation: Float = step<8 ? 0.65 : 1.5
                let direction = step<16 ? unit(b.arenaRotation.act(V3(sin(a)*0.8,elevation,cos(a)*0.8)))
                    : unit(planetDirection+V3(0,Float(step-17)*0.17,0))
                let point = center+direction*distance
                let visible = group.reduce(Float(0)) { total,f in
                    let blocked = b.rocks.contains { sphereImpact(from:point,to:f.position,center:$0.position,radius:$0.radius) != nil }
                    return total+(blocked ? 0 : (f.side == anchor.side ? 1 : 2))
                }
                let view = -direction
                let foreground = b.rocks.reduce(Float(0)) { total,rock in
                    let offset = rock.position-point, d = simd_length(offset)
                    if d<rock.radius+12 { return total+5 }
                    guard simd_dot(offset,view)>0, d<distance*1.2, simd_dot(unit(offset),view)>0.6 else { return total }
                    return total+min(3,rock.radius*rock.radius/max(1,d*d)*30)
                }
                let planetAngle = simd_dot(unit(b.planetPosition-point),view)
                let backdrop: Float = step>=16 && planetAngle>0.95 ? 0.65 : 0
                let score = visible-foreground+backdrop
                if score>best { best = score; overviewDirection = direction }
            }
        }
        var outward = overviewDirection
        if b.carriers.contains(where:{ !$0.node.isHidden && simd_distance($0.origin,center)<$0.worldRadius+400 }) {
            outward = unit(anchor.forward+V3(0,0.55,0))
        }
        return (center+outward*distance,center,fov)
    }
    func damp(_ value: inout V3, velocity: inout V3, target: V3, frequency: Float, dt: Float) {
        let offset = value-target, e = exp(-frequency*dt)
        let temp = (velocity+offset*frequency)*dt
        velocity = (velocity-temp*frequency)*e
        value = target+(offset+temp)*e
    }

    private func planetaryReveal(origin: V3, subject: V3, points: [V3], distance: Float,
                                 age: Float, cue: Float, elevation: Float = 0.24, in b: Dogfight)
        -> (position: V3, look: V3, fov: Float, roll: Float) {
        let up = V3(0,1,0)
        let outward = unit(b.planetPosition-origin)
        let right = unit(simd_cross(outward,up))
        let lateral = simd_dot(origin,right)>0 ? -right : right
        let range = distance/max(0.58,min(1,b.viewportAspect))
        let position = origin+range*(-outward+lateral*0.32+up*elevation)-lateral*distance*0.028*age
        let shipSightline = unit(subject-position)
        let planetSightline = unit(b.planetPosition-position)
        // The operator holds the wide frame until the jump, pans a beat late,
        // then briefly overshoots before settling on the arriving ship.
        let reaction = max(0,age-cue-0.08)
        let zoom = 1-exp(-reaction*reaction*52)
        let correction = sin(reaction*15)*exp(-reaction*6)
        let aim = unit(mix(shipSightline,planetSightline,0.43-zoom*0.14)
                       + lateral*correction*0.04+up*correction*0.025)
        let roll = correction*0.037
        let screenRight = simd_quatf(angle:roll,axis:aim).act(unit(simd_cross(aim,up)))
        let screenUp = simd_cross(screenRight,aim)
        // Allow the limb to extend beyond frame while keeping the hull, gate,
        // and enough of the planet's disc to read as three separate depths.
        let radius = b.planetRadius*0.68
        let backdrop = [b.planetPosition+screenUp*radius,b.planetPosition-screenUp*radius,
                        b.planetPosition+screenRight*radius,b.planetPosition-screenRight*radius]
        let tangent = (points+backdrop).reduce(Float(0)) { extent,point in
            let delta = point-position
            let depth = max(1,simd_dot(delta,aim))
            let reach = max(abs(simd_dot(delta,screenUp)),abs(simd_dot(delta,screenRight))/b.viewportAspect)
            return max(extent,reach/depth)
        }
        let fitted = atan(tangent*1.12)*360/Float.pi
        let fov = max(fitted,36)+12*(1-zoom)
        return (position,position+aim*range,fov,roll)
    }

    private func carrierReveal(_ ship: Carrier, age: Float, in b: Dogfight)
        -> (position: V3, look: V3, fov: Float, roll: Float) {
        var subject = ship.origin
        var points = ship.framingPoints.map { ship.origin+ship.node.simdOrientation.act($0*ship.scale) }
        var distance = max(950,ship.worldRadius*1.7)
        var cue: Float = ship.faction.usesBlinkFTL ? ship.arrivalDuration : 0.96
        if let window = ship.jumpWindow {
            let portal = window.node.simdPosition
            let right = unit(simd_cross(ship.forward,V3(0,1,0)))
            let radius = window.radius*0.87
            for x: Float in [-1,1] { for y: Float in [-1,1] {
                points.append(portal+right*x*radius+V3(0,y*radius,0))
            } }
            subject = mix(portal,ship.origin,0.4)
            distance = max(710,window.radius*2.15)
            cue = ship.jumpClipper == nil ? 0.38 : 1.4
        }
        return planetaryReveal(origin:ship.origin,subject:subject,points:points,distance:distance,age:age,cue:cue,in:b)
    }

    private func atlantisReveal(_ city: Atlantis, age: Float, in b: Dogfight)
        -> (position: V3, look: V3, fov: Float, roll: Float) {
        let up = V3(0,1,0)
        let shieldRadius = Atlantis.shieldRadius
        var points = [city.position+up*shieldRadius,city.position-up*shieldRadius]
        for step in 0..<12 {
            let angle = Float(step)*tau/12
            points.append(city.position+V3(sin(angle),0,cos(angle))*shieldRadius)
        }
        return planetaryReveal(origin:city.position,subject:city.position+up*72,points:points,
                               distance:1480,age:age,cue:Atlantis.revealDelay,
                               elevation:0.40+min(1,age/4.8)*0.20,in:b)
    }

    private func assaultFrame(_ assault: AtlantisAssault, city: Atlantis, in b: Dogfight)
        -> (position: V3, look: V3, fov: Float) {
        let ship = assault.ship
        let up = V3(0,1,0)
        let right = unit(simd_cross(ship.forward,up))
        let width = max(0.65,min(1,b.viewportAspect/1.45))
        switch event {
        case .atlantisBombardment:
            let focus = mix(city.position,ship.origin,0.54)+up*36
            return (focus+right*2490/width+up*590-ship.forward*110,focus,59)
        case .atlantisCounterstrike where eventAge<2.05:
            let port = city.dronePort
            return (port+ship.forward*82+right*117+up*79, mix(port,ship.origin,0.19)+up*59,57)
        case .atlantisCounterstrike:
            let focus = ship.origin+ship.forward*180+up*52
            let offset = unit(ship.forward*0.88+right*0.42+up*0.28)
            return (focus+offset*(ship.worldRadius*2.05+410)/width,focus,57)
        default:
            let focus = ship.node.simdPosition
            let offset = unit(ship.forward*0.63+right*0.85+up*0.30)
            return (focus+offset*(ship.worldRadius*1.86+150+eventAge*83)/width,focus,53)
        }
    }

    func carrierLaunchFrame(_ ship: Carrier, in b: Dogfight) -> (position: V3, look: V3) {
        let age = b.time-ship.start
        let up = ship.node.simdOrientation.act(V3(0,1,0))
        let right = unit(simd_cross(ship.forward,V3(0,1,0)))
        let hero = b.fighters[ship.squadron[0]]
        let heroPosition = hero.active ? hero.position : hero.entryPosition
        let members = ship.squadron.map { b.fighters[$0] }
        // Include the launch lanes before each fighter appears, so a new arrival
        // does not jerk the centroid from one hangar to the opposite one.
        let points = members.map { $0.active ? $0.position : $0.entryPosition }
        let group = points.reduce(V3.zero,+)/Float(points.count)
        let groupVelocity = members.reduce(V3.zero) { $0+($1.active ? $1.velocity : .zero) }/Float(members.count)
        let linear = min(1,max(0,(age-2.5)/max(0.5,ship.lastLaunchAge-2.5-0.3)))
        let pull = linear*linear*(3-2*linear)
        let focus = mix(heroPosition,group,pull)
        let focusVelocity = mix(hero.active ? hero.velocity : .zero,groupVelocity,pull)
        let forwardOffset: Float = ship.faction == .shadow ? 30 : 58
        let lateralOffset: Float = ship.faction == .shadow ? 70 : 38
        let offset: V3 = ship.forward*forwardOffset-right*lateralOffset-up*18
        let outward = unit(offset)
        let screenRight = unit(simd_cross(-outward,V3(0,1,0)))
        let screenUp = unit(simd_cross(screenRight,-outward))
        let tangent = tan(Float(26)*Float.pi/180) // Fixed 52° lens: a dolly, not a zoom.
        let fullFocus = group+up*2
        var framing = points
        for local in ship.framingPoints {
            // Keep the launch station as the backdrop when the capital accelerates
            // into hyperspace; the camera continues following the fighters.
            framing.append(ship.station(age)+ship.node.simdOrientation.act(local*ship.scale))
        }
        if ship.faction == .shadow, let window = ship.jumpWindow {
            // Reserve screen space before the departure aperture opens. The
            // lateral launch angle prevents its dark core hiding the capital.
            let portal = ship.origin+ship.forward*ship.worldRadius*1.6
            for x: Float in [-1,1] { for y: Float in [-1,1] {
                framing.append(portal+right*x*window.radius+up*y*window.radius)
            } }
        }
        var fittedDistance: Float = 100
        for point in framing {
            let delta = point-fullFocus
            let transverse = max(abs(simd_dot(delta,screenUp))/tangent,abs(simd_dot(delta,screenRight))/(tangent*b.viewportAspect))
            fittedDistance = max(fittedDistance,simd_dot(delta,outward)+transverse*1.1+20)
        }
        carrierDollyDistance = max(carrierDollyDistance,fittedDistance)
        let distance = simd_length(offset)+(carrierDollyDistance-simd_length(offset))*pull
        let position: V3 = focus+focusVelocity*(Float(2)/7)+outward*distance
        let look: V3 = focus+up*2
        return (position,look)
    }
    func update(_ dt: Float, in b: Dogfight) {
        eventAge += dt; shake *= exp(-dt*8)
        if !b.automatic && event != .none { begin(.none,in:b) }
        if b.automatic, b.atlantis?.assault?.finished != false, let flight = arrivalFlight,
           flight.start>coveredFlight, b.time>=flight.start, b.time-flight.start<1.1 {
            coveredFlight = flight.start; begin(.formation,in:b)
        }
        if event == .none && b.automatic && b.cameraIndex != 2 && b.cameraAge>shotLength { endEvent(in:b) }
        considerAtlantisCoverage(in:b)
        considerCriticalMoment(in:b)
        let up = V3(0,1,0)
        var desired = b.cameraPosition, look = b.cameraLook
        var fov: Float = 51
        var roll: Float = 0
        var revealingArrival = false
        var trackingFormation = false
        if event == .formation, let flight = arrivalFlight {
            let age = b.time-flight.start
            let right = unit(simd_cross(flight.forward,up))
            let closeAt: Float = 1.8
            if age<closeAt {
                let points = flight.indices.map { b.fighters[$0].entryPosition }
                let anchor = flight.origin+flight.forward*max(0,age-1.25)*28
                (desired,look,fov,roll) = planetaryReveal(origin:flight.origin,subject:anchor,points:points,
                    distance:285,age:age,cue:1.14,in:b)
                revealingArrival = true
            } else {
                if age-dt<closeAt { b.cut = true }
                let squadron = flight.indices.map { b.fighters[$0] }.filter(\.active)
                guard !squadron.isEmpty else { endEvent(in:b); update(0,in:b); return }
                let anchor = squadron.reduce(V3.zero) { $0+$1.position }/Float(squadron.count)
                let lead = squadron.reduce(V3.zero) { $0+$1.velocity }/Float(squadron.count)
                let spread = squadron.map { simd_distance($0.position,anchor) }.max() ?? 0
                let pan = min(1,max(0,(age-3.1)/1.8))
                let offset = right*(28+pan*70)+up*(32+pan*3)+flight.forward*(95-pan*115)
                let range = max(simd_length(offset),spread*2.8/max(0.65,min(1,b.viewportAspect)))
                desired = anchor+unit(offset)*range+lead*(Float(2)/7)
                look = anchor; fov = 49
                trackingFormation = true
            }
            if age>5.4 { endEvent(in:b,follow:flight.indices.first); update(0,in:b); return }
        } else if event == .carrierArrival || event == .carrierDeparture, let ship = b.carrier {
            let age = b.time-ship.start, right = unit(simd_cross(ship.forward,up))
            let anchor = ship.station(age)
            let framing = ship.framingScale
            if event == .carrierArrival {
                if age>=2.15 && !carrierLaunchShot {
                    // One motivated cut establishes fighter scale after the wide arrival.
                    // Keep this foreground fighter / background capital composition through departure.
                    carrierLaunchShot = true; carrierLaunchCuts += 1; b.cut = true
                }
                if carrierLaunchShot {
                    let frame = carrierLaunchFrame(ship,in:b)
                    desired = frame.position; look = frame.look; fov = 52
                } else {
                    (desired,look,fov,roll) = carrierReveal(ship,age:age,in:b)
                    revealingArrival = true
                }
                if age>ship.departureAge+ship.departureDuration {
                    if !startArrivalHandoff(in:b) { endEvent(in:b,follow:ship.squadron.first) }
                    update(0,in:b); return
                }
            } else {
                desired = anchor+(right*310+up*100+ship.forward*220)*framing
                look = ship.faction.usesBlinkFTL ? anchor : anchor+ship.forward*min(190,max(0,age-ship.departureAge)*115)
                fov = 51
                if eventAge>(ship.faction.usesBlinkFTL ? 0.65 : 2) {
                    if !startArrivalHandoff(in:b) { endEvent(in:b) }
                    update(0,in:b); return
                }
            }
        } else if event == .carrierArrival || event == .carrierDeparture {
            if !startArrivalHandoff(in:b) { endEvent(in:b) }
            update(0,in:b); return
        } else if event == .handoff {
            guard eventAge<3.5, let frame = arrivalHandoffFrame(in:b) else {
                endEvent(in:b); update(0,in:b); return
            }
            desired = frame.position; look = frame.look; fov = frame.fov
        } else if event == .atlantisCapitalArrival {
            guard let assault = b.atlantis?.assault, !assault.finished else {
                endEvent(in:b); update(0,in:b); return
            }
            (desired,look,fov,roll) = carrierReveal(assault.ship,age:b.time-assault.ship.start,in:b)
            revealingArrival = true
        } else if event == .atlantisBombardment || event == .atlantisCounterstrike || event == .atlantisCapitalDestroyed {
            guard let city = b.atlantis, let assault = city.assault, !assault.finished else {
                endEvent(in:b); update(0,in:b); return
            }
            if event == .atlantisCounterstrike && eventAge>=2.05 && eventAge-dt<2.05 {
                b.cut = true
                detail = "DRONES MAKING REPEATED PASSES THROUGH THE HULL"
                b.cameraChanged?()
            }
            let frame = assaultFrame(assault,city:city,in:b)
            desired = frame.position; look = frame.look; fov = frame.fov
        } else if event == .atlantisArrival || event == .atlantisBreach || event == .atlantisDestruction {
            guard let city = b.atlantis, eventAge<4.8 else {
                endEvent(in:b); update(0,in:b); return
            }
            if event == .atlantisArrival {
                (desired,look,fov,roll) = atlantisReveal(city,age:b.time-city.arrivalTime,in:b)
                revealingArrival = true
            } else {
                let frame = atlantisFrame(city,in:b,progress:eventAge/4.8)
                desired = frame.position; look = frame.look; fov = frame.fov
            }
        } else if event == .atlantisDefense {
            guard b.atlantisSiegeActive, eventAge<4.2, let shot = atlantisLookout else {
                endEvent(in:b); update(0,in:b); return
            }
            let fighter = b.fighters[shot.index]
            guard fighter.active, fighter.generation==shot.generation else {
                endEvent(in:b); update(0,in:b); return
            }
            desired = shot.position+shot.slide*(eventAge/4.2)
            look = shot.launchFocus ?? (fighter.position+fighter.velocity*0.16)
            let range = simd_distance(desired,fighter.position)
            fov = shot.launchFocus != nil ? 50 : max(21,min(38,38-range*0.018))
        } else if event == .atlantisAttack {
            let f = b.fighters[b.followedIndex]
            guard b.atlantisSiegeActive, f.active, f.spin == nil, eventAge<3.1 else {
                endEvent(in:b); update(0,in:b); return
            }
            heading = unit(mix(heading,f.forward,1-exp(-dt*5)))
            let right = unit(simd_cross(heading,up))
            desired = f.position-heading*48+right*17+up*12
            look = f.position+heading*26
            fov = 51
        } else if event == .attack {
            let f = b.fighters[b.followedIndex]
            guard let index = engagementTarget, f.active, b.fighters[index].active, eventAge<2.6 else {
                endEvent(in:b); update(0,in:b); return
            }
            let target = b.fighters[index]
            heading = unit(mix(heading,f.forward,1-exp(-dt*3)))
            let right = unit(simd_cross(heading,up))
            let center = mix(f.position,target.position,0.48)
            desired = center-heading*40+right*43+up*25; look = center
            fov = min(65,48+simd_distance(f.position,target.position)*0.11)
        } else if event == .explosion {
            let drift = explosionVelocity*eventAge*0.18
            desired = explosionCamera+drift; look = explosionOrigin+drift; fov = 48
            if eventAge>1.7 { endEvent(in:b); update(0,in:b); return }
        } else if event == .spin {
            let f = b.fighters[b.followedIndex]
            let right = unit(simd_cross(heading,up))
            desired = f.position-heading*37+right*26+up*13
            look = f.position; fov = 47
            if !f.active || eventAge>5 || (f.spin == nil && eventAge>2) {
                endEvent(in:b); update(0,in:b); return
            }
        } else if b.wreckHold>0 {
            b.wreckHold -= dt
            desired = b.cameraPosition+velocity*dt*0.6
            look = b.wreckPosition; fov = 48
            if b.wreckHold<=0 { b.selectCameraSubject(); prepareShot(in:b); b.cut = true }
        } else {
            if b.cameraIndex != 2 && !b.fighters[b.followedIndex].active {
                b.selectCameraSubject(); prepareShot(in:b); b.cut = true
            }
            let f = b.cameraSubject() ?? b.fighters.first(where:\.active) ?? b.fighters[0]
            heading = unit(mix(heading,f.forward,1-exp(-dt*2.6)))
            let right = unit(simd_cross(heading,up))*side
            let enemy = f.attackTarget.flatMap { b.fighters[$0].active ? b.fighters[$0] : nil } ?? b.fighters.filter { $0.active && $0.faction != f.faction }.min { simd_distance_squared($0.position,f.position)<simd_distance_squared($1.position,f.position) }
            let enemyAhead = enemy.map { simd_distance($0.position,f.position)<150 && simd_dot(unit($0.position-f.position),heading)>0.2 } ?? false
            let action = enemyAhead ? mix(f.position+heading*10,enemy!.position,0.35) : f.position+heading*12
            switch b.cameraIndex {
            case 0:
                desired = f.position-heading*30+right*10+up*6
                look = action; fov = 51
            case 1:
                desired = f.spin == nil ? f.historyPosition(at:b.time-0.85)+right*10+up*4 : f.position-heading*35+right*15+up*8
                look = f.spin == nil ? mix(f.position+f.velocity*0.5,action,0.25) : f.position
                fov = 56
            case 2:
                let drift = min(1,b.cameraAge/Self.atlantisWideDuration)*0.55
                let overview = b.atlantis.flatMap { $0.intact ? atlantisFrame($0,in:b,progress:drift) : nil } ?? battlefieldFrame(in:b)
                desired = overview.position; look = overview.look; fov = overview.fov
            case 3:
                let sweep = sin(min(1,b.cameraAge/shotLength) * Float.pi)*8
                desired = f.position+right*(27+sweep)-heading*10+up*7
                look = mix(f.position,action,0.25); fov = 47
            case 4:
                desired = flybyAnchor+heading*b.cameraAge*2.2
                look = f.position+heading*2; fov = 46
            default:
                let closeEnemy = enemy.flatMap { simd_distance($0.position,f.position)<140 ? $0 : nil }
                let center = closeEnemy.map { mix(f.position,$0.position,0.42) } ?? f.position
                desired = center+right*45-heading*38+up*24
                look = center
                let spacing = closeEnemy.map { simd_distance(f.position,$0.position) } ?? 20
                fov = max(46,min(65,40+spacing*0.13))
            }
        }
        let fromAtlantis = event == .atlantisDefense || (event == .atlantisCounterstrike && eventAge<2.05)
        desired = b.clearCamera(desired,insideAtlantisShield:fromAtlantis)
        if b.cut {
            hardCuts += 1
            b.cameraPosition = desired; b.cameraLook = look; velocity = .zero; lookVelocity = .zero
        } else if event == .handoff {
            // Attach this brief over-shoulder shot to the pilot's bounded motion,
            // so steering cannot leave the foreground ship outside the frame.
            b.cameraPosition = desired; b.cameraLook = look; velocity = .zero; lookVelocity = .zero
        } else {
            damp(&b.cameraPosition,velocity:&velocity,target:desired,frequency:7,dt:dt)
            if (event == .carrierArrival && carrierLaunchShot) || revealingArrival || trackingFormation {
                // The launch and reveal shots compute their aim from the framing.
                b.cameraLook = look; lookVelocity = .zero
            } else { damp(&b.cameraLook,velocity:&lookVelocity,target:look,frequency:9,dt:dt) }
        }
        b.cameraPosition = b.clearCamera(b.cameraPosition,insideAtlantisShield:fromAtlantis)
        let jitter = V3(sin(b.time*71),cos(b.time*59),sin(b.time*53))*shake*0.14
        b.camera.simdPosition = b.cameraPosition+jitter
        let cameraUp = roll == 0 ? up : simd_quatf(angle:roll,axis:unit(b.cameraLook-b.cameraPosition)).act(up)
        b.camera.look(at:SCNVector3(b.cameraLook),up:SCNVector3(cameraUp),localFront:SCNVector3(0,0,-1))
        let old = Float(b.camera.camera!.fieldOfView)
        b.camera.camera!.fieldOfView = CGFloat(b.cut || revealingArrival ? fov : old+(fov-old)*(1-exp(-dt*2)))
        b.cut = false
    }
}

extension Dogfight {
    func cameraSubject() -> Fighter? {
        if director.event == .handoff { return fighters[followedIndex].active ? fighters[followedIndex] : nil }
        guard director.event == .none || director.event == .spin else { return nil }
        return cameraIndex == 2 || !fighters[followedIndex].active ? nil : fighters[followedIndex]
    }
    func selectCameraSubject() {
        let faction: Faction? = cameraIndex == 0 ? sideFactions[0] : (cameraIndex == 1 ? sideFactions[1] : nil)
        let choices = fighters.indices.filter { fighters[$0].active && (faction == nil || fighters[$0].faction == faction) }
        let pool = choices.isEmpty ? fighters.indices.filter { fighters[$0].active } : choices
        var best = -Float.infinity
        for i in pool {
            let f = fighters[i]
            let nearest = rocks.map { simd_distance(f.position,$0.position)-$0.radius }.min() ?? 100
            let enemyDistance = fighters.filter { $0.active && $0.faction != f.faction }.map { simd_distance(f.position,$0.position) }.min() ?? 500
            let score = 45/max(12,nearest)+70/max(20,enemyDistance)+(f.hitPoints<3 ? 0.5 : 0)+(f.spin != nil ? 1.5 : 0)+director.rng.range(0,0.7)-(i == followedIndex ? 0.8 : 0)
            if score>best { followedIndex = i; best = score }
        }
    }
    func nextCamera() {
        director.begin(.none,in:self)
        cameraIndex = (cameraIndex+1)%cameraNames.count
        cameraAge = 0; cut = true; wreckHold = 0
        selectCameraSubject(); director.prepareShot(in:self)
        cameraChanged?()
    }
    func updateCamera(_ dt: Float) { director.update(dt,in:self) }
}
