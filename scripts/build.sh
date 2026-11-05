#!/bin/zsh
set -eu
task_root="$(cd "$(dirname "$0")/.." && pwd)"
task_arch="$(uname -m)"
xcodebuild -project "$task_root/OtherSock.xcodeproj" \
  -scheme OtherSock -configuration Debug -destination "platform=macOS,arch=$task_arch" \
  -derivedDataPath "$task_root/build" ONLY_ACTIVE_ARCH=YES CODE_SIGNING_ALLOWED=NO build
print "App: $task_root/build/Build/Products/Debug/OtherSock.app"
