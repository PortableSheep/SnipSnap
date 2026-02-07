# SnipSnap

A powerful screen capture and annotation tool for macOS that actually stays out of your way. Built entirely in Swift, it lives in your menu bar and gives you professional-grade capture and editing tools without the subscription tax.

## Why SnipSnap?

I got tired of paying $30/year for screenshot tools that do too much or too little. SnipSnap started as a weekend project to scratch my own itch: I wanted CleanShot's polish with the flexibility of Skitch, minus the bloat and the recurring charges.

What makes it different:

- **Actually native**: Built with AppKit and ScreenCaptureKit. No Electron, no web views, just pure Swift. Launches in under a second and sips power like a properly behaved Mac app should.
- **Smart capture workflow**: Your screenshots land in a persistent strip that hugs the edge of your screen. One click to edit, drag to rearrange, or present them in sequence. No hunting through Finder.
- **Baked-in overlays**: Recording a demo? SnipSnap can burn click animations and keystroke HUDs directly into your video as you record. No post-processing needed.
- **OCR that works offline**: Screenshots get indexed automatically. Search for text in any capture without sending your data to someone's cloud.
- **Free. Actually free.** No trials, no paywalls, no "upgrade to unlock." Everything works. If you find it useful, toss a few bucks my way—but it's optional.

## Features

### Screen Recording

- **Region, window, or full screen** — Pick what you want to capture with familiar macOS selection tools
- **Click and keystroke overlays** — Visualize interactions as colored rings and floating keystroke bubbles
- **Audio capture** — System audio, microphone, or both
- **GIF export** — Convert recordings to GIFs without FFmpeg nonsense
- **Video trimming** — Cut the beginning or end right from the strip context menu

### Screenshots

- **Instant capture** — ⌘⇧4 for region, ⌘⇧5 for window (customizable)
- **Delayed capture** — 3, 5, or 10 second countdown for context menus and hover states
- **Window detection** — Automatically finds and highlights windows as you hover

### Annotation Editor

The editor is where SnipSnap shines. I wanted Skitch's ease of use without the "acquired by Evernote and left to rot" vibe.

- **Shapes & arrows** — Rectangles, lines, arrows with adjustable thickness and colors
- **Text & callouts** — Add labels with speech bubbles that actually look good
- **Numbered steps** — Auto-incrementing step markers for tutorials
- **Blur & pixelate** — Hide sensitive info with gaussian blur or mosaic
- **Spotlight** — Dim everything except what matters
- **Freehand marker** — Sketch with your trackpad (surprisingly usable)
- **Measurement tool** — Pixel-perfect dimensions between elements, with edge snapping
- **Device frames** — Wrap screenshots in MacBook, iPhone, or iPad mockups
- **Custom backgrounds** — Solid colors or gradients instead of boring transparency
- **Emoji stamps** — Sometimes ✨ says it better than words

Everything supports undo/redo, keyboard shortcuts, and you can save annotation templates for repetitive work.

### Organization

- **Dockable strip** — Thumbnails snap to any screen edge (top/bottom/left/right)
- **Session management** — Captures are grouped by session; clear them or keep them forever
- **OCR indexing** — Full-text search across all your screenshots (runs locally, not in the cloud)
- **iCloud sync** — Mirror captures to iCloud Drive as a backup (optional)
- **Presentation mode** — Full-screen slideshow through your captures with arrow keys

### Smart Features

- **Smart redaction** — Automatically detects 10+ types of PII (emails, phone numbers, SSNs, credit cards with Luhn validation, API keys, AWS keys, IP addresses, street addresses, dates of birth, account numbers, private keys) and suggests blur overlays. You can accept/dismiss individual suggestions or batch process. See [PII_REDACTION.md](docs/PII_REDACTION.md) for details.
- **Annotation templates** — Save frequently-used shapes/text as reusable templates
- **Metadata preservation** — Keeps creation dates, OCR data, and edit history

## Installation

### Quick Install

```bash
curl -fsSL https://raw.githubusercontent.com/portablesheep/snipsnap/main/scripts/install.sh | bash
```

This downloads the latest release and drops it in your Applications folder.

### Manual Install

