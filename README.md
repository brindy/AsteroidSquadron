# Asteroid Squadron

A standalone macOS app: an endless crossover dogfight between Star Wars, the reimagined Battlestar Galactica, Babylon 5 and Stargate in a procedural 3D asteroid belt. An action-directed camera system, faction-specific weapons, turbulent explosions that cool into smoke, formation arrivals, capital-ship hangar launches, drifting volumetric gas, a distant planet, and a quiet cinematic overlay. All ship meshes, geometry, density fields, and textures are generated locally. No dependencies, downloads, network access, or audio.

Every launch chooses a fresh random seed for asteroid placement and shapes, cloud positions and density, planet placement, flight orientation, and the initial pair of opposing factions. **R** generates another arena and faction pairing without interrupting keep-awake. For a reproducible arena, launch with `--seed 42` (any unsigned 64-bit decimal integer).

Each side starts with six fighters. An encounter ends when a faction is defeated or when the surviving squadrons destroy Atlantis. Squadrons that have survived at least **two encounters** receive replacement pilots for their lost ships before the next enemy faction arrives. The survivors keep their positions, damage, pilot identities and records. New pilots start with no kills or encounters. A faction is still randomly replaced only when its **last ship is destroyed**, excluding the surviving opponent and the just-defeated faction. There are always two distinct factions.

| Faction | Fighters | Arrival |
| --- | --- | --- |
| Rebel Alliance | X-wings | Jump together in a V formation, then split toward separate targets |
| Galactic Empire | TIE fighters | Launch from an Imperial capital ship that arrives and departs via hyperspace |
| Colonial Fleet | Viper Mk II | Launch from Galactica's two flight pods |
| Cylon Fleet | Reimagined Cylon Raiders | Launch from a modern, six-armed basestar |
| Earth Alliance | Aurora Starfuries | Exit a shared, huge blue-black swirling jump point, which opens before the squadron and closes afterwards |
| The Shadows | Organic Shadow fighters | Launch from a giant, spined Shadow capital ship that emerges through a blue-black jump point |
| Tau’ri | F-302s | Launch from the Daedalus-class carrier’s twin hangars |
| Goa’uld | Death Gliders | Launch from the pyramid mothership’s ventral bays |
| Wraith | Darts | Launch from the Wraith hive ship |

A pilot becomes **Ace** after surviving at least **three encounters**, scoring at least **six personal enemy kills**, and beating the arena’s previous Ace kill count. The record survives the pilot’s death, so the title can remain vacant. The current Ace has a gold star above the hull and a dedicated HUD line with their current kill count and encounters survived. A vacant title keeps that line visible and labels the previous record separately. The HUD also records the number of distinct Aces and the longest survival streak. Kill credit follows the pilot who fired the lethal projectile, including its roster generation. Starting a new arena resets the records.

Fighters with no active enemy plan long patrol legs through the belt and around its outer edge. They use the same bounded steering and asteroid avoidance as in combat, and resume pursuit when the next enemy squadron arrives.

**Atlantis** can arrive after three completed encounters. Both factions divert to the city outside the belt and suspend their fight while they attack it. Close passes hit the shield first, then the city's towers and piers. Atlantis fires 30 Ancient drones in a rapid stream, then pauses for ten seconds before it can fire again. Each drone rises from the central spire and follows the same curve toward the chosen fighter. New squadrons can join an ongoing siege while the city keeps its damage. The camera cuts between short wide views, attack runs, and views of the incoming fighters from the central tower and outer piers. It also covers shield collapse and destruction. Survivors return to the belt and patrol briefly before combat resumes. Atlantis becomes eligible to return after at least ten more completed encounters. To see the scenario after the initial deployments, launch with `--factions tauri,wraith --atlantis`.

**Galactica and the basestar use BSG-style blink FTL:** a short blue-white displacement flash, the complete ship appearing at a fixed location, and another flash as it vanishes. The models neither stretch nor travel along a hyperspace trail. All capital ships are six times their original size, with hangars, jump effects and camera framing scaled accordingly. They depart about 0.18 seconds after the final fighter launches, within the same uninterrupted cinematic shot. Capital arrivals are staged so the camera can cover each deployment; simultaneous capital ships keep separate arrival locations clear of the planet.

The Babylon jump windows have opaque black interiors and animated blue spiral eddies. World-space clipping on the travelling hulls hides all geometry still in hyperspace, including from side and rear cameras; it reverses on capital departure. Starfury clipping is released once the complete fighter clears the aperture, so later manoeuvres remain unaffected. Starfuries emerge in staggered lanes without individual warp trails; their window closes as the group flies away. The Shadow capital physically emerges through its aperture, deploys its fighters, and immediately moves into a new departure aperture in the same camera scene. Both jump windows are removed after the visit. A wide reveal shows the complete opening, followed by a close fighter launch and pullback; the Shadow shot reserves space for the departure window and uses a lateral angle to keep its black core from hiding the capital. Both deployments retain the nearest-existing-fighter handoff. All nine factions participate in the same random replacement pool.

