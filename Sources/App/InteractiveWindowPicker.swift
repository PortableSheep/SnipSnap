import AppKit
import ScreenCaptureKit
import ApplicationServices

/// Interactive window picker that highlights windows on hover (like CleanShot X)
@available(macOS 13.0, *)
@MainActor
final class InteractiveWindowPicker {
  
  enum SelectionMode {
    case window        // Select entire window
    case subRegion     // Select a region within window (for scroll capture)
  }
  
  struct Selection {
    let windowID: CGWindowID
    let frame: CGRect
    let subRegion: CGRect?  // If in subRegion mode
  }
  
  // Static reference to keep the overlay alive during selection
  private static var activeOverlay: WindowPickerOverlay?
  
  /// Show interactive window picker
  static func pick(mode: SelectionMode = .window) async -> Selection? {
    debugLog("InteractiveWindowPicker: Starting in \(mode) mode")
    
    // Get all screens
    guard let mainScreen = NSScreen.main else {
      debugLog("InteractiveWindowPicker: No main screen found")
      return nil
    }
    
    // Get available windows
    let windowList: [WindowInfo]
    do {
      let content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true)
      windowList = content.windows.compactMap { scWindow -> WindowInfo? in
        guard scWindow.frame.width >= 50, scWindow.frame.height >= 50 else { return nil }
        guard let app = scWindow.owningApplication else { return nil }
        
        // Skip SnipSnap's own windows
        if app.bundleIdentifier.lowercased().contains("snipsnap") { return nil }
        
        return WindowInfo(
          id: scWindow.windowID,
          title: scWindow.title ?? "",
          ownerName: app.applicationName,
          frame: scWindow.frame
        )
      }
      debugLog("InteractiveWindowPicker: Found \(windowList.count) windows")
    } catch {
      debugLog("InteractiveWindowPicker: Failed to get windows: \(error)")
      return nil
    }
    
    guard !windowList.isEmpty else {
      showNoWindowsAlert()
      return nil
    }
    
    return await withCheckedContinuation { continuation in
      let overlay = WindowPickerOverlay(
        screen: mainScreen,
        windows: windowList,
        mode: mode
      ) { selection in
        debugLog("InteractiveWindowPicker: Overlay completed with selection")
        // Clear the reference before resuming
        activeOverlay = nil
        continuation.resume(returning: selection)
      }
      
      // Keep strong reference to prevent deallocation
      activeOverlay = overlay
      overlay.show()
    }
  }
  
  private static func showNoWindowsAlert() {
    let alert = NSAlert()
    alert.messageText = "No Windows Available"
    alert.informativeText = "There are no visible windows to capture. Please open a window and try again."
    alert.alertStyle = .warning
    alert.addButton(withTitle: "OK")
    alert.runModal()
  }
}

// MARK: - Window Picker Overlay

@MainActor
private final class WindowPickerOverlay: NSWindow {
  
  private let mainScreen: NSScreen
  private let windows: [WindowInfo]
  private let mode: InteractiveWindowPicker.SelectionMode
  private let completion: (InteractiveWindowPicker.Selection?) -> Void
  
  private var hoveredWindow: WindowInfo?
  private var highlightLayer: CAShapeLayer?
  private var labelLayer: CATextLayer?
  
  // For subRegion mode
  private var selectedWindow: WindowInfo?
  private var isDraggingRegion = false
  private var regionStart: NSPoint = .zero
  private var regionCurrent: NSPoint = .zero
  private var regionLayer: CAShapeLayer?
  
  private var trackingArea: NSTrackingArea?
  
  // Prevent multiple completions
  private var hasCompleted = false
  
  init(
    screen: NSScreen,
    windows: [WindowInfo],
    mode: InteractiveWindowPicker.SelectionMode,
    completion: @escaping (InteractiveWindowPicker.Selection?) -> Void
  ) {
    self.mainScreen = screen
    self.windows = windows
    self.mode = mode
    self.completion = completion
    
    super.init(
      contentRect: screen.frame,
      styleMask: [.borderless],
      backing: .buffered,
      defer: false
    )
    
    level = .screenSaver
    isOpaque = false
    backgroundColor = NSColor(calibratedWhite: 0, alpha: 0.2)
    ignoresMouseEvents = false
    collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
    acceptsMouseMovedEvents = true
    
    setupLayers()
    setupTracking()
    
    // Show instruction text
    showInstructions()
  }
  
