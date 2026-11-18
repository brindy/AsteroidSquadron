import SceneKit
import simd

// The camera rides in the pilot's frame. Only that fighter's exterior is
// excluded from this camera, leaving its physical hull and weapons intact.
final class CockpitCameraShot {
    static let duration: Float = 3.4
    static let fieldOfView: Float = 66
    private static let exteriorCategory = 1 << 29

    let pilot: Fighter
    private let pilotGeneration: Int
    private let targetIndex: Int
    private let targetGeneration: Int
    private let savedNodes: [(node: SCNNode, mask: Int)]
    private let cameraMask: Int
    private let nearPlane: Double
    private let depthOfField: Bool

    init?(in battle: Dogfight, pilot index: Int, target targetIndex: Int) {
        guard battle.fighters.indices.contains(index), battle.fighters.indices.contains(targetIndex) else { return nil }
        let pilot = battle.fighters[index]
        let target = battle.fighters[targetIndex]
        guard pilot.active, target.active, pilot.side != target.side,
              pilot.spin == nil, pilot.attackTarget == targetIndex, pilot.burstShotsLeft > 0,
              battle.time >= pilot.breakUntil, battle.time >= pilot.entryTime + pilot.formationHold,
              simd_distance(pilot.position,target.position) > 28,
              simd_distance(pilot.position,target.position) < 145,
              simd_dot(unit(target.position-pilot.position),pilot.forward) > 0.95,
              let camera = battle.camera.camera else { return nil }

        self.pilot = pilot
        pilotGeneration = pilot.generation
        self.targetIndex = targetIndex
        targetGeneration = target.generation
        cameraMask = camera.categoryBitMask
        nearPlane = camera.zNear
        depthOfField = camera.wantsDepthOfField
        var nodes = [(pilot.node,pilot.node.categoryBitMask)]
        pilot.node.enumerateChildNodes { node,_ in nodes.append((node,node.categoryBitMask)) }
        savedNodes = nodes

        guard frame(in:battle) != nil else { return nil }
        for entry in savedNodes { entry.node.categoryBitMask = Self.exteriorCategory }
        camera.categoryBitMask = cameraMask & ~Self.exteriorCategory
        camera.zNear = 0.12
        camera.wantsDepthOfField = false
    }

    func frame(in battle: Dogfight) -> (position: V3, look: V3, up: V3)? {
        let target = battle.fighters[targetIndex]
        guard pilot.active, pilot.spin == nil, pilot.generation == pilotGeneration,
              target.active, target.generation == targetGeneration,
              pilot.attackTarget == targetIndex, battle.time >= pilot.breakUntil else { return nil }
        let orientation = pilot.node.simdWorldOrientation
        let forward = unit(orientation.act(V3(0,0,-1)))
        let right = unit(orientation.act(V3(1,0,0)))
        let up = unit(orientation.act(V3(0,1,0)))
        let position = pilot.position + up*0.55 + forward*0.65
        let relative = target.position-position
        let depth = simd_dot(relative,forward)
        let tangent = tan(Self.fieldOfView * Float.pi/360)
        // End the shot before the target slips behind the canopy at either aspect.
        guard depth > 20, depth < 205,
              abs(simd_dot(relative,right)) < depth*tangent*max(0.25,battle.viewportAspect)*0.72,
              abs(simd_dot(relative,up)) < depth*tangent*0.64 else { return nil }
        guard !battle.rocks.contains(where: {
            sphereImpact(from:position,to:target.position,center:$0.position,radius:$0.radius+1) != nil
        }) else { return nil }
        return (position,position+forward*150,up)
    }

    func restore(in battle: Dogfight) {
        for entry in savedNodes { entry.node.categoryBitMask = entry.mask }
        battle.camera.camera?.categoryBitMask = cameraMask
        battle.camera.camera?.zNear = nearPlane
        battle.camera.camera?.wantsDepthOfField = depthOfField
    }
}
