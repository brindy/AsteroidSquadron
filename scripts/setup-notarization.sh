#!/bin/zsh
# Run this yourself in Terminal: notarytool prompts securely for the password.
set -euo pipefail
notary_profile="${1:-asteroid-squadron}"
read 'developer_apple_id?Apple Developer Apple ID: '
read 'developer_team_id?Apple Developer Team ID: '
[[ -n "$developer_apple_id" && -n "$developer_team_id" ]] || { print -u2 'Apple ID and Team ID are required.'; exit 1; }
xcrun notarytool store-credentials "$notary_profile" --apple-id "$developer_apple_id" --team-id "$developer_team_id"
print "Saved in Keychain. Release with: ./scripts/release.sh --profile ${(q)notary_profile} --publish"
