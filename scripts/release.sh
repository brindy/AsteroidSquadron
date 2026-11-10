#!/bin/zsh
# Private signing keys and notarization passwords stay in the local Keychain.
set -euo pipefail
cd "${0:A:h:h}"
notary_profile="${NOTARY_PROFILE:-}"
signing_identity=""
publish_release=false
while (( $# )); do
    case "$1" in
        --profile) notary_profile="${2:?Missing Keychain profile name}"; shift 2 ;;
        --identity) signing_identity="${2:?Missing Developer ID identity}"; shift 2 ;;
        --publish) publish_release=true; shift ;;
        *) print -u2 "Usage: $0 --profile keychain-profile [--identity developer-id] [--publish]"; exit 1 ;;
    esac
done
[[ -n "$notary_profile" ]] || { print -u2 'A notarization Keychain profile is required. Run ./scripts/setup-notarization.sh first.'; exit 1; }
app_version="$(< VERSION)"
release_tag="v$app_version"
source_commit="$(git rev-parse HEAD)"
release_notes="$PWD/releases/$release_tag.md"
[[ -f "$release_notes" ]] || { print -u2 "Missing release notes: $release_notes"; exit 1; }
if [[ -z "$signing_identity" ]]; then
    signing_identity="$(security find-identity -v -p codesigning | awk -F '"' '/"Developer ID Application:/ { print $2 }')"
    [[ -n "$signing_identity" && "$signing_identity" != *$'\n'* ]] || { print -u2 'Select one Developer ID Application certificate using --identity.'; exit 1; }
fi
if $publish_release; then
    [[ -z "$(git status --porcelain)" ]] || { print -u2 'Commit all source and release changes before publishing.'; exit 1; }
    command -v gh >/dev/null || { print -u2 'Install GitHub CLI and run gh auth login first.'; exit 1; }
    gh auth status
    # Refuse to rebuild or replace an already published release.
    if gh release view "$release_tag" --repo brindy/AsteroidSquadron >/dev/null 2>&1; then
        print -u2 "$release_tag already has a release. Use a new version, or recover an existing draft with gh release upload."
        exit 1
    fi
    remote_tag_commit="$(git ls-remote origin "refs/tags/$release_tag" "refs/tags/$release_tag^{}" | awk '{ value=$1 } END { print value }')"
    [[ -z "$remote_tag_commit" || "$remote_tag_commit" == "$(git rev-parse HEAD)" ]] || { print -u2 "$release_tag points to a different commit. Use a new version."; exit 1; }
fi
# Fail before compiling if the credentials do not authenticate with Apple.
xcrun notarytool history --keychain-profile "$notary_profile" --output-format json >/dev/null
release_dir="$PWD/build/releases/$release_tag"
release_app="$release_dir/Asteroid Squadron.app"
mkdir -p "$release_dir"
./scripts/build.sh --universal --output "$release_app" --sign "$signing_identity"
"$release_app/Contents/MacOS/AsteroidSquadron" --verify-pursuit > "$release_dir/flight-checks.log" 2>&1
"$release_app/Contents/MacOS/AsteroidSquadron" --verify-babylon > "$release_dir/arrival-checks.log" 2>&1
signature_info="$(codesign --display --verbose=4 "$release_app" 2>&1)"
print -r -- "$signature_info" | grep -q '^Authority=Developer ID Application:' || { print -u2 'App is not signed with Developer ID Application.'; exit 1; }
print -r -- "$signature_info" | grep -q 'flags=.*runtime' || { print -u2 'Hardened runtime is missing.'; exit 1; }
print -r -- "$signature_info" | grep -q '^Timestamp=' || { print -u2 'Secure signing timestamp is missing.'; exit 1; }

notarize_artifact() {
    local artifact="$1" receipt="$2"
    print "Submitting to Apple: ${artifact:t}"
    local submit_result=0
    xcrun notarytool submit "$artifact" --keychain-profile "$notary_profile" --wait --timeout 30m --output-format json > "$receipt" || submit_result=$?
    local notary_result
    notary_result="$(python3 - "$receipt" <<'PY'
import json, sys
try:
    receipt = json.load(open(sys.argv[1]))
except (OSError, ValueError):
    sys.exit(1)
print(receipt.get('status', 'Unknown'))
PY
)" || { print -u2 "Notarization did not return a receipt. See $receipt"; return 1; }
    if [[ "$notary_result" != Accepted ]]; then
        print -u2 "Notarization is $notary_result (exit $submit_result). Receipt: $receipt"
        if [[ "$notary_result" == Invalid || "$notary_result" == Rejected ]]; then
            local submission_id
            submission_id="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["id"])' "$receipt")"
            xcrun notarytool log "$submission_id" --keychain-profile "$notary_profile" "${receipt%.json}-log.json"
            print -u2 "Detailed Apple log: ${receipt%.json}-log.json"
        fi
        print -u2 'Use the submission ID in that receipt with notarytool info/log/wait; do not publish or immediately resubmit a timed-out request.'
        return 1
    fi
}

