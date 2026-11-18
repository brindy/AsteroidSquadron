import AppKit
import Metal
import SceneKit
import simd

private func requireCockpit(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else {
        print("FAIL: \(message)")
        fflush(stdout)
        exit(1)
    }
}

// A stable pursuit for the native render review and camera regression checks.
func configureCockpitReview(_ battle: Dogfight, clearRoute: Bool = true) {
    let pilot = battle.fighters[0]
    let targetIndex = battle.fighters.firstIndex { $0.side != pilot.side }!
    let target = battle.fighters[targetIndex]
    battle.time = 60
    battle.cameraAge = 12
    battle.automatic = true
    battle.cameraIndex = 2
    battle.viewportAspect = 16.0/9.0
    let origin = V3(0,180,80)
    for fighter in battle.fighters where fighter !== pilot && fighter !== target {
        fighter.state = .destroyed
        fighter.node.isHidden = true
    }
    battle.activateFlight(pilot,position:origin,forward:V3(0,0,-1),speed:48)
    battle.activateFlight(target,position:origin+V3(0,0,-72),forward:V3(0,0,-1),speed:45)
    pilot.bank = 0.22
    pilot.applyFlightPose()
    pilot.attackTarget = targetIndex
    pilot.burstShotsLeft = 4
    pilot.cooldown = 100
    target.hitPoints = 2
    target.cooldown = 100
    if clearRoute {
        for rock in battle.rocks where sphereImpact(from:origin,to:target.position,center:rock.position,radius:rock.radius+22) != nil {
            rock.node.removeFromParentNode()
        }
        battle.rocks.removeAll { $0.node.parent == nil }
    }
    battle.followedIndex = 0
    battle.director.engagementTarget = targetIndex
    battle.director.attackCuts = 1
    battle.director.begin(.attack,in:battle)
    battle.updateCamera(0)
}

