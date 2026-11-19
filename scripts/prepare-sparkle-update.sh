#!/bin/zsh
# Prepare the update feed from the completed, notarized local release.
set -euo pipefail
cd "${0:A:h:h}"
exec python3 scripts/prepare-sparkle-update.py "$@"
