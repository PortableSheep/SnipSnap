#!/bin/bash
set -euo pipefail

# SnipSnap Installer
# Installs SnipSnap to /Applications and removes quarantine flag
# Can be run locally or via curl from remote

APP_NAME="SnipSnapMac.app"
INSTALL_DIR="/Applications"
GITHUB_REPO="portablesheep/snipsnap"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}" 2>/dev/null)" && pwd 2>/dev/null || echo "")"

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🔧 SnipSnap Installer"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# Check if running from remote (piped) or local
REMOTE_INSTALL=false
if [[ -z "$SCRIPT_DIR" ]] || [[ ! -d "$SCRIPT_DIR/$APP_NAME" ]]; then
    REMOTE_INSTALL=true
fi

if [[ "$REMOTE_INSTALL" == "true" ]]; then
    echo "📡 Remote install mode - downloading latest release..."
    
    # Create temp directory
    TEMP_DIR=$(mktemp -d)
    trap "rm -rf $TEMP_DIR" EXIT
    
    # Get latest release download URL
    echo "🔍 Finding latest release..."
    RELEASE_URL=$(curl -sL "https://api.github.com/repos/$GITHUB_REPO/releases/latest" | \
        grep -o '"browser_download_url": *"[^"]*\.zip"' | \
        head -1 | \
        sed 's/"browser_download_url": *"//' | \
        sed 's/"$//')
    
    if [[ -z "$RELEASE_URL" ]]; then
        echo "❌ Could not find latest release. Check https://github.com/$GITHUB_REPO/releases"
        exit 1
    fi
    
    VERSION=$(echo "$RELEASE_URL" | grep -o 'SnipSnap-[^/]*\.zip' | sed 's/SnipSnap-//' | sed 's/\.zip//')
    echo "📦 Downloading SnipSnap $VERSION..."
    
    # Download and extract
    curl -sL "$RELEASE_URL" -o "$TEMP_DIR/snipsnap.zip"
    unzip -q "$TEMP_DIR/snipsnap.zip" -d "$TEMP_DIR"
    
    SCRIPT_DIR="$TEMP_DIR"
fi

# Check if app exists
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
