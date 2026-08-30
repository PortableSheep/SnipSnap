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
  private var resizeStartFrames: [URL: NSRect] = [:]
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
      styleMask: [.borderless, .nonactivatingPanel],
      backing: .buffered,
      defer: false
    )
    panel.isFloatingPanel = true
    panel.hidesOnDeactivate = false
    panel.level = .floating
    panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
    panel.isMovableByWindowBackground = true
    panel.hasShadow = true
    panel.isOpaque = false
    panel.backgroundColor = .clear
    panel.isReleasedWhenClosed = false

    panel.contentView = makeContentView(image: image, url: url, panel: panel)

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

    panel.contentView = makeContentView(image: image, url: sourceURL, panel: panel)
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
    resizeStartFrames[url] = nil
  }

  private func makeContentView(image: NSImage, url: URL, panel: NSPanel) -> NSView {
    let sizeLimits = sizeLimits(for: panel, imageSize: image.size)
    panel.minSize = sizeLimits.minimum
    panel.maxSize = sizeLimits.maximum

    let hostingView = NSHostingView(rootView: PinnedImageView(
      image: image,
      onResize: { [weak self, weak panel] translation in
        guard let panel else { return }
        self?.resize(
          panel: panel,
          url: url,
          translation: translation,
          aspectRatio: image.size.width / image.size.height,
          minimumWidth: sizeLimits.minimum.width,
          maximumWidth: sizeLimits.maximum.width
        )
      },
      onResizeEnded: { [weak self] in self?.resizeStartFrames[url] = nil },
      onEdit: { [weak self] in self?.editPinnedImage(url: url) },
      onCopy: { [weak self] in self?.copyPinnedImage(url: url) },
      onClose: { [weak self] in self?.unpin(url: url) }
    ))
    hostingView.wantsLayer = true
    hostingView.layer?.cornerRadius = 14
    hostingView.layer?.cornerCurve = .continuous
    hostingView.layer?.masksToBounds = true
    return hostingView
  }

  private func sizeLimits(for panel: NSPanel, imageSize: NSSize) -> (minimum: NSSize, maximum: NSSize) {
    let aspectRatio = imageSize.width / imageSize.height
    let visibleSize = (panel.screen ?? NSScreen.main)?.visibleFrame.size ?? imageSize
    let screenLimitedWidth = min(visibleSize.width, visibleSize.height * aspectRatio)
    let maximumWidth = min(imageSize.width, screenLimitedWidth)
    let minimumWidth = min(480, maximumWidth)

    return (
      minimum: NSSize(width: minimumWidth, height: minimumWidth / aspectRatio),
      maximum: NSSize(width: maximumWidth, height: maximumWidth / aspectRatio)
    )
  }

  private func resize(
    panel: NSPanel,
    url: URL,
    translation: CGSize,
    aspectRatio: CGFloat,
    minimumWidth: CGFloat,
    maximumWidth: CGFloat
  ) {
    let startFrame = resizeStartFrames[url] ?? panel.frame
    resizeStartFrames[url] = startFrame

    let inverseAspect = 1 / aspectRatio
    let projectedWidthDelta = (
      translation.width + translation.height * inverseAspect
    ) / (1 + inverseAspect * inverseAspect)
    let width = min(maximumWidth, max(minimumWidth, startFrame.width + projectedWidthDelta))
    let height = width / aspectRatio
    let frame = NSRect(
      x: startFrame.minX,
      y: startFrame.maxY - height,
      width: width,
      height: height
    )
    panel.setFrame(frame, display: true)
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
  let onResize: (CGSize) -> Void
  let onResizeEnded: () -> Void
  let onEdit: () -> Void
  let onCopy: () -> Void
  let onClose: () -> Void
  @State private var isHovered = false
  @State private var isResizing = false

  init(
    image: NSImage,
    onResize: @escaping (CGSize) -> Void,
    onResizeEnded: @escaping () -> Void,
    onEdit: @escaping () -> Void,
    onCopy: @escaping () -> Void,
    onClose: @escaping () -> Void
  ) {
    self.image = image
    self.onResize = onResize
    self.onResizeEnded = onResizeEnded
    self.onEdit = onEdit
    self.onCopy = onCopy
    self.onClose = onClose
  }

  var body: some View {
    let controlsVisible = isHovered || isResizing

    ZStack {
      Image(nsImage: image)
        .resizable()
        .aspectRatio(contentMode: .fill)

      VStack {
        HStack {
          Spacer()
          hoverButton(systemName: "pin.fill", help: "Unpin", action: onClose)
        }
        Spacer()
      }
      .padding(8)
      .opacity(controlsVisible ? 1 : 0)
      .allowsHitTesting(controlsVisible)

      VStack {
        Spacer()
        HStack {
          Spacer()
          ZStack {
            ResizeCorner()
            ResizeDragSurface(
              onResize: onResize,
              onResizeEnded: onResizeEnded,
              onDraggingChanged: { isResizing = $0 }
            )
          }
          .frame(width: 24, height: 24)
          .help("Resize")
        }
      }
      .padding(.trailing, 1)
      .padding(.bottom, 1)
      .opacity(controlsVisible ? 1 : 0)
    }
    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    .overlay {
      RoundedRectangle(cornerRadius: 14, style: .continuous)
        .stroke(.white.opacity(0.12), lineWidth: 1)
    }
    .contentShape(Rectangle())
    .onHover { hovering in
      isHovered = hovering
    }
    .contextMenu {
      Button("Edit") {
        onEdit()
      }

      Button("Copy") {
        onCopy()
      }

      Divider()

      Button("Unpin") {
        onClose()
      }
    }
  }

  private func hoverButton(
    systemName: String,
    help: String,
    action: @escaping () -> Void
  ) -> some View {
    Button(action: action) {
      Image(systemName: systemName)
        .font(.system(size: 11, weight: .bold))
        .foregroundStyle(.white)
        .frame(width: 26, height: 26)
        .background(.black.opacity(0.58), in: Circle())
    }
    .buttonStyle(.plain)
    .help(help)
  }
}

