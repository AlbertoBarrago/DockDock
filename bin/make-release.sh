#!/bin/bash
set -e

# Navigate to the project root regardless of where the script is invoked from.
cd "$(dirname "$0")/.."

BUNDLE_NAME="DockDock"
APP="/Applications/${BUNDLE_NAME}.app"
CONTENTS="${APP}/Contents"
MACOS="${CONTENTS}/MacOS"
RESOURCES="${CONTENTS}/Resources"
CERT="AAEDF6889C6461FDC8B5B9EEBB517897E32B5176"

echo "▶ Stopping running instance…"
pkill -x "${BUNDLE_NAME}" 2>/dev/null; sleep 0.3

echo "▶ Building ${BUNDLE_NAME} (release)…"
swift build -c release

mkdir -p "${MACOS}" "${RESOURCES}"

if ! diff -q "Info.plist" "${CONTENTS}/Info.plist" &>/dev/null; then
    cp "Info.plist" "${CONTENTS}/Info.plist"
fi

cp ".build/release/${BUNDLE_NAME}" "${MACOS}/${BUNDLE_NAME}"

if [ -f "${BUNDLE_NAME}.icns" ]; then
    cp "${BUNDLE_NAME}.icns" "${RESOURCES}/${BUNDLE_NAME}.icns"
fi

echo "▶ Signing…"
codesign --force --deep --sign "${CERT}" \
    --entitlements "${BUNDLE_NAME}.entitlements" \
    "${APP}"

echo "▶ Done → ${APP}"
