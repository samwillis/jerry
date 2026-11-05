#!/bin/zsh
set -eu
task_root="$(cd "$(dirname "$0")/.." && pwd)"
task_arch="$(uname -m)"
xcodebuild -project "$task_root/OtherSock.xcodeproj" \
  -scheme OtherSock -configuration Release -destination "platform=macOS,arch=$task_arch" \
  -derivedDataPath "$task_root/build/Release" ONLY_ACTIVE_ARCH=YES CODE_SIGNING_ALLOWED=NO build
mkdir -p "$task_root/build/Distribution"
/usr/bin/ditto "$task_root/build/Release/Build/Products/Release/OtherSock.app" "$task_root/build/Distribution/OtherSock.app"
/usr/bin/ditto -c -k --sequesterRsrc --keepParent "$task_root/build/Distribution/OtherSock.app" "$task_root/build/Distribution/TheOtherSock-local-$task_arch.zip"
print "Local prototype: $task_root/build/Distribution/OtherSock.app"
print "Archive: $task_root/build/Distribution/TheOtherSock-local-$task_arch.zip"
print "Unsigned local build. Developer ID signing and notarisation are required before public distribution."
