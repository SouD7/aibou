#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
mkdir -p .build/module-cache
sources=(../monitor/Sources/Common.swift)
for source in ../avatar-motion/Sources/*.swift; do
  if [[ "$(basename "$source")" != "App.swift" ]]; then sources+=("$source"); fi
done
monitor_sources=()
for source in ../monitor/Sources/*.swift; do
  if [[ "$(basename "$source")" != "App.swift" ]]; then monitor_sources+=("$source"); fi
done
xcrun swiftc -warnings-as-errors -parse-as-library -swift-version 5 \
  -module-cache-path "$PWD/.build/module-cache" -target "$(uname -m)-apple-macosx13.0" \
  "${monitor_sources[@]}" Sources/RoomConsultationView.swift Tests/ConsultationIntegrationTests.swift \
  -o .build/ConsultationIntegrationTests
.build/ConsultationIntegrationTests
for suite in HardwareRoomPolicy RoomSession; do
  xcrun swiftc -warnings-as-errors -parse-as-library -swift-version 5 \
    -module-cache-path "$PWD/.build/module-cache" -target "$(uname -m)-apple-macosx13.0" \
    "${sources[@]}" "Sources/${suite}.swift" "Tests/${suite}Tests.swift" -o ".build/${suite}Tests"
  ".build/${suite}Tests"
done
xcrun swiftc -warnings-as-errors -parse-as-library -swift-version 5 -D AIBOU_INTEGRATED \
  -module-cache-path "$PWD/.build/module-cache" -target "$(uname -m)-apple-macosx13.0" \
  "${sources[@]}" ../avatar-motion/Sources/App.swift Tests/AvatarWindowEventTests.swift \
  -o .build/AvatarWindowEventTests
.build/AvatarWindowEventTests
