#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
APP="$PWD/build/Asteroid Squadron.app"
build_arch="arm64"
signing_identity=""
while (( $# )); do
    case "$1" in
        --output) APP="${2:?Missing app path}"; shift 2 ;;
        --sign) signing_identity="${2:?Missing signing identity}"; shift 2 ;;
        *) print -u2 "Usage: $0 [--output app-path] [--sign identity]"; exit 1 ;;
    esac
done
if [[ -z "$signing_identity" ]]; then
    # A stable certificate keeps macOS recording permission valid after a rebuild.
    signing_identity="$(security find-identity -v -p codesigning | awk -F '"' '/"Developer ID Application:/ { print $2 }')"
    if [[ -z "$signing_identity" || "$signing_identity" == *$'\n'* ]]; then
        signing_identity="-"
    fi
fi
APP="${APP:A}"
app_version="$(< VERSION)"
build_number="$(< BUILD_NUMBER)"
[[ "$app_version" =~ '^[0-9]+\.[0-9]+(\.[0-9]+)?$' && "$build_number" =~ '^[0-9]+$' ]] || { print -u2 "Invalid VERSION or BUILD_NUMBER"; exit 1; }
sparkle_dir="$(./scripts/fetch-sparkle.sh)"
sparkle_public_key="$(< Resources/SparklePublicKey.txt)"
python3 - "$sparkle_public_key" <<'PYCHECK'
import base64, sys
assert len(base64.b64decode(sys.argv[1], validate=True)) == 32, 'Invalid Sparkle public key'
PYCHECK
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/Frameworks" "$PWD/.cache/clang"
build_temp="$(mktemp -d "$PWD/.cache/build.XXXXXX")"
trap 'rm -rf "$build_temp"' EXIT
print "Compiling Apple Silicon ($build_arch)"
build_slice="$build_temp/AsteroidSquadron"
xcrun swiftc -O -target "$build_arch-apple-macosx13.0" -module-cache-path "$PWD/.cache/clang" Sources/*.swift -o "$build_slice" \
    -framework AppKit -framework SceneKit -framework AVFoundation -framework ScreenCaptureKit \
    -F "$sparkle_dir" -framework Sparkle -Xlinker -rpath -Xlinker '@executable_path/../Frameworks'
install -m 755 "$build_slice" "$APP/Contents/MacOS/AsteroidSquadron"
./scripts/build-icon.sh "$APP/Contents/Resources" "$build_temp/icon-info.plist"
sparkle_framework="$APP/Contents/Frameworks/Sparkle.framework"
if [[ -d "$sparkle_framework" ]]; then rm -rf "$sparkle_framework"; fi
ditto "$sparkle_dir/Sparkle.framework" "$sparkle_framework"
install -m 644 "$sparkle_dir/LICENSE" "$APP/Contents/Resources/Sparkle-LICENSE.txt"
# Thinning invalidates the original signature. Read the downloader's release
# entitlements from the intact distribution before re-signing its arm64 slice.
codesign --display --entitlements - --xml \
    "$sparkle_dir/Sparkle.framework/Versions/B/XPCServices/Downloader.xpc" \
    > "$build_temp/downloader-entitlements.plist" 2>/dev/null
python3 - "$build_temp/downloader-entitlements.plist" <<'PYENTITLEMENTS'
import pathlib, plistlib, sys
path = pathlib.Path(sys.argv[1])
entitlements = plistlib.loads(path.read_bytes())
assert not entitlements.get('com.apple.security.get-task-allow', False), 'Debug entitlements in Sparkle downloader'
path.write_bytes(plistlib.dumps(entitlements, fmt=plistlib.FMT_XML))
PYENTITLEMENTS
sparkle_executables=(
    "$sparkle_framework/Versions/B/Sparkle"
    "$sparkle_framework/Versions/B/Autoupdate"
    "$sparkle_framework/Versions/B/Updater.app/Contents/MacOS/Updater"
    "$sparkle_framework/Versions/B/XPCServices/Downloader.xpc/Contents/MacOS/Downloader"
    "$sparkle_framework/Versions/B/XPCServices/Installer.xpc/Contents/MacOS/Installer"
)
for executable in "${sparkle_executables[@]}"; do
    xcrun lipo "$executable" -thin arm64 -output "$build_temp/${executable:t}.arm64"
    install -m 755 "$build_temp/${executable:t}.arm64" "$executable"
done
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
<key>NSScreenCaptureUsageDescription</key><string>Record the Asteroid Squadron window and its soundtrack.</string>
<key>SUFeedURL</key><string>https://raw.githubusercontent.com/brindy/AsteroidSquadron/main/app-updates/asteroid-squadron/appcast.xml</string>
<key>SUPublicEDKey</key><string>$sparkle_public_key</string>
<key>SUVerifyUpdateBeforeExtraction</key><true/>
<key>SURequireSignedFeed</key><true/>
<key>NSHumanReadableCopyright</key><string>Unofficial fan project. Star Wars, Battlestar Galactica, Babylon 5 and Stargate belong to their respective owners.</string>
</dict></plist>
PLIST
/usr/libexec/PlistBuddy -c "Merge '$build_temp/icon-info.plist'" "$APP/Contents/Info.plist"
plutil -lint "$APP/Contents/Info.plist"
sparkle_signing=(--force --sign "$signing_identity")
if [[ "$signing_identity" != "-" ]]; then sparkle_signing+=(--options runtime --timestamp); fi
# Sign each nested executable before its containing framework and the host app.
codesign "${sparkle_signing[@]}" "$sparkle_framework/Versions/B/XPCServices/Installer.xpc"
codesign "${sparkle_signing[@]}" --entitlements "$build_temp/downloader-entitlements.plist" "$sparkle_framework/Versions/B/XPCServices/Downloader.xpc"
codesign "${sparkle_signing[@]}" "$sparkle_framework/Versions/B/Autoupdate"
codesign "${sparkle_signing[@]}" "$sparkle_framework/Versions/B/Updater.app"
codesign "${sparkle_signing[@]}" "$sparkle_framework"
if [[ "$signing_identity" == "-" ]]; then
    codesign --force --sign - "$APP"
else
    codesign --force --options runtime --timestamp --sign "$signing_identity" "$APP"
fi
codesign --verify --deep --strict --verbose=2 "$APP"
[[ "$(xcrun lipo "$APP/Contents/MacOS/AsteroidSquadron" -archs)" == arm64 ]] || { print -u2 'Expected an Apple Silicon-only executable.'; exit 1; }
for executable in "${sparkle_executables[@]}"; do
    [[ "$(xcrun lipo "$executable" -archs)" == arm64 ]] || { print -u2 'Expected Apple Silicon-only updater components.'; exit 1; }
done
print "Built: $APP"
