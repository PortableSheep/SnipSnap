import AppKit
import Foundation
import os

private let updateLog = OSLog(subsystem: "com.snipsnap.Snipsnap", category: "UpdateChecker")

/// Helper to use closures as NSButton targets.
private class BlockTarget: NSObject {
  let block: () -> Void
  init(_ block: @escaping () -> Void) { self.block = block }
  @objc func invoke() { block() }
}

/// Lightweight auto-updater that checks GitHub Releases for new versions.
@MainActor
final class UpdateChecker {
  static let shared = UpdateChecker()

  private let repo = "portablesheep/snipsnap"
  private let checkIntervalSeconds: TimeInterval = 24 * 60 * 60  // 24 hours

  private enum Defaults {
    static let lastChecked = "UpdateChecker.lastCheckedDate"
    static let skippedVersion = "UpdateChecker.skippedVersion"
  }

  private var isChecking = false

  private init() {}

  // MARK: - Public API

  /// Check for updates on launch (always checks, respects skipped version).
  func checkOnLaunch() {
    Task {
      await checkForUpdate(userInitiated: false)
    }
  }

  /// Check for updates now (ignores cooldown, but respects skipped version).
  func checkNow() {
    Task {
      await checkForUpdate(userInitiated: true)
    }
  }

  // MARK: - Core Logic

  private func checkForUpdate(userInitiated: Bool) async {
    guard !isChecking else { return }
    isChecking = true
    defer { isChecking = false }

    UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: Defaults.lastChecked)

