import AppKit
import CoreGraphics
import Foundation
import Security

enum PermissionDiagnostics {
  static func snapshot() -> String {
    var lines: [String] = []

    lines.append("SnipSnap Diagnostics")
    lines.append("Timestamp: \(ISO8601DateFormatter().string(from: Date()))")

    let bundleID = Bundle.main.bundleIdentifier ?? "(nil)"
    lines.append("Bundle ID: \(bundleID)")

    let bundlePath = Bundle.main.bundleURL.path
    lines.append("Bundle Path: \(bundlePath)")

    if let executable = Bundle.main.executableURL?.path {
      lines.append("Executable: \(executable)")
    }

    if let info = signingInfo() {
      lines.append("Signing Identifier: \(info.identifier ?? "(nil)")")
      lines.append("Signing Team ID: \(info.teamID ?? "(nil)")")
      lines.append("Signing Format: \(info.format ?? "(nil)")")
      if let cdhash = info.cdHashHex {
        lines.append("CDHash: \(cdhash)")
      }
    } else {
      lines.append("Signing Info: (unavailable)")
    }

    lines.append("Screen Recording Preflight: \(CGPreflightScreenCaptureAccess())")

    if #available(macOS 10.15, *) {
      lines.append("Input Monitoring Preflight: \(CGPreflightListenEventAccess())")
    }

    lines.append("Accessibility Trusted: \(AXIsProcessTrusted())")

    lines.append("")
    lines.append("Note: If permissions keep re-prompting between Debug builds, it’s often because the app is ad-hoc signed (code requirement changes each build). A stable Apple Development signature + consistent bundle ID usually fixes it.")

    return lines.joined(separator: "\n")
  }
  /// Reset TCC permissions for SnipSnap (Debug builds only).
  /// Requires admin privileges - runs `tccutil` via shell.
  @MainActor
  static func resetTCCPermissions() {
    #if DEBUG
    let bundleID = Bundle.main.bundleIdentifier ?? "com.snipsnap.Snipsnap"
    let agentBundleID = "com.snipsnap.SnipsnapCaptureAgent"

    let script = """
    do shell script "tccutil reset ScreenCapture \(bundleID); tccutil reset ScreenCapture \(agentBundleID); tccutil reset Accessibility \(bundleID); tccutil reset ListenEvent \(bundleID)" with administrator privileges
    """

    var error: NSDictionary?
    if let appleScript = NSAppleScript(source: script) {
      appleScript.executeAndReturnError(&error)
      if let error {
        print("[PermissionDiagnostics] TCC reset error: \(error)")
      } else {
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = "Permissions Reset"
        alert.informativeText = "TCC permissions have been reset for SnipSnap. Quit and relaunch both apps to re-request permissions."
        alert.addButton(withTitle: "OK")
        alert.runModal()
      }
    }
    #endif
  }

  /// Show a combined diagnostics panel with actions.
  @MainActor
  static func showDiagnosticsPanel() {
    let info = snapshot()

    let alert = NSAlert()
    alert.alertStyle = .informational
    alert.messageText = "SnipSnap Diagnostics"
    alert.informativeText = info
    alert.addButton(withTitle: "Copy to Clipboard")
    alert.addButton(withTitle: "Open Screen Recording Settings")
    #if DEBUG
    alert.addButton(withTitle: "Reset All Permissions")
    #endif
    alert.addButton(withTitle: "Close")

    let response = alert.runModal()
    switch response {
    case .alertFirstButtonReturn:
      NSPasteboard.general.clearContents()
      NSPasteboard.general.setString(info, forType: .string)
    case .alertSecondButtonReturn:
      if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
        NSWorkspace.shared.open(url)
      }
    #if DEBUG
    case .alertThirdButtonReturn:
      resetTCCPermissions()
    #endif
    default:
      break
    }
  }
  private struct CodeSigningInfo {
    var identifier: String?
    var teamID: String?
    var format: String?
    var cdHashHex: String?
  }

  private static func signingInfo() -> CodeSigningInfo? {
    var code: SecCode?
    let selfStatus = SecCodeCopySelf([], &code)
    guard selfStatus == errSecSuccess, let code else { return nil }

    var staticCode: SecStaticCode?
    let staticStatus = SecCodeCopyStaticCode(code, [], &staticCode)
    guard staticStatus == errSecSuccess, let staticCode else { return nil }

    var cfInfo: CFDictionary?
    let status = SecCodeCopySigningInformation(staticCode, SecCSFlags(rawValue: kSecCSSigningInformation), &cfInfo)
    guard status == errSecSuccess, let dict = cfInfo as? [CFString: Any] else { return nil }

    var info = CodeSigningInfo()
    info.identifier = dict[kSecCodeInfoIdentifier] as? String
    info.teamID = dict[kSecCodeInfoTeamIdentifier] as? String
    info.format = dict[kSecCodeInfoFormat] as? String

    if let cdhash = dict[kSecCodeInfoUnique] as? Data {
      info.cdHashHex = cdhash.map { String(format: "%02x", $0) }.joined()
    }

    return info
  }
}
