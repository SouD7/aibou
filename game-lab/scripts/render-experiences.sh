#!/bin/bash
set -euo pipefail

# Compile a disposable native .app; never open the production app or its saves.
render_project="$(cd "$(dirname "$0")/.." && pwd)"
render_output="${1:-$render_project/QA/Experiences/rendered}"
if [[ $# -gt 0 ]]; then shift; fi
mkdir -p "$render_output"
render_output="$(cd "$render_output" && pwd)"
render_scratch="$(mktemp -d "${TMPDIR:-/tmp}/aibou-render-experiences.XXXXXX")"
trap 'rm -rf "$render_scratch"' EXIT
render_app="$render_scratch/RenderExperiences.app"
render_resources="$render_app/Contents/Resources"
mkdir -p "$render_app/Contents/MacOS" "$render_resources/WorkshopArt" "$render_scratch/module-cache"
cd "$render_project"
render_snapshot="$render_scratch/source"
mkdir -p "$render_snapshot/Sources" "$render_snapshot/Avatar" "$render_snapshot/Tools/Fixtures"
cp -R Sources/Core Sources/UI "$render_snapshot/Sources/"
cp Vendor/AvatarMotion/Sources/{Manifest,Motion,ImageProcessing,AvatarScene,RoomAnimation}.swift "$render_snapshot/Avatar/"
cp Tools/RenderExperiences.swift "$render_snapshot/Tools/"
cp Tools/Fixtures/*.swift "$render_snapshot/Tools/Fixtures/"
(
  cd "$render_snapshot"
  shasum -a 256 Sources/Core/*.swift Sources/Core/Experiences/*.swift Sources/UI/*.swift Sources/UI/Experiences/*.swift Avatar/*.swift Tools/RenderExperiences.swift Tools/Fixtures/*.swift
) > "$render_output/source-snapshot.sha256"
xcrun swiftc -Onone -warnings-as-errors -parse-as-library -swift-version 5 \
  -module-cache-path "$render_scratch/module-cache" -target "$(uname -m)-apple-macosx13.0" \
  "$render_snapshot"/Sources/Core/*.swift "$render_snapshot"/Sources/Core/Experiences/*.swift "$render_snapshot"/Sources/UI/*.swift "$render_snapshot"/Sources/UI/Experiences/*.swift \
  "$render_snapshot"/Avatar/*.swift "$render_snapshot"/Tools/RenderExperiences.swift "$render_snapshot"/Tools/Fixtures/*.swift -o "$render_app/Contents/MacOS/RenderExperiences"
cat > "$render_app/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>RenderExperiences</string>
<key>CFBundleIdentifier</key><string>local.aibou.render-experiences</string>
<key>CFBundleName</key><string>RenderExperiences</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>LSUIElement</key><true/>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
bash scripts/prepare-guide-resources.sh "$render_resources"
bash scripts/prepare-exhibition-resources.sh "$render_resources"
cp Art/workbench-v1.png Art/guide-presenting-v1.png "$render_resources/WorkshopArt/"
python3 scripts/prepare-workshop-sounds.py "$render_resources"
/usr/bin/codesign --force --sign - "$render_app"
"$render_app/Contents/MacOS/RenderExperiences" "$render_output" "$@"
