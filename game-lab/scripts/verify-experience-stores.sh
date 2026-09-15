#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build/experience-store-cache QA/Experiences
xcrun swiftc -parse-as-library -swift-version 5 -target "$(uname -m)-apple-macosx13.0" \
  -module-cache-path .build/experience-store-cache \
  Sources/Core/*.swift Sources/Core/Experiences/*.swift \
  Sources/UI/Experiences/ExperienceStore.swift Sources/UI/Experiences/ExperienceProgressIndex.swift \
  Tests/StoreChecks/ExperienceStoreChecks.swift -o .build/experience-store-checks
.build/experience-store-checks
