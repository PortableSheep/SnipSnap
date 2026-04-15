import AppKit
import SwiftUI

/// NSViewRepresentable bridge for scroll-wheel zoom and middle-click pan.
/// Uses local event monitors so it doesn't block left-click gestures on the Canvas below.
struct ScrollZoomView: NSViewRepresentable {
  @ObservedObject var doc: AnnotationDocument
  let viewSize: CGSize

  func makeNSView(context: Context) -> ScrollZoomNSView {
    let v = ScrollZoomNSView()
    v.doc = doc
    v.viewSize = viewSize
    return v
  }

  func updateNSView(_ nsView: ScrollZoomNSView, context: Context) {
    nsView.doc = doc
    nsView.viewSize = viewSize
  }
}

/// Invisible NSView that installs local event monitors for scroll-wheel and middle-mouse.
/// Returns nil from hitTest so left-click/drag passes through to the SwiftUI Canvas.
final class ScrollZoomNSView: NSView {
  weak var doc: AnnotationDocument?
  var viewSize: CGSize = .zero

  private var scrollMonitor: Any?
  private var otherMouseDownMonitor: Any?
  private var otherMouseDragMonitor: Any?
  private var otherMouseUpMonitor: Any?

  // Middle-click pan state
  private var isPanning = false
  private var panStart: NSPoint = .zero
  private var panStartOffset: CGSize = .zero

  // Transparent to all AppKit hit testing — left-clicks pass through to Canvas
  override func hitTest(_ point: NSPoint) -> NSView? { nil }

  override func viewDidMoveToWindow() {
    super.viewDidMoveToWindow()
    if window != nil {
      installMonitors()
    } else {
      removeMonitors()
    }
  }

  deinit {
    removeMonitors()
  }

  // MARK: - Event Monitors

  private func installMonitors() {
    removeMonitors()

    scrollMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
      guard let self, self.isMouseInBounds(event) else { return event }
      return self.handleScrollWheel(event)
    }

    otherMouseDownMonitor = NSEvent.addLocalMonitorForEvents(matching: .otherMouseDown) { [weak self] event in
      guard let self, event.buttonNumber == 2, self.isMouseInBounds(event) else { return event }
      self.startPan(event)
      return nil
    }

    otherMouseDragMonitor = NSEvent.addLocalMonitorForEvents(matching: .otherMouseDragged) { [weak self] event in
      guard let self, self.isPanning, event.buttonNumber == 2 else { return event }
      self.updatePan(event)
      return nil
    }

    otherMouseUpMonitor = NSEvent.addLocalMonitorForEvents(matching: .otherMouseUp) { [weak self] event in
      guard let self, self.isPanning, event.buttonNumber == 2 else { return event }
      self.endPan()
      return nil
    }
  }

  private func removeMonitors() {
    for monitor in [scrollMonitor, otherMouseDownMonitor, otherMouseDragMonitor, otherMouseUpMonitor] {
      if let m = monitor { NSEvent.removeMonitor(m) }
    }
    scrollMonitor = nil
    otherMouseDownMonitor = nil
    otherMouseDragMonitor = nil
    otherMouseUpMonitor = nil
  }

  /// Check if the event's mouse location is within this view's screen bounds.
  private func isMouseInBounds(_ event: NSEvent) -> Bool {
    guard let window = self.window else { return false }
    let locInWindow = event.locationInWindow
    // Only handle events from our own window
    guard event.window === window else { return false }
    let locInView = convert(locInWindow, from: nil)
    return bounds.contains(locInView)
  }

  // MARK: - Scroll Wheel → Zoom toward cursor

  /// Returns nil to consume discrete scroll events, or the event to pass trackpad scrolls through.
  private func handleScrollWheel(_ event: NSEvent) -> NSEvent? {
    guard let doc else { return event }

    // Trackpad scroll/pinch sends events with phase; let SwiftUI handle those.
    if event.phase != [] || event.momentumPhase != [] {
      return event
    }

    // Discrete scroll wheel (mouse)
    let sensitivity: CGFloat = 0.03
    let factor = 1.0 + (event.scrollingDeltaY * sensitivity)
    let newZoom = max(0.1, min(10.0, doc.zoomLevel * factor))

    if newZoom == doc.zoomLevel { return nil }

    // Zoom toward cursor: keep the point under the cursor stationary.
    let cursorInView = convert(event.locationInWindow, from: nil)
    // Flip Y: NSView is bottom-left origin, SwiftUI is top-left
    let cursorFlipped = CGPoint(x: cursorInView.x, y: bounds.height - cursorInView.y)

    let imageRect = fitRect(imageSize: doc.imageSize, in: viewSize, zoom: doc.zoomLevel, pan: doc.panOffset, padding: effectivePadding)
    let scale = imageRect.width / doc.imageSize.width

    // Point in image space under cursor
    let imgX = (cursorFlipped.x - imageRect.minX) / scale
    let imgY = (cursorFlipped.y - imageRect.minY) / scale

    // Apply zoom
    doc.zoomLevel = newZoom

    // Where that image point now appears with the new zoom
    let newRect = fitRect(imageSize: doc.imageSize, in: viewSize, zoom: newZoom, pan: doc.panOffset, padding: effectivePadding)
    let newScale = newRect.width / doc.imageSize.width
    let newViewX = newRect.minX + imgX * newScale
    let newViewY = newRect.minY + imgY * newScale

    // Adjust pan to compensate
    doc.panOffset = CGSize(
      width: doc.panOffset.width + (cursorFlipped.x - newViewX),
      height: doc.panOffset.height + (cursorFlipped.y - newViewY)
    )

    return nil // Consumed
  }

  // MARK: - Middle Mouse → Pan

  private func startPan(_ event: NSEvent) {
    isPanning = true
    panStart = event.locationInWindow
    panStartOffset = doc?.panOffset ?? .zero
    NSCursor.closedHand.push()
  }

  private func updatePan(_ event: NSEvent) {
    guard let doc else { return }
    let dx = event.locationInWindow.x - panStart.x
    let dy = event.locationInWindow.y - panStart.y
    doc.panOffset = CGSize(
      width: panStartOffset.width + dx,
      // Flip Y delta: NSView Y increases upward, SwiftUI Y increases downward
      height: panStartOffset.height - dy
    )
  }

  private func endPan() {
    isPanning = false
    NSCursor.pop()
  }

  // MARK: - Helpers

  /// Mirror of EditorCanvasView.fitRect — computes the image display rect in SwiftUI coordinates.
  private func fitRect(imageSize: CGSize, in viewSize: CGSize, zoom: CGFloat, pan: CGSize, padding: CGFloat) -> CGRect {
    let totalWidth = imageSize.width + (padding * 2)
    let totalHeight = imageSize.height + (padding * 2)
    guard totalWidth > 0, totalHeight > 0 else { return .zero }

    let scaleX = viewSize.width / totalWidth
    let scaleY = viewSize.height / totalHeight
    let baseScale = min(scaleX, scaleY)
    let scale = baseScale * zoom

    let w = imageSize.width * scale
    let h = imageSize.height * scale

    let x = (viewSize.width - w) / 2 + pan.width
    let y = (viewSize.height - h) / 2 + pan.height

    return CGRect(x: x, y: y, width: w, height: h)
  }

  private var effectivePadding: CGFloat {
    guard let doc else { return 0 }
    return doc.backgroundStyle != .none ? doc.backgroundPadding : 0
  }
}
