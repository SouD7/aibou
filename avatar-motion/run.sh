#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"

mkdir -p .build/module-cache AIBOUAvatarMotion.app/Contents/MacOS AIBOUAvatarMotion.app/Contents/Resources/Assets
xcrun swiftc -O -warnings-as-errors -parse-as-library -swift-version 5 \
  -module-cache-path "$PWD/.build/module-cache" -target "$(uname -m)-apple-macosx13.0" \
  Sources/*.swift -o AIBOUAvatarMotion.app/Contents/MacOS/AIBOUAvatarMotion
cp Info.plist AIBOUAvatarMotion.app/Contents/Info.plist
cp -R Assets/. AIBOUAvatarMotion.app/Contents/Resources/Assets/
/usr/bin/codesign --force --sign - AIBOUAvatarMotion.app

if [[ "${1:-}" == "--build" ]]; then
  exit 0
elif [[ "${1:-}" == "--qa" ]]; then
  capture_dir="${2:-QA/captures}"
  if [[ "$capture_dir" != /* ]]; then capture_dir="$PWD/$capture_dir"; fi
  open -W AIBOUAvatarMotion.app --args --capture-dir "$capture_dir" --qa
elif [[ "${1:-}" == "--capture-dir" ]]; then
  capture_dir="${2:?--capture-dir requires a path}"
  if [[ "$capture_dir" != /* ]]; then capture_dir="$PWD/$capture_dir"; fi
  shift 2
  open -W AIBOUAvatarMotion.app --args --capture-dir "$capture_dir" "$@"
else
  open AIBOUAvatarMotion.app
fi
