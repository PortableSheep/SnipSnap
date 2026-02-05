import Cocoa

/// A floating "Stop Recording" button that appears during recording.
/// This window is excluded from screen capture so it doesn't appear in the video.
@MainActor
final class FloatingStopButtonController {
  private var window: NSPanel?
  private var onStop: (() -> Void)?
  private var elapsedTimer: Timer?
  private var recordingStartTime: Date?
  private var elapsedLabel: NSTextField?
  
  func show(onStop: @escaping () -> Void) {
    self.onStop = onStop
    self.recordingStartTime = Date()
    
    // Create a floating panel
    let panel = NSPanel(
      contentRect: NSRect(x: 0, y: 0, width: 140, height: 36),
      styleMask: [.nonactivatingPanel, .fullSizeContentView],
      backing: .buffered,
      defer: false
    )
    
    panel.isFloatingPanel = true
    panel.level = .floating
    panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
    panel.isMovableByWindowBackground = true
    panel.backgroundColor = .clear
    panel.isOpaque = false
    panel.hasShadow = true
    panel.titlebarAppearsTransparent = true
    panel.titleVisibility = .hidden
    
    // Create the content view with rounded corners
    let contentView = NSView(frame: panel.contentView!.bounds)
    contentView.wantsLayer = true
    contentView.layer?.cornerRadius = 18
    contentView.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.85).cgColor
    
    // Create elapsed time label
    let elapsed = NSTextField(labelWithString: "0:00")
    elapsed.font = NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .medium)
    elapsed.textColor = .white
    elapsed.alignment = .center
    elapsed.translatesAutoresizingMaskIntoConstraints = false
    self.elapsedLabel = elapsed
    
    // Create stop button
    let stopButton = NSButton(frame: .zero)
    stopButton.bezelStyle = .circular
    stopButton.isBordered = false
    stopButton.image = NSImage(systemSymbolName: "stop.fill", accessibilityDescription: "Stop Recording")
    stopButton.contentTintColor = .systemRed
    stopButton.target = self
    stopButton.action = #selector(stopButtonClicked)
    stopButton.translatesAutoresizingMaskIntoConstraints = false
    
    // Add red recording dot
    let recordingDot = NSView(frame: .zero)
    recordingDot.wantsLayer = true
    recordingDot.layer?.cornerRadius = 4
    recordingDot.layer?.backgroundColor = NSColor.systemRed.cgColor
    recordingDot.translatesAutoresizingMaskIntoConstraints = false
    
    // Animate the recording dot
    let pulseAnimation = CABasicAnimation(keyPath: "opacity")
    pulseAnimation.fromValue = 1.0
    pulseAnimation.toValue = 0.3
    pulseAnimation.duration = 0.8
    pulseAnimation.autoreverses = true
    pulseAnimation.repeatCount = .infinity
    recordingDot.layer?.add(pulseAnimation, forKey: "pulse")
    
    contentView.addSubview(recordingDot)
    contentView.addSubview(elapsed)
    contentView.addSubview(stopButton)
    
    NSLayoutConstraint.activate([
      recordingDot.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 12),
      recordingDot.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
      recordingDot.widthAnchor.constraint(equalToConstant: 8),
      recordingDot.heightAnchor.constraint(equalToConstant: 8),
      
      elapsed.leadingAnchor.constraint(equalTo: recordingDot.trailingAnchor, constant: 8),
      elapsed.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
      
      stopButton.leadingAnchor.constraint(equalTo: elapsed.trailingAnchor, constant: 8),
      stopButton.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -8),
      stopButton.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
      stopButton.widthAnchor.constraint(equalToConstant: 28),
      stopButton.heightAnchor.constraint(equalToConstant: 28),
    ])
    
    panel.contentView = contentView
    
    // Position near top-right of main screen
    if let screen = NSScreen.main {
      let screenFrame = screen.visibleFrame
      let x = screenFrame.maxX - panel.frame.width - 20
      let y = screenFrame.maxY - panel.frame.height - 10
      panel.setFrameOrigin(NSPoint(x: x, y: y))
    }
    
    panel.orderFront(nil)
    self.window = panel
    
    // Start elapsed timer
    elapsedTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
      Task { @MainActor in
        self?.updateElapsedTime()
      }
    }
  }
  
  private func updateElapsedTime() {
    guard let startTime = recordingStartTime else { return }
    let elapsed = Int(Date().timeIntervalSince(startTime))
    let minutes = elapsed / 60
    let seconds = elapsed % 60
    elapsedLabel?.stringValue = String(format: "%d:%02d", minutes, seconds)
  }
  
  @objc private func stopButtonClicked() {
    onStop?()
  }
  
  func hide() {
    elapsedTimer?.invalidate()
    elapsedTimer = nil
    window?.close()
    window = nil
    onStop = nil
    recordingStartTime = nil
  }
  
  /// Returns the window ID for exclusion from screen capture
  var windowID: CGWindowID? {
    guard let window = window else { return nil }
    return CGWindowID(window.windowNumber)
  }
  
  /// Check if a screen point (in CG/Quartz coordinates with top-left origin) is within the floating button's window
  /// Used to filter out clicks on the pill from being recorded as overlays
  nonisolated func containsPoint(cgPoint: CGPoint) -> Bool {
    // Access the window frame on the main thread synchronously
    // This is safe because it's just reading a frame value
    var result = false
    DispatchQueue.main.sync { [self] in
      guard let window = window, let screen = window.screen ?? NSScreen.main else { return }
      // Convert from CG coordinates (top-left origin) to Cocoa coordinates (bottom-left origin)
      let cocoaY = screen.frame.height - cgPoint.y
      let cocoaPoint = NSPoint(x: cgPoint.x, y: cocoaY)
      result = window.frame.contains(cocoaPoint)
    }
    return result
  }
}