The automatic director prioritizes a wide view of the connected dogfight, including wingmen around its edges. It holds that view instead of cycling cameras on a timer, selects clearer sight lines through the asteroids, and avoids foreground boulders dominating the frame. Short highlights cover critical attack runs against weakened targets, explosions, impending asteroid strikes, and loss of control, then return to at least ten seconds of wide coverage. An attack shot follows its target into the explosion without another cut. Arrivals retain their dedicated sequences. All six camera styles remain available manually; disabling Auto preserves manual control.

Capital deployments start with a wide arrival reveal, then cut close to the first fighter. As the squadron emerges, the camera physically pulls back on a fixed lens, shifts its attention smoothly to the fighter group, and reveals the full capital ship behind it. Framing uses the actual hull silhouette and current window aspect ratio. The same continuous shot follows the group through the final launch and the capital ship's immediate departure; it does not chase the capital ship into hyperspace. After departure, a brief over-shoulder shot uses the nearest surviving fighter that was already present at the capital ship's arrival, with its camera trained on the incoming squadron. It keeps that pilot in the foreground for 3.5 seconds before returning wide. A destroyed anchor is replaced by another existing survivor; if none remain, the director returns straight to the battlefield view. New roster generations cannot be mistaken for an existing pilot. The battlefield view selects a busy group of live ships and fits its framing to their positions; separated inbound squadrons get their own readable composition instead of an empty view of the belt.

The background planet is generated entirely from seeded, seamless 3D noise: irregular continents and coastlines, ocean depths and turquoise shelves, forests, deserts, mountain relief, polar ice, and sunlight glint on water. Each seed chooses a temperate ocean world, a sand-and-white-salt desert, an icy world, or a rusty mineral world. Desert basins replace water with sand, and pale salt/chalk replaces green vegetation; frozen and rusty palettes have their own terrain colours, cloud amounts and atmospheric tints. Press **B** or choose Flight → Next Planet Biome to cycle these without resetting the battle. A separate weather layer forms curling cloud fronts and casts soft shadows. A twelve-sample atmospheric shell produces a blue limb and daylight haze with a night-side falloff. Surface rotation and differential cloud winds evolve slowly. Planet placement ensures the asteroid belt sees a lit hemisphere and a day/night edge. No texture images are downloaded or stored.

The starfield is an **infinitely distant procedural skybox**, generated as a 4096×2048 spherical texture and projected by SceneKit. A dedicated seeded stream creates approximately 38,000 stars with varied brightness and colour, an irregular Milky Way band, layered dark dust lanes, luminous arm clouds and an inclined spiral galaxy. It contains no local star particles: moving thousands of metres does not move the stars. New arena seeds choose another galaxy orientation and pattern. The sky is generated once per arena rather than animated or ray-marched every frame.

Flight runs at a fixed 60 Hz independently of the display frame rate. Ships integrate velocity with bounded acceleration and turn rates, bank into turns, lead moving targets, and steer around predicted asteroid hazards. Pilot steering filters small sensor and intercept corrections and ignores sub-degree hunting. Banking uses a deadband and a bounded roll rate; urgent asteroid and traffic avoidance receives a faster response. This reduces constant little shakes while retaining deliberate turns and danger responses. Chase cameras follow recorded flight history. Formation breakaways and spin recovery retain momentum rather than snapping onto a prescribed path.

Starfuries additionally use short, controlled inertial manoeuvres: brake to a slow drift, rotate the hull toward the firing solution using visible control jets, fire from their fixed cannons, then accelerate along the new nose. Nose rotation and translational velocity are independent, with the same acceleration and turn limits as ordinary flight. A cooldown prevents incessant pirouettes. Asteroid and traffic avoidance follow the actual velocity vector and override the manoeuvre when the drift path is threatened. Formation departures, pursuit breaks and uncontrolled spins retain priority.

Pilots also predict nearby fighters' closest approach, keep space around wingmen, choose opposing passing lanes, and brake when catching a slower ship ahead. This applies to friends and enemies. If avoidance fails, swept hull collisions exchange momentum and damage both ships: light impacts cause a tumble, while severe impacts or hits on an already damaged hull can cause destruction. A sustained contact counts as one impact, and physical separation prevents ships remaining overlapped.