  private func setupLayers() {
    guard let contentView = contentView else { return }
    contentView.wantsLayer = true
    
    // Highlight layer for window borders
    let highlight = CAShapeLayer()
    highlight.fillColor = NSColor.clear.cgColor
    highlight.strokeColor = NSColor.systemBlue.cgColor
    highlight.lineWidth = 4
    highlight.shadowColor = NSColor.black.cgColor
    highlight.shadowOpacity = 0.5
    highlight.shadowOffset = .zero
    highlight.shadowRadius = 8
    contentView.layer?.addSublayer(highlight)
    self.highlightLayer = highlight
    
    // Label layer for window info
    let label = CATextLayer()
    label.fontSize = 14
    label.foregroundColor = NSColor.white.cgColor
    label.backgroundColor = NSColor(calibratedWhite: 0, alpha: 0.8).cgColor
    label.cornerRadius = 6
    label.padding = 8
    label.alignmentMode = .center
    label.contentsScale = NSScreen.main?.backingScaleFactor ?? 2.0
    label.isHidden = true
    contentView.layer?.addSublayer(label)
    self.labelLayer = label
    
    // Region selection layer (for subRegion mode)
    if mode == .subRegion {
      let region = CAShapeLayer()
      region.fillColor = NSColor.systemBlue.withAlphaComponent(0.2).cgColor
      region.strokeColor = NSColor.systemBlue.cgColor
      region.lineWidth = 2
      region.isHidden = true
      contentView.layer?.addSublayer(region)
      self.regionLayer = region
    }
  }
  
  private func setupTracking() {
    guard let contentView = contentView else { return }
    let tracking = NSTrackingArea(
      rect: contentView.bounds,
      options: [.activeAlways, .mouseMoved, .mouseEnteredAndExited, .inVisibleRect],
      owner: self,
      userInfo: nil
    )
    contentView.addTrackingArea(tracking)
    self.trackingArea = tracking
  }
  
