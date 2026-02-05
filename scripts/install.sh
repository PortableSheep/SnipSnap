#!/bin/bash
set -euo pipefail

# SnipSnap Installer
# Installs SnipSnap to /Applications and removes quarantine flag

APP_NAME="SnipSnapMac.app"
INSTALL_DIR="/Applications"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🔧 SnipSnap Installer"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# Check if app exists in same directory as script
if [[ ! -d "$SCRIPT_DIR/$APP_NAME" ]]; then
    echo "❌ $APP_NAME not found in $SCRIPT_DIR"
    echo "   Make sure the app is in the same folder as this script."
    exit 1
fi

# Kill running instance
if pgrep -f "$APP_NAME" > /dev/null 2>&1; then
    echo "⏹️  Stopping running SnipSnap..."
    pkill -f "$APP_NAME" || true
    sleep 1
fi

# Copy to Applications
echo "📥 Installing to $INSTALL_DIR..."
if [[ -d "$INSTALL_DIR/$APP_NAME" ]]; then
    rm -rf "$INSTALL_DIR/$APP_NAME"
fi
cp -R "$SCRIPT_DIR/$APP_NAME" "$INSTALL_DIR/"

# Remove quarantine flag (bypasses Gatekeeper for unsigned apps)
echo "🔓 Removing quarantine flag..."
xattr -rd com.apple.quarantine "$INSTALL_DIR/$APP_NAME" 2>/dev/null || true

# Register with LaunchServices
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
if [[ -x "$LSREGISTER" ]]; then
    "$LSREGISTER" -f "$INSTALL_DIR/$APP_NAME" > /dev/null 2>&1 || true
fi

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "✅ SnipSnap installed successfully!"
echo ""
echo "To launch: open -a SnipSnapMac"
echo "Or find it in your Applications folder."
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# Offer to launch
read -p "Launch SnipSnap now? [Y/n] " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Nn]$ ]]; then
    open "$INSTALL_DIR/$APP_NAME"
fi
