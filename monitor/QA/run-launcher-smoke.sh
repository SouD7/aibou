#!/bin/bash
# Run after compiling .build/LauncherMonitorTests. Starts only a disposable, windowless test app.
set -euo pipefail
cd "$(dirname "$0")/.."
launcher_fixture_dir=$(mktemp -d /tmp/aibou-launcher-smoke.XXXXXX)
trap 'rm -rf "$launcher_fixture_dir"' EXIT
launcher_fixture_app="$launcher_fixture_dir/LauncherFixture.app"
mkdir -p "$launcher_fixture_app/Contents/MacOS"
cat > "$launcher_fixture_dir/Fixture.swift" <<'SWIFT'
import AppKit
@main struct Fixture {
    @MainActor static func main() throws {
        let app = NSApplication.shared
        app.setActivationPolicy(.prohibited)
        try Data("started".utf8).write(to: Bundle.main.bundleURL.appendingPathComponent("started.txt"))
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { app.terminate(nil) }
        app.run()
    }
}
SWIFT
cat > "$launcher_fixture_app/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleExecutable</key><string>LauncherFixture</string>
<key>CFBundleIdentifier</key><string>test.aibou.launcher.smoke.$(uuidgen)</string>
<key>CFBundleName</key><string>LauncherFixture</string>
<key>LSUIElement</key><true/>
</dict></plist>
PLIST
xcrun swiftc -parse-as-library -module-cache-path /tmp/aibou-consultation-module-cache "$launcher_fixture_dir/Fixture.swift" -o "$launcher_fixture_app/Contents/MacOS/LauncherFixture"
codesign --force --sign - "$launcher_fixture_app"
.build/LauncherMonitorTests --launcher-launch-smoke "$launcher_fixture_app"
