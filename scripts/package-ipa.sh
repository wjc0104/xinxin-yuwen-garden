#!/usr/bin/env bash
set -euo pipefail
APP="build/device/Build/Products/Release-iphoneos/XinxinGarden.app"
test -d "$APP"
mkdir -p build/package/Payload
cp -R "$APP" build/package/Payload/
APP="build/package/Payload/XinxinGarden.app"
while IFS= read -r -d '' item; do codesign --force --sign - "$item"; done < <(find "$APP" -type f -name '*.dylib' -print0)
while IFS= read -r -d '' item; do codesign --force --sign - "$item"; done < <(find "$APP" -type d -name '*.framework' -print0)
codesign --force --sign - --entitlements scripts/trollstore.entitlements "$APP"
codesign --verify --deep --strict "$APP"
test "$(/usr/libexec/PlistBuddy -c 'Print :MinimumOSVersion' "$APP/Info.plist")" = '15.0'
lipo "$APP/XinxinGarden" -verify_arch arm64
otool -l "$APP/XinxinGarden" > build/device-load-commands.txt
codesign -d --entitlements :- "$APP" > build/entitlements.plist 2>/dev/null || true
python3 - <<'PY'
import plistlib
p=plistlib.load(open('build/entitlements.plist','rb'))
assert p['application-identifier']=='TROLLTROLL.com.wm0104.xinxingarden'
assert p['keychain-access-groups']==['TROLLTROLL.com.wm0104.xinxingarden']
assert not p.get('get-task-allow') and not p.get('com.apple.private.security.no-sandbox')
PY
(
  cd build/package
  /usr/bin/zip -qry ../Xinyu-v0.0.5.ipa Payload
)
shasum -a 256 build/Xinyu-v0.0.5.ipa > build/SHA256SUMS.txt
python3 scripts/inspect-ipa.py build/Xinyu-v0.0.5.ipa --report build/ipa-inspection.json
python3 - <<'PY'
import json,plistlib,os
with open('build/package/Payload/XinxinGarden.app/Info.plist','rb') as f:p=plistlib.load(f)
report={'minimumOS':p['MinimumOSVersion'],'bundleID':p['CFBundleIdentifier'],'version':p['CFBundleShortVersionString'],'build':p['CFBundleVersion'],'orientations':p['UISupportedInterfaceOrientations'],'architectures':['arm64'],'calendarUsage':p.get('NSCalendarsUsageDescription'),'calendarFullAccessUsage':p.get('NSCalendarsFullAccessUsageDescription'),'deviceTested':False,'commit':os.environ.get('GITHUB_SHA')}
with open('build/package-verification.json','w') as f:json.dump(report,f,ensure_ascii=False,indent=2)
print(json.dumps(report,ensure_ascii=False,indent=2))
PY
