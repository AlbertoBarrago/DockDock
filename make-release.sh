#!/bin/bash
set -e

BUNDLE_NAME="DockDock"
APP="/Applications/${BUNDLE_NAME}.app"
CONTENTS="${APP}/Contents"
MACOS="${CONTENTS}/MacOS"
RESOURCES="${CONTENTS}/Resources"

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

echo "▶ Done → /Applications/${BUNDLE_NAME}.app"
