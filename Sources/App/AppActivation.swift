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
}