# Notarize and staple the app before making containers, for offline installation.
submission_zip="$release_dir/notarization-submission.zip"
ditto -c -k --sequesterRsrc --keepParent "$release_app" "$submission_zip"
notarize_artifact "$submission_zip" "$release_dir/app-notarization.json"
xcrun stapler staple "$release_app"
xcrun stapler validate "$release_app"
codesign --verify --deep --strict --verbose=2 "$release_app"
spctl --assess --type execute --verbose=2 "$release_app"
./scripts/package.sh "$release_app" "$release_dir"
release_dmg="$release_dir/Asteroid-Squadron-$app_version-universal.dmg"
codesign --force --timestamp --sign "$signing_identity" "$release_dmg"
notarize_artifact "$release_dmg" "$release_dir/dmg-notarization.json"
xcrun stapler staple "$release_dmg"
xcrun stapler validate "$release_dmg"
spctl --assess --type open --context context:primary-signature --verbose=2 "$release_dmg"
release_zip="$release_dir/Asteroid-Squadron-$app_version-universal.zip"
ditto -c -k --sequesterRsrc --keepParent "$release_app" "$release_zip"
(cd "$release_dir" && shasum -a 256 "${release_dmg:t}" "${release_zip:t}" > SHA256SUMS)
# Verify the exact ZIP extraction, not just the app used to create it.
archive_check="$(mktemp -d "$PWD/.cache/release-check.XXXXXX")"
trap 'rm -rf "$archive_check"' EXIT
ditto -x -k "$release_zip" "$archive_check"
codesign --verify --deep --strict --verbose=2 "$archive_check/Asteroid Squadron.app"
xcrun stapler validate "$archive_check/Asteroid Squadron.app"
spctl --assess --type execute --verbose=2 "$archive_check/Asteroid Squadron.app"
python3 - "$release_dir" "$source_commit" <<'PYREPORT'
import hashlib, json, pathlib, plistlib, subprocess, sys
folder, revision = pathlib.Path(sys.argv[1]), sys.argv[2]
app = folder / 'Asteroid Squadron.app'
info = plistlib.loads((app / 'Contents/Info.plist').read_bytes())
signature = subprocess.check_output(['codesign', '--display', '--verbose=4', str(app)], stderr=subprocess.STDOUT, text=True)
fields = dict(line.split('=',1) for line in signature.splitlines() if '=' in line)
app_receipt = json.loads((folder / 'app-notarization.json').read_text())
dmg_receipt = json.loads((folder / 'dmg-notarization.json').read_text())
report = {
    'version': info['CFBundleShortVersionString'], 'build': info['CFBundleVersion'],
    'bundleID': info['CFBundleIdentifier'], 'sourceCommit': revision,
    'team': fields.get('TeamIdentifier'), 'signingTimestamp': fields.get('Timestamp'),
    'architectures': subprocess.check_output(['xcrun','lipo',str(app / 'Contents/MacOS/AsteroidSquadron'),'-archs'],text=True).strip().split(),
    'appNotarization': {'id':app_receipt['id'],'status':app_receipt['status']},
    'dmgNotarization': {'id':dmg_receipt['id'],'status':dmg_receipt['status']},
    'verified': ['deep strict code signature','hardened runtime and secure timestamp','app and DMG stapling','Gatekeeper app and DMG assessments','ZIP extraction signature, stapling and Gatekeeper','native pursuit and rendered jump-arrival checks'],
    'notPerformed': ['browser-download installation test on a clean Mac'],
    'sha256': {p.name:hashlib.sha256(p.read_bytes()).hexdigest() for p in sorted(folder.iterdir()) if p.name.startswith('Asteroid-Squadron-') and p.suffix in ['.zip','.dmg']}
}
(folder / 'RELEASE-EVIDENCE.json').write_text(json.dumps(report,indent=2)+'\n')
PYREPORT
print "Notarized release ready: $release_dir"
print "Evidence: $release_dir/RELEASE-EVIDENCE.json"
if $publish_release; then
    [[ "$(git rev-parse HEAD)" == "$source_commit" && -z "$(git status --porcelain)" ]] || { print -u2 'Source changed during the release. Do not publish these artifacts; rebuild from a clean commit.'; exit 1; }
    release_commit="$source_commit"
    # Publish the exact source used above. No force pushes or replaced assets.
    git push origin HEAD
    if git rev-parse --verify "refs/tags/$release_tag" >/dev/null 2>&1; then
        [[ "$(git rev-list -n 1 "$release_tag")" == "$release_commit" ]] || { print -u2 'Local tag points to different source.'; exit 1; }
    else
        git tag -a "$release_tag" -m "Asteroid Squadron $app_version" "$release_commit"
    fi
    git push origin "refs/tags/$release_tag"
    gh release create "$release_tag" "$release_dmg" "$release_zip" "$release_dir/SHA256SUMS" --verify-tag --repo brindy/AsteroidSquadron --title "Asteroid Squadron $app_version" --notes-file "$release_notes"
fi
