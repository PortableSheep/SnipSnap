# SnipSnap Development Guide

SnipSnap is a native macOS screen capture and annotation app built with Swift 5.0 and AppKit, targeting macOS 13.0+. **Free and open source donationware.**

## Building and Running

### Prerequisites

```bash
brew install xcodegen
```

### Generate Xcode Project

Always regenerate the project after pulling changes:

```bash
xcodegen generate
```

The Xcode project is generated from `project.yml` and should not be edited directly.

### Build Commands

**Via Xcode:**
```bash
open SnipSnapMac.xcodeproj
# Run the "SnipSnapMac" scheme
```

**Via Command Line:**
```bash
# Build and install to ~/Applications
./scripts/build-and-install.sh

# Build Release configuration
./scripts/build-and-install.sh --release

# Build and launch immediately
./scripts/build-and-install.sh --launch
```

**Important:** Debug builds may fail to launch due to code signing issues with Swift's debug dylib when using self-signed certificates. Use `--release` for development when running outside Xcode.

### Code Signing for Development

macOS ties Screen Recording permission to your app's code signature. With ad-hoc signing, permission resets on every rebuild.

**To avoid this:**
1. Open Keychain Access → Certificate Assistant → Create a Certificate
2. Name: `SnipSnap Local Dev`, Type: Self Signed Root, Certificate Type: Code Signing
3. Double-click the cert → Trust → Always Trust
4. Regenerate project: `xcodegen generate`

The project references `SNIPSNAP_CODE_SIGN_IDENTITY` in `project.yml`. Change this environment variable if using a different certificate name.

## Testing

No automated tests currently exist in the codebase.

## Architecture

### Component Structure

```
Sources/
  App/         – Main app (menu bar, capture coordination, AppDelegate)
  Editor/      – Annotation editor and canvas
  Strip/       – Thumbnail strip window and capture library
  Recording/   – ScreenCaptureKit + AVAssetWriter pipeline
  Hotkeys/     – Global hotkey registration
  Pro/         – GIF export, OCR, cloud sync, templates
  Preferences/ – Settings UI
  Licensing/   – License validation

CaptureServiceXPC/  – XPC service for capture (stable signing target)
```

Captures are stored in `~/Library/Application Support/SnipSnap/captures/`.

### Hub-and-Spoke Design

**`AppDelegate` is the central coordinator** that owns all major components:

- `CaptureServiceClient` - XPC IPC to capture service
- `StripWindowController` - capture library UI
- `EditorWindowController` - image editor
- `PresentationWindowController` - slideshow
- `HotKeyManager` - global hotkey registration
- `FloatingStopButtonController` - stop button during recording

All state changes flow through `AppDelegate` (`Sources/App/AppDelegate.swift`, 771 lines).

### XPC Service Isolation

The app uses **privilege separation** between main app and capture service:

- **Main app**: Owns hotkeys, event taps, UI state, preferences
- **XPC Service** (`CaptureServiceXPC`): Owns screen recording, ScreenCaptureKit, file I/O

**Protocol:** `CaptureServiceProtocol` (`Sources/IPC/CaptureServiceProtocol.swift`)
- Bidirectional communication via NSXPCConnection
- Main app sends settings/events, XPC returns status/errors
- Thread-safe via NSLock in `CaptureServiceClient`

**Event Forwarding Pattern:**
- Main app captures events (it has accessibility permissions)
- Timer-based forwarding to XPC service every 33ms
- XPC bakes clicks/keystrokes into video overlay

The XPC service shares code from `Sources/Recording` and `Sources/Permissions` via direct source inclusion in `project.yml`.

### State Management

**Three-tier pattern:**

1. **Observable Stores** (Combine `@Published`):
   - `StripState` - dock position, visibility, session tracking
   - `OverlayPreferencesStore` - overlay settings
   - `ProPreferencesStore` - pro feature settings
   - `LicenseManager` - @MainActor singleton for license state
   - `CaptureLibrary` - observable capture list with metadata

2. **UserDefaults Persistence** (via `didSet` observers):
   ```swift
   @Published var isVisible: Bool {
     didSet { UserDefaults.standard.set(isVisible, ...) }
   }
   ```

3. **Keychain for Sensitive Data**:
   - License tokens stored via `KeychainStore`

### Window Management

**AppKit NSPanel + SwiftUI hybrid:**

- Strip: floating NSPanel (non-activating, all-spaces, borderless)
- Editor: standard NSWindow with custom delegates for event handling
- Modals: SwiftUI sheets with async/await continuations
- SwiftUI content embedded via NSHostingView

Key files:
- `Sources/Strip/StripWindowController.swift`
- `Sources/Editor/EditorWindowController.swift`

### Async Patterns

Heavy use of `withCheckedThrowingContinuation` to bridge XPC callbacks to async/await:

```swift
func startFullScreenRecording(settings: CaptureServiceSettings) async throws {
  try await withCheckedThrowingContinuation { continuation in
    getProxy { proxy, error in
      proxy?.startFullScreenRecording(settings: settings) { _, errorMessage in
        if let error { continuation.resume(throwing: error) }
        else { continuation.resume() }
      }
    }
  }
}
```

### Actor Isolation

All UI-touching code marked `@MainActor`:

```swift
@MainActor final class AppDelegate: NSObject, NSApplicationDelegate
@MainActor final class StripState: ObservableObject
```

Tasks that need main thread explicitly use `@MainActor` context.

## Key Conventions

### Logging

Uses OSLog with subsystem pattern:

```swift
private let appLog = OSLog(subsystem: "com.snipsnap.Snipsnap", category: "AppDelegate")
```

Debug builds also write to `~/snipsnap-debug.log` via custom `debugLog()` function.

### Error Handling

Typed error enums implementing `LocalizedError`:

```swift
enum CaptureServiceError: Error, LocalizedError {
  case remoteError(String)
  case connectionFailed(String)
}
```

Remote errors from XPC are passed through and contextualized.

### Resource Management

- Weak closure captures to prevent retain cycles: `{ [weak self] in ... }`
- Explicit cleanup in deinit: `deinit { connection?.invalidate() }`
- XPC connections have invalidation handlers

### Singletons

Global state managed via explicit singletons with clear ownership:
- `DonationWindowController.shared`
- `HotKeyManager` (owned by AppDelegate)

Multi-window support via static registries:
- `EditorWindowController.windows[URL]` for editor windows

## Permissions

The app requires runtime permissions for:
- **Screen Recording** - for capture (prompted on first use)
- **Accessibility** - for global hotkeys and overlay event capture

Permissions are checked via `PermissionChecker` in `Sources/Permissions/`.

## Donation URLs

SnipSnap is donationware. Donation options:
- One-time: https://buy.stripe.com/aFa6oHbuj9a9f2M4Hk5Ne02
- Sponsorship: https://github.com/sponsors/PortableSheep

Implemented in `Sources/App/DonationWindowController.swift` with "Support Development ❤️" menu item.

## Environment Variables

- `SNIPSNAP_CODE_SIGN_IDENTITY` - Code signing identity name (default: "SnipSnap Local Dev")
- `SNIPSNAP_DEV_INSTALL_DIR` - Install directory for build script (default: ~/Applications)
