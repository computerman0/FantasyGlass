#!/bin/bash
set -euo pipefail
PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
if ! command -v xcodebuild >/dev/null; then
  printf '%s\n' 'Xcode is required for the iOS/SwiftData tests.' >&2
  exit 1
fi
python3 "$PROJECT_ROOT/Scripts/generate-project.py"
swift test --package-path "$PROJECT_ROOT/Core"
# Prefer an explicit simulator UDID from `xcrun simctl list devices available`.
SIM_DESTINATION="${1:-platform=iOS Simulator,name=iPhone 17}"
xcodebuild -project "$PROJECT_ROOT/FantasyGlass.xcodeproj" -scheme FantasyGlass -configuration Debug \
  -destination "$SIM_DESTINATION" -derivedDataPath "$PROJECT_ROOT/build/TestDerivedData" \
  CODE_SIGNING_ALLOWED=NO build-for-testing
if [[ "$SIM_DESTINATION" == *id=* ]]; then
  python3 "$PROJECT_ROOT/Scripts/smoke-ios.py" "$SIM_DESTINATION" "$PROJECT_ROOT/build/TestDerivedData/Build/Products/Debug-iphonesimulator/FantasyGlass.app"
fi
xcodebuild -project "$PROJECT_ROOT/FantasyGlass.xcodeproj" -scheme FantasyGlass -configuration Debug \
  -destination "$SIM_DESTINATION" -derivedDataPath "$PROJECT_ROOT/build/TestDerivedData" \
  -resultBundlePath "$PROJECT_ROOT/build/Tests-$(date +%Y%m%d-%H%M%S).xcresult" CODE_SIGNING_ALLOWED=NO test-without-building
