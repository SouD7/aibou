#!/bin/bash
set -euo pipefail

GAME_LAB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
UI_DERIVED_DATA="$GAME_LAB_DIR/.build/ui-tests"
UI_PROJECT="$GAME_LAB_DIR/AIBOUGameLabUITests.xcodeproj"
UI_SCHEME="AIBOUGameLabUITests"
UI_ARCH="$(uname -m)"
UI_MODE="${1:-test}"
if [ "$#" -gt 0 ]; then shift; fi

case "$UI_MODE" in
  build|test) ;;
  *)
    echo "Usage: $0 [build|test] [xcodebuild test options]" >&2
    echo "  build compiles the UI runner without launching the game or controlling the screen." >&2
    echo "  test requires a prebuilt game and uses the current desktop session." >&2
    exit 2
    ;;
esac

xcodebuild \
  -project "$UI_PROJECT" \
  -scheme "$UI_SCHEME" \
  -destination "platform=macOS,arch=$UI_ARCH" \
  -derivedDataPath "$UI_DERIVED_DATA" \
  build-for-testing -quiet

if [ "$UI_MODE" = "build" ]; then
  echo "UI test runner compiled. No UI tests were executed."
  exit 0
fi

GAME_LAB_APP="${AIBOU_GAME_LAB_APP:-$GAME_LAB_DIR/AIBOUGameLab.app}"
if [ ! -d "$GAME_LAB_APP" ]; then
  echo "Game bundle missing: $GAME_LAB_APP" >&2
  echo "Build the app first, or set AIBOU_GAME_LAB_APP to its absolute .app path." >&2
  exit 1
fi

GAME_LAB_BUNDLE_ID="$(/usr/libexec/PlistBuddy -c 'Print CFBundleIdentifier' "$GAME_LAB_APP/Contents/Info.plist")"
if [ "$GAME_LAB_BUNDLE_ID" != "local.aibou.gamelab" ]; then
  echo "Wrong app bundle identifier: $GAME_LAB_BUNDLE_ID" >&2
  exit 1
fi

# Register the explicitly selected build so XCUIApplication(bundleIdentifier:)
# can find a swiftc-built app without an application target in this test project.
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$GAME_LAB_APP"

UI_RESULT_PARENT="$GAME_LAB_DIR/QA/results"
mkdir -p "$UI_RESULT_PARENT"
UI_RESULT_PATH="$UI_RESULT_PARENT/ui-$(date +%Y%m%d-%H%M%S)-$$.xcresult"
echo "Running UI tests on the desktop. Result bundle: $UI_RESULT_PATH"
xcodebuild \
  -project "$UI_PROJECT" \
  -scheme "$UI_SCHEME" \
  -destination "platform=macOS,arch=$UI_ARCH" \
  -derivedDataPath "$UI_DERIVED_DATA" \
  -parallel-testing-enabled NO \
  -resultBundlePath "$UI_RESULT_PATH" \
  test-without-building "$@"

echo "UI tests passed. Inspect screenshots and diagnostics in: $UI_RESULT_PATH"
