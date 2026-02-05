import AppKit
import CoreGraphics
import Foundation

final class InputMonitoringPermission {
  static func hasAccess(prompt: Bool) -> Bool {
    if #available(macOS 10.15, *) {
      if CGPreflightListenEventAccess() {
        return true
      }
      if prompt {
        return CGRequestListenEventAccess()
      }
      return false
    }

    // Before Catalina, Input Monitoring privacy gating doesn't exist.
    return true
  }

  @MainActor
  static func showInstructionsAlert() {
    let alert = NSAlert()
    alert.alertStyle = .warning
    alert.messageText = "Enable Input Monitoring"
    alert.informativeText = "To show click/keystroke overlays, SnipSnap needs Input Monitoring permission.\n\nGo to System Settings → Privacy & Security → Input Monitoring, enable SnipSnap, then quit and relaunch the app."
    alert.addButton(withTitle: "Open Settings")
    alert.addButton(withTitle: "Not Now")

    let resp = alert.runModal()
    if resp == .alertFirstButtonReturn {
      // Trigger the system prompt (if eligible) and ensure a Settings row exists.
      NSApp.activate(ignoringOtherApps: true)
      _ = hasAccess(prompt: true)
      if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent") {
        NSWorkspace.shared.open(url)
      }
    }
  }
}
