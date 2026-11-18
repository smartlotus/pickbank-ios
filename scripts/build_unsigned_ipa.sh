#!/usr/bin/env bash
set -euo pipefail

# Build an unsigned Universal (iPhone + iPad) PickBank .ipa suitable for SideStore / AltStore / Sideloadly.
# Zero $99 paid Apple Developer Program account required.

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="${ROOT_DIR}/build"
PAYLOAD_DIR="${BUILD_DIR}/Payload"
IPA_PATH="${BUILD_DIR}/PickBank-iOS.ipa"

if ! xcodebuild -version >/dev/null 2>&1; then
  echo "Error: Full Xcode (xcodebuild) is required locally to package an iOS .ipa."
  echo "Tip: Open PickBank.xcodeproj in Xcode on any Mac, or run ./scripts/enable_cloud_ipa_ci.sh"
  echo "     after 'gh auth refresh -h github.com -s workflow' to build on GitHub Actions macos-26."
  exit 1
fi

rm -rf "${BUILD_DIR}"
mkdir -p "${PAYLOAD_DIR}"

echo "[1/4] Resolving Swift Package dependencies..."
xcodebuild \
  -project "${ROOT_DIR}/PickBank.xcodeproj" \
  -scheme PickBank \
  -resolvePackageDependencies

echo "[2/4] Building PickBank (Universal iPhone + iPad, Release, Unsigned)..."
xcodebuild \
  -project "${ROOT_DIR}/PickBank.xcodeproj" \
  -scheme PickBank \
  -configuration Release \
  -destination "generic/platform=iOS" \
  -derivedDataPath "${BUILD_DIR}/DerivedData" \
  CODE_SIGN_IDENTITY="" \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGNING_ALLOWED=NO \
  AD_HOC_CODE_SIGNING_ALLOWED=YES \
  clean build

APP_BUNDLE="$(find "${BUILD_DIR}/DerivedData/Build/Products/Release-iphoneos" -maxdepth 1 -name "*.app" | head -n 1)"
if [[ -z "${APP_BUNDLE}" || ! -d "${APP_BUNDLE}" ]]; then
  echo "Error: Could not find built PickBank.app bundle."
  exit 1
fi

echo "[3/4] Packaging Payload..."
cp -R "${APP_BUNDLE}" "${PAYLOAD_DIR}/"
if command -v codesign >/dev/null 2>&1; then
  codesign --force --deep --sign - "${PAYLOAD_DIR}/PickBank.app" 2>/dev/null || true
fi
(
  cd "${BUILD_DIR}"
  zip -qry "${IPA_PATH}" Payload
  shasum -a 256 PickBank-iOS.ipa > SHA256SUMS.txt
)

echo "[4/4] Done: ${IPA_PATH}"
ls -lh "${IPA_PATH}"
cat "${BUILD_DIR}/SHA256SUMS.txt"
