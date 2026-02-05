import AppKit
import AVKit
import SwiftUI

@MainActor
final class PresentationWindowController {
  private var window: NSWindow?

  func show(items: [CaptureItem], library: CaptureLibrary, title: String = "Presentation") {
    if let window {
      AppActivation.bringToFront(window)
      return
    }

    let view = PresentationView(items: items, library: library, title: title, onToggleFullScreen: { [weak self] in
      self?.toggleFullScreen()
    })
    let hosting = NSHostingView(rootView: view)

    let w = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 980, height: 640),
      styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
      backing: .buffered,
      defer: false
    )
    w.title = "Presentation Mode"
    w.isReleasedWhenClosed = false
    w.center()
    w.contentView = hosting
    w.collectionBehavior = [.fullScreenPrimary]
    w.titlebarAppearsTransparent = true
    w.backgroundColor = .black

    NotificationCenter.default.addObserver(
      forName: NSWindow.willCloseNotification,
      object: w,
      queue: .main
    ) { [weak self] _ in
      Task { @MainActor in
        self?.window = nil
      }
    }

    window = w
    AppActivation.bringToFront(w)
  }
  
  func toggleFullScreen() {
    window?.toggleFullScreen(nil)
  }
}

// MARK: - Video Player View

private struct VideoPlayerView: NSViewRepresentable {
  let url: URL
  
  func makeNSView(context: Context) -> AVPlayerView {
    let playerView = AVPlayerView()
    playerView.controlsStyle = .floating
    playerView.showsFullScreenToggleButton = true
    let player = AVPlayer(url: url)
    playerView.player = player
    return playerView
  }
  
  func updateNSView(_ nsView: AVPlayerView, context: Context) {
    // Only update if URL changed
    if let currentURL = (nsView.player?.currentItem?.asset as? AVURLAsset)?.url, currentURL == url {
      return
    }
    nsView.player?.pause()
    nsView.player = AVPlayer(url: url)
  }
  
  static func dismantleNSView(_ nsView: AVPlayerView, coordinator: ()) {
    nsView.player?.pause()
    nsView.player = nil
  }
}

// MARK: - Presentation View

private struct PresentationView: View {
  let items: [CaptureItem]
  @ObservedObject var library: CaptureLibrary
  let title: String
  let onToggleFullScreen: () -> Void

  @State private var index: Int = 0
  @State private var showUI: Bool = true
  @State private var hideUITask: Task<Void, Never>? = nil
  @State private var showLeftEdge: Bool = false
  @State private var showRightEdge: Bool = false

  private var current: CaptureItem? {
    guard !items.isEmpty else { return nil }
    return items[min(max(0, index), items.count - 1)]
  }
  
  private var isAtStart: Bool { items.isEmpty || index == 0 }
  private var isAtEnd: Bool { items.isEmpty || index >= items.count - 1 }

