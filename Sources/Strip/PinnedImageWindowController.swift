import AppKit
import SwiftUI

/// Notification posted when the editor exports/saves a file.
/// The `object` is the source URL (`URL`) of the edited capture.
extension Notification.Name {
  static let editorDidSave = Notification.Name("SnipSnapEditorDidSave")
}

@MainActor
final class PinnedImageWindowController {
  private var windows: [URL: NSPanel] = [:]
  private var delegates: [URL: PinnedPanelDelegate] = [:]
  private var saveObserver: NSObjectProtocol?
  var onEdit: ((URL) -> Void)?

  init() {
    saveObserver = NotificationCenter.default.addObserver(
      forName: .editorDidSave,
      object: nil,
      queue: .main
    ) { [weak self] notification in
      guard let url = notification.object as? URL else { return }
      Task { @MainActor in
        self?.refresh(sourceURL: url)
      }
    }
  }

  deinit {
    if let observer = saveObserver {
      NotificationCenter.default.removeObserver(observer)
    }
  }

  /// Pin an image in a floating always-on-top window.
  func pin(url: URL) {
    if let existing = windows[url] {
      existing.makeKeyAndOrderFront(nil)
      return
    }

    let displayURL = annotatedURL(for: url) ?? url

    guard let image = NSImage(contentsOf: displayURL) else {
      NSSound.beep()
      return
    }

    let imageSize = image.size
    let maxDimension: CGFloat = 500
    let scale = min(maxDimension / imageSize.width, maxDimension / imageSize.height, 1.0)
    let panelWidth = imageSize.width * scale
    let panelHeight = imageSize.height * scale

    let panel = NSPanel(
      contentRect: NSRect(x: 0, y: 0, width: panelWidth, height: panelHeight),
      styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
      backing: .buffered,
      defer: false
    )
    panel.isFloatingPanel = true
    panel.level = .floating
    panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
    panel.titleVisibility = .hidden
    panel.titlebarAppearsTransparent = true
    panel.isMovableByWindowBackground = true
    panel.hasShadow = true
    panel.isOpaque = false
    panel.backgroundColor = .black
    panel.isReleasedWhenClosed = false
    panel.minSize = NSSize(width: 100, height: 75)
    panel.aspectRatio = NSSize(width: imageSize.width, height: imageSize.height)

    let view = PinnedImageView(
      image: image,
      onEdit: { [weak self] in self?.editPinnedImage(url: url) },
      onCopy: { [weak self] in self?.copyPinnedImage(url: url) },
      onClose: { [weak self] in self?.unpin(url: url) }
    )
    panel.contentView = NSHostingView(rootView: view)

    let delegate = PinnedPanelDelegate { [weak self] in
      self?.cleanupWindow(url: url)
    }
    panel.delegate = delegate
    delegates[url] = delegate

    windows[url] = panel
    panel.center()
    panel.makeKeyAndOrderFront(nil)
  }

  func unpin(url: URL) {
    windows[url]?.close()
    cleanupWindow(url: url)
  }

  func isPinned(url: URL) -> Bool {
    windows[url] != nil
  }

  /// Refresh pinned image after editor save. Checks both original and annotated URLs.
  func refresh(sourceURL: URL) {
    // The sourceURL from the editor is the original capture path.
    // Check if we have a pinned window for it.
    guard let panel = windows[sourceURL] else { return }

    let displayURL = annotatedURL(for: sourceURL) ?? sourceURL
    guard let image = NSImage(contentsOf: displayURL) else { return }

    let view = PinnedImageView(
      image: image,
      onEdit: { [weak self] in self?.editPinnedImage(url: sourceURL) },
      onCopy: { [weak self] in self?.copyPinnedImage(url: sourceURL) },
      onClose: { [weak self] in self?.unpin(url: sourceURL) }
    )
    panel.contentView = NSHostingView(rootView: view)
  }

  private func editPinnedImage(url: URL) {
    onEdit?(url)
  }

  private func copyPinnedImage(url: URL) {
    let displayURL = annotatedURL(for: url) ?? url
    guard let image = NSImage(contentsOf: displayURL) else { return }
    NSPasteboard.general.clearContents()
    NSPasteboard.general.writeObjects([image])
  }

  private func cleanupWindow(url: URL) {
    windows[url] = nil
    delegates[url] = nil
  }

  /// Returns the `.annotated.png` URL if it exists on disk, otherwise nil.
  private func annotatedURL(for url: URL) -> URL? {
    let annotated = url
      .deletingPathExtension()
      .appendingPathExtension("annotated.png")
    return FileManager.default.fileExists(atPath: annotated.path) ? annotated : nil
  }
}

// MARK: - Panel Delegate

@MainActor
private final class PinnedPanelDelegate: NSObject, NSWindowDelegate {
  private let onClose: () -> Void

  init(onClose: @escaping () -> Void) {
    self.onClose = onClose
  }

  func windowWillClose(_ notification: Notification) {
    onClose()
  }
}

// MARK: - SwiftUI View

private struct PinnedImageView: View {
  let image: NSImage
  let onEdit: () -> Void
  let onCopy: () -> Void
  let onClose: () -> Void

  var body: some View {
    Image(nsImage: image)
      .resizable()
      .aspectRatio(contentMode: .fit)
      .contextMenu {
        Button("Edit") {
          onEdit()
        }

        Button("Copy") {
          onCopy()
        }

        Divider()

        Button("Close") {
          onClose()
        }
      }
  }
}
