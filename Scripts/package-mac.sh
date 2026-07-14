#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERSION="${BIFROST_VERSION:-0.1.3}"
BUILD_NUMBER="${BIFROST_BUILD_NUMBER:-$(date -u +%Y%m%d%H%M)}"
ARCH_SUFFIX="${BIFROST_ARCH_SUFFIX:-$(uname -m)}"
TEAM_ID="${BIFROST_TEAM_ID:-}"
NOTARY_PROFILE="${BIFROST_NOTARY_PROFILE:-}"
DEVELOPER_ID="${BIFROST_DEVELOPER_ID:-}"
APP_NAME="BIFROST"
PRODUCT_NAME="BIFROST Browser"
BUILD_ROOT="$ROOT/build"
ARCHIVE_PATH="$BUILD_ROOT/archive/$PRODUCT_NAME.xcarchive"
EXPORT_PATH="$BUILD_ROOT/export"
DOWNLOADS="$BUILD_ROOT/downloads"
STAGE="$BUILD_ROOT/dmg-stage"
EXPORT_OPTIONS="$BUILD_ROOT/export-options.plist"
APP_PATH="$EXPORT_PATH/$APP_NAME.app"
ZIP_PATH="$DOWNLOADS/$PRODUCT_NAME-$VERSION-$ARCH_SUFFIX.zip"
DMG_PATH="$DOWNLOADS/$PRODUCT_NAME-$VERSION-$ARCH_SUFFIX.dmg"

run() {
  printf '\n==> %s\n' "$*"
  "$@"
}

require_value() {
  local name="$1"
  local value="$2"
  if [[ -z "$value" ]]; then
    printf 'Set %s before running the signed release pipeline.\n' "$name" >&2
    exit 2
  fi
}

assert_exists() {
  if [[ ! -e "$1" ]]; then
    printf 'Missing required artifact: %s\n' "$1" >&2
    exit 1
  fi
}

require_value BIFROST_TEAM_ID "$TEAM_ID"
require_value BIFROST_NOTARY_PROFILE "$NOTARY_PROFILE"
require_value BIFROST_DEVELOPER_ID "$DEVELOPER_ID"

for command in xcodebuild xcrun codesign hdiutil ditto shasum; do
  command -v "$command" >/dev/null || {
    printf 'Required command is unavailable: %s\n' "$command" >&2
    exit 2
  }
done

rm -rf "$ARCHIVE_PATH" "$EXPORT_PATH" "$STAGE"
mkdir -p "$BUILD_ROOT/archive" "$EXPORT_PATH" "$DOWNLOADS" "$STAGE"

cat > "$EXPORT_OPTIONS" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>destination</key>
  <string>export</string>
  <key>method</key>
  <string>developer-id</string>
  <key>signingStyle</key>
  <string>automatic</string>
  <key>signingCertificate</key>
  <string>Developer ID Application</string>
  <key>teamID</key>
  <string>$TEAM_ID</string>
  <key>stripSwiftSymbols</key>
  <true/>
</dict>
</plist>
PLIST

cd "$ROOT"

run xcodebuild \
  -project BareBonesBrowser.xcodeproj \
  -scheme BareBonesBrowser \
  -configuration Release \
  -destination 'generic/platform=macOS' \
  -archivePath "$ARCHIVE_PATH" \
  DEVELOPMENT_TEAM="$TEAM_ID" \
  MARKETING_VERSION="$VERSION" \
  CURRENT_PROJECT_VERSION="$BUILD_NUMBER" \
  archive

run xcodebuild \
  -exportArchive \
  -archivePath "$ARCHIVE_PATH" \
  -exportPath "$EXPORT_PATH" \
  -exportOptionsPlist "$EXPORT_OPTIONS"

assert_exists "$APP_PATH"
run codesign --verify --deep --strict --verbose=2 "$APP_PATH"
printf '\n==> pre-notary Gatekeeper check (expected to reject until stapled)\n'
spctl -a -t exec -vv "$APP_PATH" || true

rm -f "$ZIP_PATH" "$DMG_PATH" "$DMG_PATH.sha256.txt" "$ZIP_PATH.sha256.txt"
run ditto -c -k --keepParent "$APP_PATH" "$ZIP_PATH"

run xcrun notarytool submit "$ZIP_PATH" --keychain-profile "$NOTARY_PROFILE" --wait
run xcrun stapler staple "$APP_PATH"
run xcrun stapler validate "$APP_PATH"
run spctl -a -t exec -vv "$APP_PATH"

cp -R "$APP_PATH" "$STAGE/$APP_NAME.app"
ln -s /Applications "$STAGE/Applications"
cat > "$STAGE/README.txt" <<README
$PRODUCT_NAME $VERSION

Drag BIFROST.app to Applications.

BIFROST is a browser-first verification browser. It stays quiet during normal
browsing and surfaces a judgement when a page or detected AI answer crosses a
configured verification threshold.

Answer checks are deterministic local heuristics, not factual guarantees.
README

run hdiutil create \
  -volname "$PRODUCT_NAME $VERSION" \
  -srcfolder "$STAGE" \
  -ov \
  -format UDZO \
  "$DMG_PATH"

run codesign --force --timestamp --sign "$DEVELOPER_ID" "$DMG_PATH"
run codesign --verify --verbose=2 "$DMG_PATH"
run xcrun notarytool submit "$DMG_PATH" --keychain-profile "$NOTARY_PROFILE" --wait
run xcrun stapler staple "$DMG_PATH"
run xcrun stapler validate "$DMG_PATH"
run spctl -a -t open --context context:primary-signature -vvv "$DMG_PATH"

shasum -a 256 "$DMG_PATH" > "$DMG_PATH.sha256.txt"
shasum -a 256 "$ZIP_PATH" > "$ZIP_PATH.sha256.txt"

printf '\nPackaged BIFROST Browser:\n'
printf '  App: %s\n' "$APP_PATH"
printf '  DMG: %s\n' "$DMG_PATH"
printf '  DMG sha256: %s\n' "$DMG_PATH.sha256.txt"
printf '  Zip: %s\n' "$ZIP_PATH"
