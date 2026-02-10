import Foundation
import AppKit
import CoreGraphics

/// Manages a scroll capture session where the user manually scrolls
/// and the app automatically captures frames when content changes.
@MainActor
final class ScrollCaptureSession {
  
  // MARK: - Types
  
  enum State {
    case idle
    case monitoring
    case stitching
    case completed
    case cancelled
  }
  
  struct CaptureFrame {
    let image: CGImage
    let timestamp: Date
    let hash: UInt64
  }
  
  // MARK: - Properties
  
  private(set) var state: State = .idle
  private(set) var captures: [CaptureFrame] = []
  private var captureRegion: CGRect?
  private var monitorTimer: Timer?
  private var lastContentHash: UInt64 = 0
  private var onProgressUpdate: ((Int) -> Void)?
  private var onCompletion: ((Result<CGImage, Error>) -> Void)?
  
  // MARK: - Lifecycle
  
  deinit {
    // Ensure timers are cleaned up
    monitorTimer?.invalidate()
    monitorTimer = nil
    debugLog("ScrollCaptureSession: Deinitialized")
  }
  
  // MARK: - Configuration
  
  /// How often to check for content changes (seconds)
  private let pollInterval: TimeInterval = 0.05
  
  /// How long to wait for content to stabilize before capturing (debounce)
  /// Increased to ensure better overlap between frames
  private let stabilizationDelay: TimeInterval = 0.25
  
  /// Track when content last changed for debouncing
  private var lastChangeTime: Date?

  /// Minimum change in perceptual hash to consider content updated
  private let contentChangeThreshold: Int = 1

  /// Treat near-identical frames as duplicates
  private let duplicateFrameThreshold: Int = 1
  
  /// Detect when content is mostly blank (scrolled past end)
  private var consecutiveBlankFrames: Int = 0
  private let maxConsecutiveBlankFrames: Int = 3
  
  // MARK: - Public API
  
  /// Start monitoring a screen region for scroll changes
  func start(region: CGRect, onProgress: @escaping (Int) -> Void, completion: @escaping (Result<CGImage, Error>) -> Void) {
    guard state == .idle else {
      completion(.failure(ScrollCaptureError.alreadyActive))
      return
    }
    
    self.captureRegion = region
    self.onProgressUpdate = onProgress
    self.onCompletion = completion
    self.state = .monitoring
    self.captures.removeAll()
    self.lastContentHash = 0
    self.consecutiveBlankFrames = 0
    
    // Start monitoring timer
    monitorTimer = Timer.scheduledTimer(withTimeInterval: pollInterval, repeats: true) { [weak self] _ in
      Task { @MainActor in
        await self?.checkForContentChange()
      }
    }
    
    debugLog("ScrollCaptureSession: Started monitoring region \(region)")
  }
  
  /// User signals they're done scrolling - stitch and complete
  func finish() {
    guard state == .monitoring else { return }
    
    debugLog("ScrollCaptureSession: User signaled finish")
    
    // Stop monitoring immediately
    monitorTimer?.invalidate()
    monitorTimer = nil
    
    state = .stitching
    
    if captures.count >= 2,
       hammingDistance(captures[captures.count - 1].hash, captures[captures.count - 2].hash) <= duplicateFrameThreshold {
      captures.removeLast()
    }

    debugLog("ScrollCaptureSession: Stitching \(captures.count) frames")
    
    Task {
      do {
        let stitched = try await stitchCaptures()
        
        // Clear captures to free memory
        captures.removeAll()
        captureRegion = nil
        
        state = .completed
        debugLog("ScrollCaptureSession: Stitching complete, calling completion handler")
        onCompletion?(.success(stitched))
        
        // Clear completion handler to break retain cycle
        onCompletion = nil
        onProgressUpdate = nil
        
      } catch {
        captures.removeAll()
        captureRegion = nil
        state = .idle
        debugLog("ScrollCaptureSession: Stitching failed: \(error)")
        onCompletion?(.failure(error))
        onCompletion = nil
        onProgressUpdate = nil
      }
    }
  }
  
