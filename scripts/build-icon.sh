#!/bin/zsh
# Compile one native icon composition for Finder, Spotlight, the Dock and DMGs.
set -euo pipefail
cd "${0:A:h:h}"
(( $# == 2 )) || { print -u2 "Usage: $0 resources-directory partial-info.plist"; exit 1; }
icon_resources="${1:A}"
icon_info="${2:A}"
icon_source="$PWD/Resources/AppIcon.png"
[[ -f "$icon_source" ]] || { print -u2 'Missing Resources/AppIcon.png'; exit 1; }
xcrun --find actool >/dev/null || { print -u2 'Building native app icons requires full Xcode 26 or newer.'; exit 1; }
mkdir -p "$PWD/.cache" "$icon_resources" "${icon_info:h}"
icon_work="$(mktemp -d "$PWD/.cache/icon.XXXXXX")"
trap 'rm -rf "$icon_work"' EXIT
icon_composition="$icon_work/AppIcon.icon"
mkdir -p "$icon_composition/Assets"
cp Resources/IconComposition.json "$icon_composition/icon.json"
# Keep the selected original untouched. macOS applies the icon shape and margin;
# pre-insetting this image would cause the pale fallback plate on newer systems.
sips -z 1024 1024 "$icon_source" --out "$icon_composition/Assets/Artwork.png" >/dev/null
xcrun actool "$icon_composition" --compile "$icon_resources" \
    --platform macosx --minimum-deployment-target 13.0 --app-icon AppIcon \
    --standalone-icon-behavior all --output-partial-info-plist "$icon_info" \
    --output-format human-readable-text --warnings --errors
[[ -s "$icon_resources/Assets.car" && -s "$icon_resources/AppIcon.icns" ]] || { print -u2 'Native icon compilation did not produce both the catalog and compatibility icon.'; exit 1; }
# Include every compatibility size for older macOS versions and mounted DMGs.
iconutil -c iconset "$icon_resources/AppIcon.icns" -o "$icon_work/Check.iconset"
for icon_size in 16 32 128 256 512; do
    [[ -s "$icon_work/Check.iconset/icon_${icon_size}x${icon_size}.png" && -s "$icon_work/Check.iconset/icon_${icon_size}x${icon_size}@2x.png" ]] || { print -u2 "Missing compatibility icon size $icon_size"; exit 1; }
done
print "Native icon: $icon_resources"
