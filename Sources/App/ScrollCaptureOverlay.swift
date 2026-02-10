import SwiftUI
import AppKit

/// Floating overlay shown during scroll capture mode
@MainActor
final class ScrollCaptureOverlay {
  
  private var window: NSPanel?
  private var hostingView: NSHostingView<ScrollCaptureOverlayView>?
  private var frameCount: Int = 0
  private var onDone: (() -> Void)?
  private var onCancel: (() -> Void)?
  
  /// Show the scroll capture overlay
  func show(onDone: @escaping () -> Void, onCancel: @escaping () -> Void) {
    self.onDone = onDone
    self.onCancel = onCancel
    self.frameCount = 0
    
    if let window = window, hostingView != nil {
      updateView()
      if let screen = NSScreen.main {
        let hudWidth: CGFloat = 600
        let x = (screen.frame.width - hudWidth) / 2 + screen.frame.minX
        let y = screen.frame.minY + 60  // 60pt from bottom
        window.setFrameOrigin(NSPoint(x: x, y: y))
      }
      window.orderFront(nil)
      debugLog("ScrollCaptureOverlay: Shown")
      return
    }
    
    let view = ScrollCaptureOverlayView(
      frameCount: frameCount,
      onDone: onDone,
      onCancel: onCancel
    )
    
    let hostingView = NSHostingView(rootView: view)
    self.hostingView = hostingView
    
    // Create HUD-style panel at bottom of screen
    let hudWidth: CGFloat = 600
    let hudHeight: CGFloat = 80
    
    let panel = NSPanel(
      contentRect: NSRect(x: 0, y: 0, width: hudWidth, height: hudHeight),
      styleMask: [.borderless, .nonactivatingPanel, .hudWindow],
      backing: .buffered,
      defer: false
    )
    
    panel.contentView = hostingView
    panel.isFloatingPanel = true
    panel.level = .floating
    panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
    panel.hidesOnDeactivate = false
    panel.backgroundColor = .clear
    panel.isOpaque = false
    panel.sharingType = .none  // Exclude from screen capture
    panel.animationBehavior = .none  // Avoid AppKit transform animations on close
    panel.isReleasedWhenClosed = false
    
    // Position at bottom center of main screen
    if let screen = NSScreen.main {
      let x = (screen.frame.width - hudWidth) / 2 + screen.frame.minX
      let y = screen.frame.minY + 60  // 60pt from bottom
      panel.setFrameOrigin(NSPoint(x: x, y: y))
    }
    
    self.window = panel
    panel.orderFront(nil)
    
    debugLog("ScrollCaptureOverlay: Shown")
  }
  
  /// Update the frame count display
  func updateFrameCount(_ count: Int) {
    self.frameCount = count
    updateView()
  }
  
  /// Update the hosting view's root view
  private func updateView() {
    guard let hostingView = self.hostingView,
          let onDone = self.onDone,
          let onCancel = self.onCancel else { return }
    
    let updatedView = ScrollCaptureOverlayView(
      frameCount: frameCount,
      onDone: onDone,
      onCancel: onCancel
    )
    hostingView.rootView = updatedView
  }
  
  /// Dismiss the overlay
  func dismiss() {
    guard let window = window else {
      debugLog("ScrollCaptureOverlay: dismiss() called but window is nil")
      return
    }
    
    debugLog("ScrollCaptureOverlay: Dismissing overlay")
    
    // Remove from screen first
    window.orderOut(nil)

    debugLog("ScrollCaptureOverlay: Dismissed")
  }
  
  @objc private func handleClose() {
    dismiss()
    onCancel?()
  }
}

// MARK: - SwiftUI View

private struct ScrollCaptureOverlayView: View {
  let frameCount: Int
  let onDone: () -> Void
  let onCancel: () -> Void
  
  var body: some View {
    HStack(spacing: 20) {
      // Icon and status
      HStack(spacing: 12) {
        Image(systemName: "arrow.down.doc.fill")
          .font(.system(size: 24))
          .foregroundColor(.white)
        
        VStack(alignment: .leading, spacing: 2) {
          Text("Scroll Capture")
            .font(.system(size: 13, weight: .semibold))
            .foregroundColor(.white)
          
          HStack(spacing: 6) {
            Image(systemName: "photo.stack")
              .font(.system(size: 11))
            Text("\(frameCount) frames")
              .font(.system(size: 12))
          }
          .foregroundColor(.white.opacity(0.8))
        }
      }
      
      Spacer()
      
      // Buttons
      HStack(spacing: 10) {
        Button("Cancel") {
          onCancel()
        }
        .keyboardShortcut(.cancelAction)
        .buttonStyle(.borderless)
        .foregroundColor(.white.opacity(0.9))
        
        Button("Done") {
          onDone()
        }
        .keyboardShortcut(.defaultAction)
        .disabled(frameCount == 0)
        .buttonStyle(.borderedProminent)
        .tint(.blue)
        .foregroundColor(.white)
        .controlSize(.large)
      }
    }
    .padding(.horizontal, 24)
    .padding(.vertical, 16)
    .frame(width: 600, height: 80)
    .background(
      RoundedRectangle(cornerRadius: 12)
        .fill(Color.black.opacity(0.85))
        .shadow(color: .black.opacity(0.3), radius: 20, y: 10)
    )
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
