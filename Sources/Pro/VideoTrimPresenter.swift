import AppKit
import AVFoundation
import AVKit
import Foundation

// MARK: - Video Trim Window Controller

@MainActor
final class VideoTrimWindowController: NSWindowController {
  private let inputURL: URL
  private let asset: AVAsset
  private let duration: Double
  
  private var player: AVPlayer!
  private var playerView: AVPlayerView!
  private var filmStripView: FilmStripView!
  private var trimHandleView: TrimHandleView!
  private var timeLabel: NSTextField!
  private var playButton: NSButton!
  
  private var timeObserver: Any?
  
  init(inputURL: URL, asset: AVAsset, duration: Double) {
    self.inputURL = inputURL
    self.asset = asset
    self.duration = duration
    
    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 640, height: 480),
      styleMask: [.titled, .closable, .resizable],
      backing: .buffered,
      defer: false
    )
    window.title = "Trim Video"
    window.minSize = NSSize(width: 500, height: 400)
    window.isReleasedWhenClosed = false
    
    super.init(window: window)
    
    setupUI()
    setupPlayer()
  }
  
  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }
  
  private func setupUI() {
    guard let window = window else { return }
    
    let contentView = NSView()
    contentView.wantsLayer = true
    contentView.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
    window.contentView = contentView
    
    // Video player view
    playerView = AVPlayerView()
    playerView.controlsStyle = .none
    playerView.translatesAutoresizingMaskIntoConstraints = false
    contentView.addSubview(playerView)
    
    // Time label
    timeLabel = NSTextField(labelWithString: "0:00 / 0:00")
    timeLabel.font = .monospacedDigitSystemFont(ofSize: 12, weight: .medium)
    timeLabel.textColor = .secondaryLabelColor
    timeLabel.alignment = .center
    timeLabel.translatesAutoresizingMaskIntoConstraints = false
    contentView.addSubview(timeLabel)
    
    // Film strip container
    let filmStripContainer = NSView()
    filmStripContainer.wantsLayer = true
    filmStripContainer.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.3).cgColor
    filmStripContainer.layer?.cornerRadius = 8
    filmStripContainer.translatesAutoresizingMaskIntoConstraints = false
    contentView.addSubview(filmStripContainer)
    
    // Film strip (thumbnails)
    filmStripView = FilmStripView(asset: asset, duration: duration)
    filmStripView.translatesAutoresizingMaskIntoConstraints = false
    filmStripContainer.addSubview(filmStripView)
    
    // Trim handles overlay
    trimHandleView = TrimHandleView(duration: duration)
    trimHandleView.translatesAutoresizingMaskIntoConstraints = false
    trimHandleView.onTrimChanged = { [weak self] start, end in
      self?.handleTrimChanged(start: start, end: end)
    }
    trimHandleView.onScrub = { [weak self] time in
      self?.scrubTo(time: time)
    }
    filmStripContainer.addSubview(trimHandleView)
    
    // Button row
    let buttonStack = NSStackView()
    buttonStack.orientation = .horizontal
    buttonStack.spacing = 12
    buttonStack.translatesAutoresizingMaskIntoConstraints = false
    contentView.addSubview(buttonStack)
    
    // Play/Pause button
    playButton = NSButton(image: NSImage(systemSymbolName: "play.fill", accessibilityDescription: "Play")!, target: self, action: #selector(togglePlayback))
    playButton.bezelStyle = .circular
    playButton.isBordered = false
    playButton.imageScaling = .scaleProportionallyUpOrDown
    playButton.setContentHuggingPriority(.defaultHigh, for: .horizontal)
    
    let spacer = NSView()
    spacer.translatesAutoresizingMaskIntoConstraints = false
    
    let cancelButton = NSButton(title: "Cancel", target: self, action: #selector(cancel))
    cancelButton.bezelStyle = .rounded
    cancelButton.keyEquivalent = "\u{1B}" // Escape
    
    let exportButton = NSButton(title: "Export Trimmed", target: self, action: #selector(exportTrimmed))
    exportButton.bezelStyle = .rounded
    exportButton.keyEquivalent = "\r"
    
    buttonStack.addArrangedSubview(playButton)
    buttonStack.addArrangedSubview(spacer)
    buttonStack.addArrangedSubview(cancelButton)
    buttonStack.addArrangedSubview(exportButton)
    
    NSLayoutConstraint.activate([
      // Player view
      playerView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 16),
      playerView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
      playerView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
      
      // Time label
      timeLabel.topAnchor.constraint(equalTo: playerView.bottomAnchor, constant: 8),
      timeLabel.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
      
      // Film strip container
      filmStripContainer.topAnchor.constraint(equalTo: timeLabel.bottomAnchor, constant: 12),
      filmStripContainer.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
      filmStripContainer.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
      filmStripContainer.heightAnchor.constraint(equalToConstant: 60),
      
      // Film strip inside container
      filmStripView.topAnchor.constraint(equalTo: filmStripContainer.topAnchor, constant: 4),
      filmStripView.bottomAnchor.constraint(equalTo: filmStripContainer.bottomAnchor, constant: -4),
      filmStripView.leadingAnchor.constraint(equalTo: filmStripContainer.leadingAnchor, constant: 12),
      filmStripView.trailingAnchor.constraint(equalTo: filmStripContainer.trailingAnchor, constant: -12),
      
      // Trim handles overlay
      trimHandleView.topAnchor.constraint(equalTo: filmStripView.topAnchor),
      trimHandleView.bottomAnchor.constraint(equalTo: filmStripView.bottomAnchor),
      trimHandleView.leadingAnchor.constraint(equalTo: filmStripView.leadingAnchor),
      trimHandleView.trailingAnchor.constraint(equalTo: filmStripView.trailingAnchor),
      
      // Button row
      buttonStack.topAnchor.constraint(equalTo: filmStripContainer.bottomAnchor, constant: 16),
      buttonStack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
      buttonStack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
      buttonStack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -16),
      buttonStack.heightAnchor.constraint(equalToConstant: 32),
      
      // Spacer expands
      spacer.widthAnchor.constraint(greaterThanOrEqualToConstant: 1),
      
      // Player aspect ratio (16:9 default, will resize with window)
      playerView.heightAnchor.constraint(lessThanOrEqualTo: playerView.widthAnchor, multiplier: 9.0/16.0),
      playerView.heightAnchor.constraint(greaterThanOrEqualToConstant: 200),
    ])
    
    updateTimeLabel()
  }
  
  private func setupPlayer() {
    let playerItem = AVPlayerItem(asset: asset)
    player = AVPlayer(playerItem: playerItem)
    playerView.player = player
    
    // Observe playback time
    timeObserver = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.1, preferredTimescale: 600), queue: .main) { [weak self] time in
      Task { @MainActor in
        self?.handleTimeUpdate(time)
      }
    }
    
    // Observe end of playback
    NotificationCenter.default.addObserver(self, selector: #selector(playerDidFinish), name: .AVPlayerItemDidPlayToEndTime, object: playerItem)
  }
  
  private func handleTimeUpdate(_ time: CMTime) {
    let currentTime = time.seconds
    trimHandleView.updatePlayhead(at: currentTime)
    updateTimeLabel()
    
    // Loop within trim range
    let endTime = trimHandleView.trimEnd
    if currentTime >= endTime {
      player.seek(to: CMTime(seconds: trimHandleView.trimStart, preferredTimescale: 600))
    }
  }
  
  private func handleTrimChanged(start: Double, end: Double) {
    updateTimeLabel()
    // Seek to start when trim changes
    player.seek(to: CMTime(seconds: start, preferredTimescale: 600))
  }
  
  private func scrubTo(time: Double) {
    player.pause()
    updatePlayButton(isPlaying: false)
    player.seek(to: CMTime(seconds: time, preferredTimescale: 600))
  }
  
  private func updateTimeLabel() {
    let start = trimHandleView.trimStart
    let end = trimHandleView.trimEnd
    let trimDuration = end - start
    timeLabel.stringValue = "\(formatTime(start)) → \(formatTime(end))  (\(formatTime(trimDuration)))"
  }
  
  private func formatTime(_ seconds: Double) -> String {
    let mins = Int(seconds) / 60
    let secs = Int(seconds) % 60
    let frac = Int((seconds.truncatingRemainder(dividingBy: 1)) * 10)
    return String(format: "%d:%02d.%d", mins, secs, frac)
  }
  
  private func updatePlayButton(isPlaying: Bool) {
    let symbolName = isPlaying ? "pause.fill" : "play.fill"
    playButton.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: isPlaying ? "Pause" : "Play")
  }
  
  @objc private func togglePlayback() {
    if player.rate > 0 {
      player.pause()
      updatePlayButton(isPlaying: false)
    } else {
      // If at end, restart from trim start
      let currentTime = player.currentTime().seconds
      if currentTime >= trimHandleView.trimEnd - 0.1 {
        player.seek(to: CMTime(seconds: trimHandleView.trimStart, preferredTimescale: 600))
      }
      player.play()
      updatePlayButton(isPlaying: true)
    }
  }
  
  @objc private func playerDidFinish() {
    updatePlayButton(isPlaying: false)
    player.seek(to: CMTime(seconds: trimHandleView.trimStart, preferredTimescale: 600))
  }
  
  @objc private func cancel() {
    cleanup()
    close()
  }
  
  @objc private func exportTrimmed() {
    let startSeconds = trimHandleView.trimStart
    let endSeconds = trimHandleView.trimEnd
    
    let savePanel = NSSavePanel()
    savePanel.allowedContentTypes = [.mpeg4Movie, .quickTimeMovie]
    savePanel.canCreateDirectories = true
    
    let base = inputURL.deletingPathExtension().lastPathComponent
    savePanel.nameFieldStringValue = "\(base)-trimmed.mp4"
    
    guard savePanel.runModal() == .OK, let outputURL = savePanel.url else { return }
    
    // Show progress
    let progressAlert = NSAlert()
    progressAlert.messageText = "Exporting..."
    progressAlert.informativeText = "Please wait while the video is being trimmed."
    progressAlert.addButton(withTitle: "Cancel")
    progressAlert.buttons.first?.isHidden = true
    
    let progressIndicator = NSProgressIndicator()
    progressIndicator.style = .spinning
    progressIndicator.controlSize = .small
    progressIndicator.startAnimation(nil)
    progressIndicator.frame = NSRect(x: 0, y: 0, width: 32, height: 32)
    progressAlert.accessoryView = progressIndicator
    
    progressAlert.beginSheetModal(for: window!) { _ in }
    
    Task {
      do {
        let exporter = VideoTrimExporter()
        try await exporter.exportTrimmedVideo(
          from: inputURL,
          to: outputURL,
          options: .init(startSeconds: startSeconds, endSeconds: endSeconds)
        )
        
        window?.endSheet(progressAlert.window)
        cleanup()
        close()
        FinderReveal.reveal(outputURL)
      } catch {
        window?.endSheet(progressAlert.window)
        
        let errorMessage: String
        if let trimError = error as? VideoTrimError {
          switch trimError {
          case .invalidRange:
            errorMessage = "Invalid range. Ensure end > start and within the video duration."
          case .unsupportedOutputType:
            errorMessage = "Unsupported output type for this video. Try saving as .mov or .mp4."
          case .exportSessionFailed:
            errorMessage = "Export failed. Try a shorter range or a different output path."
          }
        } else {
          errorMessage = String(describing: error)
        }
        
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Export Failed"
        alert.informativeText = errorMessage
        alert.addButton(withTitle: "OK")
        alert.runModal()
      }
    }
  }
  
  private func cleanup() {
    player.pause()
    if let observer = timeObserver {
      player.removeTimeObserver(observer)
      timeObserver = nil
    }
    NotificationCenter.default.removeObserver(self)
  }
  
  deinit {
    if let observer = timeObserver {
      player?.removeTimeObserver(observer)
    }
  }
}

