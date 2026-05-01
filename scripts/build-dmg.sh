#!/bin/bash
set -e

# ═══════════════════════════════════════════════════════════════
# Tooth Fairy — Build, Sign, Notarize, and create DMG
# ═══════════════════════════════════════════════════════════════
#
# Build flow:
#   archive → extract .app from xcarchive → re-sign → DMG → sign → notarize → staple.
#   `xcodebuild -exportArchive` is intentionally skipped because it corrupts
#   the binary in a way Apple's notary service rejects.
#
# Note: the underlying Xcode project file/scheme is still named "Moonlit"
# (the app's previous name) — only the produced product is "ToothFairy".
# Renaming Xcode plumbing is brittle, so we leave it.
#
# Prerequisites:
#   1. Paid Apple Developer account.
#   2. "Developer ID Application" certificate in Keychain.
#   3. notarytool keychain profile named "tapcut-notary" (shared with the
#      Tapcut app — same Apple ID + Team ID work for any of Mario's apps):
#
#      xcrun notarytool store-credentials "tapcut-notary" \
#          --apple-id "your@email.com" \
#          --team-id  "UNEZ2C9AKH" \
#          --password "your-app-specific-password"
#
#      (the alias is just a Keychain label; any profile tied to the same
#      Apple ID/team works regardless of the app being shipped. Override
#      the default by setting NOTARY_PROFILE=<alias> before running.)
#
# Usage:
#   ./scripts/build-dmg.sh
#
# Output:
#   dist/ToothFairy-vX.Y.Z.dmg (signed + notarized + stapled)
# ═══════════════════════════════════════════════════════════════

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
BUILD_DIR="$PROJECT_ROOT/build"
DIST_DIR="$PROJECT_ROOT/dist"
APP_NAME="Tooth Fairy"           # DMG volume label (display name, can have spaces)
BUNDLE_NAME="ToothFairy"          # actual .app bundle name produced by the build (no spaces)
ARCHIVE_NAME="ToothFairy"         # .xcarchive name
BUNDLE_ID="com.mario.ToothFairy"
TEAM_ID="${TEAM_ID:-UNEZ2C9AKH}"
NOTARY_PROFILE="${NOTARY_PROFILE:-tapcut-notary}"
ENTITLEMENTS_FILE="$PROJECT_ROOT/Moonlit/Moonlit.entitlements"

VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$PROJECT_ROOT/Moonlit/Info.plist" 2>/dev/null || echo "0.1.0")
DMG_NAME="ToothFairy-v$VERSION"

echo "═══ Building $APP_NAME v$VERSION ═══"
echo ""

# ── Step 1: Clean ──────────────────────────────────────────────────────────
echo "→ Cleaning..."
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR" "$DIST_DIR"

# ── Step 2: Archive ────────────────────────────────────────────────────────
echo "→ Archiving..."
cd "$PROJECT_ROOT"
xcodebuild archive \
    -project Moonlit.xcodeproj \
    -scheme Moonlit \
    -configuration Release \
    -archivePath "$BUILD_DIR/$ARCHIVE_NAME.xcarchive" \
    CODE_SIGN_IDENTITY="Developer ID Application" \
    DEVELOPMENT_TEAM="$TEAM_ID" \
    CODE_SIGN_STYLE=Manual \
    ENABLE_HARDENED_RUNTIME=YES \
    OTHER_CODE_SIGN_FLAGS="--timestamp --options runtime" \
    2>&1 | tail -5

if [ ! -d "$BUILD_DIR/$ARCHIVE_NAME.xcarchive" ]; then
    echo "✗ Archive failed"
    exit 1
fi
echo "✓ Archive created"

# ── Step 3: Extract .app + re-sign from scratch ────────────────────────────
echo "→ Extracting .app from archive..."
rm -rf "$BUILD_DIR/export"
mkdir -p "$BUILD_DIR/export"
cp -R "$BUILD_DIR/$ARCHIVE_NAME.xcarchive/Products/Applications/$BUNDLE_NAME.app" "$BUILD_DIR/export/"
APP_PATH="$BUILD_DIR/export/$BUNDLE_NAME.app"

if [ ! -d "$APP_PATH" ]; then
    echo "✗ App not found in archive"
    exit 1
fi
echo "✓ App extracted: $APP_PATH"

