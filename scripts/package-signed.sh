#!/bin/zsh
# Build a Developer ID package. Credentials stay in the user's Keychain.
set -eu
if [[ $# -lt 2 || $# -gt 3 ]]; then
  print -u2 'Usage: ./scripts/package-signed.sh "Developer ID Application: Company (TEAMID)" TEAMID [notary-keychain-profile]'
  exit 2
fi
task_identity="$1"
task_team="$2"
task_profile="${3:-}"
task_root="$(cd "$(dirname "$0")/.." && pwd)"
task_arch="$(uname -m)"
# Keep signed bundles outside iCloud-synced Documents; Finder metadata can
# otherwise arrive after signing and invalidate strict verification.
task_derived="$HOME/Library/Developer/Jerry/SignedRelease"
if [[ "$task_identity" != 'Developer ID Application: '* ]]; then
  print -u2 'Use a Developer ID Application identity for direct distribution.'
  exit 2
fi
# Check that the matching certificate has its private key before building.
if ! /usr/bin/security find-identity -v -p codesigning | /usr/bin/grep -F -- "\"$task_identity\"" >/dev/null; then
  print -u2 'The specified signing identity and private key are not available in Keychain.'
  exit 1
fi
xcodebuild -project "$task_root/Jerry.xcodeproj" -scheme Jerry \
  -configuration Release -destination "platform=macOS,arch=$task_arch" \
  -derivedDataPath "$task_derived" ONLY_ACTIVE_ARCH=YES \
  CODE_SIGN_STYLE=Manual CODE_SIGNING_ALLOWED=YES \
  CODE_SIGN_IDENTITY="$task_identity" DEVELOPMENT_TEAM="$task_team" \
  ENABLE_HARDENED_RUNTIME=YES ENABLE_APP_SANDBOX=NO CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO \
  OTHER_CODE_SIGN_FLAGS=--timestamp build
# Use the fresh build directly; do not merge it into an older app bundle.
task_app="$task_derived/Build/Products/Release/Jerry.app"
/usr/bin/codesign --verify --deep --strict --verbose=2 "$task_app"
task_version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$task_app/Contents/Info.plist")
mkdir -p "$task_root/build/SignedDistribution"
task_zip="$task_root/build/SignedDistribution/Jerry-v$task_version-macos-$task_arch.zip"
/usr/bin/ditto -c -k --sequesterRsrc --keepParent "$task_app" "$task_zip"
if [[ -n "$task_profile" ]]; then
  xcrun notarytool submit "$task_zip" --keychain-profile "$task_profile" --wait
  xcrun stapler staple "$task_app"
  xcrun stapler validate "$task_app"
  /usr/sbin/spctl --assess --type execute --verbose=2 "$task_app"
  /usr/bin/ditto -c -k --sequesterRsrc --keepParent "$task_app" "$task_zip"
  print "Signed and notarised archive: $task_zip"
else
  print "Signed archive: $task_zip"
  print 'Not notarised. Supply a notarytool Keychain profile before distributing.'
fi