private struct ResizeDragSurface: NSViewRepresentable {
  let onResize: (CGSize) -> Void
  let onResizeEnded: () -> Void
  let onDraggingChanged: (Bool) -> Void

  func makeNSView(context: Context) -> ResizeTrackingView {
    ResizeTrackingView(
      onResize: onResize,
      onResizeEnded: onResizeEnded,
      onDraggingChanged: onDraggingChanged
    )
  }

  func updateNSView(_ nsView: ResizeTrackingView, context: Context) {
    nsView.onResize = onResize
    nsView.onResizeEnded = onResizeEnded
    nsView.onDraggingChanged = onDraggingChanged
  }
}

private final class ResizeTrackingView: NSView {
  var onResize: (CGSize) -> Void
  var onResizeEnded: () -> Void
  var onDraggingChanged: (Bool) -> Void
  private var dragStart: NSPoint?

  init(
    onResize: @escaping (CGSize) -> Void,
    onResizeEnded: @escaping () -> Void,
    onDraggingChanged: @escaping (Bool) -> Void
  ) {
    self.onResize = onResize
    self.onResizeEnded = onResizeEnded
    self.onDraggingChanged = onDraggingChanged
    super.init(frame: .zero)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
    true
  }

  override var mouseDownCanMoveWindow: Bool {
    false
  }

  override func mouseDown(with event: NSEvent) {
    dragStart = NSEvent.mouseLocation
    onDraggingChanged(true)
  }

  override func mouseDragged(with event: NSEvent) {
    guard let dragStart else { return }
    let location = NSEvent.mouseLocation
    onResize(CGSize(
      width: location.x - dragStart.x,
      height: dragStart.y - location.y
    ))
  }

  override func mouseUp(with event: NSEvent) {
    dragStart = nil
    onResizeEnded()
    onDraggingChanged(false)
  }
}

private struct ResizeCorner: View {
  var body: some View {
    ResizeCornerShape()
      .stroke(
        .white.opacity(0.9),
        style: StrokeStyle(lineWidth: 1.25, lineCap: .round, lineJoin: .round)
      )
      .padding(3)
      .shadow(color: .black.opacity(0.75), radius: 1)
  }
}

private struct ResizeCornerShape: Shape {
  func path(in rect: CGRect) -> Path {
    var path = Path()
    for inset in stride(from: CGFloat(2), through: CGFloat(12), by: 5) {
      path.move(to: CGPoint(x: rect.maxX - inset - 5, y: rect.maxY - 2))
      path.addQuadCurve(
        to: CGPoint(x: rect.maxX - 2, y: rect.maxY - inset - 5),
        control: CGPoint(x: rect.maxX - 2, y: rect.maxY - 2)
      )
    }
    return path
  }
}
