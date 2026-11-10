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
[[ "$(xcrun lipo "$package_app/Contents/MacOS/AsteroidSquadron" -archs)" == arm64 ]] || { print -u2 'Release packages must be Apple Silicon only.'; exit 1; }
codesign --verify --deep --strict --verbose=2 "$package_app"
mkdir -p "$package_output" "$PWD/.cache"
package_work="$(mktemp -d "$PWD/.cache/dmg.XXXXXX")"
package_stage="$package_work/stage"
package_mount="$package_work/mount"
package_mounted=false
cleanup_package() {
    if $package_mounted; then
        hdiutil detach "$package_mount" -quiet || { print -u2 "Unmount $package_mount before removing $package_work"; return 1; }
    fi
    rm -rf "$package_work"
}
trap cleanup_package EXIT
mkdir "$package_stage" "$package_mount"
package_icon="$package_app/Contents/Resources/AppIcon.icns"
[[ -s "$package_icon" ]] || { print -u2 'App icon is missing; rebuild the app before packaging.'; exit 1; }
package_icon_file="$(/usr/libexec/PlistBuddy -c 'Print CFBundleIconFile' "$package_app/Contents/Info.plist")"
[[ "$package_icon_file" == AppIcon || "$package_icon_file" == AppIcon.icns ]] || { print -u2 'App icon is not registered in Info.plist.'; exit 1; }
[[ "$(/usr/libexec/PlistBuddy -c 'Print CFBundleIconName' "$package_app/Contents/Info.plist")" == AppIcon && -s "$package_app/Contents/Resources/Assets.car" ]] || { print -u2 'Native icon catalog is missing; rebuild the app before packaging.'; exit 1; }
cp "$package_icon" "$package_stage/.VolumeIcon.icns"
ditto "$package_app" "$package_stage/Asteroid Squadron.app"
ln -s /Applications "$package_stage/Applications"
cat > "$package_stage/Install Asteroid Squadron.txt" <<'INSTALL'
ASTEROID SQUADRON

Drag Asteroid Squadron.app onto Applications, then open it from Applications.
Requires an Apple Silicon Mac running macOS 13 or newer.

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
package_dmg="$package_output/Asteroid-Squadron-$package_version-arm64.dmg"
# Set the volume's custom-icon flag on a writable image before compression/signing.
# The embedded .VolumeIcon.icns survives downloads, unlike a local DMG resource fork.
hdiutil create -volname 'Asteroid Squadron' -srcfolder "$package_stage" -fs HFS+ -format UDRW "$package_work/writable.dmg"
hdiutil attach "$package_work/writable.dmg" -nobrowse -noautoopen -mountpoint "$package_mount" -quiet
package_mounted=true
xcrun SetFile -a C "$package_mount"
verify_volume_icon() {
python3 - "$package_mount" "$package_icon" <<'PYICON'
import pathlib, subprocess, sys
volume, icon = pathlib.Path(sys.argv[1]), pathlib.Path(sys.argv[2])
assert (volume/'.VolumeIcon.icns').read_bytes() == icon.read_bytes(), 'Volume icon differs from app icon'
assert int.from_bytes(bytes.fromhex(subprocess.check_output(['xattr','-px','com.apple.FinderInfo',str(volume)],text=True))[8:10], 'big') & 0x400, 'Custom volume icon flag missing'
PYICON
}
verify_volume_icon
codesign --verify --deep --strict --verbose=2 "$package_mount/Asteroid Squadron.app"
hdiutil detach "$package_mount" -quiet
package_mounted=false
hdiutil convert "$package_work/writable.dmg" -format UDZO -ov -o "$package_dmg"
hdiutil verify "$package_dmg"
# Verify the actual distributable retained both Finder icons after conversion.
hdiutil attach "$package_dmg" -readonly -nobrowse -noautoopen -mountpoint "$package_mount" -quiet
package_mounted=true
verify_volume_icon
cmp "$package_icon" "$package_mount/Asteroid Squadron.app/Contents/Resources/AppIcon.icns"
codesign --verify --deep --strict --verbose=2 "$package_mount/Asteroid Squadron.app"
hdiutil detach "$package_mount" -quiet
package_mounted=false
print "Packaged: $package_dmg"
