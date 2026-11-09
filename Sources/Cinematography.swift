import SceneKit
import simd

struct ArrivalFlight {
    let indices: [Int]
    let origin: V3
    let forward: V3
    let start: Float
}

final class CinematicDirector {
    enum Event { case none, formation, carrierArrival, carrierDeparture, spin }
    var event: Event = .none
    var eventAge: Float = 0
    var arrivalFlight: ArrivalFlight?
    var coveredFlight: Float = -100
    var shotLength: Float = 7
    var velocity = V3.zero
    var lookVelocity = V3.zero
    var heading = V3(0,0,-1)
    var side: Float = 1
    var flybyAnchor = V3.zero
    var shake: Float = 0
    var rng: Random
    var formationCuts = 0
    var carrierCuts = 0
    var dangerCuts = 0
    var normalCuts = 0
    var resumeStyle = 0
    var lastDangerTime: Float = -20
    var caption: String?
    var detail: String?
    init(seed: UInt64) { rng = Random(state:seed ^ 0xC1AE_AA77) }

    func begin(_ newEvent: Event, in b: Dogfight) {
        if event == .none && newEvent != .none { resumeStyle = (b.cameraIndex+1)%6 }
        event = newEvent; eventAge = 0; b.cut = true; b.wreckHold = 0
        switch newEvent {
        case .formation: caption = "SQUADRON INBOUND"; detail = "X-WING FORMATION / HYPERSPACE INSERTION"; formationCuts += 1
        case .carrierArrival: caption = "IMPERIAL REINFORCEMENTS"; detail = "CARRIER ARRIVAL / HANGAR DEPLOYMENT"; carrierCuts += 1
        case .carrierDeparture: caption = "JUMP TO HYPERSPACE"; detail = "CAPITAL SHIP DEPARTURE"
        case .spin: caption = "LOSS OF CONTROL"; detail = "ASTEROID STRIKE / RECOVERY TRACKING"; dangerCuts += 1
        case .none: caption = nil; detail = nil
        }
        b.cameraChanged?()
    }
    func requestCarrierArrival(in b: Dogfight) { if b.automatic { begin(.carrierArrival,in:b) } }
    func requestCarrierDeparture(in b: Dogfight) { if b.automatic { begin(.carrierDeparture,in:b) } }
    func requestSpin(_ index: Int, in b: Dogfight) {
        guard b.automatic, event == .none, b.time-lastDangerTime>8, b.cameraAge>2 else { return }
        lastDangerTime = b.time; b.followedIndex = index; begin(.spin,in:b)
    }
    func endEvent(in b: Dogfight, follow index: Int? = nil) {
        begin(.none,in:b)
        b.cameraIndex = resumeStyle; b.cameraAge = 0
        resumeStyle = (resumeStyle+1)%6
        if let index, b.fighters[index].active { b.followedIndex = index } else { b.selectCameraSubject() }
        prepareShot(in:b); b.cameraChanged?()
    }
    func prepareShot(in b: Dogfight) {
        shotLength = b.cameraIndex == 4 ? 4.8 : (b.cameraIndex == 2 ? 5.5 : rng.range(6.5,9.5))
        if let f = b.cameraSubject() {
            heading = f.forward
            let right = unit(simd_cross(heading,V3(0,1,0)))
            flybyAnchor = b.path(f,b.time+1.4)+right*side*22+V3(0,7,0)
        }
        velocity = .zero; lookVelocity = .zero; normalCuts += 1
    }
    func damp(_ value: inout V3, velocity: inout V3, target: V3, frequency: Float, dt: Float) {
        let offset = value-target, e = exp(-frequency*dt)
        let temp = (velocity+offset*frequency)*dt
        velocity = (velocity-temp*frequency)*e
        value = target+(offset+temp)*e
    }
    func update(_ dt: Float, in b: Dogfight) {
        eventAge += dt; shake *= exp(-dt*8)
        if !b.automatic && event != .none { begin(.none,in:b) }
        if b.automatic, let flight = arrivalFlight, flight.start>coveredFlight, b.time-flight.start<1.1 {
            coveredFlight = flight.start; begin(.formation,in:b)
        }
        if event == .none && b.automatic && b.cameraAge>shotLength { b.nextCamera() }
        let up = V3(0,1,0)
        var desired = b.cameraPosition, look = b.cameraLook
        var fov: Float = 51
        if event == .formation, let flight = arrivalFlight {
            let age = b.time-flight.start
            let right = unit(simd_cross(flight.forward,up))
            let advance = max(0,min(2.5,age-1.25))*28
            let anchor = flight.origin+flight.forward*advance
            let pan = min(1,max(0,(age-3.1)/1.8))
            desired = anchor+right*(28+pan*70)+up*(32+pan*3)+flight.forward*(95-pan*115)
            look = anchor-flight.forward*14; fov = 49
            if age>5.4 { endEvent(in:b,follow:flight.indices.first); update(0,in:b); return }
        } else if event == .carrierArrival || event == .carrierDeparture, let ship = b.carrier {
            let age = b.time-ship.start, right = unit(simd_cross(ship.forward,up))
            let anchor = ship.station(age)
            if event == .carrierArrival {
                let dolly = min(1,max(0,(age-1.4)/2.7))
                desired = anchor+right*(220-dolly*65)+up*(85-dolly*123)+ship.forward*(180-dolly*45)
                look = anchor+ship.forward*(dolly*22)-up*(dolly*11); fov = 50
                if age>6.4 { endEvent(in:b,follow:ship.squadron.first); update(0,in:b); return }
            } else {
                desired = anchor+right*310+up*100+ship.forward*220
                look = anchor+ship.forward*min(190,max(0,age-10)*115); fov = 51
                if eventAge>2 { endEvent(in:b); update(0,in:b); return }
            }
        } else if event == .carrierArrival || event == .carrierDeparture {
            endEvent(in:b); update(0,in:b); return
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
                desired = f.spin == nil ? b.path(f,b.time-0.95)+right*10+up*4 : f.position-heading*35+right*15+up*8
                look = f.spin == nil ? mix(b.path(f,b.time+0.6),action,0.25) : f.position
                fov = 56
            case 2:
                let a = b.time*0.026
                desired = b.arenaRotation.act(V3(sin(a)*310,125,cos(a)*310))
                let live = b.fighters.filter(\.active)
                look = live.isEmpty ? .zero : live.reduce(V3.zero) { $0+$1.position } / Float(live.count)
                // Returning ships may still be far away; keep establishing shots in the arena.
                if simd_length(look)>230 { look = unit(look)*100 }
                fov = 49
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
        desired = b.clearCamera(desired)
        if b.cut {
            b.cameraPosition = desired; b.cameraLook = look; velocity = .zero; lookVelocity = .zero
        } else {
            damp(&b.cameraPosition,velocity:&velocity,target:desired,frequency:7,dt:dt)
            damp(&b.cameraLook,velocity:&lookVelocity,target:look,frequency:9,dt:dt)
        }
        b.cameraPosition = b.clearCamera(b.cameraPosition)
        let jitter = V3(sin(b.time*71),cos(b.time*59),sin(b.time*53))*shake*0.14
        b.camera.simdPosition = b.cameraPosition+jitter
        b.camera.look(at:SCNVector3(b.cameraLook),up:SCNVector3(0,1,0),localFront:SCNVector3(0,0,-1))
        let old = Float(b.camera.camera!.fieldOfView)
        b.camera.camera!.fieldOfView = CGFloat(b.cut ? fov : old+(fov-old)*(1-exp(-dt*2)))
        b.cut = false
    }
}

extension Dogfight {
    func cameraSubject() -> Fighter? {
        guard director.event == .none || director.event == .spin else { return nil }
        return cameraIndex == 2 || !fighters[followedIndex].active ? nil : fighters[followedIndex]
    }
    func selectCameraSubject() {
        let faction: Faction? = cameraIndex == 0 ? .rebel : (cameraIndex == 1 ? .empire : nil)
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
