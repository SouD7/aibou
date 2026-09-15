#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
mkdir -p .build/module-cache AIBOUGameLab.app/Contents/MacOS AIBOUGameLab.app/Contents/Resources
xcrun swiftc -O -warnings-as-errors -parse-as-library -swift-version 5 \
  -module-cache-path "$PWD/.build/module-cache" -target "$(uname -m)-apple-macosx13.0" \
  Sources/Core/*.swift Sources/Core/Experiences/*.swift Sources/UI/*.swift Sources/UI/Experiences/*.swift Sources/App/*.swift \
  Vendor/AvatarMotion/Sources/{Manifest,Motion,ImageProcessing,AvatarScene,RoomAnimation}.swift \
  -o AIBOUGameLab.app/Contents/MacOS/AIBOUGameLab
cp Info.plist AIBOUGameLab.app/Contents/Info.plist
./scripts/prepare-guide-resources.sh AIBOUGameLab.app/Contents/Resources
python3 scripts/prepare-workshop-sounds.py AIBOUGameLab.app/Contents/Resources
mkdir -p AIBOUGameLab.app/Contents/Resources/WorkshopArt
cp Art/workbench-v1.png Art/guide-presenting-v1.png AIBOUGameLab.app/Contents/Resources/WorkshopArt/
bash scripts/prepare-exhibition-resources.sh AIBOUGameLab.app/Contents/Resources
/usr/bin/codesign --force --sign - AIBOUGameLab.app
if [[ "${1:-}" != "--build" ]]; then
  open AIBOUGameLab.app
fi
