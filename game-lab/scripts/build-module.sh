#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

# Keep the learning implementation in its own module: the integrated app has
# its own avatar types, and the standalone app keeps its existing entry point.
build_directory="${1:-$PWD/.build/integration}"
mkdir -p "$build_directory"
build_directory="$(cd "$build_directory" && pwd)"
mkdir -p "$build_directory/module-cache" "$build_directory/sources"
sources=()
for directory in Sources/Core Sources/UI Sources/Integration Vendor/AvatarMotion/Sources; do
  if [[ ! -d "$directory" ]]; then
    echo "Missing learning source directory: $directory" >&2
    exit 1
  fi
done
while IFS= read -r source; do
  snapshot="$build_directory/sources/$source"
  mkdir -p "$(dirname "$snapshot")"
  cp "$source" "$snapshot"
  sources+=("$snapshot")
done < <(find Sources/Core Sources/UI Sources/Integration Vendor/AvatarMotion/Sources \
  -type f -name '*.swift' | LC_ALL=C sort)

xcrun swiftc -O -warnings-as-errors -parse-as-library -swift-version 5 \
  -module-name AIBOULearning -emit-module -emit-library -static \
  -emit-module-path "$build_directory/AIBOULearning.swiftmodule" \
  -module-cache-path "$build_directory/module-cache" \
  -target "$(uname -m)-apple-macosx13.0" \
  "${sources[@]}" -o "$build_directory/libAIBOULearning.a"