Pilots retain their initial formation assignments through the attack split, then pursue an enemy for a randomized **5–10 seconds**. If that enemy survives, the pilot cancels its burst, breaks away for 1.8–2.9 seconds with a seeded change of heading, altitude and speed, and selects the next-nearest alternative enemy. If only one enemy remains, it manoeuvres before returning to that opponent. A fresh 5–10 second window starts after the break. The clock pauses during travel to the arena and loss of control; all movement still uses bounded acceleration, turn rates and collision avoidance. Staggered deadlines and different escape planes prevent equal-speed fighters settling into an endless pursuit ring. They fire five-volley bursts with short recovery intervals; a wider continuing-burst window lets forward fire track across a target without swiveling the guns. Friendly spacing remains generous, while enemy avoidance permits closer attack passes.

Each fighter has gun-muzzle anchors on its actual model. X-wings alternate diagonal cannon pairs; TIEs use their paired chin guns, Vipers their wing cannons, and Raiders their forward guns. Starfuries alternate diagonal pairs of arm cannons, and Shadow fighters have paired forward emitters. Shots leave those muzzles parallel to the ship's nose, inherit its momentum, and never home or swivel toward a target. Swept projectile collisions test fighter hit volumes and intervening asteroids; an evading ship can make a volley miss.

Actual swept asteroid impacts make a ship ricochet into an uncontrolled tumble, then either level out and rejoin the battle or explode. A second collision during the tumble is fatal. The camera can follow both the strike and the recovery. Explosions use a short light flash, a ray-marched turbulent fuel cloud that cools from white/orange fire to dark smoke, metal fragments with inherited momentum, and small fading sparks.

The gas clouds use ray marching through three-dimensional procedural noise inside ellipsoidal volumes. They have depth and parallax as cameras and ships pass around them. Nine volumes with twenty density samples per ray keep the effect bounded; default rendering remains 30 fps.

## Download

