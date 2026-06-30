#!/bin/bash
set -e

cd "$(dirname "$0")/.."

BUNDLE_NAME="DockDock"
APP="/Applications/${BUNDLE_NAME}.app"

# Read version from Info.plist
VERSION=$(defaults read "$(pwd)/Info.plist" CFBundleShortVersionString 2>/dev/null || echo "1.0")
DMG_NAME="${BUNDLE_NAME}-${VERSION}.dmg"

# Build and install to /Applications first
echo "▶ Building release…"
bash bin/make-release.sh

# Staging area: app + /Applications symlink for drag-to-install
TMP_DIR=$(mktemp -d)
trap 'rm -rf "${TMP_DIR}"' EXIT

cp -R "${APP}" "${TMP_DIR}/"
ln -s /Applications "${TMP_DIR}/Applications"

# Re-sign with ad-hoc for distribution: Apple Development certs are device-restricted
# and are rejected by Gatekeeper on other Macs even after xattr -cr.
# Ad-hoc (-) produces a valid signature that works on any machine.
echo "▶ Re-signing ad-hoc for distribution…"
codesign --force --deep --sign - \
    --entitlements "${BUNDLE_NAME}.entitlements" \
    "${TMP_DIR}/${BUNDLE_NAME}.app"

# Produce compressed read-only DMG
echo "▶ Packaging ${DMG_NAME}…"
rm -f "${DMG_NAME}"
hdiutil create \
    -volname "${BUNDLE_NAME}" \
    -srcfolder "${TMP_DIR}" \
    -ov \
    -format UDZO \
    "${DMG_NAME}"

echo ""
echo "✅ ${DMG_NAME}"
echo ""
echo "⚠️  First-launch note for other Macs (Gatekeeper):"
echo "   Right-click DockDock.app → Open → Open Anyway"
echo "   or run once in Terminal:"
echo "   xattr -cr /Applications/${BUNDLE_NAME}.app"
