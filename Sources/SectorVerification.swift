import AppKit
import Metal
import SceneKit
import simd

private func requireSector(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else { print("FAIL: \(message)"); exit(1) }
}

private func defeatSectorSide(_ side: Int, in battle: Dogfight) {
    for fighter in battle.fighters where fighter.side == side {
        fighter.state = .destroyed; fighter.node.isHidden = true
    }
}

func verifySectors(renderDirectory: URL?) {
    var rotation = SectorBackdrops(seed:2026)
    var last: SectorLandmark?
    var limits = Set<Int>()
    for _ in 0..<12 {
        var cycle = Set<SectorLandmark>()
        for _ in SectorLandmark.allCases {
            let entry = rotation.next()
            requireSector(entry.kind != last,"Consecutive sectors used the same landmark")
            cycle.insert(entry.kind); limits.insert(entry.waves); last = entry.kind
        }
        requireSector(cycle.count == SectorLandmark.allCases.count,"A landmark was skipped within a rotation")
    }
    requireSector(limits == Set(10...20),"The sector wave limit is not sampled across 10–20")

    let beforeLimit = Dogfight(seed:820,initialArrivals:false,firstAtlantisEncounter:nil,sectorWaveLimit:10)
    beforeLimit.encountersCompleted = 8
    defeatSectorSide(1,in:beforeLimit)
    beforeLimit.updateReinforcements(0)
    requireSector(beforeLimit.encountersCompleted == 9 && beforeLimit.sectorDeparture == nil && beforeLimit.fleetRequests.count == 1,
                  "A sector change interrupted a regular victory before the wave limit")
    let noWinner = Dogfight(seed:821,initialArrivals:false,firstAtlantisEncounter:nil,sectorWaveLimit:10)
    noWinner.encountersCompleted = 9
    defeatSectorSide(0,in:noWinner); defeatSectorSide(1,in:noWinner)
    noWinner.updateReinforcements(0)
    requireSector(noWinner.sectorDeparture == nil && noWinner.fleetRequests.count == 2,
                  "Mutual destruction triggered a victory departure")

    let outgoing = Dogfight(seed:822,initialFactions:[.colonial,.cylon],initialArrivals:false,
                            firstAtlantisEncounter:10...10,sectorWaveLimit:10)
    outgoing.encountersCompleted = 9
    outgoing.aceKillRecord = 11; outgoing.acesEmerged = 3; outgoing.longestEncounterStreak = 8
    outgoing.automatic = false
    defeatSectorSide(1,in:outgoing)
    let origin = outgoing.fighters[0].position
    outgoing.update(dt:1.0/60)
    requireSector(outgoing.sectorDeparture?.side == 0 && outgoing.encountersCompleted == 10,
                  "The wave limit did not send the winning squadron home")
    requireSector(outgoing.sideCount(0) == 6 && outgoing.fleetRequests.isEmpty && outgoing.atlantisAttackingSide == nil,
                  "The departing fleet lost pilots or called in another wave")
    guard let departure = outgoing.sectorDeparture else { return }
    requireSector(departure.wipeCoverage(at:outgoing.time) == 0,"The wipe hid the departing squadron immediately")
    while outgoing.time-departure.started<4 { outgoing.update(dt:1.0/30) }
    requireSector(outgoing.fighters[0].active && simd_distance(origin,outgoing.fighters[0].position)>200,
                  "The victors did not fly toward their departure lane")
    while outgoing.time-departure.started<14 && outgoing.sectorDeparture?.wipeCoverage(at:outgoing.time) != 1 {
        outgoing.update(dt:1.0/30)
    }
    requireSector(outgoing.sectorDeparture?.wipeCoverage(at:outgoing.time) == 1,"The outgoing wipe did not reach full cover")
    let next = outgoing.followingSector(backdrop:(.babylon5,16))
    requireSector(next.seed != outgoing.seed && next.rocks[0].position != outgoing.rocks[0].position && next.landmark == .babylon5,
                  "The incoming sector reused the previous layout or landmark")
    requireSector(Set(next.sideFactions).isDisjoint(with:outgoing.sideFactions),"A departing faction was sent straight into the next sector")
    requireSector(next.aceKillRecord == 11 && next.acesEmerged == 3 && next.longestEncounterStreak == 8 && next.nextAtlantisEncounter == 1,
                  "The change of sector discarded run records or the pending Atlantis siege")
    requireSector(!next.automatic && next.showingSector && next.activeCount == 0,"The new sector did not open on its landmark")
    while next.time<2 { next.update(dt:1.0/30) }
    requireSector(next.activeCount == 0 && next.carriers.allSatisfy { $0.node.isHidden },"Ships arrived during the establishing shot")
    while next.time<8 { next.update(dt:1.0/30) }
    requireSector(!next.showingSector && next.activeCount>0,"The next battle failed to start after the reveal")
    print("PASS: All landmarks rotate without repeats, victories respect the 10–20 wave limit, survivors leave before the wipe, and each new belt reveals before arrivals. Ace history and Atlantis timing carry over.")
    let yard = Dogfight(seed:823,initialArrivals:false,firstAtlantisEncounter:nil,landmark:.graveyard)
    let wrecks = yard.rocks.filter { $0.node.name == "wreck.hull" }
    requireSector(wrecks.count>8 && yard.rocks.count==245,"Fleet wrecks failed to replace asteroids as obstacles")
    requireSector(wrecks.allSatisfy { $0.radius>=32 && $0.node.simdPosition == $0.position },"Wrecks are missing their navigation bounds")
    if let renderDirectory { renderSectors(directory:renderDirectory) }
}

