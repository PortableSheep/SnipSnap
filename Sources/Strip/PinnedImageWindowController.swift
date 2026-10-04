import AppKit
import SwiftUI

/// Notification posted when the editor exports/saves a file.
/// The `object` is the source URL (`URL`) of the edited capture.
extension Notification.Name {
  static let editorDidSave = Notification.Name("SnipSnapEditorDidSave")
  /// Asks the app to pin the capture (`object` is its source `URL`) always-on-top.
  static let pinToScreen = Notification.Name("SnipSnapPinToScreen")
}

@MainActor
final class PinnedImageWindowController {
  private static let defaultsKey = "pinnedImages.v1"
  private static let defaultMaxDimension: CGFloat = 420
  private static let minimumPinWidth: CGFloat = 160

  private struct SavedPin: Codable {
    var path: String
    var frame: CodableRect?
  }

  private var windows: [URL: PinnedImagePanel] = [:]
  private var delegates: [URL: PinnedPanelDelegate] = [:]
  private var feedback: [URL: PinFeedback] = [:]
  private var order: [URL] = []
  private var resizeStartFrames: [URL: NSRect] = [:]
  private var saveObserver: NSObjectProtocol?
  private var allHidden = false
  private let defaults: UserDefaults
  var onEdit: ((URL) -> Void)?
  var onSendToBoard: ((URL) -> Void)?
  /// Called when a new pin is created while pins are globally hidden, so the owner can un-hide them.
  var onPinWhileHidden: (() -> Void)?

