#!/bin/bash
# Direct-distribution (GitHub zip) release build.
#
# IMPORTANT: pass CODE_SIGN_ENTITLEMENTS="" — the Release config's sandboxed
# entitlements are for the Mac App Store submission only. The GitHub zip ships
# UNSANDBOXED: the update checker needs network, and folder access must work
# without grant prompts. v0.4.11/v0.4.12 were accidentally built sandboxed and
# broke "Check for Updates" with a hostname-not-found error. Don't repeat that.
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION=$(grep -m1 'MARKETING_VERSION' project.yml | sed 's/.*"\(.*\)"/\1/')
xcodegen generate
xcodebuild -project AIMemoryReader.xcodeproj -scheme AIMemoryReader \
  -configuration Release -destination 'platform=macOS' \
  ARCHS='arm64 x86_64' ONLY_ACTIVE_ARCH=NO \
  CODE_SIGN_ENTITLEMENTS="" \
  -derivedDataPath build/dd build | grep -E '^\*\*' || true

APP="build/dd/Build/Products/Release/AI Memory Reader.app"
# Guard: the GitHub zip must never be sandboxed.
if codesign -d --entitlements - "$APP" 2>/dev/null | grep -q app-sandbox; then
  echo "ERROR: build is sandboxed — wrong entitlements for the GitHub zip" >&2
  exit 1
fi

mkdir -p build/release
( cd "$(dirname "$APP")" && ditto -c -k --sequesterRsrc --keepParent "AI Memory Reader.app" \
    "$OLDPWD/build/release/AIMemoryReader-v${VERSION}-universal.zip" )
cp "build/release/AIMemoryReader-v${VERSION}-universal.zip" build/release/AIMemoryReader.zip
echo "Built build/release/AIMemoryReader-v${VERSION}-universal.zip (+ AIMemoryReader.zip alias)"