  /// Cancel the capture session
  func cancel() {
    debugLog("ScrollCaptureSession: Cancel called")
    
    monitorTimer?.invalidate()
    monitorTimer = nil
    state = .cancelled
    
    // Clear everything
    captures.removeAll()
    captureRegion = nil
    
    debugLog("ScrollCaptureSession: Cancelled")
    onCompletion?(.failure(ScrollCaptureError.cancelled))
    
    // Clear handlers
    onCompletion = nil
    onProgressUpdate = nil
  }
  

  
  // MARK: - Private Methods
  
  private func checkForContentChange() async {
    guard let region = captureRegion, state == .monitoring else { return }
    
    do {
      // Capture current region content
      guard let image = try await captureScreenRegion(region) else {
        debugLog("ScrollCaptureSession: Failed to capture region")
        return
      }
      
      // Hash only the middle content strip where text scrolls (more sensitive to changes)
      let contentHash = contentStripHash(image)
      
      // Detect if image is mostly blank (scrolled past content)
      if isBlankImage(image) {
        consecutiveBlankFrames += 1
        debugLog("ScrollCaptureSession: Blank frame detected (\(consecutiveBlankFrames)/\(maxConsecutiveBlankFrames))")
        
        if consecutiveBlankFrames >= maxConsecutiveBlankFrames {
          debugLog("ScrollCaptureSession: Multiple blank frames detected - likely scrolled past end")
        }
        return
      } else {
        consecutiveBlankFrames = 0
      }
      
      // Check if content changed
      let contentDistance = hammingDistance(contentHash, lastContentHash)
      if contentDistance >= contentChangeThreshold {
        // Content is changing - update the "last change" time but don't capture yet
        lastChangeTime = Date()
        lastContentHash = contentHash
      } else if let changeTime = lastChangeTime {
        // Same content - check if it's been stable long enough to capture
        let timeSinceChange = Date().timeIntervalSince(changeTime)
        
        // Only capture if content has been stable for the debounce period
        if timeSinceChange >= stabilizationDelay {
          // Calculate full-frame hash to avoid capturing identical frames
          let fullHash = perceptualHash(image)
          
          // Only skip if the frame is near-identical (user stopped scrolling)
          if let lastFrame = captures.last,
             hammingDistance(lastFrame.hash, fullHash) <= duplicateFrameThreshold {
            debugLog("ScrollCaptureSession: Near-identical frame detected, skipping")
            lastChangeTime = nil  // Reset to avoid repeated checks
            return
          }
          
          // Content is stable and different - capture it!
          let frame = CaptureFrame(
            image: image,
            timestamp: Date(),
            hash: fullHash
          )
          captures.append(frame)
          lastChangeTime = nil  // Reset for next scroll
          
          debugLog("ScrollCaptureSession: Captured stable frame \(captures.count) after \(String(format: "%.2f", timeSinceChange))s")
          onProgressUpdate?(captures.count)
        }
      }
    } catch {
      debugLog("ScrollCaptureSession: Error capturing: \(error)")
    }
  }
  
  private func captureScreenRegion(_ region: CGRect) async throws -> CGImage? {
    // CGDisplayCreateImage expects screen coordinates (not scaled)
    // It automatically captures at physical pixel resolution (Retina-aware)
    let image = CGDisplayCreateImage(
      CGMainDisplayID(),
      rect: region
    )
    return image
  }
  
  private func isBlankImage(_ image: CGImage) -> Bool {
    // Sample a few points to see if mostly uniform/white
    let width = image.width
    let height = image.height
    
    guard width > 0, height > 0 else { return true }
    
    // Create a small version to analyze
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
    
    // Calculate variance - blank images have very low variance
    let sum = pixels.reduce(0) { $0 + Int($1) }
    let avg = Double(sum) / Double(pixels.count)
    let variance = pixels.reduce(0.0) { $0 + pow(Double($1) - avg, 2) } / Double(pixels.count)
    
    // Also check if very bright (likely white background)
    let isBright = avg > 240
    let isLowVariance = variance < 50
    
    return isBright && isLowVariance
  }
  
