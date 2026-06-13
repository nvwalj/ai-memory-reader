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

# --- Sign with Developer ID Application + hardened runtime (required to notarize) ---
# Override the identity for forks via AIMR_SIGN_ID.
SIGN_ID="${AIMR_SIGN_ID:-Developer ID Application: Kollo Inc. (LFUDWMQGY3)}"
echo "Signing with: $SIGN_ID"
codesign --force --deep --options runtime --timestamp --sign "$SIGN_ID" "$APP"
codesign --verify --strict --verbose=2 "$APP"

mkdir -p build/release
ZIP="build/release/AIMemoryReader-v${VERSION}-universal.zip"
( cd "$(dirname "$APP")" && ditto -c -k --sequesterRsrc --keepParent "AI Memory Reader.app" "$OLDPWD/$ZIP" )

# --- Notarize + staple (enabled when credentials are set; else the zip is signed-only) ---
# Option A: xcrun notarytool store-credentials <name> ...  then  export AIMR_NOTARY_PROFILE=<name>
# Option B: export AIMR_NOTARY_KEY=/path/AuthKey_XXXX.p8  AIMR_NOTARY_KEY_ID=XXXX  AIMR_NOTARY_ISSUER=<uuid>
if [ -n "${AIMR_NOTARY_PROFILE:-}" ]; then
  echo "Notarizing via keychain profile: $AIMR_NOTARY_PROFILE"
  xcrun notarytool submit "$ZIP" --keychain-profile "$AIMR_NOTARY_PROFILE" --wait
  xcrun stapler staple "$APP"
  ( cd "$(dirname "$APP")" && ditto -c -k --sequesterRsrc --keepParent "AI Memory Reader.app" "$OLDPWD/$ZIP" )
elif [ -n "${AIMR_NOTARY_KEY:-}" ]; then
  echo "Notarizing via API key: $AIMR_NOTARY_KEY_ID"
  xcrun notarytool submit "$ZIP" --key "$AIMR_NOTARY_KEY" --key-id "$AIMR_NOTARY_KEY_ID" --issuer "$AIMR_NOTARY_ISSUER" --wait
  xcrun stapler staple "$APP"
  ( cd "$(dirname "$APP")" && ditto -c -k --sequesterRsrc --keepParent "AI Memory Reader.app" "$OLDPWD/$ZIP" )
else
  echo "⚠ No notary credentials (AIMR_NOTARY_PROFILE or AIMR_NOTARY_KEY*) — zip is SIGNED but NOT notarized."
fi

cp "$ZIP" build/release/AIMemoryReader.zip
echo "Built $ZIP (+ AIMemoryReader.zip alias)"
