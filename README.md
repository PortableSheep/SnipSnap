# SnipSnapMac (native macOS pivot)

This folder is the start of a macOS-native Swift/AppKit app.

## Why XcodeGen?
We keep the project file generated from `project.yml` so it’s easy to review changes in git.

## Prereqs
- Xcode installed
- Install XcodeGen: `brew install xcodegen`

## Generate + Run
From repo root:

- `xcodegen generate`
- Open `SnipSnapMac.xcodeproj` in Xcode.
- Run the `SnipSnapMac` scheme.

## Dev permissions (Capture Agent)
If you’re developing without stable signing, macOS privacy grants (Screen Recording / Accessibility / Input Monitoring) can re-prompt frequently.

To make iteration smoother, capture runs in a separate helper app target:

- Run the `SnipSnapCaptureAgent` scheme once and grant permissions to the agent.
- Then run `SnipSnapMac` normally; it sends capture commands to the agent via local IPC.
- Rebuild the main app as often as you want; avoid rebuilding the agent unless needed.

## Local code signing (self-signed)
If Screen Recording permission won’t “stick” while ad-hoc signed, use a self-signed Code Signing certificate so the app has a stable signing identity across rebuilds.

1) Create a self-signed Code Signing certificate
- Open **Keychain Access** → **Certificate Assistant** → **Create a Certificate…**
- Name: `SnipSnap Local Dev` (must match `SNIPSNAP_CODE_SIGN_IDENTITY` in `project.yml`)
- Identity Type: **Self Signed Root**
- Certificate Type: **Code Signing**
- Create it in your **login** keychain

2) Trust it
- In Keychain Access, find the certificate → double click → **Trust** → set to **Always Trust**

3) Regenerate + build
- `xcodegen generate`
- Build/run `SnipSnapCaptureAgent` once, then enable permissions for the agent.

If you want to change the cert name later, update `SNIPSNAP_CODE_SIGN_IDENTITY` in `project.yml` and regenerate.

## Dev install (stable path)
Some macOS privacy permissions behave more reliably when the app lives at a stable path (instead of changing DerivedData build locations).

This repo’s `project.yml` includes a post-build step that copies the built apps into a stable Applications folder:

- Default install dir: `~/Applications`
- Override install dir: set env var `SNIPSNAP_DEV_INSTALL_DIR` (e.g. `/Applications` if you have write access)

To enable it:

- Run `xcodegen generate` (regenerates the Xcode project with the build script)

To debug the installed copy from Xcode:

- Xcode → Product → Scheme → Edit Scheme… → Run → Executable → “Other…”
- Pick `~/Applications/SnipSnap.app` (or your `SNIPSNAP_DEV_INSTALL_DIR`)

This keeps the bundle location stable while still using the debugger.

## Current functionality
- Menu bar app (no dock icon)
- Start/Stop screen recording (native ScreenCaptureKit + AVAssetWriter pipeline)
- Saves recordings into `~/Library/Application Support/SnipSnap/captures/`
- Dockable thumbnail strip window (drag near an edge to snap: left/right/top/bottom)
- Global hotkeys:
	- Cmd+Shift+6: start/stop recording
	- Cmd+Shift+S: show/hide strip
- Preferences (Cmd+,): click ripple color, HUD placement, overlay toggles
	- Includes live preview + tabs (Recording / Overlays / Hotkeys / About)

## Permissions
- Screen Recording: required for recording; macOS will prompt.
- Accessibility: required for global hotkeys on many setups, and for click/keystroke overlays.

Next step is adding overlays (clicks + keystrokes) and then bringing over annotations.
