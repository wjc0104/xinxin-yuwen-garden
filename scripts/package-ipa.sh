#!/usr/bin/env bash
set -euo pipefail
APP="build/device/Build/Products/Release-iphoneos/XinxinGarden.app"
test -d "$APP"
mkdir -p build/package/Payload
cp -R "$APP" build/package/Payload/
APP="build/package/Payload/XinxinGarden.app"
while IFS= read -r -d '' item; do codesign --force --sign - "$item"; done < <(find "$APP" -type f -name '*.dylib' -print0)
while IFS= read -r -d '' item; do codesign --force --sign - "$item"; done < <(find "$APP" -type d -name '*.framework' -print0)
codesign --force --sign - "$APP"
codesign --verify --deep --strict "$APP"
test "$(/usr/libexec/PlistBuddy -c 'Print :MinimumOSVersion' "$APP/Info.plist")" = '15.0'
lipo "$APP/XinxinGarden" -verify_arch arm64
otool -l "$APP/XinxinGarden" > build/device-load-commands.txt
codesign -d --entitlements :- "$APP" > build/entitlements.plist 2>/dev/null || true
(
  cd build/package
  /usr/bin/zip -qry ../XinxinGarden-v0.1.0.ipa Payload
)
shasum -a 256 build/XinxinGarden-v0.1.0.ipa > build/SHA256SUMS.txt
python3 - <<'PY'
import json,plistlib,os
with open('build/package/Payload/XinxinGarden.app/Info.plist','rb') as f:p=plistlib.load(f)
report={'minimumOS':p['MinimumOSVersion'],'bundleID':p['CFBundleIdentifier'],'version':p['CFBundleShortVersionString'],'architectures':['arm64'],'calendarUsage':p.get('NSCalendarsUsageDescription'),'calendarFullAccessUsage':p.get('NSCalendarsFullAccessUsageDescription'),'deviceTested':False,'commit':os.environ.get('GITHUB_SHA')}
with open('build/package-verification.json','w') as f:json.dump(report,f,ensure_ascii=False,indent=2)
print(json.dumps(report,ensure_ascii=False,indent=2))
PY
