import AppKit
import SwiftUI

/// Visual border overlay showing the capture region during scroll capture
/// This window is excluded from screen captures so it doesn't appear in the output
@MainActor
final class ScrollCaptureRegionDecorator {
  
  private var window: NSWindow?
  
  /// Show a border around the capture region
  func show(region: CGRect) {
    // The region is in CG screen coordinates (bottom-left origin)
    // NSWindow contentRect also uses bottom-left origin, so we can use it directly
    // BUT: NSWindow.setFrame() expects bottom-left, while the contentRect in init is also bottom-left
    
    // However, there's a subtlety: NSWindow's coordinate system has Y=0 at the BOTTOM of the screen
    // while CGDisplayCreateImage has Y=0 at the TOP
    // So we need to flip the Y coordinate
    
    guard let screen = NSScreen.main else {
      debugLog("ScrollCaptureRegionDecorator: No main screen found")
      return
    }
    
    let screenHeight = screen.frame.height
    
    // Convert from CG coords (Y=0 at top) to NSWindow coords (Y=0 at bottom)
    let windowRect = CGRect(
      x: region.origin.x,
      y: screenHeight - region.origin.y - region.size.height,
      width: region.size.width,
      height: region.size.height
    )
    
    debugLog("ScrollCaptureRegionDecorator: Region CG coords: \(region)")
    debugLog("ScrollCaptureRegionDecorator: Window AppKit coords: \(windowRect)")
    debugLog("ScrollCaptureRegionDecorator: Screen height: \(screenHeight)")
    
    if let window = window {
      window.setFrame(windowRect, display: true)
      if let borderView = window.contentView as? BorderView {
        borderView.frame = NSRect(origin: .zero, size: region.size)
        borderView.needsDisplay = true
      }
      window.orderFront(nil)
      debugLog("ScrollCaptureRegionDecorator: Window frame after orderFront: \(window.frame)")
      return
    }
    
    // Create a borderless window that matches the region
    let window = NSWindow(
      contentRect: windowRect,
      styleMask: [.borderless],
      backing: .buffered,
      defer: false
    )
    
    // Create a view that draws a border (uses bounds, not region)
    let borderView = BorderView(frame: NSRect(origin: .zero, size: region.size))
    window.contentView = borderView
    
    // Window configuration
    window.isOpaque = false
    window.backgroundColor = .clear
    window.level = .floating
    window.ignoresMouseEvents = true
    window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
    window.animationBehavior = .none  // Avoid AppKit transform animations on close
    window.isReleasedWhenClosed = false
    
    // CRITICAL: Exclude from screen recording/capture
    window.sharingType = .none
    
    self.window = window
    window.orderFront(nil)
    
    debugLog("ScrollCaptureRegionDecorator: Window frame after orderFront: \(window.frame)")
  }
  
  /// Dismiss the border overlay
  func dismiss() {
    guard let window = window else { return }  // Prevent double-dismiss
    
    debugLog("ScrollCaptureRegionDecorator: Dismissing window")
    
    // Remove from screen first
    window.orderOut(nil)
    debugLog("ScrollCaptureRegionDecorator: Dismissed")
  }
}

// MARK: - Border View

private class BorderView: NSView {
  
  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    self.wantsLayer = true
  }
  
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }
  
  override func draw(_ dirtyRect: NSRect) {
    super.draw(dirtyRect)
    
    guard let context = NSGraphicsContext.current?.cgContext else { return }
    
    // Draw a thin dashed border
    let borderWidth: CGFloat = 2
    let dashPhase: CGFloat = 0
    
    // Red dashed line with subtle glow
    context.saveGState()
    context.setShadow(offset: .zero, blur: 3, color: NSColor.systemRed.withAlphaComponent(0.4).cgColor)
    context.setStrokeColor(NSColor.systemRed.cgColor)
    context.setLineWidth(borderWidth)
    context.setLineDash(phase: dashPhase, lengths: [8, 6])
    
    let insetRect = bounds.insetBy(dx: borderWidth / 2, dy: borderWidth / 2)
    context.stroke(insetRect)
    context.restoreGState()
    
    // Corner indicators (small dots at corners)
    let cornerSize: CGFloat = 6
    let cornerRects = [
      CGRect(x: 4, y: 4, width: cornerSize, height: cornerSize),  // Bottom-left
      CGRect(x: bounds.width - cornerSize - 4, y: 4, width: cornerSize, height: cornerSize),  // Bottom-right
      CGRect(x: 4, y: bounds.height - cornerSize - 4, width: cornerSize, height: cornerSize),  // Top-left
      CGRect(x: bounds.width - cornerSize - 4, y: bounds.height - cornerSize - 4, width: cornerSize, height: cornerSize)  // Top-right
    ]
    
    context.setFillColor(NSColor.systemRed.cgColor)
    
    for rect in cornerRects {
      context.fillEllipse(in: rect)
    }
  }
}

// MARK: - Debug Logging

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
