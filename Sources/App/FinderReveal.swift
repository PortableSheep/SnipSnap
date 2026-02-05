import AppKit

enum FinderReveal {
  @MainActor
  static func reveal(_ url: URL) {
    NSWorkspace.shared.activateFileViewerSelecting([url])

    // `activateFileViewerSelecting` sometimes opens behind other apps.
    // Explicitly activate Finder so the selection is visible.
    if let finder = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.finder").first {
      finder.activate(options: [.activateAllWindows, .activateIgnoringOtherApps])
    }
  }
}
