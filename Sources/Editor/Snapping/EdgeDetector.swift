import AppKit
import CoreGraphics
import Foundation
import Vision

/// Detects edges and UI element boundaries in images for measurement snapping
enum EdgeDetector {

  /// A detected edge that can be snapped to
  struct DetectedEdge {
    let point: CGPoint
    let orientation: EdgeOrientation
    let confidence: Float

    enum EdgeOrientation {
      case horizontal
      case vertical
    }
  }

  /// A detected rectangle (potential UI element)
  struct DetectedRect {
    let bounds: CGRect
    let confidence: Float
  }

  // MARK: - Vision-based Rectangle Detection

  /// Detect rectangles in an image using Vision framework
  /// Great for finding buttons, cards, and other UI elements
  static func detectRectangles(in cgImage: CGImage, completion: @escaping ([DetectedRect]) -> Void) {
    let request = VNDetectRectanglesRequest { request, error in
      guard error == nil,
            let results = request.results as? [VNRectangleObservation] else {
        completion([])
        return
      }

      let imageSize = CGSize(width: cgImage.width, height: cgImage.height)
      let rects = results.map { obs -> DetectedRect in
        // Convert normalized coordinates to image coordinates
        let bounds = CGRect(
          x: obs.boundingBox.origin.x * imageSize.width,
          y: (1 - obs.boundingBox.origin.y - obs.boundingBox.height) * imageSize.height,
          width: obs.boundingBox.width * imageSize.width,
          height: obs.boundingBox.height * imageSize.height
        )
        return DetectedRect(bounds: bounds, confidence: obs.confidence)
      }

      completion(rects)
    }

    request.minimumConfidence = 0.3
    request.minimumAspectRatio = 0.1
    request.maximumAspectRatio = 10.0
    request.minimumSize = 0.02
    request.maximumObservations = 50

    let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
    DispatchQueue.global(qos: .userInitiated).async {
      try? handler.perform([request])
    }
  }

  // MARK: - Contrast-based Edge Detection

  /// Simple edge detection using contrast changes
  /// Works well for high-contrast UI elements
  static func detectEdgesWithContrast(
    in cgImage: CGImage,
    nearPoint point: CGPoint,
    searchRadius: CGFloat = 50
  ) -> [DetectedEdge] {
    guard let dataProvider = cgImage.dataProvider,
          let data = dataProvider.data,
          let bytes = CFDataGetBytePtr(data) else {
      return []
    }

    let width = cgImage.width
    let height = cgImage.height
    let bytesPerPixel = cgImage.bitsPerPixel / 8
    let bytesPerRow = cgImage.bytesPerRow

    var edges: [DetectedEdge] = []

    // Search area bounds
    let searchMinX = max(0, Int(point.x - searchRadius))
    let searchMaxX = min(width - 1, Int(point.x + searchRadius))
    let searchMinY = max(0, Int(point.y - searchRadius))
    let searchMaxY = min(height - 1, Int(point.y + searchRadius))

    // Horizontal edge detection (scan vertically)
    for x in stride(from: searchMinX, to: searchMaxX, by: 5) {
      var prevLuminance: CGFloat = 0
      for y in searchMinY...searchMaxY {
        let offset = y * bytesPerRow + x * bytesPerPixel
        let r = CGFloat(bytes[offset]) / 255.0
        let g = CGFloat(bytes[offset + 1]) / 255.0
        let b = CGFloat(bytes[offset + 2]) / 255.0
        let luminance = 0.299 * r + 0.587 * g + 0.114 * b

        if y > searchMinY {
          let diff = abs(luminance - prevLuminance)
          if diff > 0.15 { // Significant contrast change
            edges.append(DetectedEdge(
              point: CGPoint(x: CGFloat(x), y: CGFloat(y)),
              orientation: .horizontal,
              confidence: Float(min(1.0, diff * 2))
            ))
          }
        }
        prevLuminance = luminance
      }
    }

    // Vertical edge detection (scan horizontally)
    for y in stride(from: searchMinY, to: searchMaxY, by: 5) {
      var prevLuminance: CGFloat = 0
      for x in searchMinX...searchMaxX {
        let offset = y * bytesPerRow + x * bytesPerPixel
        let r = CGFloat(bytes[offset]) / 255.0
        let g = CGFloat(bytes[offset + 1]) / 255.0
        let b = CGFloat(bytes[offset + 2]) / 255.0
        let luminance = 0.299 * r + 0.587 * g + 0.114 * b

        if x > searchMinX {
          let diff = abs(luminance - prevLuminance)
          if diff > 0.15 {
            edges.append(DetectedEdge(
              point: CGPoint(x: CGFloat(x), y: CGFloat(y)),
              orientation: .vertical,
              confidence: Float(min(1.0, diff * 2))
            ))
          }
        }
        prevLuminance = luminance
      }
    }

    return edges
  }

  // MARK: - Snap Point Calculation

  /// Find the nearest snappable point given detected edges/rectangles
  static func findSnapPoint(
    near point: CGPoint,
    edges: [DetectedEdge],
    rects: [DetectedRect],
    snapThreshold: CGFloat = 15
  ) -> CGPoint? {
    var bestPoint: CGPoint? = nil
    var bestDistance: CGFloat = snapThreshold

    // Check rectangle edges
    for rect in rects {
      let candidates = [
        CGPoint(x: rect.bounds.minX, y: point.y), // Left edge
        CGPoint(x: rect.bounds.maxX, y: point.y), // Right edge
        CGPoint(x: point.x, y: rect.bounds.minY), // Top edge
        CGPoint(x: point.x, y: rect.bounds.maxY), // Bottom edge
      ]

      for candidate in candidates {
        let dist = hypot(candidate.x - point.x, candidate.y - point.y)
        if dist < bestDistance {
          bestDistance = dist
          bestPoint = candidate
        }
      }
    }

    // Check contrast edges
    for edge in edges {
      let candidate: CGPoint
      switch edge.orientation {
      case .horizontal:
        candidate = CGPoint(x: point.x, y: edge.point.y)
      case .vertical:
        candidate = CGPoint(x: edge.point.x, y: point.y)
      }

      let dist = hypot(candidate.x - point.x, candidate.y - point.y)
      if dist < bestDistance {
        bestDistance = dist
        bestPoint = candidate
      }
    }

    return bestPoint
  }
}
