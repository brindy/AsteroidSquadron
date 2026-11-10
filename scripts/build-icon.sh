#!/bin/zsh
# Derive standard and Retina icon sizes from the original, preserving alpha.
set -euo pipefail
cd "${0:A:h:h}"
(( $# == 1 )) || { print -u2 "Usage: $0 output.icns"; exit 1; }
icon_output="${1:A}"
icon_source="$PWD/Resources/AppIcon.png"
[[ -f "$icon_source" ]] || { print -u2 'Missing Resources/AppIcon.png'; exit 1; }
mkdir -p "$PWD/.cache" "${icon_output:h}"
icon_work="$(mktemp -d "$PWD/.cache/icon.XXXXXX")"
trap 'rm -rf "$icon_work"' EXIT
icon_set="$icon_work/AppIcon.iconset"
mkdir "$icon_set"
for icon_size in 16 32 128 256 512; do
    sips -z "$icon_size" "$icon_size" "$icon_source" --out "$icon_set/icon_${icon_size}x${icon_size}.png" >/dev/null
    icon_retina=$((icon_size * 2))
    sips -z "$icon_retina" "$icon_retina" "$icon_source" --out "$icon_set/icon_${icon_size}x${icon_size}@2x.png" >/dev/null
done
iconutil -c icns "$icon_set" -o "$icon_output"
print "Icon: $icon_output"
