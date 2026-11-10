#!/bin/zsh
set -euo pipefail
cd "${0:A:h}"
if [[ ! -x "build/Asteroid Squadron.app/Contents/MacOS/AsteroidSquadron" ]] || [[ -n "$(find Sources scripts VERSION BUILD_NUMBER -type f -newer 'build/Asteroid Squadron.app/Contents/MacOS/AsteroidSquadron' -print -quit 2>/dev/null)" ]]; then
    ./scripts/build.sh
fi
open "build/Asteroid Squadron.app" --args "$@"