echo "→ Re-signing for notarization..."
DEVID_HASH=$(security find-identity -v -p codesigning | grep 'Developer ID Application' | head -1 | awk '{print $2}')
if [ -z "$DEVID_HASH" ]; then
    echo "✗ No Developer ID Application cert found in Keychain"
    exit 1
fi
codesign --remove-signature "$APP_PATH" 2>&1 || true
codesign --force --timestamp --options runtime --entitlements "$ENTITLEMENTS_FILE" --sign "$DEVID_HASH" "$APP_PATH" 2>&1
echo "✓ Signed with $DEVID_HASH"

# ── Step 4: Verify ─────────────────────────────────────────────────────────
echo "→ Verifying signature..."
codesign --verify --strict "$APP_PATH" 2>&1 && echo "✓ Signature valid" || echo "⚠ Signature issue"

# ── Step 5: Create DMG ─────────────────────────────────────────────────────
echo "→ Creating DMG..."
DMG_FINAL="$DIST_DIR/$DMG_NAME.dmg"
STAGING="$BUILD_DIR/dmg-staging"
rm -rf "$STAGING"
mkdir -p "$STAGING"
cp -R "$APP_PATH" "$STAGING/"
ln -s /Applications "$STAGING/Applications"

hdiutil create -volname "$APP_NAME" -srcfolder "$STAGING" -ov -format UDZO "$DMG_FINAL" 2>&1 | tail -2
rm -rf "$STAGING"

if [ ! -f "$DMG_FINAL" ]; then
    echo "✗ DMG creation failed"
    exit 1
fi
echo "✓ DMG created: $DMG_FINAL"

# ── Step 6: Sign DMG ───────────────────────────────────────────────────────
echo "→ Signing DMG..."
codesign --force --sign "$DEVID_HASH" --timestamp "$DMG_FINAL" 2>&1
echo "✓ DMG signed"

# ── Step 7: Notarize ───────────────────────────────────────────────────────
echo "→ Submitting for notarization (keychain profile: $NOTARY_PROFILE)..."
NOTARY_OUT=$(xcrun notarytool submit "$DMG_FINAL" --keychain-profile "$NOTARY_PROFILE" --wait 2>&1)
echo "$NOTARY_OUT"

if echo "$NOTARY_OUT" | grep -q "status: Accepted"; then
    echo "✓ Notarization successful"
    echo "→ Stapling..."
    xcrun stapler staple "$DMG_FINAL" 2>&1
    xcrun stapler validate "$DMG_FINAL"
    echo "✓ Stapled"
elif echo "$NOTARY_OUT" | grep -q "status: Invalid"; then
    SUBMISSION_ID=$(echo "$NOTARY_OUT" | grep -m1 "id:" | awk '{print $2}')
    echo ""
    echo "✗ Notarization rejected. Fetching log..."
    xcrun notarytool log "$SUBMISSION_ID" --keychain-profile "$NOTARY_PROFILE"
    exit 1
else
    echo ""
    echo "⚠ Notarization failed or credentials not set up yet."
    echo "  Set up with:"
    echo "    xcrun notarytool store-credentials \"$NOTARY_PROFILE\" \\"
    echo "      --apple-id \"your@email.com\" \\"
    echo "      --team-id \"$TEAM_ID\" \\"
    echo "      --password \"app-specific-password\""
    echo ""
    echo "  Unsigned DMG: $DMG_FINAL"
fi

# ── Stable-filename copy ───────────────────────────────────────────────────
# Maintain `dist/ToothFairy.dmg` alongside the versioned DMG so the website's
# "Download for macOS" button can use a permalink that survives version bumps:
#   https://github.com/Necioterco/tooth-fairy/releases/latest/download/ToothFairy.dmg
DMG_STABLE="$DIST_DIR/ToothFairy.dmg"
cp "$DMG_FINAL" "$DMG_STABLE"
echo "✓ Stable copy: $DMG_STABLE"

# ── Done ───────────────────────────────────────────────────────────────────
echo ""
echo "═══ Build complete ═══"
echo "  App:    $APP_PATH"
echo "  DMG:    $DMG_FINAL"
echo "  Stable: $DMG_STABLE"
echo "  Size:   $(du -h "$DMG_FINAL" | cut -f1)"
echo ""
echo "→ To publish:"
echo "    gh release create v$VERSION \"$DMG_FINAL\" \"$DMG_STABLE\" \\"
echo "        --title \"Tooth Fairy v$VERSION\" --notes \"…\""
