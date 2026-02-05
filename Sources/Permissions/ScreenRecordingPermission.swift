import AppKit
import CoreGraphics
import Foundation
import ScreenCaptureKit

final class ScreenRecordingPermission {
  /// Check if screen recording permission is granted.
  /// The `prompt` parameter controls whether to trigger the system permission dialog.
  static func hasAccess(prompt: Bool) -> Bool {
    // CGPreflightScreenCaptureAccess can return stale results.
    // First check: use the CG preflight as a fast path.
    if CGPreflightScreenCaptureAccess() {
      return true
    }
    if prompt {
      return CGRequestScreenCaptureAccess()
    }
    return false
  }

  /// Async check using ScreenCaptureKit - more reliable than CGPreflight on macOS 12.3+.
  /// Returns true if we can actually enumerate shareable content (proves permission is granted).
  @available(macOS 12.3, *)
  static func hasAccessAsync() async -> Bool {
    do {
      // If we can successfully get shareable content, permission is granted.
      // This is the most reliable check as it actually exercises the permission.
      _ = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true)
      return true
    } catch {
      // SCShareableContent throws if permission isn't granted
      return false
    }
  }

  /// Combined check: tries async first for reliability, falls back to sync.
  static func checkAccess() async -> Bool {
    if #available(macOS 12.3, *) {
      return await hasAccessAsync()
    }
    return hasAccess(prompt: false)
  }

  @MainActor
  static func showInstructionsAlert() {
    let alert = NSAlert()
    alert.alertStyle = .warning
    alert.messageText = "Enable Screen Recording Permission"
    alert.informativeText = "To record your screen, SnipSnap needs Screen Recording permission.\n\nGo to System Settings → Privacy & Security → Screen Recording, enable SnipSnap Capture Agent, then quit and relaunch SnipSnap."
    alert.addButton(withTitle: "Open Settings")
    alert.addButton(withTitle: "Not Now")

    let resp = alert.runModal()
    if resp == .alertFirstButtonReturn {
      if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
        NSWorkspace.shared.open(url)
      }
    }
  }
}
