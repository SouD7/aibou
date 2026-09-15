#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
mkdir -p .build/module-cache .build/sources AIBOU.app/Contents/MacOS AIBOU.app/Contents/Resources/Assets
# Give shared files distinct basenames and compile one immutable source snapshot.
sources=()
for area in avatar-motion monitor integrated; do
  for source in "../$area/Sources/"*.swift; do
    snapshot=".build/sources/${area}-$(basename "$source")"
    cp "$source" "$snapshot"
    sources+=("$snapshot")
  done
done
xcrun swiftc -O -warnings-as-errors -parse-as-library -swift-version 5 -D AIBOU_INTEGRATED \
  -module-cache-path "$PWD/.build/module-cache" -target "$(uname -m)-apple-macosx13.0" \
  "${sources[@]}" -o AIBOU.app/Contents/MacOS/AIBOU
cp Info.plist AIBOU.app/Contents/Info.plist
cp ../monitor/PrivacyInfo.xcprivacy AIBOU.app/Contents/Resources/
rsync -a --delete ../avatar-motion/Assets/ AIBOU.app/Contents/Resources/Assets/
mkdir -p AIBOU.app/Contents/Resources/StartupMotion
rsync -a --delete --include='sequence.json' --include='frame-*.png' --exclude='*' \
  ../Asset/StartupMotion/Smooth/ AIBOU.app/Contents/Resources/StartupMotion/
/usr/bin/codesign --force --sign - AIBOU.app
if [[ "${1:-}" != "--build" ]]; then
  open AIBOU.app --args "$@"
fi
