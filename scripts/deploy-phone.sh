#!/bin/zsh
# Weekly re-deploy for the free personal team (7-day provisioning expiry).
# Usage: scripts/deploy-phone.sh   — iPhone plugged in (or on Wi-Fi) and unlocked.
#
# Device identity lives in scripts/local-devices.env (gitignored):
#   cp scripts/local-devices.env.example scripts/local-devices.env
set -euo pipefail
cd "$(dirname "$0")/.."

export DEVELOPER_DIR=${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}

DEVICES_FILE="scripts/local-devices.env"
# Caller env beats the file — including explicitly-empty WATCH_* to skip
# the watch. Remember what was set before the file overwrites it.
DEVICE_NAME_SET=${DEVICE_NAME+1};     DEVICE_NAME_ENV=${DEVICE_NAME-}
WATCH_BUILD_SET=${WATCH_BUILD_ID+1};  WATCH_BUILD_ENV=${WATCH_BUILD_ID-}
WATCH_INSTALL_SET=${WATCH_INSTALL_ID+1}; WATCH_INSTALL_ENV=${WATCH_INSTALL_ID-}
[[ -f "$DEVICES_FILE" ]] && source "$DEVICES_FILE"
[[ -n "$DEVICE_NAME_SET" ]] && DEVICE_NAME=$DEVICE_NAME_ENV
[[ -n "$WATCH_BUILD_SET" ]] && WATCH_BUILD_ID=$WATCH_BUILD_ENV
[[ -n "$WATCH_INSTALL_SET" ]] && WATCH_INSTALL_ID=$WATCH_INSTALL_ENV
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

# Watch deploy: requires Mac Bluetooth ON and the watch unlocked/on
# wrist. IDs beat display names (curly apostrophes match neither tool):
# xcodebuild wants the hardware UDID, devicectl the CoreDevice identifier.
#
# No `list devices` gate: a one-shot visibility check declares a merely
# not-yet-enumerated watch "unreachable" (it skipped a reachable watch
# 2026-07-21). Per CLAUDE.md, the install ATTEMPT is the contact that
# wakes the channel — build unconditionally and loop the install,
# grepping for "App installed:" (exit codes lie through pipes).
if [[ -n "$WATCH_BUILD_ID" && -n "$WATCH_INSTALL_ID" ]]; then
  echo "→ Building for the watch"
  # generic destination, not the device id: an id-destination build
  # TIMES OUT while the watch reads "Device is busy (Connecting…)" —
  # the exact state the install loop below is built to ride out
  # (2026-07-22; CLAUDE.md's generic-build lore).
  xcodebuild -project Onigiri.xcodeproj -scheme OnigiriWatch \
    -destination 'generic/platform=watchOS' \
    -derivedDataPath build \
    -allowProvisioningUpdates \
    build
  echo "→ Installing on the watch (early 4000/3002/IXRemote-6 errors are normal — retrying)"
  installed=""
  for attempt in {1..12}; do
    out=$(xcrun devicectl device install app --device "${WATCH_INSTALL_ID}" \
      build/Build/Products/Debug-watchos/OnigiriWatch.app 2>&1) || true
    if echo "$out" | grep -q "App installed:"; then
      echo "✓ Watch installed (attempt ${attempt})."
      installed=1
      break
    fi
    echo "  attempt ${attempt} failed — retrying in 10 s"
    sleep 10
  done
  if [[ -n "$installed" ]]; then
    echo "✓ Phone and watch deployed."
  else
    echo "✗ Watch install failed after 12 attempts — see CLAUDE.md deploy notes (wake the watch, check Mac Bluetooth, pkill CoreDeviceService)." >&2
    exit 1
  fi
else
  echo "✓ Phone deployed. (Watch not configured — skipped.)"
fi
