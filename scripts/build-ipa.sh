#!/usr/bin/env bash
# Builds an unsigned .ipa for sideloading. Run on the Mac from anywhere.
# Output: build/Goldfish-unsigned.ipa. On failure, prints the compiler errors only.
set -euo pipefail
cd "$(dirname "$0")/.."

CONFIG="${CONFIG:-Release}"
mkdir -p build

if [ ! -f App/Resources/GoogleService-Info.plist ]; then
  echo "warning: App/Resources/GoogleService-Info.plist is missing." >&2
  echo "         The app will run without Firebase: scripted fish and the sample chapter only." >&2
fi

xcodegen generate --quiet

if ! xcodebuild -project Goldfish.xcodeproj -scheme Goldfish -configuration "$CONFIG" \
  -sdk iphoneos -destination 'generic/platform=iOS' -derivedDataPath build/DerivedData \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" \
  build > build/xcodebuild.log 2>&1; then
  echo "Build failed. Errors:" >&2
  grep -E "error:" build/xcodebuild.log | sort -u | head -60 >&2 || true
  echo "--- last lines of build/xcodebuild.log ---" >&2
  tail -25 build/xcodebuild.log >&2
  exit 1
fi

APP="build/DerivedData/Build/Products/${CONFIG}-iphoneos/Goldfish.app"
rm -rf build/ipa build/Goldfish-unsigned.ipa
mkdir -p build/ipa/Payload
cp -R "$APP" build/ipa/Payload/
(cd build/ipa && zip -qry ../Goldfish-unsigned.ipa Payload)

echo "Built build/Goldfish-unsigned.ipa ($(du -h build/Goldfish-unsigned.ipa | cut -f1))"
grep -cE "warning:" build/xcodebuild.log | xargs -I{} echo "{} warning lines in build/xcodebuild.log"
