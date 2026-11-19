#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
app_path="${1:?Usage: verify-sparkle.sh app-path}"
python3 - "$app_path" "$PWD/Resources/SparklePublicKey.txt" <<'PYVERIFY'
import base64, pathlib, plistlib, subprocess, sys
app=pathlib.Path(sys.argv[1])
info=plistlib.loads((app/'Contents/Info.plist').read_bytes())
key=pathlib.Path(sys.argv[2]).read_text().strip()
assert info.get('SUPublicEDKey') == key and len(base64.b64decode(key, validate=True)) == 32, 'Update public key mismatch'
assert info.get('SUFeedURL') == 'https://raw.githubusercontent.com/brindy/AsteroidSquadron/main/app-updates/asteroid-squadron/appcast.xml', 'Unexpected update feed URL'
assert info.get('SURequireSignedFeed') and info.get('SUVerifyUpdateBeforeExtraction'), 'Signed update verification is disabled'
framework=app/'Contents/Frameworks/Sparkle.framework/Versions/B'
executables=[app/'Contents/MacOS/AsteroidSquadron', framework/'Sparkle', framework/'Autoupdate',
             framework/'Updater.app/Contents/MacOS/Updater',
             framework/'XPCServices/Installer.xpc/Contents/MacOS/Installer',
             framework/'XPCServices/Downloader.xpc/Contents/MacOS/Downloader']
for executable in executables:
    assert subprocess.check_output(['xcrun','lipo',str(executable),'-archs'],text=True).split() == ['arm64'], 'Unexpected updater architecture'
    displayed=subprocess.run(['codesign','--display','--entitlements','-','--xml',str(executable)],check=True,capture_output=True)
    assert b'invalid entitlements' not in displayed.stderr.lower(), 'Invalid updater entitlements'
    entitlements=displayed.stdout
    if entitlements.strip():
        values=plistlib.loads(entitlements)
        assert not values.get('com.apple.security.get-task-allow') and not values.get('get-task-allow'), 'Debug entitlement in updater'
linked=subprocess.check_output(['otool','-L',str(executables[0])],text=True)
assert '@rpath/Sparkle.framework/Versions/B/Sparkle' in linked, 'The app does not link the bundled updater'
print('PASS: Sparkle links correctly, requires signed feeds and downloads, and all app/updater executables contain only arm64.')
PYVERIFY
codesign --verify --deep --strict --verbose=2 "$app_path"
