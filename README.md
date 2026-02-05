# SnipSnap

A native macOS screen capture and annotation app built with Swift and AppKit. Lives in your menu bar.

## What it does

**Capture:** Record your screen or capture regions/windows. Uses ScreenCaptureKit under the hood. Optional click and keystroke overlays baked into recordings.

**Annotate:** Full-featured image editor with arrows, shapes, blur/pixelate, numbered steps, callouts, text, freehand marker, spotlight, and more. Pixel-aware measurement tool too.

**Organize:** Captures show up in a dockable strip that snaps to screen edges. Click to edit, drag to present.

**Pro stuff:** GIF export, video trimming, OCR indexing, cloud sync, annotation templates.

## Installation

Install the latest release with a single command:

```bash
curl -fsSL https://raw.githubusercontent.com/portablesheep/snipsnap/main/scripts/install.sh | bash
```

Or download the DMG/ZIP from the [Releases](https://github.com/portablesheep/snipsnap/releases) page.

## Building from Source

Requires Xcode and [XcodeGen](https://github.com/yonaskolb/XcodeGen):

```bash
brew install xcodegen
xcodegen generate
open SnipSnapMac.xcodeproj
```

Run the `SnipSnapMac` scheme.

## Self-signed certificate (recommended for dev)

macOS ties Screen Recording permission to your app's code signature. With ad-hoc signing, permission resets every time you rebuild. To avoid this:

1. Open Keychain Access → Certificate Assistant → Create a Certificate
2. Name it `SnipSnap Local Dev`, type Self Signed Root, certificate type Code Signing
3. Double-click the cert → Trust → Always Trust
4. Regenerate the project (`xcodegen generate`)

The project already references this identity in `project.yml`. Change `SNIPSNAP_CODE_SIGN_IDENTITY` if you use a different name.

## Permissions

The app will prompt for:

- **Screen Recording** – required for capture
- **Accessibility** – required for global hotkeys and overlay event capture

## Hotkeys

Defaults (configurable in Preferences):

| Action | Shortcut |
|--------|----------|
| Start/stop recording | ⌘⇧6 |
| Show/hide strip | ⌘⇧S |
| Capture region | ⌘⇧4 |
| Capture window | ⌘⇧5 |

## Project layout

```
Sources/
  App/         – Main app (menu bar, capture coordination)
  Editor/      – Annotation editor and canvas
  Strip/       – Thumbnail strip window
  Recording/   – ScreenCaptureKit + AVAssetWriter pipeline
  Hotkeys/     – Global hotkey registration
  Pro/         – GIF export, OCR, cloud sync, templates
  Preferences/ – Settings UI
  Licensing/   – License validation

CaptureServiceXPC/  – XPC service for capture (stable signing target)
```

Captures are stored in `~/Library/Application Support/SnipSnap/captures/`.
