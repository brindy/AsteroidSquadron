#!/bin/zsh
# Publish existing approved files without rebuilding or modifying the app.
set -euo pipefail
cd "${0:A:h:h}"
check_only=false
if [[ "${1:-}" == --check ]]; then check_only=true; shift; fi
release_tag="${1:-v$(< VERSION)}"
[[ "$release_tag" =~ '^v[0-9]+\.[0-9]+(\.[0-9]+)?$' ]] || { print -u2 'Expected a version tag such as v1.15.'; exit 1; }
release_version="${release_tag#v}"
release_dir="$PWD/build/releases/$release_tag"
release_app="$release_dir/Asteroid Squadron.app"
[[ -f "$release_dir/RELEASE-EVIDENCE.json" ]] || { print -u2 'No completed local release exists for this version. Build it with scripts/release.sh first.'; exit 1; }
# Keep old approved archives readable without ever rebuilding or re-signing them.
artifact_label="$(python3 - "$release_dir/RELEASE-EVIDENCE.json" <<'PYARCH'
import json, sys
arches = set(json.load(open(sys.argv[1]))['architectures'])
if arches == {'arm64'}: print('arm64')
elif arches == {'arm64','x86_64'}: print('universal')
else: raise SystemExit('Unsupported artifact architecture metadata')
PYARCH
)"
release_dmg="$release_dir/Asteroid-Squadron-$release_version-$artifact_label.dmg"
release_zip="$release_dir/Asteroid-Squadron-$release_version-$artifact_label.zip"
release_notes="$PWD/releases/$release_tag.md"
source_commit="$(python3 - "$release_dir" "$release_version" "$artifact_label" <<'PY'
import hashlib, json, pathlib, plistlib, re, subprocess, sys
folder, version = pathlib.Path(sys.argv[1]), sys.argv[2]
report = json.loads((folder/'RELEASE-EVIDENCE.json').read_text())
assert report['version'] == version, 'Evidence version mismatch'
assert re.fullmatch('[0-9a-f]{40}', report['sourceCommit']), 'Invalid source commit'
for kind in ['app','dmg']:
    assert report[kind+'Notarization']['status'] == 'Accepted', 'Notarization was not accepted'
for ext in ['zip','dmg']:
    name = f'Asteroid-Squadron-{version}-{sys.argv[3]}.{ext}'
    assert hashlib.sha256((folder/name).read_bytes()).hexdigest() == report['sha256'][name], 'Artifact checksum mismatch'
app = folder/'Asteroid Squadron.app'
info = plistlib.loads((app/'Contents/Info.plist').read_bytes())
assert info['CFBundleIdentifier'] == 'dev.brindy.asteroid-squadron', 'Bundle ID mismatch'
assert info['CFBundleShortVersionString'] == version, 'Bundle version mismatch'
actual = subprocess.check_output(['xcrun','lipo',str(app/'Contents/MacOS/AsteroidSquadron'),'-archs'],text=True).split()
assert set(actual) == set(report['architectures']), 'Executable architecture mismatch'
source_version = subprocess.check_output(['git','show',report['sourceCommit']+':VERSION'],text=True).strip()
assert source_version == version, 'Source commit version mismatch'
print(report['sourceCommit'])
PY
)"
(cd "$release_dir" && shasum -a 256 -c SHA256SUMS)
codesign --verify --deep --strict --verbose=2 "$release_app"
xcrun stapler validate "$release_app"
xcrun stapler validate "$release_dmg"
spctl --assess --type execute --verbose=2 "$release_app"
spctl --assess --type open --context context:primary-signature --verbose=2 "$release_dmg"
if $check_only; then
    print "Validated $release_tag at $source_commit; nothing published or modified."
    exit 0
fi
[[ -f "$release_notes" ]] || { print -u2 'Release notes are missing.'; exit 1; }
gh auth status
if gh release view "$release_tag" --repo brindy/AsteroidSquadron >/dev/null 2>&1; then
    print -u2 'A release already exists. Existing releases and assets are never replaced.'
    exit 1
fi
remote_commit="$(git ls-remote origin "refs/tags/$release_tag" "refs/tags/$release_tag^{}" | awk '{value=$1} END {print value}')"
[[ -z "$remote_commit" || "$remote_commit" == "$source_commit" ]] || { print -u2 'Remote tag points to different source.'; exit 1; }
if git rev-parse --verify "refs/tags/$release_tag" >/dev/null 2>&1; then
    [[ "$(git rev-list -n 1 "$release_tag")" == "$source_commit" ]] || { print -u2 'Local tag points to different source.'; exit 1; }
else
    git tag -a "$release_tag" -m "Asteroid Squadron $release_version" "$source_commit"
fi
git push origin "refs/tags/$release_tag"
gh release create "$release_tag" "$release_dmg" "$release_zip" "$release_dir/SHA256SUMS" --verify-tag --repo brindy/AsteroidSquadron --title "Asteroid Squadron $release_version" --notes-file "$release_notes"
