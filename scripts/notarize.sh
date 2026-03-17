#!/bin/bash
# notarize.sh — Submit an app or DMG to Apple's notary service
#
# Usage:
#   ./scripts/notarize.sh <path-to-app-or-dmg>
#
# Required environment variables:
#   APPLE_ID            — Apple ID email for notarization
#   APPLE_ID_PASSWORD   — App-specific password (NOT your Apple ID password)
#   APPLE_TEAM_ID       — 10-character Apple Developer Team ID
#
# Examples:
#   ./scripts/notarize.sh build/Build/Products/Release/SnipSnap.app
#   ./scripts/notarize.sh SnipSnap-1.0.0.dmg

set -euo pipefail

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Validate inputs
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

if [[ $# -lt 1 ]]; then
    echo "❌ Usage: $0 <path-to-app-or-dmg>"
    exit 1
fi

TARGET_PATH="$1"

if [[ ! -e "$TARGET_PATH" ]]; then
    echo "❌ File not found: $TARGET_PATH"
    exit 1
fi

MISSING_VARS=()
[[ -z "${APPLE_ID:-}" ]] && MISSING_VARS+=("APPLE_ID")
[[ -z "${APPLE_ID_PASSWORD:-}" ]] && MISSING_VARS+=("APPLE_ID_PASSWORD")
[[ -z "${APPLE_TEAM_ID:-}" ]] && MISSING_VARS+=("APPLE_TEAM_ID")

if [[ ${#MISSING_VARS[@]} -gt 0 ]]; then
    echo "❌ Missing required environment variables:"
    for var in "${MISSING_VARS[@]}"; do
        echo "   • $var"
    done
    exit 1
fi

# Determine file type
case "$TARGET_PATH" in
    *.app)
        FILE_TYPE="app"
        ;;
    *.dmg)
        FILE_TYPE="dmg"
        ;;
    *)
        echo "❌ Unsupported file type: $TARGET_PATH"
        echo "   Provide a .app bundle or .dmg file."
        exit 1
        ;;
esac

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🔐 SnipSnap Notarization"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Target:    $TARGET_PATH"
echo "Type:      $FILE_TYPE"
echo "Apple ID:  $APPLE_ID"
echo "Team ID:   $APPLE_TEAM_ID"
echo ""

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Temp directory cleanup
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

TEMP_DIR=""

cleanup() {
    if [[ -n "$TEMP_DIR" && -d "$TEMP_DIR" ]]; then
        rm -rf "$TEMP_DIR"
    fi
}
trap cleanup EXIT

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Prepare submission artifact
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

if [[ "$FILE_TYPE" == "app" ]]; then
    TEMP_DIR="$(mktemp -d)"
    ZIP_PATH="$TEMP_DIR/SnipSnap.zip"
    echo "📦 Creating zip archive for submission..."
    ditto -c -k --keepParent "$TARGET_PATH" "$ZIP_PATH"
    SUBMIT_PATH="$ZIP_PATH"
else
    SUBMIT_PATH="$TARGET_PATH"
fi

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Submit to notary service
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

echo "🔐 Submitting to Apple notary service (timeout: 15 min)..."

SUBMIT_OUTPUT=""
SUBMIT_EXIT=0

SUBMIT_OUTPUT=$(xcrun notarytool submit "$SUBMIT_PATH" \
    --apple-id "$APPLE_ID" \
    --password "$APPLE_ID_PASSWORD" \
    --team-id "$APPLE_TEAM_ID" \
    --wait \
    --timeout 900 \
    2>&1) || SUBMIT_EXIT=$?

echo "$SUBMIT_OUTPUT"

# Extract submission ID for log retrieval on failure
SUBMISSION_ID=$(echo "$SUBMIT_OUTPUT" | grep -oE '[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}' | head -1 || true)

if [[ $SUBMIT_EXIT -ne 0 ]] || echo "$SUBMIT_OUTPUT" | grep -qi "invalid\|rejected"; then
    echo ""
    echo "❌ Notarization failed!"

    if [[ -n "$SUBMISSION_ID" ]]; then
        echo ""
        echo "📋 Fetching notarization log for submission $SUBMISSION_ID..."
        xcrun notarytool log "$SUBMISSION_ID" \
            --apple-id "$APPLE_ID" \
            --password "$APPLE_ID_PASSWORD" \
            --team-id "$APPLE_TEAM_ID" \
            2>&1 || true
    else
        echo "   Could not extract submission ID to fetch log."
    fi

    exit 1
fi

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Staple the notarization ticket
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

echo ""
echo "📎 Stapling notarization ticket..."
xcrun stapler staple "$TARGET_PATH"

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Verify the result
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

echo ""
echo "🔍 Verifying notarized artifact..."

if [[ "$FILE_TYPE" == "app" ]]; then
    codesign --verify --deep --strict "$TARGET_PATH"
    spctl --assess --type exec -v "$TARGET_PATH"
else
    spctl --assess --type open --context context:primary-signature -v "$TARGET_PATH"
fi

echo ""
echo "✅ Notarization complete: $TARGET_PATH"
