#!/bin/zsh
set -eu
task_root="$(cd "$(dirname "$0")/.." && pwd)"
task_arch="$(uname -m)"
xcodebuild -project "$task_root/Jerry.xcodeproj" \
  -scheme Jerry -configuration Release -destination "platform=macOS,arch=$task_arch" \
  -derivedDataPath "$task_root/build/Release" ONLY_ACTIVE_ARCH=YES CODE_SIGNING_ALLOWED=NO build
mkdir -p "$task_root/build/Distribution"
/usr/bin/ditto "$task_root/build/Release/Build/Products/Release/Jerry.app" "$task_root/build/Distribution/Jerry.app"
/usr/bin/ditto -c -k --sequesterRsrc --keepParent "$task_root/build/Distribution/Jerry.app" "$task_root/build/Distribution/Jerry-local-$task_arch.zip"
print "Local prototype: $task_root/build/Distribution/Jerry.app"
print "Archive: $task_root/build/Distribution/Jerry-local-$task_arch.zip"
print "Unsigned local build. Developer ID signing and notarisation are required before public distribution."
