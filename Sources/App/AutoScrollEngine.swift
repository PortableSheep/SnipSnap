import Foundation
import CoreGraphics
import AppKit

/// Programmatically scrolls the target window using CGEvent scroll wheel events.
/// Used by ScrollCaptureSession in auto-scroll mode to ensure consistent, predictable frame overlap.
@MainActor
final class AutoScrollEngine {

  // MARK: - Configuration

  /// Fraction of region height to scroll per step (0.7 = 70%, leaving 30% overlap).
  var overlapFraction: CGFloat = 0.30

  /// Delay after posting a scroll event before capturing, to let the content render.
  private let renderDelay: UInt64 = 150_000_000  // 150ms in nanoseconds

  /// Maximum consecutive duplicate frames before declaring end-of-scroll.
  private let maxConsecutiveDuplicates = 2

  /// Pixel threshold for Vision duplicate detection.
  private let duplicateThreshold: CGFloat = 5

  // MARK: - State

  private(set) var isRunning = false
  private var shouldStop = false

  // MARK: - Public API

  struct CapturedFrame {
    let image: CGImage
    let overlapWithPrevious: Int?  // nil for first frame
  }

  /// Run the auto-scroll capture loop.
  /// - Parameters:
  ///   - region: Screen region to capture (CG coordinates, top-left origin).
  ///   - onFrame: Called each time a new frame is captured. Return `false` to stop.
  ///   - onComplete: Called when scrolling reaches the end or is stopped.
  func run(
    region: CGRect,
    onFrame: @escaping (CapturedFrame) -> Bool,
    onComplete: @escaping (Result<Void, Error>) -> Void
  ) {
    guard !isRunning else {
      onComplete(.failure(AutoScrollError.alreadyRunning))
      return
    }

    isRunning = true
    shouldStop = false

    Task { @MainActor [weak self] in
      guard let self else { return }

      defer {
        self.isRunning = false
      }

      do {
        try await self.scrollLoop(region: region, onFrame: onFrame)
        onComplete(.success(()))
      } catch {
        onComplete(.failure(error))
      }
    }
  }

  /// Stop the auto-scroll loop after the current iteration.
  func stop() {
    shouldStop = true
  }

  // MARK: - Scroll Loop

  private func scrollLoop(
    region: CGRect,
    onFrame: @escaping (CapturedFrame) -> Bool
  ) async throws {
    // Click inside the region to ensure the correct window has focus
    activateWindow(at: region)
    try await Task.sleep(nanoseconds: 200_000_000)  // 200ms for focus

    // Capture initial frame
    guard let firstImage = captureRegion(region) else {
      throw AutoScrollError.captureFailed
    }

    let firstFrame = CapturedFrame(image: firstImage, overlapWithPrevious: nil)
    guard onFrame(firstFrame) else { return }

    var previousImage = firstImage
    var consecutiveDuplicates = 0
    let scrollPixels = Int(region.height * (1.0 - overlapFraction))

    debugLog("AutoScrollEngine: Starting loop, scroll step = \(scrollPixels)px, region = \(region)")

    while !shouldStop {
      // Post scroll event
      postScrollEvent(pixels: scrollPixels, at: region)

      // Wait for content to render
      try await Task.sleep(nanoseconds: renderDelay)

      // Capture frame
      guard let currentImage = captureRegion(region) else {
        debugLog("AutoScrollEngine: Capture failed mid-scroll, stopping")
        break
      }

      // Check for duplicate (end-of-scroll)
      if VisionImageRegistration.isDuplicate(
        frame1: previousImage,
        frame2: currentImage,
        threshold: duplicateThreshold
      ) {
        consecutiveDuplicates += 1
        debugLog("AutoScrollEngine: Duplicate frame \(consecutiveDuplicates)/\(maxConsecutiveDuplicates)")

        if consecutiveDuplicates >= maxConsecutiveDuplicates {
          debugLog("AutoScrollEngine: End of scroll detected")
          break
        }
        continue  // Skip this frame but keep scrolling to confirm
      }
      consecutiveDuplicates = 0

      // Compute overlap with previous frame
      let overlap = VisionImageRegistration.computeOverlap(top: previousImage, bottom: currentImage)
        ?? fallbackOverlap(top: previousImage, bottom: currentImage)

      let frame = CapturedFrame(image: currentImage, overlapWithPrevious: overlap)
      guard onFrame(frame) else {
        debugLog("AutoScrollEngine: Stopped by onFrame callback")
        break
      }

      previousImage = currentImage
    }

    debugLog("AutoScrollEngine: Loop finished")
  }

  // MARK: - CGEvent Helpers

  private func postScrollEvent(pixels: Int, at region: CGRect) {
    // Position the cursor at the center of the capture region
    let centerX = region.midX
    let centerY = region.midY

    // Move mouse to center of region (ensures scroll targets the right window)
    let moveEvent = CGEvent(mouseEventSource: nil, mouseType: .mouseMoved,
                            mouseCursorPosition: CGPoint(x: centerX, y: centerY),
                            mouseButton: .left)
    moveEvent?.post(tap: .cghidEventTap)

    // Post scroll wheel event — negative wheel1 = scroll down
    guard let scrollEvent = CGEvent(
      scrollWheelEvent2Source: nil,
      units: .pixel,
      wheelCount: 1,
      wheel1: -Int32(pixels),
      wheel2: 0,
      wheel3: 0
    ) else {
      debugLog("AutoScrollEngine: Failed to create scroll event")
      return
    }

    // Set the event location to the center of the region
    scrollEvent.location = CGPoint(x: centerX, y: centerY)
    scrollEvent.post(tap: .cghidEventTap)
  }

  private func activateWindow(at region: CGRect) {
    let centerX = region.midX
    let centerY = region.midY
    let point = CGPoint(x: centerX, y: centerY)

    // Click to focus
    let mouseDown = CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown,
                            mouseCursorPosition: point, mouseButton: .left)
    let mouseUp = CGEvent(mouseEventSource: nil, mouseType: .leftMouseUp,
                          mouseCursorPosition: point, mouseButton: .left)
    mouseDown?.post(tap: .cghidEventTap)
    mouseUp?.post(tap: .cghidEventTap)
  }

  // MARK: - Screen Capture

  private func captureRegion(_ region: CGRect) -> CGImage? {
    CGDisplayCreateImage(CGMainDisplayID(), rect: region)
  }

  // MARK: - Fallback Overlap

  /// When Vision registration fails, estimate overlap from the known scroll amount.
  private func fallbackOverlap(top: CGImage, bottom: CGImage) -> Int {
    // Use FeatureMatcher as fallback
    if let match = FeatureMatcher.findOverlap(top: top, bottom: bottom), match.confidence >= 0.7 {
      debugLog("AutoScrollEngine: Using FeatureMatcher fallback: \(match.offset)px")
      return match.offset
    }
    // Last resort: assume the configured overlap fraction held
    let estimated = Int(CGFloat(top.height) * overlapFraction)
    debugLog("AutoScrollEngine: Using estimated overlap: \(estimated)px")
    return estimated
  }

  // MARK: - Errors

  enum AutoScrollError: LocalizedError {
    case alreadyRunning
    case captureFailed

    var errorDescription: String? {
      switch self {
      case .alreadyRunning:
        return "Auto-scroll is already running"
      case .captureFailed:
        return "Failed to capture screen region"
      }
    }
  }
}
