#!/bin/bash
set -e

cd "$(dirname "$0")/.."

BUNDLE_NAME="DockDock"
APP="/Applications/${BUNDLE_NAME}.app"
CONTENTS="${APP}/Contents"
MACOS="${CONTENTS}/MacOS"
RESOURCES="${CONTENTS}/Resources"

# Release builds require a real Apple Development cert — ad-hoc is not acceptable
# because macOS will kill the binary on any machine other than where it was signed.
CERT=$(security find-identity -v -p codesigning 2>/dev/null \
    | awk '/Apple Development/ && !/REVOKED/ { print $2; exit }')
if [ -z "${CERT}" ]; then
    echo "❌ No valid Apple Development cert found."
    echo "   Release builds must be signed with a real cert."
    echo "   Run: security find-identity -v -p codesigning"
    exit 1
fi

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

echo "▶ Signing (${CERT})…"
codesign --force --deep --sign "${CERT}" \
    --entitlements "${BUNDLE_NAME}.entitlements" \
    "${APP}"

# Reject a silently-invalid signature before the user tries to launch.
if ! codesign --verify --deep --strict "${APP}" 2>/dev/null; then
    echo "❌ Signature verification failed."
    exit 1
fi

echo "▶ Done → ${APP}"
