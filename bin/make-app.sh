#!/bin/bash
set -e

cd "$(dirname "$0")/.."

BUNDLE_NAME="DockDock"
APP="/Applications/${BUNDLE_NAME}.app"
CONTENTS="${APP}/Contents"
MACOS="${CONTENTS}/MacOS"
RESOURCES="${CONTENTS}/Resources"

# Pick the first non-revoked Apple Development cert automatically.
# Falls back to ad-hoc (-) so the script works without a paid developer account.
CERT=$(security find-identity -v -p codesigning 2>/dev/null \
    | awk '/Apple Development/ && !/REVOKED/ { print $2; exit }')
if [ -z "${CERT}" ]; then
    CERT="-"
    echo "⚠️  No valid Apple Development cert found — using ad-hoc signing (local use only)"
fi

echo "▶ Building ${BUNDLE_NAME} (debug)…"
swift build -c debug

mkdir -p "${MACOS}" "${RESOURCES}"

if ! diff -q "Info.plist" "${CONTENTS}/Info.plist" &>/dev/null; then
    cp "Info.plist" "${CONTENTS}/Info.plist"
fi

cp ".build/debug/${BUNDLE_NAME}" "${MACOS}/${BUNDLE_NAME}"

if [ -f "${BUNDLE_NAME}.icns" ]; then
    cp "${BUNDLE_NAME}.icns" "${RESOURCES}/${BUNDLE_NAME}.icns"
fi

echo "▶ Signing (${CERT})…"
codesign --force --deep --sign "${CERT}" \
    --entitlements "${BUNDLE_NAME}.entitlements" \
    "${APP}"

# Sanity-check: reject a silently-invalid signature before the user tries to launch.
if ! codesign --verify --deep --strict "${APP}" 2>/dev/null; then
    echo "❌ Signature verification failed — the app will be killed by macOS on launch."
    echo "   Try: security find-identity -v -p codesigning"
    exit 1
fi

echo "▶ Done → ${APP}"
