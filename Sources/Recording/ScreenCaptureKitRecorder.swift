@preconcurrency import AVFoundation
import AppKit
import CoreText
import Foundation
import ScreenCaptureKit

private func debugLog(_ message: String) {
  let logFile = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("snipsnap-debug.log")
  let timestamp = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
  let line = "[\(timestamp)] SCKRecorder: \(message)\n"
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

enum ScreenRecorderError: Error {
  case alreadyRecording
  case notRecording
  case failedToStartCapture(String)
  case failedToStartWriter(String)
  case writerNotReady
  case writerFailed(String)
  case appSupportDirUnavailable
}

@available(macOS 13.0, *)
final class ScreenCaptureKitRecorder: Recording, @unchecked Sendable {
  // Overlay settings
  var showClickOverlay: Bool = true
  var showKeystrokeHUD: Bool = true
  var clickRingColor: CGColor = CGColor(red: 1, green: 1, blue: 1, alpha: 1)
  var hudPlacement: HUDPlacement = .bottomCenter
  var showCursor: Bool = true

  // State
  private let queue = DispatchQueue(label: "SnipSnap.ScreenCaptureKitRecorder")
  private var stream: SCStream?
  private var streamOutput: StreamOutput?
  private var writer: AVAssetWriter?
  private var videoInput: AVAssetWriterInput?
  private var pixelBufferAdaptor: AVAssetWriterInputPixelBufferAdaptor?
  private(set) var lastRecordingURL: URL?
  private var rawMovURL: URL?
  var lastErrorMessage: String?

  private var startedSession = false
  private var startedWriting = false
  private var writerStartFailed = false
  private var writerFailureMessage: String?
  private var hasLastVideoPTS = false
  private var lastVideoPTS: CMTime = .zero
  private var isStopping = false
  private var screenFrameInPoints: CGRect = .zero

  private let overlays = OverlayEventTap()

  var isRecording: Bool {
    stream != nil
  }

  // MARK: - External Event Recording (from main app via XPC)

  /// Record a click event sent from the main app (which has CGEvent tap permissions).
  func recordExternalClick(x: CGFloat, y: CGFloat, time: CFTimeInterval) {
    debugLog("recordExternalClick received: x=\(x) y=\(y) time=\(time)")
    overlays.recordClick(x: x, y: y, time: time)
  }

  /// Record a keystroke event sent from the main app (which has CGEvent tap permissions).
  func recordExternalKey(text: String, time: CFTimeInterval) {
    debugLog("recordExternalKey received: '\(text)' time=\(time)")
    overlays.recordKey(text: text, time: time)
  }

  func start() async throws {
    try await start(regionRectInScreenPoints: nil)
  }

  func start(regionRectInScreenPoints: CGRect?) async throws {
    debugLog("ScreenCaptureKitRecorder.start called, regionRect=\(String(describing: regionRectInScreenPoints)), stream=\(stream != nil)")
    if isRecording { 
      debugLog("ScreenCaptureKitRecorder: already recording! stream is NOT nil")
      throw ScreenRecorderError.alreadyRecording 
    }

    lastErrorMessage = nil
    isStopping = false
    startedSession = false
    startedWriting = false
    writerStartFailed = false
    writerFailureMessage = nil
    hasLastVideoPTS = false
    
    debugLog("ScreenCaptureKitRecorder: getting shareable content...")
    let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
    guard let display = content.displays.first(where: { $0.displayID == CGMainDisplayID() }) ?? content.displays.first else {
      throw ScreenRecorderError.failedToStartCapture("No displays available")
    }
    debugLog("ScreenCaptureKitRecorder: got display \(display.displayID)")

    // Always exclude all SnipSnap windows from capture
    let snipApps = NSWorkspace.shared.runningApplications.filter { app in
      app.bundleIdentifier?.lowercased().contains("snipsnap") == true
    }
    let excludedPIDs = Set(snipApps.map { $0.processIdentifier } + [ProcessInfo.processInfo.processIdentifier])
    let excludedWindows = content.windows.filter { w in
      if let pid = w.owningApplication?.processID, excludedPIDs.contains(pid) {
        return true
      }
      return false
    }

    // Used to map global mouse locations -> captured pixel buffer.
    screenFrameInPoints = regionRectInScreenPoints ?? (NSScreen.main?.frame ?? .zero)

    // Compute region crop if provided.
    // IMPORTANT: NSScreen coordinates use bottom-left origin, but ScreenCaptureKit uses top-left origin.
    // We need to flip the Y coordinate.
    var sourceRect: CGRect?
    var regionWidth = Int(display.width)
    var regionHeight = Int(display.height)
    
    if let regionRectInScreenPoints {
      guard let mainScreen = NSScreen.main else {
        throw ScreenRecorderError.failedToStartCapture("No main screen available")
      }
      
      let screenHeight = mainScreen.frame.height
      let displayScale = CGFloat(display.height) / screenHeight
      
      // Convert from NSScreen coordinates (bottom-left origin) to ScreenCaptureKit coordinates (top-left origin)
      // NSScreen: y=0 is at bottom, y increases upward
      // SCK: y=0 is at top, y increases downward
      let flippedY = screenHeight - regionRectInScreenPoints.origin.y - regionRectInScreenPoints.height
      
      let pxRect = CGRect(
        x: regionRectInScreenPoints.origin.x * displayScale,
        y: flippedY * displayScale,
        width: regionRectInScreenPoints.width * displayScale,
        height: regionRectInScreenPoints.height * displayScale
      )
      sourceRect = pxRect
      
      // Use region dimensions for video output
      regionWidth = max(2, (Int(regionRectInScreenPoints.width * displayScale) / 2) * 2)
      regionHeight = max(2, (Int(regionRectInScreenPoints.height * displayScale) / 2) * 2)
      
      debugLog("ScreenCaptureKitRecorder: Region conversion - input: \(regionRectInScreenPoints), screenHeight: \(screenHeight), flippedY: \(flippedY), sourceRect: \(pxRect)")
    }

    // Configure writer.
    let outURL = try Self.makeRecordingURL(ext: "mov")
    let writer: AVAssetWriter
    do {
      writer = try AVAssetWriter(outputURL: outURL, fileType: .mov)
    } catch {
      throw ScreenRecorderError.failedToStartWriter(String(describing: error))
    }

    // Use region dimensions if recording a region, otherwise full display
    let width = regionWidth
    let height = regionHeight
    
    debugLog("ScreenCaptureKitRecorder: Video dimensions: \(width)x\(height)")

    let videoSettings: [String: Any] = [
      AVVideoCodecKey: AVVideoCodecType.h264,
      AVVideoWidthKey: width,
      AVVideoHeightKey: height,
      AVVideoCompressionPropertiesKey: [
        AVVideoAverageBitRateKey: 8_000_000,
        AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel
      ]
    ]

    let input = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
    input.expectsMediaDataInRealTime = true

    guard writer.canAdd(input) else { throw ScreenRecorderError.failedToStartWriter("cannot add video input") }
    writer.add(input)

    // Use a pixel buffer adaptor to handle ScreenCaptureKit's IOSurface-backed buffers.
    let sourcePixelBufferAttributes: [String: Any] = [
      kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
      kCVPixelBufferWidthKey as String: width,
      kCVPixelBufferHeightKey as String: height
    ]
    let adaptor = AVAssetWriterInputPixelBufferAdaptor(
      assetWriterInput: input,
      sourcePixelBufferAttributes: sourcePixelBufferAttributes
    )

    // Store writer state before starting capture to avoid dropping early frames.
    self.lastRecordingURL = outURL
    self.rawMovURL = outURL
    self.writer = writer
    self.videoInput = input
    self.pixelBufferAdaptor = adaptor
    self.startedSession = false
    self.startedWriting = false
    self.writerStartFailed = false
    self.writerFailureMessage = nil

    // Configure stream.
    let filter = SCContentFilter(display: display, excludingWindows: excludedWindows)

    let config = SCStreamConfiguration()
    config.width = width
    config.height = height
    config.minimumFrameInterval = CMTime(value: 1, timescale: 60)
    config.queueDepth = 8
    config.pixelFormat = kCVPixelFormatType_32BGRA
    config.showsCursor = showCursor
    if let sourceRect {
      config.sourceRect = sourceRect
    }

    let output = StreamOutput(onSampleBuffer: { [weak self] sampleBuffer in
      self?.handleVideoSampleBuffer(sampleBuffer)
    })

    let stream = SCStream(filter: filter, configuration: config, delegate: nil)

    do {
      try stream.addStreamOutput(output, type: .screen, sampleHandlerQueue: queue)
      try await stream.startCapture()
    } catch {
      writer.cancelWriting()
      self.writer = nil
      self.videoInput = nil
      self.pixelBufferAdaptor = nil
      self.startedSession = false
      self.startedWriting = false
      self.writerStartFailed = false
      self.writerFailureMessage = nil
      try? FileManager.default.removeItem(at: outURL)
      lastErrorMessage = String(describing: error)
      throw ScreenRecorderError.failedToStartCapture(String(describing: error))
    }

    // NOTE: Overlay events are now sent from the main app via XPC (recordExternalClick/recordExternalKey)
    // because the XPC service process cannot create CGEvent taps - permissions are per-application.
    // The old internal event tap code has been removed.
    debugLog("ScreenCaptureKitRecorder: Ready to receive overlay events from main app via XPC")

    self.stream = stream
    self.streamOutput = output
  }

  /// Start recording a specific window by its window ID.
  func start(windowID: CGWindowID) async throws {
    if isRecording { throw ScreenRecorderError.alreadyRecording }

    lastErrorMessage = nil
    isStopping = false
    startedSession = false
    startedWriting = false
    writerStartFailed = false
    writerFailureMessage = nil
    hasLastVideoPTS = false

    // Get the window from ScreenCaptureKit
    let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
    guard let scWindow = content.windows.first(where: { $0.windowID == windowID }) else {
      throw ScreenRecorderError.failedToStartCapture("Window not found (ID: \(windowID))")
    }

    let windowFrame = scWindow.frame
    guard windowFrame.width >= 1, windowFrame.height >= 1 else {
      throw ScreenRecorderError.failedToStartCapture("Window has invalid size")
    }

    // Note: XPC services can't show windows, so we skip preview overlays for window recording

    // Configure writer.
    let outURL = try Self.makeRecordingURL(ext: "mov")
    let writer: AVAssetWriter
    do {
      writer = try AVAssetWriter(outputURL: outURL, fileType: .mov)
    } catch {
      throw ScreenRecorderError.failedToStartWriter(String(describing: error))
    }

    let width = max(2, (Int(windowFrame.width) / 2) * 2)
    let height = max(2, (Int(windowFrame.height) / 2) * 2)

    let videoSettings: [String: Any] = [
      AVVideoCodecKey: AVVideoCodecType.h264,
      AVVideoWidthKey: width,
      AVVideoHeightKey: height,
      AVVideoCompressionPropertiesKey: [
        AVVideoAverageBitRateKey: 8_000_000,
        AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel
      ]
    ]

    let input = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
    input.expectsMediaDataInRealTime = true

    guard writer.canAdd(input) else { throw ScreenRecorderError.failedToStartWriter("cannot add video input") }
    writer.add(input)

    let sourcePixelBufferAttributes: [String: Any] = [
      kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
      kCVPixelBufferWidthKey as String: width,
      kCVPixelBufferHeightKey as String: height
    ]
    let adaptor = AVAssetWriterInputPixelBufferAdaptor(
      assetWriterInput: input,
      sourcePixelBufferAttributes: sourcePixelBufferAttributes
    )

    // Store writer state.
    self.lastRecordingURL = outURL
    self.rawMovURL = outURL
    self.writer = writer
    self.videoInput = input
    self.pixelBufferAdaptor = adaptor
    self.startedSession = false
    self.startedWriting = false
    self.writerStartFailed = false
    self.writerFailureMessage = nil
    self.screenFrameInPoints = windowFrame

    // Create filter for specific window
    let filter = SCContentFilter(desktopIndependentWindow: scWindow)

    let config = SCStreamConfiguration()
    config.width = width
    config.height = height
    config.minimumFrameInterval = CMTime(value: 1, timescale: 60)
    config.queueDepth = 8
    config.pixelFormat = kCVPixelFormatType_32BGRA
    config.showsCursor = showCursor

    let output = StreamOutput(onSampleBuffer: { [weak self] sampleBuffer in
      self?.handleVideoSampleBuffer(sampleBuffer)
    })

    let stream = SCStream(filter: filter, configuration: config, delegate: nil)

    do {
      try stream.addStreamOutput(output, type: .screen, sampleHandlerQueue: queue)
      try await stream.startCapture()
    } catch {
      writer.cancelWriting()
      self.writer = nil
      self.videoInput = nil
      self.pixelBufferAdaptor = nil
      self.startedSession = false
      self.startedWriting = false
      self.writerStartFailed = false
      self.writerFailureMessage = nil
      try? FileManager.default.removeItem(at: outURL)
      lastErrorMessage = String(describing: error)
      throw ScreenRecorderError.failedToStartCapture(String(describing: error))
    }

    self.stream = stream
    self.streamOutput = output
  }

  private func handleVideoSampleBuffer(_ sampleBuffer: CMSampleBuffer) {
    if isStopping { return }
    guard let writer, let input = videoInput, let adaptor = pixelBufferAdaptor else { return }
    if writerStartFailed { return }
    if writerFailureMessage != nil { return }
    guard let sourcePixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

    if !startedWriting {
      if writer.startWriting() == false {
        writerStartFailed = true
        writerFailureMessage = writer.error.map { String(describing: $0) } ?? "AVAssetWriter.startWriting() failed"
        return
      }
      startedWriting = true
    }

    let pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
    lastVideoPTS = pts
    hasLastVideoPTS = true
    if !startedSession {
      startedSession = true
      writer.startSession(atSourceTime: pts)
    }

    guard input.isReadyForMoreMediaData else { return }

    guard let pixelBufferPool = adaptor.pixelBufferPool else {
      if input.append(sampleBuffer) == false {
        writerStartFailed = true
        writerFailureMessage = writer.error.map { String(describing: $0) } ?? "Failed to append video sample buffer"
        lastErrorMessage = writerFailureMessage
      }
      return
    }

    var newPixelBuffer: CVPixelBuffer?
    let status = CVPixelBufferPoolCreatePixelBuffer(nil, pixelBufferPool, &newPixelBuffer)
    guard status == kCVReturnSuccess, let destPixelBuffer = newPixelBuffer else {
      if input.append(sampleBuffer) == false {
        writerStartFailed = true
        writerFailureMessage = writer.error.map { String(describing: $0) } ?? "Failed to append video sample buffer"
        lastErrorMessage = writerFailureMessage
      }
      return
    }

    CVPixelBufferLockBaseAddress(sourcePixelBuffer, .readOnly)
    CVPixelBufferLockBaseAddress(destPixelBuffer, [])
    defer {
      CVPixelBufferUnlockBaseAddress(sourcePixelBuffer, .readOnly)
      CVPixelBufferUnlockBaseAddress(destPixelBuffer, [])
    }

    let srcWidth = CVPixelBufferGetWidth(sourcePixelBuffer)
    let srcHeight = CVPixelBufferGetHeight(sourcePixelBuffer)
    let dstWidth = CVPixelBufferGetWidth(destPixelBuffer)
    let dstHeight = CVPixelBufferGetHeight(destPixelBuffer)

    guard srcWidth == dstWidth && srcHeight == dstHeight else { return }

    if let srcBase = CVPixelBufferGetBaseAddress(sourcePixelBuffer),
       let dstBase = CVPixelBufferGetBaseAddress(destPixelBuffer) {
      let srcBytesPerRow = CVPixelBufferGetBytesPerRow(sourcePixelBuffer)
      let dstBytesPerRow = CVPixelBufferGetBytesPerRow(destPixelBuffer)

      if srcBytesPerRow == dstBytesPerRow {
        memcpy(dstBase, srcBase, srcBytesPerRow * srcHeight)
      } else {
        let copyBytesPerRow = min(srcBytesPerRow, dstBytesPerRow)
        for row in 0..<srcHeight {
          let srcRow = srcBase.advanced(by: row * srcBytesPerRow)
          let dstRow = dstBase.advanced(by: row * dstBytesPerRow)
          memcpy(dstRow, srcRow, copyBytesPerRow)
        }
      }
    }

    if showClickOverlay || showKeystrokeHUD {
      drawOverlays(into: destPixelBuffer, width: dstWidth, height: dstHeight)
    }

    let ok = adaptor.append(destPixelBuffer, withPresentationTime: pts)
    if ok == false {
      writerStartFailed = true
      if let err = writer.error {
        writerFailureMessage = String(describing: err)
      } else {
        writerFailureMessage = "Failed to append pixel buffer"
      }
      lastErrorMessage = writerFailureMessage
      return
    }
  }

  func stop() async throws {
    guard let stream else { throw ScreenRecorderError.notRecording }

    // Prevent late buffers from being appended while we're finalizing.
    isStopping = true

    // Stop capture first to stop buffers.
    do {
      try await stream.stopCapture()
    } catch {
      // Best-effort; continue to finalize.
    }

    // Release stream early.
    self.stream = nil
    self.streamOutput = nil

    let overlays = self.overlays
    DispatchQueue.main.async {
      overlays.stop()
    }

    guard let writer, let videoInput else {
      self.writer = nil
      self.videoInput = nil
      self.pixelBufferAdaptor = nil
      throw ScreenRecorderError.writerNotReady
    }

    if writerStartFailed {
      let msg = writerFailureMessage
        ?? writer.error.map { String(describing: $0) }
        ?? "AVAssetWriter failed to start"
      lastErrorMessage = msg
      writer.cancelWriting()
      self.writer = nil
      self.videoInput = nil
      self.pixelBufferAdaptor = nil
      self.startedSession = false
      self.startedWriting = false
      self.writerStartFailed = false
      self.writerFailureMessage = nil
      throw ScreenRecorderError.writerFailed(msg)
    }

    // If we never received frames, cancel writing (empty movies are often unplayable).
    if !startedSession {
      writer.cancelWriting()
      self.writer = nil
      self.videoInput = nil
      self.pixelBufferAdaptor = nil
      self.startedSession = false
      self.startedWriting = false
      self.writerStartFailed = false
      self.writerFailureMessage = nil
      try? lastRecordingURL.map { try FileManager.default.removeItem(at: $0) }
      lastErrorMessage = "No frames captured"
      throw ScreenRecorderError.writerFailed("No frames captured")
    }

    if let msg = writerFailureMessage {
      writer.cancelWriting()
      self.writer = nil
      self.videoInput = nil
      self.pixelBufferAdaptor = nil
      self.startedSession = false
      self.startedWriting = false
      self.writerStartFailed = false
      self.writerFailureMessage = nil
      lastErrorMessage = msg
      throw ScreenRecorderError.writerFailed(msg)
    }

    // Finalize timeline.
    if hasLastVideoPTS {
      writer.endSession(atSourceTime: lastVideoPTS)
    }

    videoInput.markAsFinished()

    try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
      writer.finishWriting {
        if writer.status == .failed, let err = writer.error {
          self.lastErrorMessage = String(describing: err)
          cont.resume(throwing: err)
          return
        }
        if let err = writer.error {
          self.lastErrorMessage = String(describing: err)
          cont.resume(throwing: err)
          return
        }
        cont.resume(returning: ())
      }
    }

    self.writer = nil
    self.videoInput = nil
    self.pixelBufferAdaptor = nil
    self.startedSession = false
    self.startedWriting = false
    self.writerStartFailed = false
    self.writerFailureMessage = nil

    // Convert the finalized .mov to .mp4 for broad compatibility.
    if let movURL = rawMovURL {
      let mp4URL = movURL.deletingPathExtension().appendingPathExtension("mp4")
      do {
        try await Self.convertMOVToMP4(inputURL: movURL, outputURL: mp4URL)
        lastRecordingURL = mp4URL
        rawMovURL = nil
        try? FileManager.default.removeItem(at: movURL)
      } catch {
        // Keep the .mov if conversion fails.
        lastRecordingURL = movURL
        rawMovURL = nil
      }
    }
  }

  private func drawOverlays(into pixelBuffer: CVPixelBuffer, width: Int, height: Int) {
    let now = CACurrentMediaTime()
    let clickWindow: CFTimeInterval = 0.45  // Shorter click animation for snappier feel
    let keyWindow: CFTimeInterval = 2.0     // Keys visible longer

    let clicks = overlays.recentClicks(since: now - clickWindow)
    let keys = overlays.recentKeys(since: now - keyWindow)
    let hasClicks = showClickOverlay && !clicks.isEmpty
    let hasKeys = showKeystrokeHUD && !keys.isEmpty
    
    if !hasClicks && !hasKeys { return }

    guard let base = CVPixelBufferGetBaseAddress(pixelBuffer) else { return }
    let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)

    guard let ctx = CGContext(
      data: base,
      width: width,
      height: height,
      bitsPerComponent: 8,
      bytesPerRow: bytesPerRow,
      space: CGColorSpaceCreateDeviceRGB(),
      bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
    ) else {
      return
    }

    ctx.translateBy(x: 0, y: CGFloat(height))
    ctx.scaleBy(x: 1, y: -1)

    if hasClicks {
      for c in clicks {
        let age = now - c.time
        let t = max(0, min(1, 1 - age / clickWindow))
        let progress = 1 - CGFloat(t)
        let alpha = CGFloat(t) * 0.92

        let point = mapGlobalPointToPixel(x: c.x, y: c.y, pixelWidth: width, pixelHeight: height)
        debugLog("Click: input(\(c.x), \(c.y)) -> pixel(\(point.x), \(point.y)) frame=\(screenFrameInPoints) bufSize=\(width)x\(height)")

        let baseRadius: CGFloat = 10
        let ringGap: CGFloat = 10
        let radius1: CGFloat = baseRadius + progress * 20
        let radius2: CGFloat = radius1 + ringGap

        let r = clickRingColor

        ctx.setStrokeColor(r.copy(alpha: alpha) ?? CGColor(red: 1, green: 1, blue: 1, alpha: alpha))
        ctx.setLineWidth(3)
        ctx.strokeEllipse(
          in: CGRect(x: point.x - radius1, y: point.y - radius1, width: radius1 * 2, height: radius1 * 2)
        )

        ctx.setLineWidth(2)
        ctx.strokeEllipse(
          in: CGRect(x: point.x - radius2, y: point.y - radius2, width: radius2 * 2, height: radius2 * 2)
        )
      }
    }

    if hasKeys {
      // CleanShot-style horizontal key pills
      drawKeystrokeHUD(ctx: ctx, keys: keys, now: now, keyWindow: keyWindow, bufferWidth: width, bufferHeight: height)
    }
  }
  
  /// Draw CleanShot-style keystroke HUD with horizontal key pills
  private func drawKeystrokeHUD(ctx: CGContext, keys: [KeyEvent], now: CFTimeInterval, keyWindow: CFTimeInterval, bufferWidth: Int, bufferHeight: Int) {
    let pillHeight: CGFloat = 32
    let pillPadding: CGFloat = 10
    let pillGap: CGFloat = 6
    let hudPadding: CGFloat = 12
    let maxKeys = 12
    let cornerRadius: CGFloat = 8
    
    // Collect recent keys with display names
    var recentKeys: [(text: String, age: CFTimeInterval)] = []
    for k in keys.reversed() {
      let age = now - k.time
      if age > keyWindow { continue }
      recentKeys.append((k.displayText, age))
      if recentKeys.count >= maxKeys { break }
    }
    
    guard !recentKeys.isEmpty else { return }
    
    // Reverse so oldest is first (left to right)
    recentKeys.reverse()
    
    // Calculate pill widths using Core Text
    let font = CTFontCreateWithName("SF Pro Text" as CFString, 18, nil)
    var pillWidths: [CGFloat] = []
    var totalWidth: CGFloat = 0
    
    for (text, _) in recentKeys {
      let attrs: [NSAttributedString.Key: Any] = [.font: font]
      let attrString = NSAttributedString(string: text, attributes: attrs)
      let line = CTLineCreateWithAttributedString(attrString)
      let textWidth = CTLineGetTypographicBounds(line, nil, nil, nil)
      let pillWidth = max(pillHeight, CGFloat(textWidth) + pillPadding * 2)
      pillWidths.append(pillWidth)
      totalWidth += pillWidth
    }
    totalWidth += CGFloat(recentKeys.count - 1) * pillGap
    
    // Calculate HUD size and position
    let hudWidth = totalWidth + hudPadding * 2
    let hudHeight = pillHeight + hudPadding * 2
    let hudSize = CGSize(width: hudWidth, height: hudHeight)
    let hudOrigin = hudOrigin(for: hudSize, bufferWidth: bufferWidth, bufferHeight: bufferHeight)
    let hudRect = CGRect(origin: hudOrigin, size: hudSize)
    
    // Draw semi-transparent background
    ctx.setFillColor(CGColor(gray: 0, alpha: 0.75))
    let bgPath = CGPath(roundedRect: hudRect, cornerWidth: cornerRadius + 4, cornerHeight: cornerRadius + 4, transform: nil)
    ctx.addPath(bgPath)
    ctx.fillPath()
    
    // Draw each key pill
    var xOffset = hudRect.minX + hudPadding
    let pillY = hudRect.minY + hudPadding
    
    for (i, (text, age)) in recentKeys.enumerated() {
      let pillWidth = pillWidths[i]
      let pillRect = CGRect(x: xOffset, y: pillY, width: pillWidth, height: pillHeight)
      
      // Fade out based on age
      let fadeProgress = CGFloat(age / keyWindow)
      let alpha = 1.0 - (fadeProgress * 0.5)  // Fade from 1.0 to 0.5
      
      // Draw pill background (dark gray)
      ctx.setFillColor(CGColor(gray: 0.25, alpha: alpha))
      let pillPath = CGPath(roundedRect: pillRect, cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil)
      ctx.addPath(pillPath)
      ctx.fillPath()
      
      // Draw subtle border
      ctx.setStrokeColor(CGColor(gray: 0.4, alpha: alpha * 0.8))
      ctx.setLineWidth(1)
      ctx.addPath(pillPath)
      ctx.strokePath()
      
      // Draw text centered in pill (flip context for correct text orientation)
      let attrs: [NSAttributedString.Key: Any] = [
        .font: font,
        .foregroundColor: CGColor(gray: 1.0, alpha: alpha)
      ]
      let attrString = NSAttributedString(string: text, attributes: attrs)
      let line = CTLineCreateWithAttributedString(attrString)
      let textWidth = CTLineGetTypographicBounds(line, nil, nil, nil)
      
      let textX = pillRect.midX - CGFloat(textWidth) / 2
      let textY = pillRect.midY + 6  // Baseline position
      
      // Core Text draws upside down in a flipped context, so we need to flip locally
      ctx.saveGState()
      ctx.translateBy(x: 0, y: CGFloat(bufferHeight))
      ctx.scaleBy(x: 1, y: -1)
      // After this flip, Y coordinates are inverted: newY = bufferHeight - oldY
      let flippedTextY = CGFloat(bufferHeight) - textY
      ctx.textPosition = CGPoint(x: textX, y: flippedTextY)
      CTLineDraw(line, ctx)
      ctx.restoreGState()
      
      xOffset += pillWidth + pillGap
    }
  }

  private static func convertMOVToMP4(inputURL: URL, outputURL: URL) async throws {
    let asset = AVAsset(url: inputURL)
    _ = try await asset.load(.tracks)

    guard let export = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetHighestQuality) else {
      throw ScreenRecorderError.writerFailed("Failed to create export session")
    }

    guard export.supportedFileTypes.contains(.mp4) else {
      throw ScreenRecorderError.writerFailed("MP4 export not supported")
    }

    try? FileManager.default.createDirectory(at: outputURL.deletingLastPathComponent(), withIntermediateDirectories: true)
    try? FileManager.default.removeItem(at: outputURL)

    export.outputURL = outputURL
    export.outputFileType = .mp4

    try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
      export.exportAsynchronously {
        switch export.status {
        case .completed:
          cont.resume(returning: ())
        case .failed:
          cont.resume(throwing: export.error ?? ScreenRecorderError.writerFailed("MP4 export failed"))
        case .cancelled:
          cont.resume(throwing: export.error ?? CancellationError())
        default:
          cont.resume(throwing: export.error ?? ScreenRecorderError.writerFailed("MP4 export failed"))
        }
      }
    }
  }

  private func mapGlobalPointToPixel(x: CGFloat, y: CGFloat, pixelWidth: Int, pixelHeight: Int) -> CGPoint {
    // Map global screen coordinates to pixel buffer coordinates.
    // 
    // CGEvent uses Quartz/CoreGraphics coordinates: origin at TOP-LEFT of main display, Y increases DOWNWARD.
    // screenFrameInPoints uses NSScreen coordinates: origin at BOTTOM-LEFT of main display, Y increases UPWARD.
    // Our CGContext has been flipped for drawing so origin is top-left.
    //
    // We need to:
    // 1. Convert CGEvent Y to NSScreen Y (flip relative to screen height)
    // 2. Map the point relative to the recording region
    // 3. Scale from points to pixels
    
    let frame = screenFrameInPoints
    guard let mainScreen = NSScreen.main else {
      return CGPoint(x: CGFloat(pixelWidth) / 2, y: CGFloat(pixelHeight) / 2)
    }
    
    let screenHeight = mainScreen.frame.height
    
    // Convert CGEvent Y (top-left origin) to NSScreen Y (bottom-left origin)
    let nsScreenY = screenHeight - y
    
    // Now map relative to the region frame (which is in NSScreen coordinates)
    let sx = frame.width > 0 ? CGFloat(pixelWidth) / frame.width : 1
    let sy = frame.height > 0 ? CGFloat(pixelHeight) / frame.height : 1

    let px = (x - frame.minX) * sx
    // For Y: frame.minY is at the bottom of the region in NSScreen coords
    // We want pixels from top of the video, so flip within the region
    let relativeY = nsScreenY - frame.minY  // distance from bottom of region
    let py = CGFloat(pixelHeight) - (relativeY * sy)  // flip to get distance from top

    return CGPoint(x: max(0, min(CGFloat(pixelWidth), px)), y: max(0, min(CGFloat(pixelHeight), py)))
  }

  private func hudOrigin(for size: CGSize, bufferWidth: Int, bufferHeight: Int) -> CGPoint {
    let padding: CGFloat = 18
    switch hudPlacement {
    case .bottomCenter:
      return CGPoint(
        x: (CGFloat(bufferWidth) - size.width) / 2,
        y: CGFloat(bufferHeight) - size.height - padding
      )
    case .topCenter:
      return CGPoint(x: (CGFloat(bufferWidth) - size.width) / 2, y: padding)
    case .bottomLeft:
      return CGPoint(x: padding, y: CGFloat(bufferHeight) - size.height - padding)
    case .bottomRight:
      return CGPoint(x: CGFloat(bufferWidth) - size.width - padding, y: CGFloat(bufferHeight) - size.height - padding)
    case .topLeft:
      return CGPoint(x: padding, y: padding)
    case .topRight:
      return CGPoint(x: CGFloat(bufferWidth) - size.width - padding, y: padding)
    }
  }

  private static func makeRecordingURL(ext: String) throws -> URL {
    let fm = FileManager.default

    guard let appSupport = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
      throw ScreenRecorderError.appSupportDirUnavailable
    }

    let dir = appSupport
      .appendingPathComponent("SnipSnap", isDirectory: true)
      .appendingPathComponent("captures", isDirectory: true)

    try fm.createDirectory(at: dir, withIntermediateDirectories: true)

    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    let ts = formatter.string(from: Date()).replacingOccurrences(of: ":", with: "-")

    return dir.appendingPathComponent("recording_\(ts).\(ext)")
  }
}

private final class StreamOutput: NSObject, SCStreamOutput {
  private let onSampleBuffer: (CMSampleBuffer) -> Void

  init(onSampleBuffer: @escaping (CMSampleBuffer) -> Void) {
    self.onSampleBuffer = onSampleBuffer
  }

  func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
    guard type == .screen else { return }
    guard sampleBuffer.isValid else { return }

    // Only pass through sample buffers that are ready for encoding.
    if CMSampleBufferGetNumSamples(sampleBuffer) > 0 {
      onSampleBuffer(sampleBuffer)
    }
  }
}