  init(defaults: UserDefaults = .standard) {
    self.defaults = defaults
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

  /// Re-opens pins that were on screen when the app last quit, at their saved frames.
  func restorePins() {
    let saved = loadSaved()
    for entry in saved {
      let url = URL(fileURLWithPath: entry.path)
      guard FileManager.default.fileExists(atPath: url.path) else { continue }
      pin(url: url, savedFrame: entry.frame?.cgRect, activate: false)
    }
    persist()
  }

  /// Pin an image in a floating always-on-top window.
  func pin(url: URL) {
    pin(url: url, savedFrame: nil, activate: true)
  }

  private func pin(url: URL, savedFrame: CGRect?, activate: Bool) {
    if let existing = windows[url] {
      if !allHidden { existing.makeKeyAndOrderFront(nil) }
      flash(url, "Already pinned")
      return
    }

    let displayURL = annotatedURL(for: url) ?? url

    guard let image = NSImage(contentsOf: displayURL), image.size.width > 0, image.size.height > 0 else {
      NSSound.beep()
      return
    }

    let panel = PinnedImagePanel(
      contentRect: NSRect(origin: .zero, size: defaultSize(for: image.size)),
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
    panel.onClose = { [weak self] in self?.unpin(url: url) }
    panel.onCopy = { [weak self] in self?.copyPinnedImage(url: url) }
    panel.onEdit = { [weak self] in self?.editPinnedImage(url: url) }

    feedback[url] = PinFeedback()
    panel.contentView = makeContentView(image: image, url: url, panel: panel)
    panel.setFrame(initialFrame(for: panel, imageSize: image.size, saved: savedFrame), display: false)

    let delegate = PinnedPanelDelegate(
      onClose: { [weak self] in self?.cleanupWindow(url: url) },
      onFrameChange: { [weak self] in self?.persist() }
    )
    panel.delegate = delegate
    delegates[url] = delegate

    windows[url] = panel
    order.append(url)
    persist()
    if allHidden, activate {
      onPinWhileHidden?()
    }
    if !allHidden {
      if activate { panel.makeKeyAndOrderFront(nil) } else { panel.orderFrontRegardless() }
    }
  }

  /// Temporarily hides (or re-shows) every pinned image without unpinning it.
  func setAllHidden(_ hidden: Bool) {
    allHidden = hidden
    for panel in windows.values {
      if hidden {
        panel.orderOut(nil)
      } else {
        panel.orderFrontRegardless()
      }
    }
  }

  var hasPins: Bool { !windows.isEmpty }

  func unpin(url: URL) {
    windows[url]?.close()
    cleanupWindow(url: url)
  }

  func isPinned(url: URL) -> Bool {
    windows[url] != nil
  }

  /// Refresh pinned image after editor save. Checks both original and annotated URLs.
  func refresh(sourceURL: URL) {
    guard let panel = windows[sourceURL] else { return }

    let displayURL = annotatedURL(for: sourceURL) ?? sourceURL
    guard let image = NSImage(contentsOf: displayURL), image.size.width > 0, image.size.height > 0 else { return }

    let oldFrame = panel.frame
    panel.contentView = makeContentView(image: image, url: sourceURL, panel: panel)
    // Keep the width the user chose, but follow the new aspect ratio (e.g. after a crop).
    let width = min(max(oldFrame.width, panel.minSize.width), panel.maxSize.width)
    let height = width * image.size.height / image.size.width
    panel.setFrame(NSRect(x: oldFrame.minX, y: oldFrame.maxY - height, width: width, height: height), display: true)
  }

  private func editPinnedImage(url: URL) {
    onEdit?(url)
  }

  private func copyPinnedImage(url: URL) {
    let displayURL = annotatedURL(for: url) ?? url
    guard let image = NSImage(contentsOf: displayURL) else { return }
    NSPasteboard.general.clearContents()
    NSPasteboard.general.writeObjects([image])
    flash(url, "Copied")
  }

  private func sendToBoard(url: URL) {
    onSendToBoard?(url)
    flash(url, "Sent to Board")
  }

  private func flash(_ url: URL, _ message: String) {
    feedback[url]?.show(message)
  }

  private func cleanupWindow(url: URL) {
    windows[url] = nil
    delegates[url] = nil
    feedback[url] = nil
    resizeStartFrames[url] = nil
    order.removeAll { $0 == url }
    persist()
  }

  private func makeContentView(image: NSImage, url: URL, panel: NSPanel) -> NSView {
    let sizeLimits = sizeLimits(for: panel, imageSize: image.size)
    panel.minSize = sizeLimits.minimum
    panel.maxSize = sizeLimits.maximum

    let hostingView = NSHostingView(rootView: PinnedImageView(
      image: image,
      feedback: feedback[url] ?? PinFeedback(),
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
      onResizeEnded: { [weak self] in
        self?.resizeStartFrames[url] = nil
        self?.persist()
      },
      onEdit: { [weak self] in self?.editPinnedImage(url: url) },
      onCopy: { [weak self] in self?.copyPinnedImage(url: url) },
      onSendToBoard: onSendToBoard == nil ? nil : { [weak self] in self?.sendToBoard(url: url) },
      onClose: { [weak self] in self?.unpin(url: url) }
    ))
    hostingView.wantsLayer = true
    hostingView.layer?.cornerRadius = PinStyle.cornerRadius
    hostingView.layer?.cornerCurve = .continuous
    hostingView.layer?.masksToBounds = true
    return hostingView
  }

  // MARK: - Placement

  private func defaultSize(for imageSize: NSSize) -> NSSize {
    let scale = min(Self.defaultMaxDimension / imageSize.width, Self.defaultMaxDimension / imageSize.height, 1.0)
    return NSSize(width: imageSize.width * scale, height: imageSize.height * scale)
  }

  /// Saved frame if it's still on a screen, otherwise centred on the mouse and cascaded
  /// away from existing pins so new pins don't stack exactly on top of each other.
  private func initialFrame(for panel: NSPanel, imageSize: NSSize, saved: CGRect?) -> NSRect {
    let aspect = imageSize.width / imageSize.height
    if let saved, saved.width > 0,
       let screen = NSScreen.screens.first(where: { $0.visibleFrame.intersects(saved) }) {
      let width = min(max(saved.width, panel.minSize.width), screen.visibleFrame.width)
      let size = NSSize(width: width, height: width / aspect)
      return Self.clamp(NSRect(x: saved.minX, y: saved.maxY - size.height, width: size.width, height: size.height),
                        into: screen.visibleFrame)
    }

    let mouse = NSEvent.mouseLocation
    let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
    let visible = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
    var size = defaultSize(for: imageSize)
    if size.width < panel.minSize.width {
      size = NSSize(width: panel.minSize.width, height: panel.minSize.width / aspect)
    }
    var frame = NSRect(x: mouse.x - size.width / 2, y: mouse.y - size.height / 2, width: size.width, height: size.height)
    frame = Self.clamp(frame, into: visible)
    let occupied = windows.values.map(\.frame.origin)
    var attempts = 0
    while attempts < 12, occupied.contains(where: { abs($0.x - frame.minX) < 8 && abs($0.y - frame.minY) < 8 }) {
      frame = Self.clamp(frame.offsetBy(dx: 28, dy: -28), into: visible)
      attempts += 1
    }
    return frame
  }

  static func clamp(_ frame: NSRect, into visible: NSRect) -> NSRect {
    var f = frame
    f.size.width = min(f.width, visible.width)
    f.size.height = min(f.height, visible.height)
    f.origin.x = min(max(f.minX, visible.minX), visible.maxX - f.width)
    f.origin.y = min(max(f.minY, visible.minY), visible.maxY - f.height)
    return f
  }

  private func sizeLimits(for panel: NSPanel, imageSize: NSSize) -> (minimum: NSSize, maximum: NSSize) {
    let aspectRatio = imageSize.width / imageSize.height
    let visibleSize = (panel.screen ?? NSScreen.main)?.visibleFrame.size ?? imageSize
    let screenLimitedWidth = min(visibleSize.width, visibleSize.height * aspectRatio)
    let maximumWidth = max(min(imageSize.width, screenLimitedWidth), min(Self.minimumPinWidth, screenLimitedWidth))
    let minimumWidth = min(Self.minimumPinWidth, maximumWidth)

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

  // MARK: - Persistence

  private func loadSaved() -> [SavedPin] {
    guard let data = defaults.data(forKey: Self.defaultsKey) else { return [] }
    return (try? JSONDecoder().decode([SavedPin].self, from: data)) ?? []
  }

  private func persist() {
    let pins = order.compactMap { url -> SavedPin? in
      guard let panel = windows[url] else { return nil }
      return SavedPin(path: url.path, frame: CodableRect(panel.frame))
    }
    if let data = try? JSONEncoder().encode(pins) {
      defaults.set(data, forKey: Self.defaultsKey)
    }
  }

  /// Returns the `.annotated.png` URL if it exists on disk, otherwise nil.
  private func annotatedURL(for url: URL) -> URL? {
    let annotated = url
      .deletingPathExtension()
      .appendingPathExtension("annotated.png")
    return FileManager.default.fileExists(atPath: annotated.path) ? annotated : nil
  }
}

// MARK: - Panel

/// Borderless pin panel that can take key focus (without activating the app) so
/// Esc / ⌘W unpin and ⌘C copies.
private final class PinnedImagePanel: NSPanel {
  var onClose: (() -> Void)?
  var onCopy: (() -> Void)?
  var onEdit: (() -> Void)?

  override var canBecomeKey: Bool { true }
  override var canBecomeMain: Bool { false }

  override func cancelOperation(_ sender: Any?) {
    onClose?()
  }

  override func performKeyEquivalent(with event: NSEvent) -> Bool {
    let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
    guard mods == .command else { return super.performKeyEquivalent(with: event) }
    switch event.charactersIgnoringModifiers?.lowercased() {
    case "w": onClose?(); return true
    case "c": onCopy?(); return true
    case "e": onEdit?(); return true
    default: return super.performKeyEquivalent(with: event)
    }
  }
}

/// Transient overlay message ("Copied") shown on a pin.
@MainActor
final class PinFeedback: ObservableObject {
  @Published private(set) var message: String?
  private var work: DispatchWorkItem?

  func show(_ text: String) {
    work?.cancel()
    withAnimation(.easeOut(duration: 0.15)) { message = text }
    let item = DispatchWorkItem { [weak self] in
      withAnimation(.easeIn(duration: 0.25)) { self?.message = nil }
    }
    work = item
    DispatchQueue.main.asyncAfter(deadline: .now() + 1.1, execute: item)
  }
}

// MARK: - Panel Delegate

@MainActor
private final class PinnedPanelDelegate: NSObject, NSWindowDelegate {
  private let onClose: () -> Void
  private let onFrameChange: () -> Void

  init(onClose: @escaping () -> Void, onFrameChange: @escaping () -> Void) {
    self.onClose = onClose
    self.onFrameChange = onFrameChange
  }

  func windowWillClose(_ notification: Notification) {
    onClose()
  }

  func windowDidMove(_ notification: Notification) {
    onFrameChange()
  }
}

// MARK: - SwiftUI View

private struct PinnedImageView: View {
  let image: NSImage
  @ObservedObject var feedback: PinFeedback
  let onResize: (CGSize) -> Void
  let onResizeEnded: () -> Void
  let onEdit: () -> Void
  let onCopy: () -> Void
  let onSendToBoard: (() -> Void)?
  let onClose: () -> Void
  @State private var isHovered = false
  @State private var isResizing = false

  var body: some View {
    let controlsVisible = isHovered || isResizing

    ZStack {
      Image(nsImage: image)
        .resizable()
        .aspectRatio(contentMode: .fill)

      VStack {
        HStack(spacing: 4) {
          Spacer()
          CardIconButton(systemName: "doc.on.doc", help: "Copy (⌘C)", action: onCopy)
          CardIconButton(systemName: "pencil", help: "Edit in Editor (⌘E or double-click)", action: onEdit)
          if let onSendToBoard {
            CardIconButton(systemName: "square.grid.2x2", help: "Send to Board", action: onSendToBoard)
          }
          CardIconButton(systemName: "pin.slash", help: "Unpin (Esc)", action: onClose)
        }
        Spacer()
      }
      .padding(8)
      .opacity(controlsVisible ? 1 : 0)
      .allowsHitTesting(controlsVisible)

      if let message = feedback.message {
        Label(message, systemImage: "checkmark.circle.fill")
          .font(.system(size: 12, weight: .semibold))
          .foregroundStyle(.white)
          .padding(.horizontal, 12)
          .padding(.vertical, 6)
          .background(.black.opacity(0.65), in: Capsule())
          .transition(.opacity.combined(with: .scale(scale: 0.9)))
          .allowsHitTesting(false)
      }

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
    .clipShape(RoundedRectangle(cornerRadius: PinStyle.cornerRadius, style: .continuous))
    .overlay {
      RoundedRectangle(cornerRadius: PinStyle.cornerRadius, style: .continuous)
        .strokeBorder(.white.opacity(PinStyle.borderOpacity))
    }
    .contentShape(Rectangle())
    .onHover { hovering in
      withAnimation(.easeOut(duration: 0.12)) { isHovered = hovering }
    }
    .onTapGesture(count: 2, perform: onEdit)
    .contextMenu {
      Button("Edit in Editor") { onEdit() }
      Button("Copy") { onCopy() }
      if let onSendToBoard {
        Button("Send to Board") { onSendToBoard() }
      }
      Divider()
      Button("Unpin") { onClose() }
    }
  }
}

/// Shared look for always-on-top pin windows (pinned images and board cards).
enum PinStyle {
  static let cornerRadius: CGFloat = 12
  static let borderOpacity: Double = 0.14
}

struct ResizeDragSurface: NSViewRepresentable {
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

final class ResizeTrackingView: NSView {
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

struct ResizeCorner: View {
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
