#!/bin/bash
set -euo pipefail

# SnipSnap Build & Install Script
# Builds the app and installs it to ~/Applications
#
# NOTE: Debug builds may fail to launch due to code signing issues with
# Swift's debug dylib when using self-signed certificates. Use --release
# for development when running outside of Xcode.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
INSTALL_DIR="${SNIPSNAP_DEV_INSTALL_DIR:-$HOME/Applications}"

# Parse arguments
CONFIGURATION="Debug"
LAUNCH=false

while [[ $# -gt 0 ]]; do
    case $1 in
        -l|--launch)
            LAUNCH=true
            shift
            ;;
        -r|--release)
            CONFIGURATION="Release"
            shift
            ;;
        Debug|Release)
            CONFIGURATION="$1"
            shift
            ;;
        -h|--help)
            echo "Usage: $0 [options] [Debug|Release]"
            echo ""
            echo "Options:"
            echo "  -l, --launch    Launch the app after installing"
            echo "  -r, --release   Build Release configuration"
            echo "  -h, --help      Show this help"
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

cd "$PROJECT_DIR"

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🔧 SnipSnap Build & Install"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Configuration: $CONFIGURATION"
echo "Install Dir:   $INSTALL_DIR"
echo ""

# Check for xcodegen
if ! command -v xcodegen &> /dev/null; then
    echo "❌ xcodegen not found. Install with: brew install xcodegen"
    exit 1
fi

# Regenerate project
echo "📦 Regenerating Xcode project..."
xcodegen generate --quiet

# Build
echo "🔨 Building SnipSnapMac ($CONFIGURATION)..."
xcodebuild \
    -project SnipSnap.xcodeproj \
    -scheme SnipSnap \
    -configuration "$CONFIGURATION" \
    -quiet \
    build

# Get the built app path (must pass same configuration!)
DERIVED_DATA=$(xcodebuild -project SnipSnap.xcodeproj -scheme SnipSnap -configuration "$CONFIGURATION" -showBuildSettings 2>/dev/null | grep -m1 "BUILT_PRODUCTS_DIR" | awk '{print $3}')
APP_SRC="$DERIVED_DATA/SnipSnap.app"

if [[ ! -d "$APP_SRC" ]]; then
    echo "❌ Build output not found at: $APP_SRC"
    exit 1
fi

# Install
echo "📥 Installing to $INSTALL_DIR..."
mkdir -p "$INSTALL_DIR"
APP_DST="$INSTALL_DIR/SnipSnap.app"

# Kill running instance if any
if pgrep -f "SnipSnap.app" > /dev/null 2>&1; then
    echo "⏹️  Stopping running SnipSnap..."
    pkill -f "SnipSnap.app" || true
    sleep 1
fi

# Copy app
rm -rf "$APP_DST"
ditto "$APP_SRC" "$APP_DST"

# Register with LaunchServices
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
if [[ -x "$LSREGISTER" ]]; then
    "$LSREGISTER" -f "$APP_DST" > /dev/null 2>&1 || true
fi

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "✅ Installed to: $APP_DST"
echo ""
echo "To run:  open '$APP_DST'"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# Launch if requested
if [[ "$LAUNCH" == "true" ]]; then
    echo "🚀 Launching SnipSnap..."
    open "$APP_DST"
fi
