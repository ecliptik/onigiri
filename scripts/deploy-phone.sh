#!/bin/zsh
# Weekly re-deploy for the free personal team (7-day provisioning expiry).
# Usage: scripts/deploy-phone.sh   — iPhone plugged in (or on Wi-Fi) and unlocked.
set -euo pipefail
cd "$(dirname "$0")/.."

export DEVELOPER_DIR=${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}
DEVICE_NAME=${DEVICE_NAME:-"My iPhone"}

echo "→ Regenerating Xcode project"
xcodegen generate

echo "→ Building for device"
xcodebuild -project Onigiri.xcodeproj -scheme Onigiri \
  -destination "platform=iOS,name=${DEVICE_NAME}" \
  -derivedDataPath build \
  -allowProvisioningUpdates \
  build

APP=build/Build/Products/Debug-iphoneos/Onigiri.app
echo "→ Installing on ${DEVICE_NAME}"
xcrun devicectl device install app --device "${DEVICE_NAME}" "${APP}"

# Watch deploy (best effort): requires Mac Bluetooth ON and the watch
# unlocked. Skipped quietly when the watch isn't reachable.
WATCH_NAME=${WATCH_NAME:-"Micheal’s Apple Watch"}
if xcrun devicectl list devices 2>/dev/null | grep -q "Apple Watch"; then
  echo "→ Building for ${WATCH_NAME}"
  xcodebuild -project Onigiri.xcodeproj -scheme OnigiriWatch \
    -destination "platform=watchOS,name=${WATCH_NAME}" \
    -derivedDataPath build \
    -allowProvisioningUpdates \
    build
  echo "→ Installing on ${WATCH_NAME}"
  xcrun devicectl device install app --device "${WATCH_NAME}" \
    build/Build/Products/Debug-watchos/OnigiriWatch.app
  echo "✓ Phone and watch deployed."
else
  echo "✓ Phone deployed. (Watch not reachable — is Mac Bluetooth on? — skipped.)"
fi
