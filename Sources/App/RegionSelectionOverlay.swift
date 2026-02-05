import AppKit

final class RegionSelectionOverlay: NSWindow {
  private var startPoint: NSPoint = .zero
  private var currentPoint: NSPoint = .zero
  private var isDragging = false
  private let shapeLayer = CAShapeLayer()

  init(screen: NSScreen) {
    super.init(
      contentRect: screen.frame,
      styleMask: [.borderless],
      backing: .buffered,
      defer: false
    )
    level = .screenSaver  // Higher level to be above everything
    isOpaque = false
    backgroundColor = NSColor(calibratedWhite: 0, alpha: 0.3)  // Semi-transparent background so user can see they're selecting
    ignoresMouseEvents = false
    collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
    acceptsMouseMovedEvents = true
    
    let view = NSView(frame: screen.frame)
    view.wantsLayer = true
    view.layer?.addSublayer(shapeLayer)
    contentView = view

    shapeLayer.fillColor = NSColor(calibratedWhite: 1, alpha: 0.2).cgColor
    shapeLayer.strokeColor = NSColor.systemBlue.cgColor
    shapeLayer.lineWidth = 2
  }
  
  override var canBecomeKey: Bool { true }
  override var canBecomeMain: Bool { true }

  override func mouseDown(with event: NSEvent) {
    debugLog("RegionSelectionOverlay: mouseDown at \(event.locationInWindow)")
    isDragging = true
    startPoint = event.locationInWindow
    currentPoint = startPoint
    updatePath()
  }

  override func mouseDragged(with event: NSEvent) {
    guard isDragging else { return }
    currentPoint = event.locationInWindow
    updatePath()
  }

  override func mouseUp(with event: NSEvent) {
    debugLog("RegionSelectionOverlay: mouseUp at \(event.locationInWindow), startPoint was \(startPoint)")
    guard isDragging else { return }
    isDragging = false
    currentPoint = event.locationInWindow
    updatePath()
    close()
  }
  
  override func keyDown(with event: NSEvent) {
    // Allow Escape to cancel
    if event.keyCode == 53 { // Escape key
      debugLog("RegionSelectionOverlay: Escape pressed, cancelling")
      startPoint = .zero
      currentPoint = .zero
      close()
    }
  }

  private func updatePath() {
    let rect = selectionRect()
    let path = CGPath(rect: rect, transform: nil)
    shapeLayer.path = path
  }

  private func selectionRect() -> CGRect {
    CGRect(
      x: min(startPoint.x, currentPoint.x),
      y: min(startPoint.y, currentPoint.y),
      width: abs(currentPoint.x - startPoint.x),
      height: abs(currentPoint.y - startPoint.y)
    )
  }

  static func select() async -> CGRect? {
    await withCheckedContinuation { cont in
      guard let screen = NSScreen.main else {
        debugLog("RegionSelectionOverlay: No main screen")
        cont.resume(returning: nil)
        return
      }
      debugLog("RegionSelectionOverlay: Starting selection on screen: \(screen.frame)")
      NSRunningApplication.current.activate(options: [.activateAllWindows, .activateIgnoringOtherApps])
      NSApp.activate(ignoringOtherApps: true)
      let overlay = RegionSelectionOverlay(screen: screen)
      overlay.makeKeyAndOrderFront(nil)
      overlay.orderFrontRegardless()
      debugLog("RegionSelectionOverlay: Overlay shown, waiting for selection")

      NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: overlay, queue: nil) { _ in
        let rect = overlay.selectionRect()
        debugLog("RegionSelectionOverlay: Selection completed: \(rect)")
        if rect.width > 2 && rect.height > 2 {
          cont.resume(returning: rect)
        } else {
          debugLog("RegionSelectionOverlay: Selection too small or cancelled")
          cont.resume(returning: nil)
        }
      }
    }
  }
}

private func debugLog(_ message: String) {
  let logFile = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("snipsnap-debug.log")
  let timestamp = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
  let line = "[\(timestamp)] \(message)\n"
  if let data = line.data(using: .utf8) {
    if FileManager.default.fileExists(atPath: logFile.path) {
      if let fileHandle = try? FileHandle(forWritingTo: logFile) {
        fileHandle.seekToEndOfFile()
        fileHandle.write(data)
        fileHandle.closeFile()
      }
    } else {
      try? data.write(to: logFile)
    }
  }
}
