import AppKit
import Foundation
import os.log

private let contextLog = OSLog(subsystem: "com.snipsnap.Snipsnap", category: "SourceContext")

/// Snapshot of "where the user was" when a capture/clipboard action fired.
struct SourceContext: Hashable {
  var appName: String?
  var bundleID: String?
  var pageURL: URL?
  var pageTitle: String?
  var capturedAt: Date = Date()

  func asCardSource(originalCaptureFilename: String? = nil) -> CardSource {
    CardSource(
      appName: appName,
      bundleID: bundleID,
      pageURL: pageURL,
      pageTitle: pageTitle,
      originalCaptureFilename: originalCaptureFilename,
      capturedAt: capturedAt
    )
  }
}

enum SourceContextProvider {
  /// Captures the frontmost app synchronously (SnipSnap is an LSUIElement, so the
  /// user's app is still frontmost when a global hotkey fires).
  @MainActor
  static func snapshotFrontmostApp() -> SourceContext {
    let app = NSWorkspace.shared.frontmostApplication
    if app?.bundleIdentifier == Bundle.main.bundleIdentifier {
      return SourceContext()
    }
    return SourceContext(appName: app?.localizedName, bundleID: app?.bundleIdentifier)
  }

  /// Frontmost app plus (optionally) the active browser tab URL/title.
  @MainActor
  static func snapshot(includeBrowserTab: Bool) async -> SourceContext {
    var context = snapshotFrontmostApp()
    guard includeBrowserTab, let bundleID = context.bundleID, BrowserTabReader.isSupported(bundleID) else {
      return context
    }
    if let tab = await BrowserTabReader.activeTab(bundleID: bundleID) {
      context.pageURL = tab.url
      context.pageTitle = tab.title
    }
    return context
  }
}

/// Reads the active tab of a supported browser via Apple Events.
///
/// Requires `NSAppleEventsUsageDescription` and the
/// `com.apple.security.automation.apple-events` entitlement (hardened runtime).
/// macOS prompts once per browser; failures/denials are silently ignored.
enum BrowserTabReader {
  struct Tab: Hashable {
    var url: URL
    var title: String?
  }

  private static let chromiumStyle: Set<String> = [
    "com.google.Chrome",
    "com.google.Chrome.beta",
    "com.google.Chrome.canary",
    "com.microsoft.edgemac",
    "com.brave.Browser",
    "company.thebrowser.Browser", // Arc
    "com.vivaldi.Vivaldi",
  ]

  private static let safariStyle: Set<String> = [
    "com.apple.Safari",
    "com.apple.SafariTechnologyPreview",
  ]

  static func isSupported(_ bundleID: String) -> Bool {
    chromiumStyle.contains(bundleID) || safariStyle.contains(bundleID)
  }

  static func script(for bundleID: String) -> String? {
    if safariStyle.contains(bundleID) {
      return """
      tell application id "\(bundleID)"
        if (count of windows) is 0 then return ""
        set t to current tab of front window
        return (URL of t) & linefeed & (name of t)
      end tell
      """
    }
    if chromiumStyle.contains(bundleID) {
      return """
      tell application id "\(bundleID)"
        if (count of windows) is 0 then return ""
        set t to active tab of front window
        return (URL of t) & linefeed & (title of t)
      end tell
      """
    }
    return nil
  }

  /// Parses "<url>\n<title>" script output.
  static func parse(_ output: String) -> Tab? {
    let parts = output.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false)
    guard let first = parts.first,
          let url = URL(string: String(first).trimmingCharacters(in: .whitespaces)),
          let scheme = url.scheme, ["http", "https", "file"].contains(scheme.lowercased()) else { return nil }
    let title = parts.count > 1 ? String(parts[1]).trimmingCharacters(in: .whitespacesAndNewlines) : nil
    return Tab(url: url, title: (title?.isEmpty ?? true) ? nil : title)
  }

  static func activeTab(bundleID: String, timeout: TimeInterval = 1.5) async -> Tab? {
    guard let source = script(for: bundleID) else { return nil }
    return await withCheckedContinuation { cont in
      let once = ResumeOnce { cont.resume(returning: $0) }
      DispatchQueue.global(qos: .userInitiated).async {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", source]
        let out = Pipe()
        process.standardOutput = out
        process.standardError = Pipe()
        do {
          try process.run()
        } catch {
          once.resume(nil)
          return
        }
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout) {
          if process.isRunning { process.terminate() }
        }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
          os_log(.info, log: contextLog, "Browser tab lookup failed (status %d)", process.terminationStatus)
          once.resume(nil)
          return
        }
        once.resume(String(data: data, encoding: .utf8).flatMap(parse))
      }
      DispatchQueue.global().asyncAfter(deadline: .now() + timeout) {
        once.resume(nil)
      }
    }
  }

  /// Ensures a continuation is resumed exactly once when racing work against a timeout.
  private final class ResumeOnce: @unchecked Sendable {
    private let lock = NSLock()
    private var done = false
    private let body: (Tab?) -> Void

    init(_ body: @escaping (Tab?) -> Void) { self.body = body }

    func resume(_ value: Tab?) {
      lock.lock()
      guard !done else { lock.unlock(); return }
      done = true
      lock.unlock()
      body(value)
    }
  }
}
