#!/bin/zsh
set -eu
task_root="$(cd "$(dirname "$0")/.." && pwd)"
if [[ ! -f "$task_root/build/Build/Products/Debug/ExpeditionCore.o" ]]; then
  "$task_root/scripts/build.sh"
fi
mkdir -p "$task_root/build/Tools"
xcrun swiftc -parse-as-library -I "$task_root/build/Build/Products/Debug" \
  "$task_root/scripts/render-app-icon.swift" \
  "$task_root/OtherSock/Rendering/ExplorerRig.swift" \
  "$task_root/OtherSock/Rendering/PaintedPart.swift" \
  "$task_root/build/Build/Products/Debug/ExpeditionCore.o" \
  -o "$task_root/build/Tools/render-app-icon"
"$task_root/build/Tools/render-app-icon" "$task_root"
iconutil -c icns "$task_root/build/AppIcon.iconset" -o "$task_root/OtherSock/Resources/AppIcon.icns"
