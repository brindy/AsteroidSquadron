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
    shooter.encountersSurvived = 3
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
    aceCheck(shooter.isAce && shooter.tally.count == 4,"Three encounters / six kills should start with four scratches")
    aceCheck(b.acesEmerged == 1 && b.longestEncounterStreak == 3,"First Ace or survival record missing")
    shooter.encountersSurvived = 4; b.updateAce()
    aceCheck(shooter.tally.count == 5,"Ace scratch count did not advance after another encounter")
    let rival = b.fighters[1], rookie = b.fighters[3]
    rival.state = .active; rival.node.isHidden = false
    rival.encountersSurvived = 3; rival.enemyKills = 6
    b.updateAce()
    aceCheck(shooter.isAce && !rival.isAce,"A kill-count tie displaced the incumbent ace")
    aceCheck(b.acesEmerged == 1 && b.longestEncounterStreak == 4,"Tied challenger counted as a new Ace")
    rival.enemyKills = 7; b.updateAce()
    aceCheck(b.acesEmerged == 2,"New Ace leader was not counted")
    aceCheck(rival.isAce && !shooter.isAce && shooter.tally.node.parent == nil,"A higher-kill eligible enemy did not take the sole title")
    rookie.state = .active; rookie.node.isHidden = false
    rookie.encountersSurvived = 2; rookie.enemyKills = 20
    b.updateAce()
    aceCheck(rival.isAce && !rookie.isAce,"A rookie became ace without surviving three encounters")
    rookie.encountersSurvived = 3; b.updateAce()
    aceCheck(rookie.isAce && !rival.isAce,"Highest-kill qualified pilot did not take the title")
    aceCheck(b.fighters.filter(\.isAce).count == 1 && b.fighters.filter{$0.tally.count>0}.count == 1,"More than one ace marker exists")
    aceCheck(b.acesEmerged == 3,"Third distinct Ace was not counted")
    b.destroy(rookie)
    aceCheck(b.acesEmerged == 3,"Returning incumbent counted twice")
    aceCheck(rival.isAce && !rookie.isAce && rookie.tally.node.parent == nil,"A dead ace retained its title or badge")
    rival.replaceFaction(.cylon); b.updateAce()
    aceCheck(rival.enemyKills == 0 && rival.encountersSurvived == 0 && !rival.isAce && shooter.isAce,"Replacement pilot inherited a rank or blocked succession")
    b.destroy(shooter)
    aceCheck(b.fighters.allSatisfy{!$0.isAce && $0.tally.count == 0},"An ace remained after the final qualified pilot died")

    aceCheck(b.acesEmerged == 3 && b.longestEncounterStreak == 4,"Destroyed pilots erased arena records")
    // The same roster slot now contains a different pilot, eligible in its own right.
    rival.state = .active; rival.node.isHidden = false
    rival.encountersSurvived = 3; rival.enemyKills = 6; b.updateAce()
    aceCheck(b.acesEmerged == 4 && b.longestEncounterStreak == 4,"Replacement Ace inherited or lost the old pilot's identity")
    b.updateAce(); b.updateAce()
    aceCheck(b.acesEmerged == 4 && b.honouredAceGenerations.count<=b.fighters.count,"Ace history grew on ordinary updates")
    b.creditEncounter(surviving:rival.side); b.creditEncounter(surviving:rival.side)
    aceCheck(b.longestEncounterStreak == 5,"Completed encounters did not advance the survival record")
    b.destroy(rival); rival.replaceFaction(.earth); b.updateAce()
    aceCheck(b.acesEmerged == 4 && b.longestEncounterStreak == 5,"Roster replacement erased arena history")

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
    aceCheck(!victim.active && fallen.enemyKills == 6 && !fallen.isAce && fallen.tally.count == 0,"A posthumous kill promoted a dead pilot")
    print("PASS: actual lethal shots award one pilot kill; six kills and three encounters qualify one global Ace; stable ties, higher-score handoffs, death succession, generation-safe credit, no posthumous Ace, four initial scratch marks, unique historical Ace counts, and persistent encounter-survival records.")
    fflush(stdout)
}
