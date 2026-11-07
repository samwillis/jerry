#!/bin/zsh
set -eu
task_root="$(cd "$(dirname "$0")/.." && pwd)"
task_app="$task_root/build/TerrainFixture.app"
mkdir -p "$task_app/Contents/MacOS"
/usr/bin/swiftc -swift-version 6 "$task_root/scripts/fixtures/TerrainFixture.swift" -o "$task_app/Contents/MacOS/TerrainFixture"
cat > "$task_app/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleVersion</key><string>1</string>
<key>CFBundleDisplayName</key><string>Terrain Fixture</string>
<key>CFBundleExecutable</key><string>TerrainFixture</string>
<key>CFBundleIdentifier</key><string>com.jerry.terrainfixture</string>
<key>CFBundleName</key><string>Terrain Fixture</string>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$task_app"
print "Fixture: $task_app"