// MARK: - Film Strip View (Thumbnails)

@MainActor
final class FilmStripView: NSView {
  private let asset: AVAsset
  private let duration: Double
  private var thumbnails: [NSImage] = []
  private var imageGenerator: AVAssetImageGenerator?
  
  init(asset: AVAsset, duration: Double) {
    self.asset = asset
    self.duration = duration
    super.init(frame: .zero)
    wantsLayer = true
    layer?.cornerRadius = 4
    layer?.masksToBounds = true
    generateThumbnails()
  }
  
  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }
  
  private func generateThumbnails() {
    let generator = AVAssetImageGenerator(asset: asset)
    generator.appliesPreferredTrackTransform = true
    generator.maximumSize = CGSize(width: 120, height: 80)
    self.imageGenerator = generator
    
    // Generate ~20 thumbnails across the duration
    let count = min(20, max(5, Int(duration)))
    var times: [NSValue] = []
    for i in 0..<count {
      let time = CMTime(seconds: (Double(i) / Double(count)) * duration, preferredTimescale: 600)
      times.append(NSValue(time: time))
    }
    
    var generatedThumbnails: [NSImage] = []
    
    generator.generateCGImagesAsynchronously(forTimes: times) { [weak self] _, cgImage, _, _, _ in
      if let cgImage = cgImage {
        let nsImage = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
        generatedThumbnails.append(nsImage)
        
        DispatchQueue.main.async {
          self?.thumbnails = generatedThumbnails
          self?.needsDisplay = true
        }
      }
    }
  }
  
  override func draw(_ dirtyRect: NSRect) {
    super.draw(dirtyRect)
    
    guard !thumbnails.isEmpty else {
      NSColor.darkGray.setFill()
      NSBezierPath(roundedRect: bounds, xRadius: 4, yRadius: 4).fill()
      return
    }
    
    let thumbnailWidth = bounds.width / CGFloat(thumbnails.count)
    
    for (index, thumbnail) in thumbnails.enumerated() {
      let rect = NSRect(
        x: CGFloat(index) * thumbnailWidth,
        y: 0,
        width: thumbnailWidth,
        height: bounds.height
      )
      thumbnail.draw(in: rect, from: .zero, operation: .copy, fraction: 1.0)
    }
  }
}

