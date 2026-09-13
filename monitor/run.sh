#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
mkdir -p .build/module-cache AIBOUMonitor.app/Contents/MacOS AIBOUMonitor.app/Contents/Resources
xcrun swiftc -O -warnings-as-errors -parse-as-library -swift-version 5 \
  -module-cache-path "$PWD/.build/module-cache" -target "$(uname -m)-apple-macosx13.0" \
  Sources/*.swift -o AIBOUMonitor.app/Contents/MacOS/AIBOUMonitor
cp Info.plist AIBOUMonitor.app/Contents/Info.plist
cp PrivacyInfo.xcprivacy AIBOUMonitor.app/Contents/Resources/
/usr/bin/codesign --force --sign - AIBOUMonitor.app
if [[ "${1:-}" != "--build" ]]; then
  open AIBOUMonitor.app
fi
