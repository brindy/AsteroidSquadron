#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
APP="$PWD/build/Asteroid Squadron.app"
build_archs=("$(uname -m)")
signing_identity="-"
while (( $# )); do
    case "$1" in
        --universal) build_archs=(arm64 x86_64); shift ;;
        --arch) build_archs=("${2:?Missing architecture}"); shift 2 ;;
        --output) APP="${2:?Missing app path}"; shift 2 ;;
        --sign) signing_identity="${2:?Missing signing identity}"; shift 2 ;;
        *) print -u2 "Usage: $0 [--universal | --arch arm64|x86_64] [--output app-path] [--sign identity]"; exit 1 ;;
    esac
done
for build_arch in "${build_archs[@]}"; do
    [[ "$build_arch" == arm64 || "$build_arch" == x86_64 ]] || { print -u2 "Unsupported architecture: $build_arch"; exit 1; }
done
APP="${APP:A}"
app_version="$(< VERSION)"
build_number="$(< BUILD_NUMBER)"
[[ "$app_version" =~ '^[0-9]+\.[0-9]+(\.[0-9]+)?$' && "$build_number" =~ '^[0-9]+$' ]] || { print -u2 "Invalid VERSION or BUILD_NUMBER"; exit 1; }
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$PWD/.cache/clang"
build_temp="$(mktemp -d "$PWD/.cache/build.XXXXXX")"
trap 'rm -rf "$build_temp"' EXIT
build_slices=()
for build_arch in "${build_archs[@]}"; do
    print "Compiling $build_arch"
    build_slice="$build_temp/AsteroidSquadron-$build_arch"
    xcrun swiftc -O -target "$build_arch-apple-macosx13.0" -module-cache-path "$PWD/.cache/clang" Sources/*.swift -o "$build_slice" -framework AppKit -framework SceneKit
    build_slices+=("$build_slice")
done
xcrun lipo -create "${build_slices[@]}" -output "$APP/Contents/MacOS/AsteroidSquadron"
chmod 755 "$APP/Contents/MacOS/AsteroidSquadron"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleName</key><string>Asteroid Squadron</string>
<key>CFBundleDisplayName</key><string>Asteroid Squadron</string>
<key>CFBundleIdentifier</key><string>dev.brindy.asteroid-squadron</string>
<key>CFBundleExecutable</key><string>AsteroidSquadron</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleVersion</key><string>$build_number</string>
<key>CFBundleShortVersionString</key><string>$app_version</string>
<key>LSApplicationCategoryType</key><string>public.app-category.entertainment</string>
<key>LSMinimumSystemVersion</key><string>13.0</string>
<key>NSHighResolutionCapable</key><true/>
<key>NSSupportsAutomaticGraphicsSwitching</key><true/>
<key>NSPrincipalClass</key><string>NSApplication</string>
<key>NSHumanReadableCopyright</key><string>Unofficial fan project. Star Wars, Battlestar Galactica and Babylon 5 belong to their respective owners.</string>
</dict></plist>
PLIST
plutil -lint "$APP/Contents/Info.plist"
if [[ "$signing_identity" == "-" ]]; then
    codesign --force --sign - "$APP"
else
    codesign --force --options runtime --timestamp --sign "$signing_identity" "$APP"
fi
codesign --verify --deep --strict --verbose=2 "$APP"
for build_arch in "${build_archs[@]}"; do
    xcrun lipo "$APP/Contents/MacOS/AsteroidSquadron" -verify_arch "$build_arch"
done
print "Built: $APP"
