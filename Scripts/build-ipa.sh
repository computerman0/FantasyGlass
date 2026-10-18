#!/bin/bash
set -euo pipefail
PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_MODE="${1:-unsigned}"
if [[ "$(uname -s)" != "Darwin" ]] || ! command -v xcodebuild >/dev/null; then
  printf '%s\n' 'Building an iPhone app requires macOS and Xcode 26 or newer. This environment cannot produce a validated IPA.' >&2
  exit 1
fi
SDK_VERSION="$(xcrun --sdk iphoneos --show-sdk-version)"
if [[ "${SDK_VERSION%%.*}" -lt 26 ]]; then
  printf 'iOS SDK %s is too old; select stable Xcode 26 or newer.\n' "$SDK_VERSION" >&2
  exit 1
fi
SCHEME=FantasyGlass
CONFIGURATION=Release
case "$BUILD_MODE" in
  unsigned|signed-local) ;;
  signed-push) SCHEME=FantasyGlass-Push; CONFIGURATION=PushRelease ;;
  *) printf '%s\n' 'Usage: Scripts/build-ipa.sh unsigned|signed-local|signed-push [ExportOptions.plist]' >&2; exit 2 ;;
esac
python3 "$PROJECT_ROOT/Scripts/generate-project.py"
BUILD_ROOT="$PROJECT_ROOT/build/$BUILD_MODE"
mkdir -p "$BUILD_ROOT"
ARCHIVE_PATH="$BUILD_ROOT/FantasyGlass.xcarchive"
if [[ "$BUILD_MODE" == "unsigned" ]]; then
  xcodebuild -project "$PROJECT_ROOT/FantasyGlass.xcodeproj" -scheme "$SCHEME" -configuration "$CONFIGURATION" \
    -destination 'generic/platform=iOS' -archivePath "$ARCHIVE_PATH" \
    -derivedDataPath "$BUILD_ROOT/DerivedData" CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO archive
  PAYLOAD_STAGE="$(mktemp -d "$BUILD_ROOT/ipa-stage.XXXXXX")"
  trap 'rm -rf "$PAYLOAD_STAGE"' EXIT
  mkdir "$PAYLOAD_STAGE/Payload"
  ditto "$ARCHIVE_PATH/Products/Applications/FantasyGlass.app" "$PAYLOAD_STAGE/Payload/FantasyGlass.app"
  ditto -c -k --sequesterRsrc --keepParent "$PAYLOAD_STAGE/Payload" "$BUILD_ROOT/FantasyGlass-unsigned.ipa"
  printf 'Unsigned input for a compatible re-signing tool: %s\n' "$BUILD_ROOT/FantasyGlass-unsigned.ipa"
  printf '%s\n' 'This IPA cannot run on a normal iPhone until it is signed with a compatible app profile.'
else
  EXPORT_OPTIONS="${2:-$PROJECT_ROOT/Config/ExportOptions.local.plist}"
  if [[ ! -f "$EXPORT_OPTIONS" ]]; then
    printf '%s\n' 'Copy a Config/ExportOptions.*.plist template to ExportOptions.local.plist and set your team ID.' >&2
    exit 1
  fi
  xcodebuild -project "$PROJECT_ROOT/FantasyGlass.xcodeproj" -scheme "$SCHEME" -configuration "$CONFIGURATION" \
    -destination 'generic/platform=iOS' -archivePath "$ARCHIVE_PATH" \
    -derivedDataPath "$BUILD_ROOT/DerivedData" -allowProvisioningUpdates archive
  xcodebuild -exportArchive -archivePath "$ARCHIVE_PATH" -exportPath "$BUILD_ROOT/export" -exportOptionsPlist "$EXPORT_OPTIONS" -allowProvisioningUpdates
  printf 'Signed export: %s\n' "$BUILD_ROOT/export"
fi