Download the latest `.dmg` or `.zip` from the [Releases](https://github.com/portablesheep/snipsnap/releases) page, drag to Applications, and launch.

### First Launch

macOS will ask for two permissions:

1. **Screen Recording** — Required for captures (duh)
2. **Accessibility** — Needed for global hotkeys and overlay event capture

Grant both and you're set. The app lives in your menu bar as a scissors icon.

## Usage

### Basic Workflow

1. Hit **⌘⇧4** to grab a region or **⌘⇧5** for a window
2. Your capture appears in the strip (⌘⇧S to show/hide)
3. Click a thumbnail to open the editor
4. Annotate, export, or just leave it there for later

### Recording a Demo

1. Click the menu bar icon → Start Recording, or press **⌘⇧6**
2. Choose full screen, region, or specific window
3. Enable click/keystroke overlays if you want them
4. Do your thing
5. **⌘⇧6** again to stop
6. Video lands in the strip, ready to trim or export as GIF

### Hotkeys (All Customizable)

| Action | Default Shortcut |
|--------|----------|
| Start/stop recording | ⌘⇧6 |
| Capture region | ⌘⇧4 |
| Capture window | ⌘⇧5 |
| Show/hide strip | ⌘⇧S |
| Present session | ⌘⇧P |

## Building from Source

You'll need:
- Xcode 15+ (macOS 13 SDK)
- [XcodeGen](https://github.com/yonaskolb/XcodeGen)

```bash
brew install xcodegen
git clone https://github.com/portablesheep/snipsnap.git
cd snipsnap
xcodegen generate
open SnipSnapMac.xcodeproj
```

Hit **⌘R** to build and run.

### Code Signing for Development

macOS ties Screen Recording permission to your app's code signature. If you use ad-hoc signing (the default for local builds), the permission resets every time you rebuild. Annoying.

**Fix:** Create a self-signed certificate once:

1. Open **Keychain Access** → Certificate Assistant → Create a Certificate
2. Name: `SnipSnap Local Dev`
3. Type: Self Signed Root
4. Certificate Type: Code Signing
5. Double-click the cert → Trust → Always Trust
6. Regenerate the Xcode project: `xcodegen generate`

The project's `project.yml` already expects this certificate name. Change `SNIPSNAP_CODE_SIGN_IDENTITY` if you used something else.

Now rebuilds won't wipe your Screen Recording permission.

### Quick Build Script

```bash
./scripts/build-and-install.sh --release --launch
```

This builds, installs to `~/Applications`, and launches the app. Use `--release` to avoid debug dylib signing issues with self-signed certs.

## Architecture

SnipSnap uses a hub-and-spoke design with `AppDelegate` coordinating everything. The interesting bit is the XPC service isolation:

### XPC Service Architecture

Recording runs in a separate XPC service (`CaptureServiceXPC`) instead of the main app. Why?

1. **Stable code signature** — The XPC service binary doesn't change between builds, so its Screen Recording permission persists
2. **Privilege separation** — The main app handles UI and hotkeys; the XPC service owns ScreenCaptureKit
3. **Clean process isolation** — If the main app crashes, recordings continue; if recording crashes, the main app stays alive

Event forwarding is clever: the main app (which has Accessibility permission) captures clicks and keystrokes, then sends them to the XPC service every 33ms to bake into the video overlay. Bidirectional XPC with callbacks.

### Key Components

```
Sources/
  App/              Main app, menu bar, coordination
  Editor/           Annotation canvas and tools
  Strip/            Thumbnail strip window
  Recording/        ScreenCaptureKit wrapper
  Pro/              GIF export, OCR, cloud sync
  Hotkeys/          Global hotkey registration
  Preferences/      Settings UI
  Permissions/      Permission checks and prompts

CaptureServiceXPC/  Isolated capture service
```

### State Management

- **Combine-based**: `@Published` properties with UserDefaults persistence
- **Actor isolation**: Everything UI touches is `@MainActor`
- **Async/await**: XPC callbacks bridged via `withCheckedThrowingContinuation`

Captures live in `~/Library/Application Support/SnipSnap/captures/` with sidecar JSON for metadata (OCR text, redaction hints, etc).

## Tech Stack

- **Swift 5** — Pure Swift, no Objective-C bridging
- **AppKit** — Native UI, no SwiftUI for windows (SwiftUI for views only)
- **ScreenCaptureKit** — Modern capture API (macOS 13+)
- **AVFoundation** — Video encoding/decoding
- **Vision** — OCR text recognition
- **CoreGraphics** — Low-level canvas rendering

No third-party dependencies. XcodeGen generates the Xcode project from `project.yml` so it's not checked into Git.

## Donationware

SnipSnap is **completely free**. No trials, no feature limits, no nag screens.

If you find it useful and want to support development:

- **One-time**: [Stripe payment](https://buy.stripe.com/aFa6oHbuj9a9f2M4Hk5Ne02)
- **Monthly**: [GitHub Sponsors](https://github.com/sponsors/PortableSheep)

Every dollar goes toward keeping this maintained and adding features people actually want.

## Contributing

Pull requests are welcome. For major changes, open an issue first so we can discuss what you're trying to do.

If you're fixing a bug:
1. Fork and create a branch
2. Make your change with a clear commit message
3. Add a test if applicable (we don't have many, but we should)
4. Open a PR

If you're adding a feature:
1. Open an issue first to discuss scope
2. Same process as above

## Roadmap

Things I'm considering (no promises):

- [ ] Multi-monitor recording with separate audio sources
- [ ] Annotation presets (save colors/thickness as named styles)
- [ ] Pasteboard monitoring (auto-capture screenshots from other apps)
- [ ] Scripting support (AppleScript/JavaScript for Automation)
- [ ] Capture scheduling (time-based auto-capture)
- [ ] Video annotation (draw on videos, not just images)

Got ideas? Open an issue.

## License

MIT. See [LICENSE](LICENSE) for details.

## Credits

Built by [PortableSheep](https://github.com/portablesheep).

Inspired by CleanShot, Skitch, and Droplr—but cheaper and less annoying.

## FAQ

**Q: Does this work on macOS Monterey or earlier?**  
A: No. SnipSnap requires macOS 13 (Ventura) for ScreenCaptureKit.

**Q: Why not just use the built-in screenshot tool?**  
A: You should! It's great for basic captures. SnipSnap is for people who need annotations, session management, and recording features.

**Q: Can I use this commercially?**  
A: Yes. MIT license means do whatever you want, including commercial use.

**Q: Does SnipSnap send my screenshots anywhere?**  
A: Nope. OCR runs locally via the Vision framework. Cloud sync is optional and just mirrors to your own iCloud Drive.

**Q: Why did you make this?**  
A: I was paying for CleanShot but only used 20% of its features. Built SnipSnap to have exactly what I wanted, nothing more. Then figured others might want it too.

**Q: Can I disable the strip?**  
A: Yes, but why would you? It's the best part. (⌘⇧S to toggle visibility)

**Q: Will you add Windows/Linux support?**  
A: No. This is intentionally macOS-only to stay native and fast.
