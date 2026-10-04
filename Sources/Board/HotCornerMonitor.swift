import AppKit

/// Detects the pointer resting in a screen corner using tiny transparent panels with tracking
/// areas — no Accessibility or Input Monitoring permission required.
@MainActor
final class HotCornerMonitor {
  private var panels: [NSPanel] = []
  private var dwellWork: DispatchWorkItem?
  private var screenObserver: NSObjectProtocol?
  private(set) var corner: HotCorner = .none
  private var delay: TimeInterval = 0.25
  private var lastFire = Date.distantPast

  var onTrigger: (() -> Void)?

  /// Size of the hot zone in points (kept tiny so it doesn't steal clicks from e.g. the Apple menu).
  static let size: CGFloat = 2

  init() {
    screenObserver = NotificationCenter.default.addObserver(
      forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
    ) { [weak self] _ in
      Task { @MainActor in self?.rebuild() }
    }
  }

  deinit {
    if let screenObserver { NotificationCenter.default.removeObserver(screenObserver) }
  }

  func configure(corner: HotCorner, delay: TimeInterval) {
    self.corner = corner
    self.delay = max(0, delay)
    rebuild()
  }

  private func rebuild() {
    for panel in panels { panel.orderOut(nil) }
    panels.removeAll()
    guard corner != .none else { return }
    for screen in NSScreen.screens {
      let frame = Self.cornerRect(corner, in: screen.frame, size: Self.size)
      let panel = NSPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
      panel.level = .screenSaver
      panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
      panel.isOpaque = false
      panel.backgroundColor = .clear
      panel.hasShadow = false
      panel.ignoresMouseEvents = false
      panel.hidesOnDeactivate = false
      panel.isReleasedWhenClosed = false
      let view = CornerTrackingView(frame: NSRect(origin: .zero, size: frame.size))
      view.onEnter = { [weak self] in self?.pointerEntered() }
      view.onExit = { [weak self] in self?.pointerExited() }
      panel.contentView = view
      panel.orderFrontRegardless()
      panels.append(panel)
    }
  }

  private func pointerEntered() {
    dwellWork?.cancel()
    let work = DispatchWorkItem { [weak self] in
      guard let self else { return }
      // Ignore if the user is dragging something into the corner.
      guard NSEvent.pressedMouseButtons == 0 else { return }
      guard Date().timeIntervalSince(self.lastFire) > 0.8 else { return }
      self.lastFire = Date()
      self.onTrigger?()
    }
    dwellWork = work
    DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
  }

  private func pointerExited() {
    dwellWork?.cancel()
    dwellWork = nil
  }

  static func cornerRect(_ corner: HotCorner, in frame: CGRect, size: CGFloat) -> CGRect {
    switch corner {
    case .none: return .zero
    case .topLeft: return CGRect(x: frame.minX, y: frame.maxY - size, width: size, height: size)
    case .topRight: return CGRect(x: frame.maxX - size, y: frame.maxY - size, width: size, height: size)
    case .bottomLeft: return CGRect(x: frame.minX, y: frame.minY, width: size, height: size)
    case .bottomRight: return CGRect(x: frame.maxX - size, y: frame.minY, width: size, height: size)
    }
  }
}

private final class CornerTrackingView: NSView {
  var onEnter: (() -> Void)?
  var onExit: (() -> Void)?

  override func updateTrackingAreas() {
    super.updateTrackingAreas()
    for area in trackingAreas { removeTrackingArea(area) }
    addTrackingArea(NSTrackingArea(
      rect: bounds,
      options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
      owner: self
    ))
  }

  override func mouseEntered(with event: NSEvent) { onEnter?() }
  override func mouseExited(with event: NSEvent) { onExit?() }
  override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}
