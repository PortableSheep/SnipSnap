import Foundation
import CoreGraphics
import AppKit

/// Stitches multiple overlapping images into a single tall image
enum ImageStitcher {
  
  /// Stitch images vertically (for scrolling down)
  static func stitchVertical(_ images: [CGImage]) async throws -> CGImage {
    guard !images.isEmpty else {
      throw StitchError.noImages
    }
    
    if images.count == 1 {
      return images[0]
    }
    
    debugLog("ImageStitcher: Stitching \(images.count) images")
    
    // Calculate total height and find overlaps
    let width = images[0].width
    var totalHeight = images[0].height
    var offsets: [Int] = [0]  // Y offset for each image
    
    for i in 1..<images.count {
      let prevImage = images[i - 1]
      let currentImage = images[i]
      
      // Find overlap between previous and current image
      let overlap = findOverlapOffset(top: prevImage, bottom: currentImage)
      
      debugLog("ImageStitcher: Overlap between frame \(i-1) and \(i): \(overlap) pixels")
      
      // Calculate Y offset for this image
      let prevOffset = offsets[i - 1]
      let prevHeight = prevImage.height
      let newOffset = prevOffset + prevHeight - overlap
      offsets.append(newOffset)
      
      // Update total height
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
      throw StitchError.failedToCreateContext
    }
    
    // Draw each image at its calculated offset
    for (i, image) in images.enumerated() {
      let yOffset = offsets[i]
      let rect = CGRect(
        x: 0,
        y: totalHeight - yOffset - image.height,  // Flip Y for Core Graphics
        width: image.width,
        height: image.height
      )
      
      context.draw(image, in: rect)
      debugLog("ImageStitcher: Drew frame \(i) at y=\(yOffset)")
    }
    
    guard let stitched = context.makeImage() else {
      throw StitchError.failedToMakeImage
    }
    
    debugLog("ImageStitcher: Successfully stitched \(images.count) images into \(stitched.width)x\(stitched.height)")
    
    return stitched
  }
  
  /// Find the overlap offset between two images
  /// Returns the number of pixels from the bottom of topImage that match the top of bottomImage
  private static func findOverlapOffset(top: CGImage, bottom: CGImage) -> Int {
    let width = min(top.width, bottom.width)
    let searchHeight = min(top.height, bottom.height, 1200)  // Search up to full height or 1200px
    
    // Extract pixel data for comparison
    guard let topData = extractBottomRows(top, rowCount: searchHeight),
          let bottomData = extractTopRows(bottom, rowCount: searchHeight) else {
      debugLog("ImageStitcher: Failed to extract pixel data for overlap detection")
      return 0  // No overlap found, stack end-to-end
    }
    
    // Find best matching offset by comparing rows
    var bestMatch = 0
    var bestScore = 0
    var candidates: [(overlap: Int, match: Int)] = []
    
    // Start from reasonable overlaps and work up (stride by 2 for better precision)
    let minimumOverlap = 20
    let maximumOverlap = max(minimumOverlap, Int(Double(searchHeight) * 0.7))
    for overlapSize in stride(from: minimumOverlap, through: maximumOverlap, by: 2) {
      let compareRows = min(200, overlapSize)  // Compare more rows for better accuracy
      var matchingPixels = 0
      
      for row in 0..<compareRows {
        // topRow is from the bottom of top image
        let topRow = searchHeight - overlapSize + row
        let bottomRow = row
        
        if rowsMatch(topData: topData, topRow: topRow, bottomData: bottomData, bottomRow: bottomRow, width: width) {
          matchingPixels += 1
        }
      }
      
      let matchPercentage = compareRows > 0 ? (matchingPixels * 100) / compareRows : 0
      
      if matchingPixels > bestScore {
        bestScore = matchingPixels
        bestMatch = overlapSize
      }
      candidates.append((overlap: overlapSize, match: matchPercentage))
    }
    
    // Only use the overlap if it's a good match (>50% rows matching)
    let compareRows = min(200, bestMatch)
    let matchPercentage = compareRows > 0 ? (bestScore * 100) / compareRows : 0
    
    if matchPercentage < 50 {
      debugLog("ImageStitcher: Poor overlap match (\(matchPercentage)% with \(bestMatch)px), assuming minimal overlap")
      return minimumOverlap
    }

    let tolerance = 5
    if let preferred = candidates
      .filter({ $0.match >= matchPercentage - tolerance })
      .map(\.overlap)
      .min() {
      debugLog("ImageStitcher: Good overlap found: \(preferred)px (\(matchPercentage)%)")
      return preferred
    }
    
    debugLog("ImageStitcher: Good overlap found: \(bestMatch)px (\(matchPercentage)%)")
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
    
    var pixelData = Data(count: bytesPerRow * height)
    
    guard let context = CGContext(
      data: pixelData.withUnsafeMutableBytes { $0.baseAddress },
      width: width,
      height: height,
      bitsPerComponent: 8,
      bytesPerRow: bytesPerRow,
      space: CGColorSpaceCreateDeviceRGB(),
      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else {
      return nil
    }
    
    context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
    
    return pixelData
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
    let threshold = 20  // Allow larger differences per pixel channel
    let maxDifferences = max(1, compareWidth / 5)  // Allow 20% of pixels to differ
    
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
}

// MARK: - Errors

enum StitchError: LocalizedError {
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
