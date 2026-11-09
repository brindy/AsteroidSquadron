# Asteroid Squadron

A standalone macOS app: X-wings and TIE fighters in an endless procedural dogfight through a 3D asteroid belt. An action-directed camera system, red and green laser fire, turbulent explosions that cool into smoke, formation arrivals, capital-ship hangar launches, drifting volumetric gas, a distant planet, and a quiet cinematic overlay. All geometry, density fields, and textures are generated locally. No dependencies, downloads, network access, or audio.

Every launch chooses a fresh random seed for asteroid placement and shapes, cloud positions and density, planet placement, and flight orientation. **R** generates another arena without interrupting keep-awake. For a reproducible arena, launch with `--seed 42` (any unsigned 64-bit decimal integer).

Ships destroyed in combat stay lost until the active fleet drops to seven, or either faction drops to two. X-wing reinforcements jump together in a V formation, hold their offsets, then peel off on curved attack runs toward separately assigned targets. Standard TIE fighters never jump themselves: an Imperial capital ship exits hyperspace outside the asteroid belt, launches them from its ventral hangar, and jumps away after deployment.

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
```

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

The simulation check covers held V-formation offsets, individual target assignment, attack splits, carrier-only TIE deployment, manual camera control, both spin-out outcomes, and ten simulated minutes on each of three seeds. It checks normal flight and camera clearance, fleet attrition, event-camera coverage, carrier departure, finite positions, bounded effects, and exact scene-node cleanup. It also verifies seed randomization and reproducibility. The render review writes the six shot styles, explosion stages, formation arrivals and splits, carrier arrival/hangar/departure, and multiple views of both fighter meshes, exercising the actual GPU shaders. The smoke-test flag saves a snapshot and JSON runtime status, including native window bounds and full-screen/zoom state, while leaving the app running.

This is an unofficial personal fan project, not affiliated with Lucasfilm. Star Wars, X-wing, and TIE fighter names and designs belong to their respective owners.
