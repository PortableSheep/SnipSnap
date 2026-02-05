import AppKit
import SwiftUI

@MainActor
final class PreferencesWindowController {
  private var window: NSWindow?

  func show(prefs: OverlayPreferencesStore, proPrefs: ProPreferencesStore, license: LicenseManager) {
    if let window {
      AppActivation.bringToFront(window)
      return
    }

    let view = PreferencesRootView(prefs: prefs, proPrefs: proPrefs, license: license)
    let hosting = NSHostingView(rootView: view)

    let win = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 750, height: 520),
      styleMask: [.titled, .closable, .miniaturizable],
      backing: .buffered,
      defer: false
    )
    win.title = "Preferences"
    win.isReleasedWhenClosed = false
    win.contentView = hosting
    win.center()

    // Avoid mixing a manually-installed NSToolbar with SwiftUI toolbar bridging.
    // The SwiftUI view renders its own segmented control header.

    NotificationCenter.default.addObserver(
      forName: NSWindow.willCloseNotification,
      object: win,
      queue: .main
    ) { [weak self] _ in
      Task { @MainActor in
        self?.window = nil
      }
    }

    window = win
    AppActivation.bringToFront(win)
  }
}