See [GitHub Releases](https://github.com/brindy/AsteroidSquadron/releases) for published Mac builds. Use the Apple Silicon DMG, drag **Asteroid Squadron** into **Applications**, then launch it. Release downloads require an Apple Silicon Mac running macOS 13 or newer. The release script signs with Developer ID, notarizes and staples the app and DMG, and publishes a ZIP alternative and SHA-256 checksums. Building, signing and notarization run locally; GitHub hosts the source and releases.

Maintainers: see [the release guide](docs/RELEASING.md) for Keychain setup and the one-command release workflow.

## Run

Double-click **Start Dogfight.command**, or open **build/Asteroid Squadron.app** after building. The launcher builds the app if needed; building requires full Xcode 26 or newer, including its command-line tools. The built app requires an Apple Silicon Mac running macOS 13 or newer. Builds and release packages contain only the arm64 architecture. Version numbers come from `VERSION` and `BUILD_NUMBER`.

```sh
./scripts/build.sh
./"Start Dogfight.command"
# Optional:
./"Start Dogfight.command" --fullscreen
# Start with the two BSG fleets (subsequent defeated factions still change randomly):
./"Start Dogfight.command" --factions colonial,cylon
# Start with the Babylon 5 factions:
./"Start Dogfight.command" --factions earth,shadow
# Other valid faction names: rebel, empire
```

Quit an already-running instance before using startup arguments. The starting pair must contain two distinct factions.

The app starts in a normal, resizable window, so agents can continue to use the desktop. Full screen is optional. Default rendering is 30 fps with 2× antialiasing to leave resources for agents; J toggles 60 fps / 4× antialiasing.

**Drag the scene to move the window. Double-click it to fill the available desktop, then double-click again to restore its previous size.** This keeps the app windowed, with the normal menu bar and Dock; it does not create a full-screen Space. Trackpad smart zoom and Flight → Fill / Restore Window do the same. **F** is the separate true-full-screen control.

## Keep awake

On launch, the app starts `/usr/bin/caffeinate -d -i -w <app-pid>`. This prevents **idle display sleep and idle system sleep**. It continues while flight is paused, minimized, or hidden. The cyan indicator shows whether the child process is running. **K** toggles it.

**Closing the window or quitting the app stops its caffeinate process.** The `-w` process binding also makes caffeinate release its assertions if the app crashes. This app never changes system power preferences and does not interfere with any separate caffeinate process you already have running. It does not override deliberate sleep, lid closure, lock policies, or a manual screen lock.

## Controls

| Key | Action |
| --- | --- |
| C / N / right arrow | Next camera |
| A | Cinematic automatic director on/off |
| F | Toggle full screen |
| Escape | Leave full screen |
| Space / P | Pause or resume flight (keeps awake) |
| H / U | Hide or show overlay |
| K | Toggle keep awake |
| J | Toggle 30 / 60 fps |
| R | Generate a fresh random arena |
| B | Cycle planet biomes without resetting the battle |
| ? | Help |
| ⌘Q | Quit and release this app's keep-awake assertions |

The overlay dims after nine seconds without mouse movement; move the pointer to restore it. Window size and position are remembered.

## Verification

```sh
./scripts/build.sh
"build/Asteroid Squadron.app/Contents/MacOS/AsteroidSquadron" --verify-simulation
"build/Asteroid Squadron.app/Contents/MacOS/AsteroidSquadron" --verify-veterans
"build/Asteroid Squadron.app/Contents/MacOS/AsteroidSquadron" --render-veteran-review build/veteran-review
"build/Asteroid Squadron.app/Contents/MacOS/AsteroidSquadron" --verify-babylon
"build/Asteroid Squadron.app/Contents/MacOS/AsteroidSquadron" --render-babylon-review build/babylon-review
"build/Asteroid Squadron.app/Contents/MacOS/AsteroidSquadron" --verify-pursuit
"build/Asteroid Squadron.app/Contents/MacOS/AsteroidSquadron" --verify-stargate
"build/Asteroid Squadron.app/Contents/MacOS/AsteroidSquadron" --verify-stargate --render-stargate-review build/stargate-review
"build/Asteroid Squadron.app/Contents/MacOS/AsteroidSquadron" --render-review build/review --seed 42
"build/Asteroid Squadron.app/Contents/MacOS/AsteroidSquadron" --render-planet-review build/planet-review
"build/Asteroid Squadron.app/Contents/MacOS/AsteroidSquadron" --combat-benchmark
open "build/Asteroid Squadron.app" --args --smoke-test /tmp/asteroid-squadron.png
```

The Babylon check renders both new hulls against an isolated black backdrop from front, side and rear, on both sides of a rotated, offset jump plane. It verifies that geometry still in hyperspace is invisible, hulls are partially clipped while crossing, and fully emerged hulls remain complete. It also covers jump-point-before-ship timing, six-craft deployment, forward muzzles, complete window cleanup, uninterrupted departure/handoff, and a Starfury drifting, pivoting, firing and burning onto a new heading with bounded movement and flight-path hazard overrides. The Babylon render review produces jump-window, emergence, close-launch, squadron, departure and handoff frames plus three views of each new procedural model.

The veteran check covers the two-encounter top-up threshold, preservation of living pilots and their damage, arrival ordering before the next opponent, exclusive Ace leadership, three-encounter/six-kill eligibility, lethal-shot attribution, strict record-breaking succession, newcomer and generation resets, mutual destruction, a world-up Ace star, and suppression of tiny alternating steering inputs. It also renders the same sky from cameras 16,000 metres apart to verify zero translation parallax, and checks seeded galaxy reproducibility. The veteran render review saves the Ace star, a banked Ace, galaxy views and the complete sky panorama.

The simulation check covers post-departure handoffs, nearest-existing-pilot selection, squadron aim, foreground framing, survivor/generation fallbacks and manual-camera protection. It also covers pursuit timeouts, nearest-alternative selection, the single-enemy fallback, and four equal-speed Vipers/Raiders forced to exhaust their pursuit windows before resuming live fire on four seeds. It also covers whole-furball framing, forty seconds without arbitrary cuts, critical attack-to-explosion continuity, return-to-wide dwell, and a predominantly wide combat view over three ten-minute runs. It also covers readable battlefield framing for separated squadrons far outside the belt, close launch shots that pull back continuously to frame the full capital ship and all six fighters while following the group through departure, friendly head-on and overtaking avoidance for all nine factions, friendly/enemy contact damage, momentum conservation, sustained-contact handling, fatal swept crossings, and overlap prevention during full battles. It also covers forward muzzle alignment for every fighter, physical projectile hits and evasion, identical flight at 30/60 fps, acceleration/turn/displacement limits, swept asteroid impacts, and an uninterrupted camera shot through every capital ship's final launch and immediate departure. It also covers full-faction elimination, no premature refills, replacements across all nine factions, separate targets, model cleanup, and protection against old projectiles hitting a replacement generation. Capital-ship hull meshes are checked for closure and consistent orientation, and both BSG capital ships must blink at fixed positions and deploy the correct fighters. Three seeds each run ten simulated minutes, checking clearance, camera coverage, bounded effects, scene-node cleanup, and seed reproducibility. The combat benchmark measures shots and physical hits over two simulated minutes on three fixed seeds. The planet review renders all four biomes with two seeds in daylight, at the terminator, as a crescent, on the night side, and after rotation, with separate layer views for inspection. The render review writes fighter and capital-ship model views, before/during/after blink frames, hangar deployment, cinematic camera styles, and explosion stages. The smoke-test flag saves a snapshot and JSON runtime status, including faction/replacement counts, blink events, native window bounds, and full-screen/zoom state, while leaving the app running.

The Stargate check flies a lone patrol, deploys all three squadrons from their carriers, and runs a siege through shield collapse, destruction, return to the belt and the encounter cooldown. The optional review renders launches and siege camera shots.

This is an unofficial personal fan project. Star Wars, Battlestar Galactica, Babylon 5 and Stargate names and designs belong to their respective owners.
