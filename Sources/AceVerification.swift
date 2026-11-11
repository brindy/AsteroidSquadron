import SceneKit
import simd

private func aceCheck(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() { print("FAIL: \(message)"); fflush(stdout); exit(1) }
}

private func aceCombatFixture(seed: UInt64) -> Dogfight {
    let b = Dogfight(seed:seed,initialFactions:[.rebel,.empire],initialArrivals:false)
    b.automatic = false; b.rocks.removeAll()
    for (i,f) in b.fighters.enumerated() where i != 0 && i != 6 { f.state = .destroyed; f.node.isHidden = true }
    b.activateFlight(b.fighters[0],position:V3(0,250,0),forward:V3(0,0,-1),speed:0)
    b.activateFlight(b.fighters[6],position:V3(0,250,-100),forward:V3(0,0,-1),speed:0)
    return b
}

func verifyAceLeadership() {
    let b = aceCombatFixture(seed:1616), shooter = b.fighters[0], target = b.fighters[6]
    aceCheck(b.acesEmerged == 0 && b.longestEncounterStreak == 0,"New arena inherited Ace history")
    for _ in 0..<3 { b.creditEncounter(survivingSides:[shooter.side],replenish:false) }
    aceCheck(b.fire(from:0,to:6),"Ace scoring fixture could not fire")
    b.updateLasers(0.4)
    aceCheck(target.active && target.hitPoints<6 && shooter.enemyKills == 0,"Nonlethal hits counted as kills")
    b.destroy(target)
    aceCheck(shooter.enemyKills == 0,"Environmental destruction awarded a weapon kill")
    for kill in 1...6 {
        target.replaceFaction(.empire); target.state = .active; target.node.isHidden = false
        b.activateFlight(target,position:V3(0,250,-100),forward:V3(0,0,-1),speed:0)
        target.hitPoints = 1
        aceCheck(b.fire(from:0,to:6),"Pilot could not fire a scoring volley")
        b.updateLasers(0.4); b.updateLasers(2)
        aceCheck(!target.active && shooter.enemyKills == kill,"Paired cannon volley lost or double-counted a kill")
        aceCheck(shooter.isAce == (kill == 6),"Ace ignored the six-kill threshold")
    }
    aceCheck(shooter.isAce && shooter.aceBadge.visible,"The first qualifying Ace has no badge")
    aceCheck(b.aceHUDStatus.contains("KILLS 6") && b.aceHUDStatus.contains("ENCOUNTERS SURVIVED 3"),
             "The current Ace HUD omitted the active pilot's kills or survival count")
    aceCheck(b.acesEmerged == 1 && b.longestEncounterStreak == 3 && b.aceKillRecord == 6,"First Ace or record missing")
    b.creditEncounter(survivingSides:[shooter.side],replenish:false)
    let rival = b.fighters[1], rookie = b.fighters[3]
    rival.state = .active; rival.node.isHidden = false
    rival.encountersSurvived = 3; rival.enemyKills = 6
    b.updateAce()
    aceCheck(shooter.isAce && !rival.isAce && b.acesEmerged == 1,"A tied challenger displaced the Ace")
    rival.enemyKills = 7; b.updateAce()
    aceCheck(rival.isAce && !shooter.aceBadge.visible && b.acesEmerged == 2,"A new record did not transfer the badge")
    rookie.state = .active; rookie.node.isHidden = false
    rookie.encountersSurvived = 2; rookie.enemyKills = 20
    b.updateAce()
    aceCheck(rival.isAce && !rookie.isAce,"A rookie became Ace before surviving three encounters")
    rookie.encountersSurvived = 3; b.updateAce()
    aceCheck(rookie.isAce && b.aceKillRecord == 20 && b.acesEmerged == 3,"An eligible record breaker did not become Ace")
    aceCheck(b.fighters.filter(\.isAce).count == 1 && b.fighters.filter{$0.aceBadge.visible}.count == 1,"More than one Ace badge exists")
    b.destroy(rookie)
    aceCheck(b.acePilot == nil && b.aceKillRecord == 20 && !rookie.aceBadge.visible,"Death erased the previous Ace record or left its badge")
    aceCheck(b.aceHUDStatus.contains("KILLS —") && b.aceHUDStatus.contains("RECORD TO BEAT 20"),
             "The vacant Ace HUD confused the previous record with a current kill count")
    rival.enemyKills = 20; b.updateAce()
    aceCheck(b.acePilot == nil,"Tying the previous Ace record filled a vacant title")
    rival.enemyKills = 21; b.updateAce()
    aceCheck(rival.isAce && b.aceKillRecord == 21 && b.acesEmerged == 3,"A returning record breaker was double-counted or rejected")
    b.destroy(rival)
    rival.replaceFaction(.empire); rival.state = .active; rival.node.isHidden = false
    b.updateAce()
    aceCheck(rival.enemyKills == 0 && rival.encountersSurvived == 0 && !rival.isAce,"A replacement inherited the previous pilot's record")
    rival.encountersSurvived = 3; rival.enemyKills = 22; b.updateAce()
    aceCheck(rival.isAce && b.acesEmerged == 4,"A distinct replacement Ace was not counted")
    rival.enemyKills = 23; b.updateAce()
    aceCheck(b.aceKillRecord == 23,"An incumbent's kills did not advance the record")
    aceCheck(b.aceHUDStatus.contains("KILLS 23"),"The current Ace HUD kept a stale kill count")
    b.creditEncounter(survivingSides:[rival.side],replenish:false)
    b.creditEncounter(survivingSides:[rival.side],replenish:false)
    b.destroy(rival)
    aceCheck(b.acePilot == nil && b.acesEmerged == 4 && b.longestEncounterStreak == 5 && b.aceKillRecord == 23,"Losing a pilot erased an arena record")

    let stale = aceCombatFixture(seed:1617), oldShooter = stale.fighters[0], staleVictim = stale.fighters[6]
    oldShooter.encountersSurvived = 3; oldShooter.enemyKills = 5; staleVictim.hitPoints = 1
    aceCheck(stale.fire(from:0,to:6),"Stale-shot fixture could not fire")
    oldShooter.replaceFaction(.rebel); oldShooter.state = .active; oldShooter.node.isHidden = false
    stale.activateFlight(oldShooter,position:V3(0,250,0),forward:V3(0,0,-1),speed:0)
    stale.updateLasers(0.4)
    aceCheck(!staleVictim.active && oldShooter.enemyKills == 0 && !oldShooter.isAce,"An old shot credited a replacement pilot")

    let posthumous = aceCombatFixture(seed:1618), fallen = posthumous.fighters[0], victim = posthumous.fighters[6]
    fallen.encountersSurvived = 3; fallen.enemyKills = 5; victim.hitPoints = 1
    aceCheck(posthumous.fire(from:0,to:6),"Posthumous-shot fixture could not fire")
    posthumous.destroy(fallen); posthumous.updateLasers(0.4)
    aceCheck(!victim.active && fallen.enemyKills == 6 && !fallen.isAce && !fallen.aceBadge.visible,"A posthumous kill promoted a dead pilot")
    print("PASS: actual lethal shots award one pilot kill; six kills and three encounters qualify one global Ace; strict record-breaking succession after death, a single star, generation-safe credit, no posthumous Ace, unique historical Ace counts, and persistent survival records.")
    fflush(stdout)
}
