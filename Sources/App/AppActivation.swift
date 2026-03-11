import AppKit

enum AppActivation {
  @MainActor
  static func bringAppToFront() {
    NSRunningApplication.current.activate(options: [.activateAllWindows, .activateIgnoringOtherApps])
    NSApp.activate(ignoringOtherApps: true)
  }

  @MainActor
  static func bringToFront(_ window: NSWindow?) {
    bringAppToFront()
    guard let window else { return }
    window.makeKeyAndOrderFront(nil)
    window.orderFrontRegardless()
  }

  /// Switch to .regular so the app appears in Cmd+Tab.
  @MainActor
  static func showInAppSwitcher() {
    guard NSApp.activationPolicy() != .regular else { return }
    NSApp.setActivationPolicy(.regular)
    // Activate to make the Dock icon + switcher icon appear immediately
    NSApp.activate(ignoringOtherApps: true)
  }

  /// Switch back to .accessory (menu bar only, no Cmd+Tab).
  @MainActor
  static func hideFromAppSwitcher() {
    guard NSApp.activationPolicy() != .accessory else { return }
    NSApp.setActivationPolicy(.accessory)
  }
}
