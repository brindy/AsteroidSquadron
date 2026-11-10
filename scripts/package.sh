#!/bin/zsh
# This only packages an app. Signing and notarization belong to release.sh.
set -euo pipefail
cd "${0:A:h:h}"
(( $# == 2 )) || { print -u2 "Usage: $0 app-path output-directory"; exit 1; }
package_app="${1:A}"
package_output="${2:A}"
[[ -x "$package_app/Contents/MacOS/AsteroidSquadron" ]] || { print -u2 "App executable is missing"; exit 1; }
package_version="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$package_app/Contents/Info.plist")"
[[ "$package_version" =~ '^[0-9]+\.[0-9]+(\.[0-9]+)?$' ]] || { print -u2 "Invalid app version"; exit 1; }
for package_arch in arm64 x86_64; do
    xcrun lipo "$package_app/Contents/MacOS/AsteroidSquadron" -verify_arch "$package_arch"
done
codesign --verify --deep --strict --verbose=2 "$package_app"
mkdir -p "$package_output" "$PWD/.cache"
package_stage="$(mktemp -d "$PWD/.cache/dmg.XXXXXX")"
trap 'rm -rf "$package_stage"' EXIT
ditto "$package_app" "$package_stage/Asteroid Squadron.app"
ln -s /Applications "$package_stage/Applications"
cat > "$package_stage/Install Asteroid Squadron.txt" <<'INSTALL'
ASTEROID SQUADRON

Drag Asteroid Squadron.app onto Applications, then open it from Applications.
Requires macOS 13 or newer. Supports Apple Silicon and Intel Macs.

The app keeps your display and computer awake while it runs, including when
paused or minimized. Quit with Command-Q or close its window to release this.
K toggles keep-awake. It does not change your system power preferences.

Drag the scene to move the window. Double-click to fill / restore the desktop.
F: full screen    A: automatic cinematic cameras    Space: pause
R: new arena     B: planet biome                   ?: all controls

Updates and source: https://github.com/brindy/AsteroidSquadron

Unofficial fan project. Star Wars, Battlestar Galactica and Babylon 5 names
and designs belong to their respective owners.
INSTALL
package_dmg="$package_output/Asteroid-Squadron-$package_version-universal.dmg"
hdiutil create -volname 'Asteroid Squadron' -srcfolder "$package_stage" -fs HFS+ -format UDZO -ov "$package_dmg"
hdiutil verify "$package_dmg"
print "Packaged: $package_dmg"
