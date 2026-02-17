import Foundation
import CoreGraphics

/// Stitches multiple overlapping images into a single tall image.
enum ImageStitcher {

  /// Default blend height for seam transitions.
  private static let defaultBlendHeight = 32

  /// Stitch images vertically (for scrolling down).
  /// - Parameters:
  ///   - images: Ordered frames from top to bottom.
  ///   - precomputedOverlaps: Optional pre-computed overlap for each frame (index 0 is nil/ignored).
  ///     When provided, skips expensive re-computation.
  static func stitchVertical(_ images: [CGImage], precomputedOverlaps: [Int?]? = nil) throws -> CGImage {
    guard !images.isEmpty else {
      throw Error.noImages
    }

    if images.count == 1 {
      return images[0]
    }

    debugLog("ImageStitcher: Stitching \(images.count) images")

    // Calculate total height and find overlaps
    let width = images[0].width
    var totalHeight = images[0].height
    var offsets: [Int] = [0]
    var overlaps: [Int] = [0]  // overlap[0] unused

    for i in 1..<images.count {
      let prevImage = images[i - 1]
      let currentImage = images[i]

      // Use pre-computed overlap if available, otherwise compute
      let overlap: Int
      if let precomputed = precomputedOverlaps, i < precomputed.count, let pre = precomputed[i], pre > 0 {
        overlap = pre
        debugLog("ImageStitcher: Using pre-computed overlap for frame \(i): \(overlap)px")
      } else {
        overlap = findOverlapOffset(top: prevImage, bottom: currentImage)
        debugLog("ImageStitcher: Computed overlap for frame \(i): \(overlap)px")
      }

      overlaps.append(overlap)

      let prevOffset = offsets[i - 1]
      let newOffset = prevOffset + prevImage.height - overlap
      offsets.append(newOffset)

      totalHeight = newOffset + currentImage.height
    }

    debugLog("ImageStitcher: Total composite size: \(width)x\(totalHeight)")

    // Create composite image
    guard let context = CGContext(
      data: nil,
      width: width,
      height: totalHeight,
      bitsPerComponent: 8,
      bytesPerRow: width * 4,
      space: CGColorSpaceCreateDeviceRGB(),
      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else {
      throw Error.failedToCreateContext
    }

    // Draw each image at its calculated offset, with seam blending for overlaps
    for (i, image) in images.enumerated() {
      let yOffset = offsets[i]
      let rect = CGRect(
        x: 0,
        y: totalHeight - yOffset - image.height,  // Flip Y for Core Graphics
        width: image.width,
        height: image.height
      )

      if i > 0 {
        let prevBottom = offsets[i - 1] + images[i - 1].height
        let overlapPixels = prevBottom - yOffset

        if overlapPixels > 0 && overlapPixels < image.height {
          let blendHeight = min(defaultBlendHeight, overlapPixels)

          // Draw non-overlap portion at full opacity
          context.saveGState()
          context.clip(to: CGRect(
            x: 0,
            y: totalHeight - yOffset - image.height,
            width: image.width,
            height: image.height - overlapPixels
          ))
          context.draw(image, in: rect)
          context.restoreGState()

          // Draw overlap portion with gradient mask for smooth seam blending
          if let mask = createSeamMask(width: image.width, height: overlapPixels, blendHeight: blendHeight) {
            context.saveGState()
            context.clip(to: CGRect(
              x: 0,
              y: totalHeight - yOffset - overlapPixels,
              width: image.width,
              height: overlapPixels
            ), mask: mask)
            context.draw(image, in: rect)
            context.restoreGState()
          }

          debugLog("ImageStitcher: Drew frame \(i) at y=\(yOffset) with \(blendHeight)px seam blend")
          continue
        }
      }

      context.draw(image, in: rect)
      debugLog("ImageStitcher: Drew frame \(i) at y=\(yOffset)")
    }

    guard let stitched = context.makeImage() else {
      throw Error.failedToMakeImage
    }

    debugLog("ImageStitcher: Successfully stitched \(images.count) images into \(stitched.width)x\(stitched.height)")

    return stitched
  }

  /// Find the overlap offset between two images.
  /// Uses Vision framework as primary, with FeatureMatcher and legacy as fallbacks.
  private static func findOverlapOffset(top: CGImage, bottom: CGImage) -> Int {
    // Primary: Vision framework image registration
    if let visionOverlap = VisionImageRegistration.computeOverlap(top: top, bottom: bottom) {
      debugLog("ImageStitcher: Using Vision overlap: \(visionOverlap)px")
      return visionOverlap
    }

    // Fallback 1: FeatureMatcher pixel correlation
    if let match = FeatureMatcher.findOverlap(top: top, bottom: bottom) {
      if match.confidence >= 0.7 {
        debugLog("ImageStitcher: Using FeatureMatcher fallback: \(match.offset)px (confidence: \(String(format: "%.2f", match.confidence)))")
        return match.offset
      } else {
        debugLog("ImageStitcher: FeatureMatcher too low confidence (\(String(format: "%.2f", match.confidence)))")
      }
    }

    // Fallback 2: Legacy pixel-based method
    return findOverlapOffsetLegacy(top: top, bottom: bottom)
  }

  /// Legacy pixel-based overlap detection (last-resort fallback).
  private static func findOverlapOffsetLegacy(top: CGImage, bottom: CGImage) -> Int {
    let width = min(top.width, bottom.width)
    let searchHeight = min(top.height, bottom.height, 1200)

    guard let topData = extractBottomRows(top, rowCount: searchHeight),
          let bottomData = extractTopRows(bottom, rowCount: searchHeight) else {
      debugLog("ImageStitcher: Failed to extract pixel data, using minimal overlap")
      return 30
    }

    var bestMatch = 0
    var bestScore = 0

    let minimumOverlap = 30
    let maximumOverlap = max(minimumOverlap, Int(Double(searchHeight) * 0.5))

    for overlapSize in stride(from: minimumOverlap, through: maximumOverlap, by: 2) {
      let sampleStep = max(1, overlapSize / 200)
      var matchingPixels = 0

      for row in stride(from: 0, to: overlapSize, by: sampleStep) {
        let topRow = searchHeight - overlapSize + row
        let bottomRow = row

        if rowsMatch(topData: topData, topRow: topRow, bottomData: bottomData, bottomRow: bottomRow, width: width) {
          matchingPixels += 1
        }
      }

      if matchingPixels > bestScore {
        bestScore = matchingPixels
        bestMatch = overlapSize
      }
    }

    let bestSampleStep = max(1, bestMatch / 200)
    let totalSampled = bestMatch > 0 ? (bestMatch + bestSampleStep - 1) / bestSampleStep : 0
    let matchPercentage = totalSampled > 0 ? (bestScore * 100) / totalSampled : 0

    if matchPercentage < 40 {
      debugLog("ImageStitcher: Poor legacy match (\(matchPercentage)%), using minimal overlap")
      return minimumOverlap
    }

    debugLog("ImageStitcher: Legacy match found: \(bestMatch)px (\(matchPercentage)%)")
    return bestMatch
  }

  /// Extract bottom rows of an image as raw pixel data
  private static func extractBottomRows(_ image: CGImage, rowCount: Int) -> Data? {
    let width = image.width
    let height = image.height
    let actualRows = min(rowCount, height)
    let startY = height - actualRows

    guard let cropped = image.cropping(to: CGRect(x: 0, y: startY, width: width, height: actualRows)) else {
      return nil
    }

    return extractPixelData(cropped)
  }

  /// Extract top rows of an image as raw pixel data
  private static func extractTopRows(_ image: CGImage, rowCount: Int) -> Data? {
    let width = image.width
    let actualRows = min(rowCount, image.height)

    guard let cropped = image.cropping(to: CGRect(x: 0, y: 0, width: width, height: actualRows)) else {
      return nil
    }

    return extractPixelData(cropped)
  }

  /// Extract raw pixel data from an image
  private static func extractPixelData(_ image: CGImage) -> Data? {
    let width = image.width
    let height = image.height
    let bytesPerRow = width * 4
    let bufferSize = bytesPerRow * height

    let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
    defer { buffer.deallocate() }

    guard let context = CGContext(
      data: buffer,
      width: width,
      height: height,
      bitsPerComponent: 8,
      bytesPerRow: bytesPerRow,
      space: CGColorSpaceCreateDeviceRGB(),
      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else { return nil }

    context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
    return Data(bytes: buffer, count: bufferSize)
  }

  /// Check if two rows match (with some tolerance for compression artifacts)
  private static func rowsMatch(topData: Data, topRow: Int, bottomData: Data, bottomRow: Int, width: Int) -> Bool {
    let bytesPerRow = width * 4
    let topOffset = topRow * bytesPerRow
    let bottomOffset = bottomRow * bytesPerRow

    guard topOffset + bytesPerRow <= topData.count,
          bottomOffset + bytesPerRow <= bottomData.count else {
      return false
    }

    let margin = max(1, width / 5)
    let startX = margin
    let endX = max(margin + 1, width - margin)
    let compareWidth = endX - startX

    var differences = 0
    let threshold = 20
    let maxDifferences = max(1, compareWidth / 5)

    for x in startX..<endX {
      let topPixelOffset = topOffset + x * 4
      let bottomPixelOffset = bottomOffset + x * 4

      let rDiff = abs(Int(topData[topPixelOffset]) - Int(bottomData[bottomPixelOffset]))
      let gDiff = abs(Int(topData[topPixelOffset + 1]) - Int(bottomData[bottomPixelOffset + 1]))
      let bDiff = abs(Int(topData[topPixelOffset + 2]) - Int(bottomData[bottomPixelOffset + 2]))

      if rDiff > threshold || gDiff > threshold || bDiff > threshold {
        differences += 1
        if differences > maxDifferences {
          return false
        }
      }
    }

    return true
  }

  /// Create a grayscale gradient mask for smooth seam blending between frames.
  private static func createSeamMask(width: Int, height: Int, blendHeight: Int) -> CGImage? {
    var pixels = [UInt8](repeating: 255, count: width * height)

    for y in 0..<min(blendHeight, height) {
      let alpha = UInt8(min(255, (y * 255) / max(blendHeight - 1, 1)))
      for x in 0..<width {
        pixels[y * width + x] = alpha
      }
    }

    let data = Data(pixels)
    guard let provider = CGDataProvider(data: data as CFData) else { return nil }

    return CGImage(
      width: width,
      height: height,
      bitsPerComponent: 8,
      bitsPerPixel: 8,
      bytesPerRow: width,
      space: CGColorSpaceCreateDeviceGray(),
      bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue),
      provider: provider,
      decode: nil,
      shouldInterpolate: false,
      intent: .defaultIntent
    )
  }

  // MARK: - Errors

  enum Error: LocalizedError {
    case noImages
    case failedToCreateContext
    case failedToMakeImage

    var errorDescription: String? {
      switch self {
      case .noImages:
        return "No images to stitch"
      case .failedToCreateContext:
        return "Failed to create graphics context"
      case .failedToMakeImage:
        return "Failed to create final image"
      }
    }
  }
}