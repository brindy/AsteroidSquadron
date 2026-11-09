# Asteroid Squadron

A standalone macOS app: X-wings and TIE fighters in an endless procedural dogfight through a 3D asteroid belt. Six automatic cameras, red and green laser fire, fireballs and shockwaves, hyperspace reinforcement waves, drifting volumetric gas, a distant planet, and a quiet cinematic overlay. All geometry, density fields, and textures are generated locally. No dependencies, downloads, network access, or audio.

Every launch chooses a fresh random seed for asteroid placement and shapes, cloud positions and density, planet placement, and flight orientation. **R** generates another arena without interrupting keep-awake. For a reproducible arena, launch with `--seed 42` (any unsigned 64-bit decimal integer).

Ships destroyed in combat stay lost until the active fleet drops to seven, or either faction drops to two. After a short hyperspace warning, the missing fighters arrive in a staggered wave of blue streaks and arrival flashes. The camera can witness its own subject exploding, then follows a surviving fighter. The overlay tracks live faction counts, losses, reinforcement waves, and incoming ships.

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

## Keep awake

On launch, the app starts `/usr/bin/caffeinate -d -i -w <app-pid>`. This prevents **idle display sleep and idle system sleep**. It continues while flight is paused, minimized, or hidden. The cyan indicator shows whether the child process is running. **K** toggles it.

**Closing the window or quitting the app stops its caffeinate process.** The `-w` process binding also makes caffeinate release its assertions if the app crashes. This app never changes system power preferences and does not interfere with any separate caffeinate process you already have running. It does not override deliberate sleep, lid closure, lock policies, or a manual screen lock.

## Controls

| Key | Action |
| --- | --- |
| C / N / right arrow | Next camera |
| A | Automatic cuts every 14 seconds on/off |
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

The simulation check runs ten simulated minutes on each of three seeds. It checks ship and camera clearance, fleet attrition, hyperspace waves, visibility, finite positions and headings, all six cameras, bounded effects, and scene-node cleanup. It also checks that different seeds change the arena and the same seed reproduces it. The render review writes six camera views and front, rear, and three-quarter views of both production ship meshes, exercising the actual GPU cloud shader. The smoke-test flag saves a rendered snapshot and JSON runtime status after three seconds while leaving the app running.

This is an unofficial personal fan project, not affiliated with Lucasfilm. Star Wars, X-wing, and TIE fighter names and designs belong to their respective owners.
