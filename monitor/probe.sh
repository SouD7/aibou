#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
mkdir -p .build/module-cache
sources=()
for source in Sources/*.swift; do
  if [[ "$source" != "Sources/App.swift" && "$source" != "Sources/MonitorStore.swift" ]]; then sources+=("$source"); fi
done
xcrun swiftc -O -warnings-as-errors -parse-as-library -swift-version 5 \
  -module-cache-path "$PWD/.build/module-cache" -target "$(uname -m)-apple-macosx13.0" \
  "${sources[@]}" QA/Probe.swift -o .build/MonitorProbe
.build/MonitorProbe "$@"
