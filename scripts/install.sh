#!/bin/bash
set -euo pipefail

# SnipSnap Installer
# Downloads the latest signed & notarized release and installs to /Applications.
# Can be run locally or via: curl -fsSL <url> | bash

APP_NAME="SnipSnap.app"
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

# Verify code signature before installing
echo "🔏 Verifying code signature..."
if ! codesign --verify --deep --strict "$SCRIPT_DIR/$APP_NAME" 2>/dev/null; then
    echo "❌ Code signature verification failed!"
    echo "   The app may be corrupted or tampered with."
    echo "   Download a fresh copy from https://github.com/$GITHUB_REPO/releases"
    exit 1
fi
echo "   ✅ Code signature valid"

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

# Verify notarization (warning only — may fail offline or before ticket is cached)
if ! spctl --assess --type exec "$INSTALL_DIR/$APP_NAME" 2>/dev/null; then
    echo "⚠️  Could not verify notarization status."
    echo "   This is normal on first launch or when offline."
    echo "   macOS will verify notarization when you open the app."
fi

# Register with LaunchServices
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
if [[ -x "$LSREGISTER" ]]; then
    "$LSREGISTER" -f "$INSTALL_DIR/$APP_NAME" > /dev/null 2>&1 || true
fi

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "✅ SnipSnap installed successfully!"
echo ""
echo "To launch: open -a SnipSnap"
echo "Or find it in your Applications folder."
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# Offer to launch (skip prompt when piped via curl — stdin isn't a terminal)
if [ -t 0 ]; then
  read -p "Launch SnipSnap now? [Y/n] " -n 1 -r
  echo
  if [[ ! $REPLY =~ ^[Nn]$ ]]; then
    open "$INSTALL_DIR/$APP_NAME"
  fi
else
  echo "Launching SnipSnap..."
  open "$INSTALL_DIR/$APP_NAME"
fi
