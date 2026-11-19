#!/bin/zsh
# Publish the signed feed only after its release downloads are available.
set -euo pipefail
cd "${0:A:h:h}"
release_tag="${1:-v$(< VERSION)}"
[[ "$release_tag" =~ '^v[0-9]+\.[0-9]+(\.[0-9]+)?$' ]] || { print -u2 'Expected a release tag such as v1.34.'; exit 1; }
[[ "$(git branch --show-current)" == main ]] || { print -u2 'Publish the main-branch update feed from main.'; exit 1; }
release_dir="$PWD/build/releases/$release_tag"
feed_path='app-updates/asteroid-squadron/appcast.xml'
prepared_feed="$release_dir/sparkle/appcast.xml"
sparkle_dir="$(./scripts/fetch-sparkle.sh)"
"$sparkle_dir/bin/sign_update" --account asteroid-squadron --verify "$prepared_feed"
python3 - "$release_dir" "$release_tag" "$prepared_feed" "$feed_path" <<'PYVERIFY'
import hashlib, json, pathlib, subprocess, sys, xml.etree.ElementTree as ET
folder, tag, feed, published = pathlib.Path(sys.argv[1]), sys.argv[2], pathlib.Path(sys.argv[3]), pathlib.Path(sys.argv[4])
evidence = json.loads((folder/'sparkle/SPARKLE-EVIDENCE.json').read_text())
assert evidence['version'] == tag[1:], 'Sparkle evidence version mismatch'
assert evidence['signedFeedVerified'] and evidence['archiveSignatureVerified'], 'Sparkle signature checks are incomplete'
assert hashlib.sha256(feed.read_bytes()).hexdigest() == evidence['feedSHA256'], 'The prepared feed changed after signing'
archive = folder/evidence['archive']
assert hashlib.sha256(archive.read_bytes()).hexdigest() == evidence['archiveSHA256'], 'The signed update archive changed'
release = json.loads(subprocess.check_output(['gh','release','view',tag,'--repo','brindy/AsteroidSquadron','--json','tagName,isDraft,assets']))
assert release['tagName'] == tag and not release['isDraft'], 'The GitHub release is not public'
asset = next((a for a in release['assets'] if a['name'] == archive.name), None)
assert asset and asset['size'] == evidence['archiveLength'], 'The update download is missing or has the wrong length'
if asset.get('digest'):
    assert asset['digest'] == 'sha256:'+evidence['archiveSHA256'], 'The GitHub download checksum does not match'
namespace = '{http://www.andymatuschak.org/xml-namespaces/sparkle}'
def builds(path):
    return {int(item.findtext(namespace+'version') or item.find('enclosure').get(namespace+'version'))
            for item in ET.parse(path).getroot().find('channel').findall('item')}
assert int(evidence['build']) in builds(feed), 'The signed feed omits this release'
if published.exists():
    assert builds(published).issubset(builds(feed)), 'Publishing would remove existing updates'
print('Verified public release downloads and signed update feed.')
PYVERIFY
if ! cmp -s "$prepared_feed" "$feed_path"; then
    git diff --quiet -- "$feed_path"
    git diff --cached --quiet -- "$feed_path"
    cp "$prepared_feed" "$feed_path"
    git add -- "$feed_path"
    git commit --only -m "Publish signed Sparkle feed for $release_tag" -- "$feed_path"
fi
git push origin main
print "Published Sparkle feed for $release_tag."
