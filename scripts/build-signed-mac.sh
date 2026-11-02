#!/usr/bin/env bash
# Build + Developer ID sign (+ optional notarize) FlexDisplay on a Mac with Xcode.
# Usage:
#   export TEAM_ID=XXXXXXXXXX          # required — Apple Developer Team ID
#   export SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)"  # optional override
#   export NOTARIZE=1                  # optional — run notarytool (needs API key env below)
#   export APPLE_API_KEY_ID=...
#   export APPLE_API_ISSUER_ID=...
#   export APPLE_API_KEY_P8_PATH=/path/to/AuthKey_XXX.p8
#   ./scripts/build-signed-mac.sh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

PRODUCT_NAME="FlexDisplay"
BUNDLE_ID="com.cicadahk.flexdisplay"

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "此 script 只能喺 macOS + Xcode 跑（而家係 $(uname -s)）。" >&2
  exit 1
fi

if [[ -z "${TEAM_ID:-}" ]]; then
  echo "請設定 TEAM_ID（Apple Developer Team ID），例如：" >&2
  echo "  export TEAM_ID=ABCD1234XY" >&2
  exit 1
fi

if ! command -v xcodegen >/dev/null 2>&1; then
  echo "未安裝 xcodegen。建議: brew install xcodegen" >&2
  exit 1
fi

if [[ -z "${SIGN_IDENTITY:-}" ]]; then
  SIGN_IDENTITY="$(security find-identity -v -p codesigning 2>/dev/null | \
    sed -n 's/.*"\(Developer ID Application:[^"]*\)".*/\1/p' | head -1 || true)"
fi
if [[ -z "${SIGN_IDENTITY}" ]]; then
  echo "搵唔到 Keychain 入面嘅 Developer ID Application 證書。" >&2
  echo "請喺 Apple Developer → Certificates 建立／下載 Developer ID Application，" >&2
  echo "安裝入 Login Keychain，或手動：" >&2
  echo "  export SIGN_IDENTITY='Developer ID Application: Your Name (TEAMID)'" >&2
  security find-identity -v -p codesigning || true
  exit 1
fi

echo "==> XcodeGen"
xcodegen generate

echo "==> Archive (identity: $SIGN_IDENTITY, team: $TEAM_ID)"
rm -rf build/DerivedData build/FlexDisplay.xcarchive dist
mkdir -p build dist

xcodebuild \
  -project FlexDisplay.xcodeproj \
  -scheme FlexDisplay \
  -configuration Release \
  -derivedDataPath build/DerivedData \
  -archivePath build/FlexDisplay.xcarchive \
  archive \
  CODE_SIGN_STYLE=Manual \
  CODE_SIGN_IDENTITY="$SIGN_IDENTITY" \
  DEVELOPMENT_TEAM="$TEAM_ID" \
  PRODUCT_BUNDLE_IDENTIFIER="$BUNDLE_ID" \
  OTHER_CODE_SIGN_FLAGS="--timestamp" \
  ENABLE_HARDENED_RUNTIME=YES

APP_SRC="build/FlexDisplay.xcarchive/Products/Applications/${PRODUCT_NAME}.app"
test -d "$APP_SRC"
ditto "$APP_SRC" "dist/${PRODUCT_NAME}.app"

echo "==> Verify signature"
codesign --verify --deep --strict --verbose=2 "dist/${PRODUCT_NAME}.app"
codesign -dv --verbose=2 "dist/${PRODUCT_NAME}.app" || true

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "dist/${PRODUCT_NAME}.app/Contents/Info.plist")"
BUILD="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "dist/${PRODUCT_NAME}.app/Contents/Info.plist")"

if [[ "${NOTARIZE:-0}" == "1" ]]; then
  if [[ -z "${APPLE_API_KEY_ID:-}" || -z "${APPLE_API_ISSUER_ID:-}" || -z "${APPLE_API_KEY_P8_PATH:-}" ]]; then
    echo "NOTARIZE=1 需要 APPLE_API_KEY_ID、APPLE_API_ISSUER_ID、APPLE_API_KEY_P8_PATH" >&2
    exit 1
  fi
  echo "==> Notarize"
  ZIP_NOTARY="dist/${PRODUCT_NAME}-for-notary.zip"
  ditto -c -k --keepParent "dist/${PRODUCT_NAME}.app" "$ZIP_NOTARY"
  xcrun notarytool submit "$ZIP_NOTARY" \
    --key "$APPLE_API_KEY_P8_PATH" \
    --key-id "$APPLE_API_KEY_ID" \
    --issuer "$APPLE_API_ISSUER_ID" \
    --wait
  xcrun stapler staple "dist/${PRODUCT_NAME}.app"
  spctl --assess --type execute -vv "dist/${PRODUCT_NAME}.app" || true
fi

ZIP_NAME="${PRODUCT_NAME}-${VERSION}.${BUILD}-macOS.zip"
DMG_NAME="${PRODUCT_NAME}-${VERSION}.${BUILD}-macOS.dmg"
ditto -c -k --keepParent "dist/${PRODUCT_NAME}.app" "dist/${ZIP_NAME}"

STAGE="$(mktemp -d)"
ditto "dist/${PRODUCT_NAME}.app" "$STAGE/${PRODUCT_NAME}.app"
ln -sf /Applications "$STAGE/Applications"
hdiutil create -volname "$PRODUCT_NAME" -srcfolder "$STAGE" -ov -format UDZO "dist/${DMG_NAME}"
rm -rf "$STAGE"

echo ""
echo "完成（呢部 Mac 先簽到名；Linux CI runner／呢個 Linux box 簽唔到）。"
echo "  App:  dist/${PRODUCT_NAME}.app"
echo "  Zip:  dist/${ZIP_NAME}"
echo "  DMG:  dist/${DMG_NAME}"
echo "Bundle ID: $BUNDLE_ID"