  private func perceptualHash(_ image: CGImage) -> UInt64 {
    // Simple perceptual hash using 8x8 grid
    let size = 8
    let width = image.width
    let height = image.height
    
    guard width > 0, height > 0 else { return 0 }
    
    // Create a small grayscale version
    var pixels: [UInt8] = Array(repeating: 0, count: size * size)
    
    let colorSpace = CGColorSpaceCreateDeviceGray()
    guard let context = CGContext(
      data: &pixels,
      width: size,
      height: size,
      bitsPerComponent: 8,
      bytesPerRow: size,
      space: colorSpace,
      bitmapInfo: CGImageAlphaInfo.none.rawValue
    ) else { return 0 }
    
    context.interpolationQuality = .high
    context.draw(image, in: CGRect(x: 0, y: 0, width: size, height: size))
    
    // Calculate average brightness
    let sum = pixels.reduce(0) { $0 + Int($1) }
    let avg = UInt8(sum / pixels.count)
    
    // Create hash: 1 if pixel > average, 0 otherwise
    var hash: UInt64 = 0
    for pixel in pixels {
      hash = (hash << 1) | (pixel > avg ? 1 : 0)
    }
    
    return hash
  }

  private func sampledHash(_ image: CGImage, size: Int = 24) -> UInt64 {
    let width = image.width
    let height = image.height
    
    guard width > 0, height > 0 else { return 0 }
    
    var pixels: [UInt8] = Array(repeating: 0, count: size * size)
    
    let colorSpace = CGColorSpaceCreateDeviceGray()
    guard let context = CGContext(
      data: &pixels,
      width: size,
      height: size,
      bitsPerComponent: 8,
      bytesPerRow: size,
      space: colorSpace,
      bitmapInfo: CGImageAlphaInfo.none.rawValue
    ) else { return 0 }
    
    context.interpolationQuality = .high
    context.draw(image, in: CGRect(x: 0, y: 0, width: size, height: size))
    
    var hash: UInt64 = 0xcbf29ce484222325
    for pixel in pixels {
      hash ^= UInt64(pixel)
      hash &*= 0x100000001b3
    }
    
    return hash
  }

  private func hammingDistance(_ a: UInt64, _ b: UInt64) -> Int {
    (a ^ b).nonzeroBitCount
  }
  
  /// Hash just the middle horizontal strip of content (where scrolling text appears)
  /// This is much more sensitive to scroll changes than hashing the entire viewport
  private func contentStripHash(_ image: CGImage) -> UInt64 {
    let stripHeight = image.height / 3  // Use middle third of viewport
    let stripY = image.height / 3  // Start at 1/3 from top
    
    // Crop to middle strip (avoid toolbars/scrollbars at edges)
    let marginX = image.width / 5  // Ignore left/right 20% (scrollbars/sidebars)
    let stripWidth = image.width - (marginX * 2)
    
    guard let strip = image.cropping(to: CGRect(
      x: marginX,
      y: stripY,
      width: stripWidth,
      height: stripHeight
    )) else {
      return 0
    }
    
    return sampledHash(strip)
  }
  
  private func stitchCaptures() async throws -> CGImage {
    guard !captures.isEmpty else {
      throw ScrollCaptureError.noFramesCaptured
    }
    
    if captures.count == 1 {
      // Only one frame, just return it
      return captures[0].image
    }
    
    // Use ImageStitcher to merge all frames
    let images = captures.map { $0.image }
    return try await ImageStitcher.stitchVertical(images)
  }
}

// MARK: - Errors

enum ScrollCaptureError: LocalizedError {
  case alreadyActive
  case cancelled
  case noFramesCaptured
  case noRegionSelected
  case captureFailed
  case stitchingFailed(Error)
  
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
