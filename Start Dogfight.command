#!/bin/zsh
set -euo pipefail
cd "${0:A:h}"
if [[ ! -x "build/Asteroid Squadron.app/Contents/MacOS/AsteroidSquadron" || Sources/main.swift -nt "build/Asteroid Squadron.app/Contents/MacOS/AsteroidSquadron" ]]; then
    ./scripts/build.sh
fi
open "build/Asteroid Squadron.app" --args "$@"
