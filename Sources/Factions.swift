import AppKit
import SceneKit

enum Faction: String, CaseIterable, Hashable {
    case rebel, empire, colonial, cylon

    var title: String {
        switch self {
        case .rebel: return "REBEL ALLIANCE"
        case .empire: return "GALACTIC EMPIRE"
        case .colonial: return "COLONIAL FLEET"
        case .cylon: return "CYLON FLEET"
        }
    }
    var fighterName: String {
        switch self {
        case .rebel: return "X-WINGS"
        case .empire: return "TIES"
        case .colonial: return "VIPERS"
        case .cylon: return "RAIDERS"
        }
    }
    var carrierName: String {
        switch self {
        case .rebel: return "REBEL SQUADRON"
        case .empire: return "IMPERIAL CARRIER"
        case .colonial: return "BATTLESTAR GALACTICA"
        case .cylon: return "CYLON BASESTAR"
        }
    }
    var usesBlinkFTL: Bool { self == .colonial || self == .cylon }
    var usesCarrier: Bool { self != .rebel }
    var projectileSpeed: Float { usesBlinkFTL ? 430 : 340 }
    var gunOffset: Float {
        switch self { case .rebel: return 3.7; case .empire: return 0.5; case .colonial: return 3; case .cylon: return 2.5 }
    }
    func fighterModel() -> SCNNode {
        switch self { case .rebel: return xWing(); case .empire: return tieFighter(); case .colonial: return colonialViper(); case .cylon: return cylonRaider() }
    }
    func capitalModel() -> SCNNode {
        switch self { case .colonial: return battlestarGalactica(); case .cylon: return cylonBasestar(); default: return imperialCarrier() }
    }
    func shotMaterial() -> SCNMaterial {
        switch self {
        case .rebel: return material(color(1,0.13,0.045),emission:color(3,0.12,0.025))
        case .empire: return material(color(0.2,1,0.2),emission:color(0.15,3,0.15))
        case .colonial: return material(color(1,0.82,0.52),emission:color(3,2.1,0.8))
        case .cylon: return material(color(1,0.24,0.07),emission:color(3,0.45,0.055))
        }
    }
}

struct FleetReplacement {
    let side: Int
    let defeated: Faction
    let incoming: Faction
    let time: Float
}

struct FleetRequest {
    let side: Int
    var countdown: Float
}

func requestedFactions() -> [Faction]? {
    guard let i = CommandLine.arguments.firstIndex(of:"--factions"), i+1<CommandLine.arguments.count else { return nil }
    let names = CommandLine.arguments[i+1].split(separator:",").compactMap { Faction(rawValue:String($0)) }
    return names.count == 2 && names[0] != names[1] ? names : nil
}
