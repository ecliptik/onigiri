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

echo "✓ Deployed. The watch app rides along; open the Watch app on the"
echo "  phone to update it if watchOS doesn't refresh it automatically."
