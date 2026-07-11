#!/bin/zsh
# Weekly re-deploy for the free personal team (7-day provisioning expiry).
# Usage: scripts/deploy-phone.sh   — iPhone plugged in (or on Wi-Fi) and unlocked.
#
# Device identity lives in scripts/local-devices.env (gitignored):
#   cp scripts/local-devices.env.example scripts/local-devices.env
set -euo pipefail
cd "$(dirname "$0")/.."

DEVICES_FILE="scripts/local-devices.env"
[[ -f "$DEVICES_FILE" ]] && source "$DEVICES_FILE"
DEVICE_NAME=${DEVICE_NAME:-}
WATCH_BUILD_ID=${WATCH_BUILD_ID:-}
WATCH_INSTALL_ID=${WATCH_INSTALL_ID:-}

if [[ -z "$DEVICE_NAME" ]]; then
  echo "No device configured. Copy the example and fill in your devices:"
  echo "  cp scripts/local-devices.env.example $DEVICES_FILE"
  exit 1
fi

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
# unlocked/on wrist. Skipped quietly when unconfigured or unreachable.
# IDs beat display names (curly apostrophes match neither tool):
# xcodebuild wants the hardware UDID, devicectl the CoreDevice identifier.
if [[ -n "$WATCH_BUILD_ID" && -n "$WATCH_INSTALL_ID" ]] \
   && xcrun devicectl list devices 2>/dev/null | grep -q "Watch"; then
  echo "→ Building for the watch"
  xcodebuild -project Onigiri.xcodeproj -scheme OnigiriWatch \
    -destination "platform=watchOS,id=${WATCH_BUILD_ID}" \
    -derivedDataPath build \
    -allowProvisioningUpdates \
    build
  echo "→ Installing on the watch"
  xcrun devicectl device install app --device "${WATCH_INSTALL_ID}" \
    build/Build/Products/Debug-watchos/OnigiriWatch.app
  echo "✓ Phone and watch deployed."
else
  echo "✓ Phone deployed. (Watch unconfigured or unreachable — skipped.)"
fi