private func renderSectors(directory: URL) {
    try! FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
    let renderer = SCNRenderer(device:MTLCreateSystemDefaultDevice(),options:nil)
    let size = NSSize(width:1280,height:800)
    let bounds = NSRect(origin:.zero,size:size)
    func save(_ image: NSImage, as name: String) {
        let bitmap = NSBitmapImageRep(data:image.tiffRepresentation!)!
        try! bitmap.representation(using:.png,properties:[:])!.write(to:directory.appendingPathComponent(name+".png"))
    }
    for kind in SectorLandmark.allCases {
        let battle = Dogfight(seed:822,initialFactions:[.earth,.shadow],firstAtlantisEncounter:nil,landmark:kind,
                              sectorEstablishingUntil:SectorDeparture.establishingDuration)
        renderer.scene = battle.scene; renderer.pointOfView = battle.camera
        let establishing = renderer.snapshot(atTime:0,with:size,antialiasingMode:.multisampling2X)
        save(establishing,as:kind.rawValue)
        if kind == .shatteredMoon || kind == .babylon5 {
            let wipe = SectorWipeView(frame:bounds)
            wipe.style = kind == .shatteredMoon ? 0 : 1
            wipe.opening = kind == .babylon5
            wipe.coverage = 0.52
            let frame = NSImage(size:size,flipped:false) { rect in
                establishing.draw(in:rect)
                wipe.draw(rect)
                return true
            }
            save(frame,as:kind.rawValue+"-wipe")
        }
        while battle.time<4.98 { battle.update(dt:1.0/30) }
        save(renderer.snapshot(atTime:Double(battle.time),with:size,antialiasingMode:.multisampling2X),as:kind.rawValue+"-arrival")
        print("Rendered \(kind.title)")
    }
    let outgoing = Dogfight(seed:822,initialFactions:[.colonial,.cylon],initialArrivals:false,
                            firstAtlantisEncounter:nil,landmark:.shatteredMoon,sectorWaveLimit:10)
    outgoing.encountersCompleted = 9
    defeatSectorSide(1,in:outgoing)
    while outgoing.time<5 { outgoing.update(dt:1.0/30) }
    renderer.scene = outgoing.scene; renderer.pointOfView = outgoing.camera
    save(renderer.snapshot(atTime:Double(outgoing.time),with:size,antialiasingMode:.multisampling2X),as:"return-to-fleet")
}