    do {
      guard let release = try await fetchLatestRelease() else {
        if userInitiated { showUpToDateAlert() }
        return
      }

      let remoteVersion = release.version
      let currentVersion = currentAppVersion()

      guard isVersion(remoteVersion, newerThan: currentVersion) else {
        if userInitiated { showUpToDateAlert() }
        return
      }

      // Skip if user previously dismissed this version (unless manually checking)
      if !userInitiated {
        let skipped = UserDefaults.standard.string(forKey: Defaults.skippedVersion)
        if skipped == remoteVersion { return }
      }

      showUpdateAlert(release: release)
    } catch {
      os_log("Update check failed: %{public}@", log: updateLog, type: .error, error.localizedDescription)
      if userInitiated {
        showErrorAlert(error)
      }
    }
  }

  // MARK: - GitHub API

  private struct GitHubRelease {
    let version: String
    let tagName: String
    let name: String
    let body: String
    let zipURL: URL?
  }

  private func fetchLatestRelease() async throws -> GitHubRelease? {
    let url = URL(string: "https://api.github.com/repos/\(repo)/releases/latest")!
    var request = URLRequest(url: url)
    request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
    request.timeoutInterval = 15

    let (data, response) = try await URLSession.shared.data(for: request)

    guard let httpResponse = response as? HTTPURLResponse else { return nil }
    guard httpResponse.statusCode == 200 else {
      if httpResponse.statusCode == 404 { return nil }  // No releases yet
      throw UpdateError.httpError(httpResponse.statusCode)
    }

    guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
      return nil
    }

    let tagName = json["tag_name"] as? String ?? ""
    let version = tagName.hasPrefix("v") ? String(tagName.dropFirst()) : tagName
    let name = json["name"] as? String ?? "SnipSnap \(version)"
    let body = json["body"] as? String ?? ""

    // Find the ZIP asset
    var zipURL: URL?
    if let assets = json["assets"] as? [[String: Any]] {
      for asset in assets {
        if let assetName = asset["name"] as? String,
           assetName.hasSuffix(".zip"),
           let downloadURL = asset["browser_download_url"] as? String {
          zipURL = URL(string: downloadURL)
          break
        }
      }
    }

    return GitHubRelease(
      version: version,
      tagName: tagName,
      name: name,
      body: body,
      zipURL: zipURL
    )
  }

  // MARK: - Version Comparison

  private func currentAppVersion() -> String {
    Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
  }

  /// Compares semantic version strings (e.g. "1.2.3" > "1.2.0").
  private func isVersion(_ remote: String, newerThan local: String) -> Bool {
    let r = remote.split(separator: ".").compactMap { Int($0) }
    let l = local.split(separator: ".").compactMap { Int($0) }

    for i in 0..<max(r.count, l.count) {
      let rv = i < r.count ? r[i] : 0
      let lv = i < l.count ? l[i] : 0
      if rv > lv { return true }
      if rv < lv { return false }
    }
    return false
  }

  // MARK: - UI

  private func showUpdateAlert(release: GitHubRelease) {
    let alert = NSAlert()
    alert.messageText = "\(release.name)"
    alert.informativeText = "Current version: \(currentAppVersion())  →  New version: \(release.version)"
    alert.alertStyle = .informational

    // Render the changelog as styled text in a scrollable accessory view
    let changelogBody = release.body.trimmingCharacters(in: .whitespacesAndNewlines)
    if !changelogBody.isEmpty {
      let scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: 420, height: 220))
      scrollView.hasVerticalScroller = true
      scrollView.hasHorizontalScroller = false
      scrollView.autohidesScrollers = true
      scrollView.borderType = .bezelBorder

      let textView = NSTextView(frame: scrollView.contentView.bounds)
      textView.isEditable = false
      textView.isSelectable = true
      textView.autoresizingMask = [.width]
      textView.textContainerInset = NSSize(width: 10, height: 10)
      textView.textContainer?.widthTracksTextView = true
      textView.textContainer?.lineFragmentPadding = 4
      textView.backgroundColor = .controlBackgroundColor

      let styledText = renderMarkdownChangelog(changelogBody)
      textView.textStorage?.setAttributedString(styledText)

      scrollView.documentView = textView
      alert.accessoryView = scrollView
    }

    if release.zipURL != nil {
      alert.addButton(withTitle: "Download & Install")
    }
    alert.addButton(withTitle: "Remind Later")
    alert.addButton(withTitle: "Skip This Version")

    // Size the alert window to accommodate the accessory view
    alert.layout()

    let response = alert.runModal()
    let buttonIndex = response.rawValue - NSApplication.ModalResponse.alertFirstButtonReturn.rawValue

    if release.zipURL != nil {
      switch buttonIndex {
      case 0:
        downloadAndInstall(release: release)
      case 2:
        UserDefaults.standard.set(release.version, forKey: Defaults.skippedVersion)
      default:
        break
      }
    } else {
      if buttonIndex == 1 {
        UserDefaults.standard.set(release.version, forKey: Defaults.skippedVersion)
      }
    }
  }

  /// Converts a GitHub release body (markdown) into a styled NSAttributedString.
  private func renderMarkdownChangelog(_ markdown: String) -> NSAttributedString {
    let result = NSMutableAttributedString()
    let bodyFont = NSFont.systemFont(ofSize: 12)
    let bodyColor = NSColor.labelColor
    let headerFont = NSFont.systemFont(ofSize: 13, weight: .semibold)
    let dimColor = NSColor.secondaryLabelColor

    let defaultAttrs: [NSAttributedString.Key: Any] = [
      .font: bodyFont,
      .foregroundColor: bodyColor
    ]

    let lines = markdown.components(separatedBy: "\n")
    var isFirstBlock = true

    for line in lines {
      let trimmed = line.trimmingCharacters(in: .whitespaces)

      // Skip empty lines but preserve paragraph spacing
      if trimmed.isEmpty {
        if result.length > 0 {
          result.append(NSAttributedString(string: "\n", attributes: defaultAttrs))
        }
        continue
      }

      // ### Section headers (e.g. "### ✨ Features")
      if trimmed.hasPrefix("### ") {
        let headerText = String(trimmed.dropFirst(4))
        if !isFirstBlock {
          result.append(NSAttributedString(string: "\n", attributes: defaultAttrs))
        }
        result.append(NSAttributedString(string: headerText + "\n", attributes: [
          .font: headerFont,
          .foregroundColor: bodyColor
        ]))
        isFirstBlock = false
        continue
      }

      // ## Top-level headers
      if trimmed.hasPrefix("## ") {
        let headerText = String(trimmed.dropFirst(3))
        if !isFirstBlock {
          result.append(NSAttributedString(string: "\n", attributes: defaultAttrs))
        }
        result.append(NSAttributedString(string: headerText + "\n", attributes: [
          .font: NSFont.systemFont(ofSize: 14, weight: .bold),
          .foregroundColor: bodyColor
        ]))
        isFirstBlock = false
        continue
      }

      // Bullet items (- or *)
      if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") {
        var itemText = String(trimmed.dropFirst(2))

        // Strip trailing commit hashes like (`abc1234`)
        if let range = itemText.range(of: #"\s*\(`?[a-f0-9]{7,}`?\)\s*$"#, options: .regularExpression) {
          itemText = String(itemText[itemText.startIndex..<range.lowerBound])
        }

        // Strip inline markdown bold **text**
        itemText = itemText.replacingOccurrences(of: #"\*\*(.+?)\*\*"#, with: "$1", options: .regularExpression)

        // Strip inline markdown backticks `code`
        itemText = itemText.replacingOccurrences(of: #"`(.+?)`"#, with: "$1", options: .regularExpression)

        result.append(NSAttributedString(string: "  •  " + itemText + "\n", attributes: defaultAttrs))
        continue
      }

      // Plain text (strip bold/backtick markers)
      var plainText = trimmed
      plainText = plainText.replacingOccurrences(of: #"\*\*(.+?)\*\*"#, with: "$1", options: .regularExpression)
      plainText = plainText.replacingOccurrences(of: #"`(.+?)`"#, with: "$1", options: .regularExpression)
      result.append(NSAttributedString(string: plainText + "\n", attributes: defaultAttrs))
    }

    // Trim trailing whitespace/newlines
    let fullRange = NSRange(location: 0, length: result.length)
    let str = result.string as NSString
    var end = str.length
    while end > 0 && CharacterSet.whitespacesAndNewlines.contains(Unicode.Scalar(str.character(at: end - 1))!) {
      end -= 1
    }
    if end < str.length {
      result.deleteCharacters(in: NSRange(location: end, length: str.length - end))
    }

    // Apply paragraph style for comfortable line spacing
    let paraStyle = NSMutableParagraphStyle()
    paraStyle.lineSpacing = 2
    paraStyle.paragraphSpacing = 2
    result.addAttribute(.paragraphStyle, value: paraStyle, range: NSRange(location: 0, length: result.length))

    return result
  }

  private func showUpToDateAlert() {
    let alert = NSAlert()
    alert.messageText = "You're up to date"
    alert.informativeText = "SnipSnap \(currentAppVersion()) is the latest version."
    alert.alertStyle = .informational
    alert.addButton(withTitle: "OK")
    alert.runModal()
  }

  private func showErrorAlert(_ error: Error) {
    let alert = NSAlert()
    alert.messageText = "Update check failed"
    alert.informativeText = "Could not check for updates. Please try again later.\n\n\(error.localizedDescription)"
    alert.alertStyle = .warning
    alert.addButton(withTitle: "OK")
    alert.runModal()
  }

  // MARK: - Download & Install

  private func downloadAndInstall(release: GitHubRelease) {
    guard let zipURL = release.zipURL else { return }

    // Show a progress window during download
    let progressWindow = NSPanel(
      contentRect: NSRect(x: 0, y: 0, width: 340, height: 120),
      styleMask: [.titled, .closable],
      backing: .buffered,
      defer: false
    )
    progressWindow.title = "Updating SnipSnap"
    progressWindow.isFloatingPanel = true
    progressWindow.center()

    let container = NSView(frame: NSRect(x: 0, y: 0, width: 340, height: 120))

    let label = NSTextField(labelWithString: "Downloading SnipSnap \(release.version)…")
    label.font = .systemFont(ofSize: 13, weight: .medium)
    label.frame = NSRect(x: 20, y: 70, width: 300, height: 20)
    container.addSubview(label)

    let indicator = NSProgressIndicator(frame: NSRect(x: 20, y: 45, width: 300, height: 20))
    indicator.style = .bar
    indicator.isIndeterminate = true
    indicator.startAnimation(nil)
    container.addSubview(indicator)

    let cancelButton = NSButton(title: "Cancel", target: nil, action: nil)
    cancelButton.frame = NSRect(x: 240, y: 10, width: 80, height: 28)
    container.addSubview(cancelButton)

    progressWindow.contentView = container
    progressWindow.makeKeyAndOrderFront(nil)

    let downloadTask = Task { [weak self] in
      do {
        let tempDir = try await self?.downloadAndExtract(from: zipURL)
        guard let self, let tempDir else { return }
        progressWindow.close()
        self.installUpdate(tempDir: tempDir)
      } catch {
        progressWindow.close()
        if !Task.isCancelled {
          os_log("Download failed: %{public}@", log: updateLog, type: .error, error.localizedDescription)
          await MainActor.run {
            let alert = NSAlert()
            alert.messageText = "Download failed"
            alert.informativeText = error.localizedDescription
            alert.alertStyle = .warning
            alert.addButton(withTitle: "OK")
            alert.runModal()
          }
        }
      }
    }

    cancelButton.target = nil
    cancelButton.action = nil
    // Wire cancel to close window and cancel task
    let cancelHandler = BlockTarget {
      downloadTask.cancel()
      progressWindow.close()
    }
    cancelButton.target = cancelHandler
    cancelButton.action = #selector(BlockTarget.invoke)
    // Prevent deallocation
    objc_setAssociatedObject(cancelButton, "blockTarget", cancelHandler, .OBJC_ASSOCIATION_RETAIN)
  }

  private func downloadAndExtract(from url: URL) async throws -> URL {
    let (fileURL, response) = try await URLSession.shared.download(from: url)

    guard let httpResponse = response as? HTTPURLResponse,
          httpResponse.statusCode == 200 else {
      throw UpdateError.downloadFailed
    }

    let tempDir = FileManager.default.temporaryDirectory
      .appendingPathComponent("snipsnap-update-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

    let zipDest = tempDir.appendingPathComponent("update.zip")
    try FileManager.default.moveItem(at: fileURL, to: zipDest)

    // Extract
    let extractDir = tempDir.appendingPathComponent("extracted")
    try FileManager.default.createDirectory(at: extractDir, withIntermediateDirectories: true)

    let unzip = Process()
    unzip.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
    unzip.arguments = ["-q", "-o", zipDest.path, "-d", extractDir.path]
    try unzip.run()
    unzip.waitUntilExit()

    guard unzip.terminationStatus == 0 else {
      throw UpdateError.extractFailed
    }

    return tempDir
  }

  private func installUpdate(tempDir: URL) {
    let fm = FileManager.default
    let extractDir = tempDir.appendingPathComponent("extracted")

    do {
      let appName = "SnipSnap.app"
      guard let appPath = findApp(named: appName, in: extractDir) else {
        throw UpdateError.appNotFound
      }

      guard let currentAppURL = Bundle.main.bundleURL as URL? else {
        throw UpdateError.installFailed("Could not determine current app location")
      }

      os_log("Installing update from %{public}@ to %{public}@", log: updateLog, type: .info,
             appPath.path, currentAppURL.path)

      let backupURL = currentAppURL.deletingLastPathComponent()
        .appendingPathComponent("SnipSnap-backup.app")
      try? fm.removeItem(at: backupURL)
      try fm.moveItem(at: currentAppURL, to: backupURL)

      do {
        try fm.copyItem(at: appPath, to: currentAppURL)
      } catch {
        try? fm.moveItem(at: backupURL, to: currentAppURL)
        throw UpdateError.installFailed(error.localizedDescription)
      }

      // Remove quarantine
      let xattr = Process()
      xattr.executableURL = URL(fileURLWithPath: "/usr/bin/xattr")
      xattr.arguments = ["-rd", "com.apple.quarantine", currentAppURL.path]
      try? xattr.run()
      xattr.waitUntilExit()

      try? fm.removeItem(at: backupURL)
      try? fm.removeItem(at: tempDir)

      relaunch(at: currentAppURL)

    } catch {
      os_log("Install failed: %{public}@", log: updateLog, type: .error, error.localizedDescription)

      let alert = NSAlert()
      alert.messageText = "Update failed"
      alert.informativeText = "Could not install the update: \(error.localizedDescription)"
      alert.alertStyle = .critical
      alert.addButton(withTitle: "OK")
      alert.runModal()

      try? fm.removeItem(at: tempDir)
    }
  }

  private func findApp(named name: String, in directory: URL) -> URL? {
    let fm = FileManager.default
    // Check directly
    let direct = directory.appendingPathComponent(name)
    if fm.fileExists(atPath: direct.path) { return direct }

    // Search one level deep
    if let contents = try? fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) {
      for item in contents {
        if item.lastPathComponent == name { return item }
        let nested = item.appendingPathComponent(name)
        if fm.fileExists(atPath: nested.path) { return nested }
      }
    }
    return nil
  }

  private func relaunch(at appURL: URL) {
    let task = Process()
    task.executableURL = URL(fileURLWithPath: "/usr/bin/open")
    task.arguments = ["-n", appURL.path]
    try? task.run()

    // Give the new instance a moment to start, then exit
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
      NSApp.terminate(nil)
    }
  }

  // MARK: - Errors

  private enum UpdateError: LocalizedError {
    case httpError(Int)
    case downloadFailed
    case extractFailed
    case appNotFound
    case installFailed(String)

    var errorDescription: String? {
      switch self {
      case .httpError(let code):
        return "Server returned status \(code)"
      case .downloadFailed:
        return "Failed to download the update"
      case .extractFailed:
        return "Failed to extract the update archive"
      case .appNotFound:
        return "Could not find SnipSnap.app in the update"
      case .installFailed(let reason):
        return "Installation failed: \(reason)"
      }
    }
  }
}
