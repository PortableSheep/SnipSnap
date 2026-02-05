import AppKit
import Foundation

@MainActor
final class OverlayPreviewWindowController {
  private let overlays: OverlayEventTap
  private let view: RecordingOverlayPreviewNSView
  private let window: NSWindow

  init(overlays: OverlayEventTap) {
    self.overlays = overlays
    self.view = RecordingOverlayPreviewNSView(overlays: overlays)

    let window = NSWindow(
      contentRect: .zero,
      styleMask: [.borderless],
      backing: .buffered,
      defer: false
    )

    window.isOpaque = false
    window.backgroundColor = .clear
    window.hasShadow = false
    window.ignoresMouseEvents = true
    window.level = .statusBar
    window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

    window.contentView = view

    self.window = window
  }

  var windowNumber: Int { window.windowNumber }

  func update(showClicks: Bool, showKeys: Bool, ringColor: CGColor, hudPlacement: HUDPlacement) {
    view.showClicks = showClicks
    view.showKeys = showKeys
    view.ringColor = NSColor(cgColor: ringColor) ?? .white
    view.hudPlacement = hudPlacement
  }

  func show(on screen: NSScreen) {
    let frame = screen.frame
    window.setFrame(frame, display: true)
    window.orderFrontRegardless()
    view.startAnimating()
  }

  func hide() {
    view.stopAnimating()
    window.orderOut(nil)
  }
}

private final class RecordingOverlayPreviewNSView: NSView {
  private let overlays: OverlayEventTap

  var showClicks: Bool = true
  var showKeys: Bool = true
  var ringColor: NSColor = .white
  var hudPlacement: HUDPlacement = .bottomCenter

  private var timer: Timer?

  init(overlays: OverlayEventTap) {
    self.overlays = overlays
    super.init(frame: .zero)
    wantsLayer = true
    layer?.backgroundColor = NSColor.clear.cgColor
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  override func viewDidMoveToWindow() {
    super.viewDidMoveToWindow()
    // Keep animating in sync with visibility.
    if window == nil {
      stopAnimating()
    }
  }

  func startAnimating() {
    guard timer == nil else { return }
    timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
      self?.needsDisplay = true
    }
    RunLoop.main.add(timer!, forMode: .common)
  }

  func stopAnimating() {
    timer?.invalidate()
    timer = nil
    needsDisplay = true
  }

  override func draw(_ dirtyRect: NSRect) {
    super.draw(dirtyRect)

    guard let ctx = NSGraphicsContext.current?.cgContext else { return }
    guard let w = window else { return }

    ctx.clear(bounds)

    let now = CACurrentMediaTime()

    let clickWindow: CFTimeInterval = 0.65
    let keyWindow: CFTimeInterval = 1.25

    let clicks = overlays.recentClicks(since: now - clickWindow)
    let keys = overlays.recentKeys(since: now - keyWindow)

    if showClicks {
      for c in clicks {
        let age = now - c.time
        let t = max(0, min(1, 1 - age / clickWindow))
        let progress = 1 - CGFloat(t)
        let alpha = CGFloat(t) * 0.92

        let pWin = w.convertPoint(fromScreen: NSPoint(x: c.x, y: c.y))

        let baseRadius: CGFloat = 10
        let ringGap: CGFloat = 10
        let radius1: CGFloat = baseRadius + progress * 20
        let radius2: CGFloat = radius1 + ringGap

        ctx.setStrokeColor(ringColor.withAlphaComponent(alpha).cgColor)
        ctx.setLineWidth(3)
        ctx.strokeEllipse(in: CGRect(x: pWin.x - radius1, y: pWin.y - radius1, width: radius1 * 2, height: radius1 * 2))

        ctx.setStrokeColor(ringColor.withAlphaComponent(alpha * 0.78).cgColor)
        ctx.setLineWidth(2)
        ctx.strokeEllipse(in: CGRect(x: pWin.x - radius2, y: pWin.y - radius2, width: radius2 * 2, height: radius2 * 2))
      }
    }

    if showKeys, !keys.isEmpty {
      let maxKeys = 12
      let text = keys.suffix(maxKeys).map { $0.text }.joined(separator: " ")
      drawKeyHUD(text: text, ctx: ctx)
    }
  }

  private func drawKeyHUD(text: String, ctx: CGContext) {
    let paddingX: CGFloat = 12
    let paddingY: CGFloat = 8

    let attrs: [NSAttributedString.Key: Any] = [
      .font: NSFont.systemFont(ofSize: 18, weight: .semibold),
      .foregroundColor: NSColor.white.withAlphaComponent(0.95)
    ]

    let attributed = NSAttributedString(string: text, attributes: attrs)
    let size = attributed.size()

    let w = size.width + paddingX * 2
    let h = size.height + paddingY * 2

    let padding: CGFloat = 22

    let x: CGFloat
    let y: CGFloat
    switch hudPlacement {
    case .bottomCenter:
      x = (bounds.width - w) / 2
      y = padding
    case .topCenter:
      x = (bounds.width - w) / 2
      y = bounds.height - h - padding
    case .bottomLeft:
      x = padding
      y = padding
    case .bottomRight:
      x = bounds.width - w - padding
      y = padding
    case .topLeft:
      x = padding
      y = bounds.height - h - padding
    case .topRight:
      x = bounds.width - w - padding
      y = bounds.height - h - padding
    }

    let rect = CGRect(x: x, y: y, width: w, height: h)

    // Bubble
    ctx.setFillColor(NSColor.black.withAlphaComponent(0.55).cgColor)
    ctx.addPath(CGPath(roundedRect: rect, cornerWidth: 12, cornerHeight: 12, transform: nil))
    ctx.fillPath()

    // Text
    let textRect = CGRect(x: rect.minX + paddingX, y: rect.minY + paddingY, width: size.width, height: size.height)
    attributed.draw(in: textRect)
  }
}
