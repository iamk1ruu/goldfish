#!/usr/bin/env bash
# One-time setup on the EC2 Mac. Safe to run again.
set -euo pipefail

echo "macOS $(sw_vers -productVersion), $(uname -m)"

if ! xcodebuild -version > /dev/null 2>&1; then
  echo "Xcode is not installed or not selected."
  echo "Install Xcode 26.2 or later (a free Apple ID can download it), then run:"
  echo "  sudo xcode-select -s /Applications/Xcode.app && sudo xcodebuild -license accept"
  exit 1
fi

XCODE_VERSION="$(xcodebuild -version | head -1 | awk '{print $2}')"
echo "Xcode $XCODE_VERSION"
if [ "$(printf '%s\n%s\n' "26.2" "$XCODE_VERSION" | sort -V | head -1)" != "26.2" ]; then
  echo "Xcode 26.2 or later is required for Firebase AI Logic hybrid inference." >&2
  exit 1
fi

xcodebuild -runFirstLaunch > /dev/null 2>&1 || echo "note: xcodebuild -runFirstLaunch needs sudo on some setups"

if ! command -v brew > /dev/null 2>&1; then
  echo "Homebrew is missing. Install it from https://brew.sh, then run this script again."
  exit 1
fi
command -v xcodegen > /dev/null 2>&1 || brew install xcodegen
echo "XcodeGen $(xcodegen --version 2>/dev/null | tail -1)"
swift --version | head -1

if xcrun simctl list runtimes | grep -q "iOS 26"; then
  echo "iOS 26 Simulator runtime: installed"
else
  echo "iOS 26 Simulator runtime: missing. For Simulator work run: xcodebuild -downloadPlatform iOS"
fi

cd "$(dirname "$0")/.."
if [ -f App/Resources/GoogleService-Info.plist ]; then
  echo "Firebase config: present"
else
  echo "Firebase config: missing. Copy it once from Windows: scripts/remote.ps1 -Action secrets"
fi
echo "Ready. Next: scripts/test-core.sh, then scripts/build-ipa.sh"
