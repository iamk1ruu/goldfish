#!/usr/bin/env bash
# Opens each screen in the Simulator with fixture data and saves a PNG.
# Fixture mode skips Firebase and saving, and uses the scripted fish.
# Usage: scripts/screenshots.sh [screen ...]   Env: DEVICE, WAIT, APPEARANCE=dark
set -euo pipefail
cd "$(dirname "$0")/.."

DEVICE="${DEVICE:-iPhone 17}"
WAIT="${WAIT:-4}"
BUNDLE_ID="com.kiruu.goldfish"
SCREENS=("$@")
if [ ${#SCREENS[@]} -eq 0 ]; then
  SCREENS=(onboarding today chapter teach quiz review yourturn final report map settings diagnostics friends teachoff)
fi

mkdir -p build screenshots
xcodegen generate --quiet
if ! xcodebuild -project Goldfish.xcodeproj -scheme Goldfish -configuration Debug \
  -destination "platform=iOS Simulator,name=$DEVICE" -derivedDataPath build/DerivedData \
  build > build/simulator-build.log 2>&1; then
  echo "Simulator build failed:" >&2
  grep -E "error:" build/simulator-build.log | sort -u | head -60 >&2 || true
  exit 1
fi

APP="build/DerivedData/Build/Products/Debug-iphonesimulator/Goldfish.app"
xcrun simctl boot "$DEVICE" 2> /dev/null || true
xcrun simctl bootstatus "$DEVICE" -b > /dev/null
xcrun simctl ui "$DEVICE" appearance "${APPEARANCE:-light}"
xcrun simctl install "$DEVICE" "$APP"

for screen in "${SCREENS[@]}"; do
  xcrun simctl terminate "$DEVICE" "$BUNDLE_ID" 2> /dev/null || true
  xcrun simctl launch "$DEVICE" "$BUNDLE_ID" -GoldfishScreen "$screen" > /dev/null
  sleep "$WAIT"
  xcrun simctl io "$DEVICE" screenshot "screenshots/$screen.png" > /dev/null 2>&1
  echo "screenshots/$screen.png"
done