// MARK: - Trim Handle View

@MainActor
final class TrimHandleView: NSView {
  private let duration: Double
  private(set) var trimStart: Double = 0
  private(set) var trimEnd: Double
  
  private var playheadPosition: Double = 0
  
  var onTrimChanged: ((Double, Double) -> Void)?
  var onScrub: ((Double) -> Void)?
  
  private enum DragMode {
    case none
    case leftHandle
    case rightHandle
    case scrub
  }
  private var dragMode: DragMode = .none
  
  private let handleWidth: CGFloat = 14
  private let handleColor = NSColor.systemYellow
  private let dimColor = NSColor.black.withAlphaComponent(0.6)
  
  init(duration: Double) {
    self.duration = duration
    self.trimEnd = duration
    super.init(frame: .zero)
    wantsLayer = true
  }
  
  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }
  
  func updatePlayhead(at time: Double) {
    playheadPosition = time
    needsDisplay = true
  }
  
  private func timeToX(_ time: Double) -> CGFloat {
    let usableWidth = bounds.width - (handleWidth * 2)
    return handleWidth + CGFloat(time / duration) * usableWidth
  }
  
  private func xToTime(_ x: CGFloat) -> Double {
    let usableWidth = bounds.width - (handleWidth * 2)
    let normalizedX = (x - handleWidth) / usableWidth
    return max(0, min(duration, Double(normalizedX) * duration))
  }
  
  override func draw(_ dirtyRect: NSRect) {
    super.draw(dirtyRect)
    
    let leftX = timeToX(trimStart)
    let rightX = timeToX(trimEnd)
    
    // Dim areas outside trim range
    dimColor.setFill()
    NSBezierPath(rect: NSRect(x: 0, y: 0, width: leftX, height: bounds.height)).fill()
    NSBezierPath(rect: NSRect(x: rightX, y: 0, width: bounds.width - rightX, height: bounds.height)).fill()
    
    // Left handle
    let leftHandleRect = NSRect(x: leftX - handleWidth, y: 0, width: handleWidth, height: bounds.height)
    handleColor.setFill()
    let leftPath = NSBezierPath(roundedRect: leftHandleRect, xRadius: 4, yRadius: 4)
    leftPath.fill()
    
    // Left handle grip lines
    NSColor.black.withAlphaComponent(0.4).setStroke()
    let leftGripX = leftHandleRect.midX
    for offset: CGFloat in [-2, 2] {
      let line = NSBezierPath()
      line.move(to: NSPoint(x: leftGripX + offset, y: bounds.height * 0.3))
      line.line(to: NSPoint(x: leftGripX + offset, y: bounds.height * 0.7))
      line.lineWidth = 1.5
      line.stroke()
    }
    
    // Right handle
    let rightHandleRect = NSRect(x: rightX, y: 0, width: handleWidth, height: bounds.height)
    handleColor.setFill()
    let rightPath = NSBezierPath(roundedRect: rightHandleRect, xRadius: 4, yRadius: 4)
    rightPath.fill()
    
    // Right handle grip lines
    NSColor.black.withAlphaComponent(0.4).setStroke()
    let rightGripX = rightHandleRect.midX
    for offset: CGFloat in [-2, 2] {
      let line = NSBezierPath()
      line.move(to: NSPoint(x: rightGripX + offset, y: bounds.height * 0.3))
      line.line(to: NSPoint(x: rightGripX + offset, y: bounds.height * 0.7))
      line.lineWidth = 1.5
      line.stroke()
    }
    
    // Top and bottom border of selected range
    handleColor.setStroke()
    let topBorder = NSBezierPath()
    topBorder.move(to: NSPoint(x: leftX, y: bounds.height - 2))
    topBorder.line(to: NSPoint(x: rightX, y: bounds.height - 2))
    topBorder.lineWidth = 4
    topBorder.stroke()
    
    let bottomBorder = NSBezierPath()
    bottomBorder.move(to: NSPoint(x: leftX, y: 2))
    bottomBorder.line(to: NSPoint(x: rightX, y: 2))
    bottomBorder.lineWidth = 4
    bottomBorder.stroke()
    
    // Playhead
    let playheadX = timeToX(playheadPosition)
    if playheadX >= leftX && playheadX <= rightX {
      NSColor.white.setFill()
      let playheadRect = NSRect(x: playheadX - 1.5, y: 0, width: 3, height: bounds.height)
      NSBezierPath(roundedRect: playheadRect, xRadius: 1.5, yRadius: 1.5).fill()
      
      // Playhead shadow
      NSColor.black.withAlphaComponent(0.3).setStroke()
      let shadow = NSBezierPath(roundedRect: playheadRect.insetBy(dx: -0.5, dy: 0), xRadius: 2, yRadius: 2)
      shadow.lineWidth = 1
      shadow.stroke()
    }
  }
  
  override func mouseDown(with event: NSEvent) {
    let point = convert(event.locationInWindow, from: nil)
    let leftX = timeToX(trimStart)
    let rightX = timeToX(trimEnd)
    
    let leftHandleRect = NSRect(x: leftX - handleWidth - 4, y: 0, width: handleWidth + 8, height: bounds.height)
    let rightHandleRect = NSRect(x: rightX - 4, y: 0, width: handleWidth + 8, height: bounds.height)
    
    if leftHandleRect.contains(point) {
      dragMode = .leftHandle
    } else if rightHandleRect.contains(point) {
      dragMode = .rightHandle
    } else if point.x > leftX && point.x < rightX {
      dragMode = .scrub
      let time = xToTime(point.x)
      onScrub?(time)
    }
    
    needsDisplay = true
  }
  
  override func mouseDragged(with event: NSEvent) {
    let point = convert(event.locationInWindow, from: nil)
    let time = xToTime(point.x)
    
    switch dragMode {
    case .leftHandle:
      trimStart = max(0, min(time, trimEnd - 0.5))
      onTrimChanged?(trimStart, trimEnd)
    case .rightHandle:
      trimEnd = min(duration, max(time, trimStart + 0.5))
      onTrimChanged?(trimStart, trimEnd)
    case .scrub:
      let clampedTime = max(trimStart, min(trimEnd, time))
      onScrub?(clampedTime)
    case .none:
      break
    }
    
    needsDisplay = true
  }
  
  override func mouseUp(with event: NSEvent) {
    dragMode = .none
  }
  
  override func resetCursorRects() {
    let leftX = timeToX(trimStart)
    let rightX = timeToX(trimEnd)
    
    let leftHandleRect = NSRect(x: leftX - handleWidth, y: 0, width: handleWidth, height: bounds.height)
    let rightHandleRect = NSRect(x: rightX, y: 0, width: handleWidth, height: bounds.height)
    
    addCursorRect(leftHandleRect, cursor: .resizeLeftRight)
    addCursorRect(rightHandleRect, cursor: .resizeLeftRight)
  }
}

// MARK: - Presenter Entry Point

enum VideoTrimPresenter {
  private static var windowController: VideoTrimWindowController?
  
  @MainActor
  static func trimVideo(at inputURL: URL) {
    Task {
      do {
        let asset = AVAsset(url: inputURL)
        let duration = try await asset.load(.duration)
        let durationSeconds = duration.seconds
        
        guard durationSeconds > 0.5 else {
          showError("Video is too short to trim.")
          return
        }
        
        let controller = VideoTrimWindowController(inputURL: inputURL, asset: asset, duration: durationSeconds)
        windowController = controller
        controller.window?.center()
        controller.showWindow(nil)
        controller.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
      } catch {
        showError("Could not load video: \(error.localizedDescription)")
      }
    }
  }

  @MainActor
  private static func showError(_ message: String) {
    let alert = NSAlert()
    alert.alertStyle = .warning
    alert.messageText = "Trim Video"
    alert.informativeText = message
    alert.addButton(withTitle: "OK")
    alert.runModal()
  }
}