  private func showInstructions() {
    guard let contentView = contentView else { return }
    
    let instruction = CATextLayer()
    if mode == .window {
      instruction.string = "Click on a window to select it • ESC to cancel"
    } else {
      instruction.string = "Click and drag to select the scrollable region • ESC to cancel"
    }
    instruction.fontSize = 15
    instruction.foregroundColor = NSColor.white.cgColor
    instruction.backgroundColor = NSColor(calibratedWhite: 0, alpha: 0.8).cgColor
    instruction.cornerRadius = 8
    instruction.alignmentMode = .center
    instruction.contentsScale = NSScreen.main?.backingScaleFactor ?? 2.0
    
    let textWidth: CGFloat = 500
    let textHeight: CGFloat = 36
    let padding: CGFloat = 16
    
    instruction.frame = CGRect(
      x: (frame.width - textWidth) / 2,
      y: frame.height - 80,
      width: textWidth,
      height: textHeight
    )
    
    contentView.layer?.addSublayer(instruction)
    
    // Fade out after 4 seconds
    DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
      CATransaction.begin()
      CATransaction.setAnimationDuration(0.8)
      instruction.opacity = 0
      CATransaction.commit()
    }
  }
  
  func show() {
    NSApp.activate(ignoringOtherApps: true)
    makeKeyAndOrderFront(nil)
    orderFrontRegardless()
  }
  
  override var canBecomeKey: Bool { true }
  override var canBecomeMain: Bool { true }
  
  // MARK: - Mouse Events
  
  override func mouseMoved(with event: NSEvent) {
    // Only highlight windows in window mode, not in subRegion mode
    if mode == .window {
      let locationInWindow = event.locationInWindow
      updateHoveredWindow(at: locationInWindow)
    }
  }
  
  override func mouseDown(with event: NSEvent) {
    guard !hasCompleted else { return }
    
    let locationInWindow = event.locationInWindow
    debugLog("InteractiveWindowPicker: mouseDown at \(locationInWindow)")
    
    if mode == .window {
      // Direct selection in window mode
      if let window = hoveredWindow {
        debugLog("InteractiveWindowPicker: Window mode - selecting window \(window.id)")
        complete(with: InteractiveWindowPicker.Selection(
          windowID: window.id,
          frame: window.frame,
          subRegion: nil
        ))
      }
    } else if mode == .subRegion {
      // Start manual drag selection - no window needed
      debugLog("InteractiveWindowPicker: SubRegion mode - starting drag at \(locationInWindow)")
      isDraggingRegion = true
      regionStart = locationInWindow
      regionCurrent = locationInWindow
      
      updateRegionSelection()
    }
  }
  
  override func mouseDragged(with event: NSEvent) {
    guard !hasCompleted else { return }
    
    if mode == .subRegion && isDraggingRegion {
      regionCurrent = event.locationInWindow
      updateRegionSelection()
    }
  }
  
  override func mouseUp(with event: NSEvent) {
    guard !hasCompleted else { return }
    
    debugLog("InteractiveWindowPicker: mouseUp at \(event.locationInWindow)")
    
    if mode == .subRegion && isDraggingRegion {
      isDraggingRegion = false
      regionCurrent = event.locationInWindow
      
      // Calculate selected region in window coordinates
      let windowRect = regionRect()
      debugLog("InteractiveWindowPicker: Region rect (window coords) = \(windowRect)")
      
      // Validate region size
      guard windowRect.width > 10 && windowRect.height > 10 else {
        debugLog("InteractiveWindowPicker: Region too small (\(windowRect.width)x\(windowRect.height)), resetting")
        regionLayer?.isHidden = true
        return
      }
      
      // Convert window coordinates to screen coordinates
      // The overlay window has its origin at the screen's origin
      // macOS uses bottom-left origin, so we need to flip Y
      let screenFrame = mainScreen.frame
      
      // Window coords are already relative to screen origin since window.frame = screen.frame
      // But Y is flipped (top-left in AppKit vs bottom-left in CG)
      let screenRect = CGRect(
        x: windowRect.origin.x,
        y: screenFrame.height - windowRect.origin.y - windowRect.height,
        width: windowRect.width,
        height: windowRect.height
      )
      
      debugLog("InteractiveWindowPicker: Selected sub-region \(screenRect) (screen coords, flipped)")
      
      // We don't need a windowID for region-only capture
      complete(with: InteractiveWindowPicker.Selection(
        windowID: 0,  // Dummy value, not used for region capture
        frame: screenRect,
        subRegion: screenRect
      ))
    }
  }
  
  override func keyDown(with event: NSEvent) {
    guard !hasCompleted else { return }
    
    if event.keyCode == 53 { // Escape
      debugLog("InteractiveWindowPicker: User cancelled with ESC")
      complete(with: nil)
    }
  }
  
  // MARK: - Window Highlighting
  
  private func updateHoveredWindow(at point: NSPoint) {
    // Find window under cursor
    var newHovered: WindowInfo?
    
    for window in windows {
      if window.frame.contains(point) {
        // If multiple windows overlap, pick the topmost one (first in list)
        newHovered = window
        break
      }
    }
    
    guard newHovered?.id != hoveredWindow?.id else { return }
    
    hoveredWindow = newHovered
    
    if let window = hoveredWindow {
      highlightWindow(window)
    } else {
      clearHighlight()
    }
  }
  
  private func highlightWindow(_ window: WindowInfo) {
    let path = CGPath(rect: window.frame, transform: nil)
    highlightLayer?.path = path
    
    // Update label
    labelLayer?.string = window.displayName
    
    let labelWidth: CGFloat = 300
    let labelHeight: CGFloat = 40
    let labelX = min(max(window.frame.midX - labelWidth / 2, 20), frame.width - labelWidth - 20)
    let labelY = window.frame.maxY + 10
    
    labelLayer?.frame = CGRect(x: labelX, y: labelY, width: labelWidth, height: labelHeight)
    labelLayer?.isHidden = false
  }
  
  private func clearHighlight() {
    highlightLayer?.path = nil
    labelLayer?.isHidden = true
  }
  
  // MARK: - Region Selection
  
  private func updateRegionSelection() {
    let rect = regionRect()
    let path = CGPath(rect: rect, transform: nil)
    regionLayer?.path = path
    regionLayer?.isHidden = false
  }
  
  private func regionRect() -> CGRect {
    CGRect(
      x: min(regionStart.x, regionCurrent.x),
      y: min(regionStart.y, regionCurrent.y),
      width: abs(regionCurrent.x - regionStart.x),
      height: abs(regionCurrent.y - regionStart.y)
    )
  }
  
  // MARK: - Completion
  
  private func complete(with selection: InteractiveWindowPicker.Selection?) {
    guard !hasCompleted else {
      debugLog("InteractiveWindowPicker: Already completed, ignoring duplicate completion")
      return
    }
    
    hasCompleted = true
    debugLog("InteractiveWindowPicker: Completing with selection: windowID=\(selection?.windowID.description ?? "nil"), subRegion=\(selection?.subRegion?.debugDescription ?? "nil")")
    
    // Disable mouse events immediately to prevent further interactions
    ignoresMouseEvents = true
    
    // Hide all visual feedback
    highlightLayer?.isHidden = true
    labelLayer?.isHidden = true
    regionLayer?.isHidden = true
    
    // Close the window
    orderOut(nil)
    
    // Call completion handler after a brief delay to ensure window is fully closed
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [completion] in
      completion(selection)
    }
  }
}

// MARK: - CALayer Extension for Padding

private extension CATextLayer {
  var padding: CGFloat {
    get { 0 }
    set {
      // CATextLayer doesn't support padding directly - this is a placeholder
      _ = newValue
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
