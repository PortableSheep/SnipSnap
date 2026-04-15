import Foundation
import AppKit
import CoreGraphics

/// Manages a scroll capture session.
/// The user scrolls manually; the app polls for content changes and captures frames.
@MainActor
final class ScrollCaptureSession {

  // MARK: - Types

  enum State {
    case idle
    case capturing
    case stitching
    case completed
    case cancelled
  }

  struct CaptureFrame {
    let image: CGImage
    let timestamp: Date
    /// Pre-computed overlap with the previous frame (nil for first frame).
    let overlapWithPrevious: Int?
  }

  enum Error: LocalizedError {
    case alreadyActive
    case cancelled
    case noFramesCaptured
    case noRegionSelected
    case captureFailed
    case stitchingFailed(Swift.Error)

    var errorDescription: String? {
      switch self {
      case .alreadyActive:
        return "A scroll capture session is already active"
      case .cancelled:
        return "Scroll capture was cancelled"
      case .noFramesCaptured:
        return "No frames were captured. Try scrolling the window."
      case .noRegionSelected:
        return "Scroll capture requires a region to be selected. Please drag to select a region."
      case .captureFailed:
        return "Failed to capture screen region"
      case .stitchingFailed(let error):
        return "Failed to stitch images: \(error.localizedDescription)"
      }
    }
  }

  // MARK: - Configuration

  private let pollInterval: TimeInterval = 0.05
  private let stabilizationDelay: TimeInterval = 0.25
  private let maxIntervalWithoutCapture: TimeInterval = 1.0
  private let blankVarianceThreshold: Double = 50
  private let maxConsecutiveBlankFrames: Int = 3
  /// Minimum vertical shift (px) to treat a frame as new content.
  private let minimumNewContent: CGFloat = 20

  // MARK: - Session State

  private(set) var state: State = .idle
  private(set) var captures: [CaptureFrame] = []
  private var captureRegion: CGRect?
  private var onProgressUpdate: ((Int) -> Void)?
  private var onStatusUpdate: ((String) -> Void)?
  private var onCompletion: ((Result<CGImage, Swift.Error>) -> Void)?

  // Manual mode state
  private var monitorTimer: Timer?
  private var lastCapturedImage: CGImage?
  private var lastChangeTime: Date?
  private var lastCaptureTime: Date?
  private var consecutiveBlankFrames: Int = 0
  private var isProcessingFrame = false
  private var contentChanged = false

  // MARK: - Lifecycle

  deinit {
    monitorTimer?.invalidate()
    monitorTimer = nil
  }

  // MARK: - Public API

  /// Start a scroll capture session.
  func start(
    region: CGRect,
    onProgress: @escaping (Int) -> Void,
    onStatus: ((String) -> Void)? = nil,
    completion: @escaping (Result<CGImage, Swift.Error>) -> Void
  ) {
    guard state == .idle else {
      completion(.failure(Error.alreadyActive))
      return
    }

    self.captureRegion = region
    self.onProgressUpdate = onProgress
    self.onStatusUpdate = onStatus
    self.onCompletion = completion
    self.state = .capturing
    self.captures.removeAll()
    self.lastCapturedImage = nil

    debugLog("ScrollCaptureSession: Starting scroll capture for region \(region)")
    startManualMonitoring(region: region)
  }

  /// User signals they're done scrolling.
  func finish() {
    guard state == .capturing else { return }

    debugLog("ScrollCaptureSession: User signaled finish")
    monitorTimer?.invalidate()
    monitorTimer = nil
    performStitching()
  }

  /// Cancel the capture session.
  func cancel() {
    debugLog("ScrollCaptureSession: Cancel called")

    monitorTimer?.invalidate()
    monitorTimer = nil
    state = .cancelled

    captures.removeAll()
    captureRegion = nil
    lastCapturedImage = nil

    debugLog("ScrollCaptureSession: Cancelled")
    onCompletion?(.failure(Error.cancelled))
    clearHandlers()
  }

  // MARK: - Manual Mode

  private func startManualMonitoring(region: CGRect) {
    self.consecutiveBlankFrames = 0
    self.isProcessingFrame = false
    self.lastCaptureTime = nil
    self.lastChangeTime = nil
    self.contentChanged = false

    // Capture initial frame
    if let image = captureScreenRegion(region) {
      let frame = CaptureFrame(image: image, timestamp: Date(), overlapWithPrevious: nil)
      captures.append(frame)
      lastCapturedImage = image
      lastCaptureTime = Date()
      onProgressUpdate?(captures.count)
      debugLog("ScrollCaptureSession: Captured initial frame")
    }

    // Start polling timer
    monitorTimer = Timer.scheduledTimer(withTimeInterval: pollInterval, repeats: true) { [weak self] _ in
      Task { @MainActor in
        self?.checkForContentChange()
      }
    }

    onStatusUpdate?("Scroll now — click Done when finished")
  }

