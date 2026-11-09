# Asteroid Squadron

A standalone macOS app: an endless crossover dogfight between Star Wars and the reimagined Battlestar Galactica in a procedural 3D asteroid belt. An action-directed camera system, faction-specific weapons, turbulent explosions that cool into smoke, formation arrivals, capital-ship hangar launches, drifting volumetric gas, a distant planet, and a quiet cinematic overlay. All ship meshes, geometry, density fields, and textures are generated locally. No dependencies, downloads, network access, or audio.

Every launch chooses a fresh random seed for asteroid placement and shapes, cloud positions and density, planet placement, flight orientation, and the initial pair of opposing factions. **R** generates another arena and faction pairing without interrupting keep-awake. For a reproducible arena, launch with `--seed 42` (any unsigned 64-bit decimal integer).

Each side starts with six fighters. Losses stay lost until that faction's **last ship is destroyed**. Its replacement is then randomly selected from the catalog, excluding the surviving opponent and the just-defeated faction. There are always two distinct factions; a weakened squadron does not get topped up early.

| Faction | Fighters | Arrival |
| --- | --- | --- |
| Rebel Alliance | X-wings | Jump together in a V formation, then split toward separate targets |
| Galactic Empire | TIE fighters | Launch from an Imperial capital ship that arrives and departs via hyperspace |
| Colonial Fleet | Viper Mk II | Launch from Galactica's two flight pods |
| Cylon Fleet | Reimagined Cylon Raiders | Launch from a modern, six-armed basestar |

**Galactica and the basestar use BSG-style blink FTL:** a short blue-white displacement flash, the complete ship appearing at a fixed location, and another flash as it vanishes. The models neither stretch nor travel along a hyperspace trail. Vipers and Raiders deploy from their respective capital ships before those ships leave. Capital arrivals are staged so the camera can cover each deployment; simultaneous capital ships keep separate arrival locations.

The automatic director mixes six shot styles with varied lengths: pursuit, low asteroid-corridor tracking, brief establishing shots, lateral dolly shots, forward flybys, and two-ship engagements. It chooses active, threatened ships near the action, uses damped movement and gentle lens changes within shots, and cuts to formation arrivals, carrier deployment and departure, and loss-of-control incidents. Disabling Auto preserves manual camera control.

Dangerous close passes can clip an asteroid. The ship ricochets into an uncontrolled tumble, then either levels out and rejoins the battle or explodes. A second collision during the tumble is fatal. The camera can follow both the strike and the recovery. Explosions use a short light flash, a ray-marched turbulent fuel cloud that cools from white/orange fire to dark smoke, metal fragments with inherited momentum, and small fading sparks.

The gas clouds use ray marching through three-dimensional procedural noise inside ellipsoidal volumes. They have depth and parallax as cameras and ships pass around them. Nine volumes with twenty density samples per ray keep the effect bounded; default rendering remains 30 fps.

## Run

Double-click **Start Dogfight.command**, or open **build/Asteroid Squadron.app** after building. The launcher builds the app if needed; building requires Xcode Command Line Tools. The built app itself only needs macOS 13 or newer on the architecture it was built for.

```sh
./scripts/build.sh
./"Start Dogfight.command"
# Optional:
./"Start Dogfight.command" --fullscreen
# Start with the two BSG fleets (subsequent defeated factions still change randomly):
./"Start Dogfight.command" --factions colonial,cylon
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
| ? | Help |
| ⌘Q | Quit and release this app's keep-awake assertions |

The overlay dims after nine seconds without mouse movement; move the pointer to restore it. Window size and position are remembered.

## Verification

```sh
./scripts/build.sh
"build/Asteroid Squadron.app/Contents/MacOS/AsteroidSquadron" --verify-simulation
"build/Asteroid Squadron.app/Contents/MacOS/AsteroidSquadron" --render-review build/review --seed 42
open "build/Asteroid Squadron.app" --args --smoke-test /tmp/asteroid-squadron.png
```

The simulation check covers full-faction elimination, no partial refills, twelve forced replacements across the four-faction catalog, separate targets, model cleanup, and protection against old projectiles hitting a replacement generation. It checks that capital-ship hull meshes are closed and consistently oriented, and that both BSG capital ships blink at fixed positions and deploy the correct fighters. It also covers V-formation offsets, attack splits, manual camera control, spin-out outcomes, and ten simulated minutes on each of three seeds, checking clearance, camera coverage, bounded effects, exact scene-node cleanup, and seed reproducibility. The render review writes fighter and capital-ship model views, before/during/after blink frames, hangar deployment, cinematic camera styles, and explosion stages. The smoke-test flag saves a snapshot and JSON runtime status, including faction/replacement counts, blink events, native window bounds, and full-screen/zoom state, while leaving the app running.

This is an unofficial personal fan project. Star Wars and Battlestar Galactica names and designs belong to their respective owners.
