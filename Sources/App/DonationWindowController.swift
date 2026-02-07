import AppKit
import SwiftUI

@MainActor
final class DonationWindowController {
  static let shared = DonationWindowController()
  
  private var window: NSWindow?
  
  private init() {}
  
  func show() {
    if let existing = window {
      existing.makeKeyAndOrderFront(nil)
      NSApp.activate(ignoringOtherApps: true)
      return
    }
    
    let view = DonationView(onClose: { [weak self] in
      self?.window?.close()
    })
    let hosting = NSHostingView(rootView: view)
    
    let win = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 480, height: 420),
      styleMask: [.titled, .closable],
      backing: .buffered,
      defer: false
    )
    win.title = "Support SnipSnap"
    win.center()
    win.contentView = hosting
    win.isReleasedWhenClosed = false
    
    window = win
    win.makeKeyAndOrderFront(nil)
    NSApp.activate(ignoringOtherApps: true)
  }
}

struct DonationView: View {
  let onClose: () -> Void
  
  var body: some View {
    VStack(spacing: 24) {
      // Header
      VStack(spacing: 8) {
        Image(systemName: "gift.fill")
          .font(.system(size: 48))
          .foregroundColor(.pink)
        
        Text("Support SnipSnap")
          .font(.title)
          .fontWeight(.bold)
        
        Text("SnipSnap is free and open source")
          .font(.subheadline)
          .foregroundColor(.secondary)
      }
      .padding(.top, 20)
      
      // Description
      Text("If you find SnipSnap useful, please consider supporting its development. Your support helps keep the project alive and enables new features.")
        .multilineTextAlignment(.center)
        .foregroundColor(.secondary)
        .padding(.horizontal)
      
      Spacer()
      
      // Donation buttons
      VStack(spacing: 12) {
        Button(action: {
          if let url = URL(string: "https://buy.stripe.com/aFa6oHbuj9a9f2M4Hk5Ne02") {
            NSWorkspace.shared.open(url)
          }
          onClose()
        }) {
          HStack {
            Image(systemName: "creditcard.fill")
            Text("One-Time Donation")
              .fontWeight(.semibold)
          }
          .frame(maxWidth: .infinity)
          .padding(.vertical, 12)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        
        Button(action: {
          if let url = URL(string: "https://github.com/sponsors/PortableSheep") {
            NSWorkspace.shared.open(url)
          }
          onClose()
        }) {
          HStack {
            Image(systemName: "heart.fill")
            Text("Become a Sponsor")
              .fontWeight(.semibold)
          }
          .frame(maxWidth: .infinity)
          .padding(.vertical, 12)
        }
        .buttonStyle(.bordered)
        .controlSize(.large)
      }
      .padding(.horizontal, 32)
      
      Spacer()
      
      // Footer
      Text("Thank you for using SnipSnap! 🎉")
        .font(.caption)
        .foregroundColor(.secondary)
        .padding(.bottom, 16)
    }
    .frame(width: 480, height: 420)
  }
}
