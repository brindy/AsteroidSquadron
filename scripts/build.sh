#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
APP="$PWD/build/Asteroid Squadron.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$PWD/.cache/clang"
xcrun swiftc -O -target "$(uname -m)-apple-macosx13.0" -module-cache-path "$PWD/.cache/clang" Sources/*.swift -o "$APP/Contents/MacOS/AsteroidSquadron" -framework AppKit -framework SceneKit
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleName</key><string>Asteroid Squadron</string>
<key>CFBundleDisplayName</key><string>Asteroid Squadron</string>
<key>CFBundleIdentifier</key><string>dev.brindy.asteroid-squadron</string>
<key>CFBundleExecutable</key><string>AsteroidSquadron</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleVersion</key><string>12</string>
<key>CFBundleShortVersionString</key><string>1.11</string>
<key>LSMinimumSystemVersion</key><string>13.0</string>
<key>NSHighResolutionCapable</key><true/>
<key>NSSupportsAutomaticGraphicsSwitching</key><true/>
<key>NSPrincipalClass</key><string>NSApplication</string>
<key>NSHumanReadableCopyright</key><string>Unofficial fan project. Star Wars and Battlestar Galactica belong to their respective owners.</string>
</dict></plist>
PLIST
codesign --force --sign - "$APP"
print "Built: $APP"
