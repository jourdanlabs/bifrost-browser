#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MACOS_LOG="$(mktemp -t bifrost-browser-macos.XXXXXX.log)"
IOS_LOG="$(mktemp -t bifrost-browser-ios.XXXXXX.log)"
trap 'rm -f "$MACOS_LOG" "$IOS_LOG"' EXIT

run_xcodebuild() {
  local log="$1"
  shift
  if ! xcodebuild "$@" >"$log" 2>&1; then
    tail -200 "$log" >&2
    return 1
  fi
}

cd "$ROOT"

echo "== BIFROST Browser acceptance =="
echo "Repo: $ROOT"

echo "== Package tests =="
swift test
swift test --package-path Packages/AURORAKit
swift test --package-path Packages/HEIMDALLKit
swift test --package-path Packages/LUNAStore
swift test --package-path Packages/BIFROSTKit

echo "== Brake grep audit =="
! grep -rn "case authorize" Packages/HEIMDALLKit/Sources/
! grep -rn "\\.authorize" Packages/HEIMDALLKit/Sources/
! grep -rn "permit.*forever" Packages/

echo "== macOS substrate build =="
run_xcodebuild "$MACOS_LOG" \
  -project BareBonesBrowser.xcodeproj \
  -scheme BareBonesBrowser \
  -configuration Debug \
  -destination 'generic/platform=macOS' \
  CODE_SIGNING_ALLOWED=NO \
  build

echo "== iOS device substrate build =="
IOS_DESTINATION="${IOS_DESTINATION:-generic/platform=iOS}"
run_xcodebuild "$IOS_LOG" \
  -project BareBonesBrowser.xcodeproj \
  -scheme BareBonesBrowser \
  -configuration Debug \
  -destination "$IOS_DESTINATION" \
  CODE_SIGNING_ALLOWED=NO \
  build

echo "BIFROST Browser acceptance passed."