func verifyCockpit() {
    let battle = Dogfight(seed:7219,initialFactions:[.rebel,.empire],initialArrivals:false,firstAtlantisEncounter:nil)
    configureCockpitReview(battle)
    let director = battle.director
    let pilot = battle.fighters[0]
    let target = battle.fighters[pilot.attackTarget!]
    requireCockpit(director.cockpitFaction == .rebel && director.cockpitActive,"A qualifying pursuit did not select a cockpit shot")
    let expectedUp = pilot.node.simdWorldOrientation.act(V3(0,1,0))
    let expectedPosition = pilot.position+expectedUp*0.55+pilot.forward*0.65
    requireCockpit(simd_distance(battle.cameraPosition,expectedPosition)<0.001,"Cockpit camera was displaced by exterior collision clearance")
    requireCockpit(simd_dot(battle.camera.simdWorldOrientation.act(V3(0,0,-1)),pilot.forward)>0.999,"Cockpit view does not look forward from the pursuing pilot")
    requireCockpit(simd_dot(battle.camera.simdWorldOrientation.act(V3(0,1,0)),expectedUp)>0.999,"Cockpit view does not follow the pilot's bank")
    requireCockpit(battle.camera.camera!.fieldOfView == CGFloat(CockpitCameraShot.fieldOfView) && !battle.camera.camera!.wantsDepthOfField,
                   "Cockpit optics were changed by exterior camera focus")
    requireCockpit(pilot.node.categoryBitMask & battle.camera.camera!.categoryBitMask == 0,
                   "The pilot's exterior remains visible to its cockpit camera")
    requireCockpit(target.node.categoryBitMask & battle.camera.camera!.categoryBitMask != 0 && !pilot.node.isHidden,
                   "Cockpit masking hid the opponent or disabled the pilot's actual hull")
    let position = battle.cameraPosition
    pilot.position += pilot.forward*2
    target.position += pilot.forward*2
    pilot.applyFlightPose()
    target.applyFlightPose()
    battle.updateCamera(1.0/60)
    requireCockpit(simd_distance(battle.cameraPosition-position,pilot.forward*2)<0.001,"Cockpit camera lagged behind its moving pilot")
    director.eventAge = CockpitCameraShot.duration
    battle.updateCamera(0)
    requireCockpit(!director.cockpitActive && director.event == .none && battle.cameraIndex == 2,
                   "Cockpit highlight did not return to the wide battle view")
    requireCockpit(pilot.node.categoryBitMask == 1 && battle.camera.camera!.categoryBitMask & pilot.node.categoryBitMask != 0,
                   "Cockpit highlight left the pilot hidden after returning to exterior coverage")
    var childVisibilityRestored = true
    pilot.node.enumerateChildNodes { node,_ in childVisibilityRestored = childVisibilityRestored && node.categoryBitMask == 1 }
    requireCockpit(childVisibilityRestored,"Cockpit highlight failed to restore an engine or fighter submesh")

    // Preserve caller-specific visibility categories, then test manual override.
    battle.time = 100
    battle.followedIndex = 0
    director.attackCuts = 1
    let child = pilot.node.childNodes.first!
    child.categoryBitMask = 73
    director.begin(.attack,in:battle)
    requireCockpit(director.cockpitActive,"The next eligible cockpit shot did not start after cooldown")
    battle.selectCamera(3)
    requireCockpit(!director.cockpitActive && child.categoryBitMask == 73 && battle.cameraIndex == 3,
                   "Manual camera change did not restore original model visibility")
    child.categoryBitMask = 1

    battle.time = 140
    battle.followedIndex = 0
    director.attackCuts = 1
    director.begin(.attack,in:battle)
    requireCockpit(director.cockpitActive,"A clear pursuit was not eligible for cockpit coverage")
    target.position = pilot.position-pilot.forward*70
    target.applyFlightPose()
    battle.updateCamera(0)
    requireCockpit(!director.cockpitActive && director.event == .none,"Cockpit shot stayed on a target behind the pilot")
    target.position = pilot.position+pilot.forward*72
    target.applyFlightPose()

    battle.time = 180
    battle.followedIndex = 0
    director.attackCuts = 1
    director.begin(.attack,in:battle)
    battle.destroy(target)
    battle.updateCamera(0)
    requireCockpit(!director.cockpitActive && director.event == .explosion && pilot.node.categoryBitMask == 1,
                   "A cockpit kill did not cut to the explosion and restore the pursuing hull")

    let manual = Dogfight(seed:7220,initialFactions:[.colonial,.cylon],initialArrivals:false,firstAtlantisEncounter:nil)
    configureCockpitReview(manual)
    manual.director.begin(.carrierArrival,in:manual)
    requireCockpit(!manual.director.cockpitActive && manual.director.event == .carrierArrival && manual.fighters[0].node.categoryBitMask == 1,
                   "Capital arrival did not immediately take priority over cockpit coverage")
    manual.time = 100
    manual.followedIndex = 0
    manual.director.attackCuts = 1
    manual.director.begin(.attack,in:manual)
    manual.automatic = false
    manual.updateCamera(0)
    requireCockpit(!manual.director.cockpitActive && manual.director.event == .none,
                   "Disabling the automatic director did not exit cockpit mode")
    print("PASS: pursuing pilot position and bank, fixed forward view, own-hull masking and restoration, brief wide return, manual override, lost target and cockpit kill coverage.")
}

func renderCockpitReview(directory: URL) {
    try! FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
    let renderer = SCNRenderer(device:MTLCreateSystemDefaultDevice(),options:nil)
    let size = NSSize(width:1280,height:720)
    for faction in Faction.allCases {
        autoreleasepool {
            let opponent: Faction = faction == .empire ? .rebel : .empire
            let battle = Dogfight(seed:7219,initialFactions:[faction,opponent],initialArrivals:false,firstAtlantisEncounter:nil)
            configureCockpitReview(battle)
            requireCockpit(battle.director.cockpitFaction == faction,"Could not render a cockpit for \(faction.rawValue)")
            renderer.scene = battle.scene
            renderer.pointOfView = battle.camera
            let flight = renderer.snapshot(atTime:Double(battle.time),with:size,antialiasingMode:.multisampling4X)
            let canopy = CockpitOverlay(frame:NSRect(origin:.zero,size:size))
            canopy.setFaction(faction)
            let image = NSImage(size:size)
            image.lockFocus()
            flight.draw(in:NSRect(origin:.zero,size:size))
            canopy.draw(canopy.bounds)
            image.unlockFocus()
            let bitmap = NSBitmapImageRep(data:image.tiffRepresentation!)!
            try! bitmap.representation(using:.png,properties:[:])!.write(to:directory.appendingPathComponent("cockpit-\(faction.rawValue).png"))
            print("Rendered \(faction.rawValue) cockpit pursuit")
            fflush(stdout)
        }
    }
}
