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
mkdir -p "$PWD/.cache/clang"
# Compile the small native layout helper when its source changes.
icon_renderer="$PWD/.cache/render-app-icon"
if [[ ! -x "$icon_renderer" || scripts/RenderAppIcon.swift -nt "$icon_renderer" ]]; then
    xcrun swiftc -O -module-cache-path "$PWD/.cache/clang" scripts/RenderAppIcon.swift -o "$icon_work/render-app-icon"
    install -m 755 "$icon_work/render-app-icon" "$icon_renderer"
fi
"$icon_renderer" "$icon_source" "$icon_set"
iconutil -c icns "$icon_set" -o "$icon_output"
print "Icon: $icon_output"