  private func checkForContentChange() {
    guard let region = captureRegion, state == .capturing else { return }
    guard !isProcessingFrame else { return }
    isProcessingFrame = true
    defer { isProcessingFrame = false }

    guard let image = captureScreenRegion(region) else { return }

    // Blank detection
    if isBlankImage(image) {
      consecutiveBlankFrames += 1
      if consecutiveBlankFrames >= maxConsecutiveBlankFrames {
        debugLog("ScrollCaptureSession: Blank frames detected — likely scrolled past end")
      }
      return
    }
    consecutiveBlankFrames = 0

    guard let previousImage = lastCapturedImage else {
      // No previous frame to compare — capture this one
      captureManualFrame(image)
      return
    }

    // Use Vision to detect movement
    if let result = VisionImageRegistration.findTranslation(reference: previousImage, target: image) {
      let verticalShift = abs(result.yTranslation)

      if verticalShift < minimumNewContent {
        // Not enough new content yet
        if verticalShift > 2 {
          // Content is changing — mark it
          contentChanged = true
          lastChangeTime = Date()
        }
        // Force-capture if we've been waiting too long
        if let lastCapture = lastCaptureTime,
           Date().timeIntervalSince(lastCapture) >= maxIntervalWithoutCapture,
           contentChanged {
          captureManualFrame(image)
        }
        return
      }

      // Significant content change detected — wait for stabilization
      if contentChanged, let changeTime = lastChangeTime,
         Date().timeIntervalSince(changeTime) >= stabilizationDelay {
        captureManualFrame(image)
      } else {
        contentChanged = true
        lastChangeTime = lastChangeTime ?? Date()
      }
    } else {
      // Vision failed — fall back to assuming content changed if enough time passed
      if let lastCapture = lastCaptureTime,
         Date().timeIntervalSince(lastCapture) >= maxIntervalWithoutCapture {
        captureManualFrame(image)
      }
    }
  }

  private func captureManualFrame(_ image: CGImage) {
    // Compute overlap with previous frame via Vision
    var overlap: Int? = nil
    if let previousImage = lastCapturedImage {
      overlap = VisionImageRegistration.computeOverlap(top: previousImage, bottom: image)
    }

    let frame = CaptureFrame(
      image: image,
      timestamp: Date(),
      overlapWithPrevious: overlap
    )
    captures.append(frame)
    lastCapturedImage = image
    lastCaptureTime = Date()
    lastChangeTime = nil
    contentChanged = false

    debugLog("ScrollCaptureSession: Captured manual frame \(captures.count) (overlap: \(overlap.map { "\($0)px" } ?? "unknown"))")
    onProgressUpdate?(captures.count)
  }

  // MARK: - Stitching

  private func performStitching() {
    guard state == .capturing || state == .idle else { return }
    state = .stitching
    onStatusUpdate?("Stitching \(captures.count) frames…")

    debugLog("ScrollCaptureSession: Stitching \(captures.count) frames")

    guard !captures.isEmpty else {
      state = .idle
      onCompletion?(.failure(Error.noFramesCaptured))
      clearHandlers()
      return
    }

    if captures.count == 1 {
      let image = captures[0].image
      captures.removeAll()
      captureRegion = nil
      state = .completed
      onCompletion?(.success(image))
      clearHandlers()
      return
    }

    Task {
      do {
        let images = captures.map { $0.image }
        let precomputedOverlaps = captures.map { $0.overlapWithPrevious }

        let stitched = try ImageStitcher.stitchVertical(images, precomputedOverlaps: precomputedOverlaps)

        captures.removeAll()
        captureRegion = nil
        lastCapturedImage = nil
        state = .completed
        debugLog("ScrollCaptureSession: Stitching complete")
        onCompletion?(.success(stitched))
        clearHandlers()
      } catch {
        captures.removeAll()
        captureRegion = nil
        lastCapturedImage = nil
        state = .idle
        debugLog("ScrollCaptureSession: Stitching failed: \(error)")
        onCompletion?(.failure(error))
        clearHandlers()
      }
    }
  }

  // MARK: - Helpers

  private func captureScreenRegion(_ region: CGRect) -> CGImage? {
    CGDisplayCreateImage(CGMainDisplayID(), rect: region)
  }

  private func isBlankImage(_ image: CGImage) -> Bool {
    let width = image.width
    let height = image.height
    guard width > 0, height > 0 else { return true }

    let sampleSize = 16
    var pixels: [UInt8] = Array(repeating: 0, count: sampleSize * sampleSize)

    let colorSpace = CGColorSpaceCreateDeviceGray()
    guard let context = CGContext(
      data: &pixels,
      width: sampleSize,
      height: sampleSize,
      bitsPerComponent: 8,
      bytesPerRow: sampleSize,
      space: colorSpace,
      bitmapInfo: CGImageAlphaInfo.none.rawValue
    ) else { return false }

    context.interpolationQuality = .low
    context.draw(image, in: CGRect(x: 0, y: 0, width: sampleSize, height: sampleSize))

    let sum = pixels.reduce(0) { $0 + Int($1) }
    let avg = Double(sum) / Double(pixels.count)
    let variance = pixels.reduce(0.0) { $0 + pow(Double($1) - avg, 2) } / Double(pixels.count)

    return variance < blankVarianceThreshold
  }

  private func clearHandlers() {
    onCompletion = nil
    onProgressUpdate = nil
    onStatusUpdate = nil
  }
}