  var body: some View {
    ZStack {
      // Background
      Color.black
        .ignoresSafeArea()
      
      // Content area (always visible)
      Group {
        if let item = current {
          switch item.kind {
          case .image:
            if let img = NSImage(contentsOf: item.url) {
              Image(nsImage: img)
                .resizable()
                .scaledToFit()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: showUI ? 8 : 0, style: .continuous))
                .padding(showUI ? 20 : 0)
            } else {
              placeholderView("Failed to load image")
            }
          case .video:
            VideoPlayerView(url: item.url)
              .clipShape(RoundedRectangle(cornerRadius: showUI ? 8 : 0, style: .continuous))
              .padding(showUI ? 20 : 0)
          }
        } else {
          placeholderView("No captures to present")
        }
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      .padding(.top, showUI ? 44 : 0)
      .padding(.bottom, showUI ? 52 : 0)
      
      // Edge indicators (boundary feedback)
      HStack(spacing: 0) {
        // Left edge indicator
        Rectangle()
          .fill(
            LinearGradient(
              colors: [.white.opacity(showLeftEdge ? 0.15 : 0), .clear],
              startPoint: .leading,
              endPoint: .trailing
            )
          )
          .frame(width: 40)
          .allowsHitTesting(false)
        
        Spacer()
        
        // Right edge indicator
        Rectangle()
          .fill(
            LinearGradient(
              colors: [.clear, .white.opacity(showRightEdge ? 0.15 : 0)],
              startPoint: .leading,
              endPoint: .trailing
            )
          )
          .frame(width: 40)
          .allowsHitTesting(false)
      }
      .ignoresSafeArea()
      
      // UI Overlay (hideable)
      VStack(spacing: 0) {
        // Top bar
        HStack {
          Text(title)
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(.white.opacity(0.9))

          Spacer()
          
          // Counter
          Text(items.isEmpty ? "No items" : "\(index + 1) / \(items.count)")
            .font(.system(size: 12, weight: .medium).monospacedDigit())
            .foregroundStyle(.white.opacity(0.6))
          
          Spacer()
          
          // Hide UI button
          Button(action: { withAnimation(.easeInOut(duration: 0.2)) { showUI.toggle() } }) {
            Image(systemName: showUI ? "eye.slash" : "eye")
              .font(.system(size: 12, weight: .medium))
              .foregroundStyle(.white.opacity(0.7))
          }
          .buttonStyle(.plain)
          .help("Toggle UI (H)")
          .padding(.trailing, 8)
          
          // Full screen button
          Button(action: onToggleFullScreen) {
            Image(systemName: "arrow.up.left.and.arrow.down.right")
              .font(.system(size: 12, weight: .medium))
              .foregroundStyle(.white.opacity(0.7))
          }
          .buttonStyle(.plain)
          .help("Toggle Full Screen (⌃⌘F)")
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(Color.black.opacity(0.5))

        Spacer()

        // Bottom navigation bar
        HStack(spacing: 20) {
          // Previous button
          Button(action: goPrevious) {
            HStack(spacing: 6) {
              Image(systemName: "chevron.left")
              Text("Previous")
            }
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(isAtStart ? .white.opacity(0.3) : .white.opacity(0.8))
          }
          .buttonStyle(.plain)

          Spacer()
          
          // Filename
          if let item = current {
            Text(item.url.lastPathComponent)
              .font(.system(size: 11))
              .foregroundStyle(.white.opacity(0.4))
              .lineLimit(1)
              .truncationMode(.middle)
          }
          
          Spacer()

          // Next button
          Button(action: goNext) {
            HStack(spacing: 6) {
              Text("Next")
              Image(systemName: "chevron.right")
            }
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(isAtEnd ? .white.opacity(0.3) : .white.opacity(0.8))
          }
          .buttonStyle(.plain)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .background(Color.black.opacity(0.5))
      }
      .opacity(showUI ? 1 : 0)
      .allowsHitTesting(showUI)
    }
    .frame(minWidth: 600, minHeight: 400)
    .onTapGesture {
      // Show UI on tap if hidden, or toggle on double-tap area (content)
      if !showUI {
        withAnimation(.easeInOut(duration: 0.2)) { showUI = true }
        scheduleHideUI()
      }
    }
    .onHover { hovering in
      if hovering && !showUI {
        withAnimation(.easeInOut(duration: 0.2)) { showUI = true }
        scheduleHideUI()
      }
    }
    .background(KeyEventHandlingView(onKeyPress: handleKeyPress))
  }
  
  private func goPrevious() {
    if isAtStart {
      flashEdge(left: true)
    } else {
      index = max(0, index - 1)
    }
  }
  
  private func goNext() {
    if isAtEnd {
      flashEdge(left: false)
    } else {
      index = min(max(0, items.count - 1), index + 1)
    }
  }
  
  private func flashEdge(left: Bool) {
    if left {
      withAnimation(.easeOut(duration: 0.15)) { showLeftEdge = true }
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
        withAnimation(.easeIn(duration: 0.25)) { showLeftEdge = false }
      }
    } else {
      withAnimation(.easeOut(duration: 0.15)) { showRightEdge = true }
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
        withAnimation(.easeIn(duration: 0.25)) { showRightEdge = false }
      }
    }
  }
  
  private func handleKeyPress(_ event: NSEvent) -> Bool {
    switch event.keyCode {
    case 123: // Left arrow
      goPrevious()
      return true // Always consume to prevent video seeking
    case 124: // Right arrow
      goNext()
      return true // Always consume to prevent video seeking
    case 4: // H key
      withAnimation(.easeInOut(duration: 0.2)) { showUI.toggle() }
      if showUI { scheduleHideUI() }
      return true
    case 53: // Escape key - show UI if hidden
      if !showUI {
        withAnimation(.easeInOut(duration: 0.2)) { showUI = true }
        return true
      }
      return false
    default:
      return false
    }
  }
  
  private func scheduleHideUI() {
    hideUITask?.cancel()
    hideUITask = Task {
      try? await Task.sleep(nanoseconds: 3_000_000_000) // 3 seconds
      if !Task.isCancelled {
        await MainActor.run {
          withAnimation(.easeInOut(duration: 0.3)) { showUI = false }
        }
      }
    }
  }
  
  private func placeholderView(_ message: String) -> some View {
    VStack(spacing: 12) {
      Image(systemName: "photo.on.rectangle.angled")
        .font(.system(size: 48))
        .foregroundStyle(.white.opacity(0.3))
      Text(message)
        .font(.system(size: 14))
        .foregroundStyle(.white.opacity(0.5))
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }
}

// MARK: - Key Event Handler

private struct KeyEventHandlingView: NSViewRepresentable {
  let onKeyPress: (NSEvent) -> Bool
  
  func makeNSView(context: Context) -> KeyEventNSView {
    let view = KeyEventNSView()
    view.onKeyPress = onKeyPress
    // Delay to ensure window is ready
    DispatchQueue.main.async {
      view.window?.makeFirstResponder(view)
    }
    return view
  }
  
  func updateNSView(_ nsView: KeyEventNSView, context: Context) {
    nsView.onKeyPress = onKeyPress
    // Ensure we stay first responder
    if nsView.window?.firstResponder != nsView {
      nsView.window?.makeFirstResponder(nsView)
    }
  }
}

private class KeyEventNSView: NSView {
  var onKeyPress: ((NSEvent) -> Bool)?
  
  override var acceptsFirstResponder: Bool { true }
  
  override func viewDidMoveToWindow() {
    super.viewDidMoveToWindow()
    window?.makeFirstResponder(self)
  }
  
  override func keyDown(with event: NSEvent) {
    if onKeyPress?(event) != true {
      super.keyDown(with: event)
    }
  }
}
