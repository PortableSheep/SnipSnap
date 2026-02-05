import CoreGraphics
import Foundation

/// Manages snap guides and caching for measurement tool
class SnapGuideManager {
  private var cachedRects: [EdgeDetector.DetectedRect] = []
  private var lastImageHash: Int = 0
  private var isProcessing = false

  /// Pre-process image for snapping when measurement tool is activated
  func prepareSnapping(for cgImage: CGImage) {
    let imageHash = cgImage.hashValue

    // Skip if already processed
    guard imageHash != lastImageHash, !isProcessing else { return }

    isProcessing = true
    lastImageHash = imageHash

    EdgeDetector.detectRectangles(in: cgImage) { [weak self] rects in
      DispatchQueue.main.async {
        self?.cachedRects = rects.sorted { $0.confidence > $1.confidence }
        self?.isProcessing = false
      }
    }
  }

  /// Get snap point for a given location
  func snapPoint(
    near point: CGPoint,
    in cgImage: CGImage,
    threshold: CGFloat = 15
  ) -> CGPoint? {
    // Use cached rectangles if available
    if !cachedRects.isEmpty {
      return EdgeDetector.findSnapPoint(
        near: point,
        edges: [],
        rects: cachedRects,
        snapThreshold: threshold
      )
    }

    // Fall back to contrast-based detection
    let edges = EdgeDetector.detectEdgesWithContrast(
      in: cgImage,
      nearPoint: point,
      searchRadius: threshold * 2
    )

    return EdgeDetector.findSnapPoint(
      near: point,
      edges: edges,
      rects: [],
      snapThreshold: threshold
    )
  }

  /// Clear cached data
  func invalidateCache() {
    cachedRects = []
    lastImageHash = 0
  }

  /// Get all detected rectangles for debug visualization
  var detectedRectangles: [EdgeDetector.DetectedRect] {
    cachedRects
  }
}
