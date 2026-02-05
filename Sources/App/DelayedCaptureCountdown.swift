import AppKit

/// A floating countdown window for delayed screen captures.
/// Shows a large countdown number in the center of the screen.
final class DelayedCaptureCountdown {
  private static var window: NSWindow?
  private static var countdownLabel: NSTextField?
  private static var timer: Timer?
  private static var remainingSeconds: Int = 0
  private static var completion: (() -> Void)?
  
  /// Show a countdown window and call completion when finished.
  @MainActor
  static func show(seconds: Int, completion: @escaping () -> Void) {
    dismiss()
    
    self.remainingSeconds = seconds
    self.completion = completion
    
    guard let screen = NSScreen.main else {
      completion()
      return
    }
    
    // Create a small floating window
    let windowSize = CGSize(width: 120, height: 120)
    let screenFrame = screen.frame
    let windowOrigin = CGPoint(
      x: screenFrame.midX - windowSize.width / 2,
      y: screenFrame.midY - windowSize.height / 2
    )
    let windowRect = CGRect(origin: windowOrigin, size: windowSize)
    
    let win = NSWindow(
      contentRect: windowRect,
      styleMask: [.borderless],
      backing: .buffered,
      defer: false
    )
    win.level = .floating
    win.isOpaque = false
    win.backgroundColor = .clear
    win.ignoresMouseEvents = true
    win.collectionBehavior = [.canJoinAllSpaces, .stationary]
    
    // Semi-transparent rounded background
    let bgView = NSVisualEffectView(frame: NSRect(origin: .zero, size: windowSize))
    bgView.material = .hudWindow
    bgView.blendingMode = .behindWindow
    bgView.state = .active
    bgView.wantsLayer = true
    bgView.layer?.cornerRadius = 20
    bgView.layer?.masksToBounds = true
    
    // Countdown label
    let label = NSTextField(labelWithString: "\(seconds)")
    label.font = NSFont.monospacedDigitSystemFont(ofSize: 64, weight: .bold)
    label.textColor = .white
    label.alignment = .center
    label.frame = NSRect(x: 0, y: 20, width: windowSize.width, height: 80)
    
    bgView.addSubview(label)
    win.contentView = bgView
    
    window = win
    countdownLabel = label
    
    win.orderFront(nil)
    
    // Start the countdown timer
    timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
      Task { @MainActor in
        tick()
      }
    }
  }
  
  @MainActor
  private static func tick() {
    remainingSeconds -= 1
    
    if remainingSeconds <= 0 {
      // Time's up - dismiss and trigger capture
      let comp = completion
      dismiss()
      comp?()
    } else {
      // Update the label
      countdownLabel?.stringValue = "\(remainingSeconds)"
      
      // Pulse animation
      if let layer = countdownLabel?.layer {
        let pulse = CABasicAnimation(keyPath: "transform.scale")
        pulse.fromValue = 1.2
        pulse.toValue = 1.0
        pulse.duration = 0.3
        pulse.timingFunction = CAMediaTimingFunction(name: .easeOut)
        layer.add(pulse, forKey: "pulse")
      }
    }
  }
  
  @MainActor
  static func dismiss() {
    timer?.invalidate()
    timer = nil
    window?.orderOut(nil)
    window = nil
    countdownLabel = nil
    completion = nil
    remainingSeconds = 0
  }
}
