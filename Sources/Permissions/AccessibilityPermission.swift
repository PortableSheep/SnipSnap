import AppKit
import Foundation

final class AccessibilityPermission {
  static func isTrusted(prompt: Bool) -> Bool {
    let key = kAXTrustedCheckOptionPrompt.takeRetainedValue() as NSString
    let options = [key: prompt] as CFDictionary
    return AXIsProcessTrustedWithOptions(options)
  }

  @MainActor
  static func showInstructionsAlert() {
    let alert = NSAlert()
    alert.alertStyle = .warning
    alert.messageText = "Enable Accessibility Permission"
    alert.informativeText = "To show click/keystroke overlays and support global hotkeys, SnipSnap needs Accessibility permission.\n\nGo to System Settings → Privacy & Security → Accessibility, enable SnipSnap, then quit and relaunch the app. (If you just clicked Allow, you may still need to toggle SnipSnap on in Settings.)"
    alert.addButton(withTitle: "Open Settings")
    alert.addButton(withTitle: "Not Now")

    let resp = alert.runModal()
    if resp == .alertFirstButtonReturn {
      // Trigger the system prompt (if eligible) and ensure a Settings row exists.
      NSApp.activate(ignoringOtherApps: true)
      _ = isTrusted(prompt: true)
      if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
        NSWorkspace.shared.open(url)
      }
    }
  }
}
