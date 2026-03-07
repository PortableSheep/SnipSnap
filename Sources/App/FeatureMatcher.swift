import Foundation
import CoreGraphics

/// Pixel-correlation-based overlap detection for scrolling capture frame stitching.
enum FeatureMatcher {
  
  struct Match {
    let offset: Int
    let confidence: Double
  }
  
  /// Maximum region height (in pixels) to search for overlaps.
  private static let maxSearchHeight = 800
  
  /// Minimum confidence score (0–1) required to accept an overlap match.
  private static let minimumConfidence = 0.7
  
  /// Coarse-pass stride (pixels) for initial overlap search.
  private static let coarseStride = 10
  
  /// Fine-pass search radius (pixels) around best coarse match.
  private static let refinementRadius = 15
  
  /// Find the best overlap offset between two images using pixel correlation.
  /// Returns the number of pixels from the bottom of topImage that overlap with top of bottomImage.
  static func findOverlap(top: CGImage, bottom: CGImage) -> Match? {
    let searchHeight = min(top.height, bottom.height, maxSearchHeight)
    
    guard let topRegion = top.cropping(to: CGRect(
      x: 0,
      y: top.height - searchHeight,
      width: top.width,
      height: searchHeight
    )) else { return nil }
    
    guard let bottomRegion = bottom.cropping(to: CGRect(
      x: 0,
      y: 0,
      width: bottom.width,
      height: searchHeight
    )) else { return nil }
    
    if let match = pixelCorrelationMatch(topRegion: topRegion, bottomRegion: bottomRegion, searchHeight: searchHeight) {
      debugLog("FeatureMatcher: Pixel correlation match found: \(match.offset)px (confidence: \(String(format: "%.2f", match.confidence)))")
      return match
    }
    
    debugLog("FeatureMatcher: No reliable match found")
    return nil
  }
  
  // MARK: - Pixel Correlation Matching
  
  private static func pixelCorrelationMatch(topRegion: CGImage, bottomRegion: CGImage, searchHeight: Int) -> Match? {
    guard let topData = extractPixelData(topRegion),
          let bottomData = extractPixelData(bottomRegion) else {
      return nil
    }
    
    // Search for overlaps between 10% and 50% of the frame height
    let minOverlap = max(100, searchHeight / 10)
    let maxOverlap = min(searchHeight - 100, searchHeight / 2)
    
    var bestMatch: Match?
    var bestScore = 0.0
    
    for overlap in stride(from: minOverlap, through: maxOverlap, by: coarseStride) {
      let score = computePixelCorrelation(
        topData: topData,
        bottomData: bottomData,
        overlap: overlap,
        width: topRegion.width,
        searchHeight: searchHeight
      )
      
      if score > bestScore {
        bestScore = score
        bestMatch = Match(offset: overlap, confidence: score)
      }
    }
    
    // Refinement pass: search ±15px around best coarse match at pixel granularity
    if let coarseMatch = bestMatch {
      let refineMin = max(minOverlap, coarseMatch.offset - refinementRadius)
      let refineMax = min(maxOverlap, coarseMatch.offset + refinementRadius)
      
      for overlap in refineMin...refineMax {
        let score = computePixelCorrelation(
          topData: topData,
          bottomData: bottomData,
          overlap: overlap,
          width: topRegion.width,
          searchHeight: searchHeight
        )
        
        if score > bestScore {
          bestScore = score
          bestMatch = Match(offset: overlap, confidence: score)
        }
      }
    }
    
    return bestScore > minimumConfidence ? bestMatch : nil
  }
  
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
  
  private static func computePixelCorrelation(topData: Data, bottomData: Data, overlap: Int, width: Int, searchHeight: Int) -> Double {
    let bytesPerRow = width * 4
    let topStart = searchHeight - overlap
    
    var totalDiff = 0
    var totalPixels = 0
    
    // Sample more rows for better accuracy
    let sampleEveryNRows = max(1, overlap / 100)
    
    for row in stride(from: 0, to: overlap, by: sampleEveryNRows) {
      let topRow = topStart + row
      let bottomRow = row
      
      let topOffset = topRow * bytesPerRow
      let bottomOffset = bottomRow * bytesPerRow
      let sampleEveryNPixels = max(1, width / 200)
      
      for col in stride(from: 0, to: width, by: sampleEveryNPixels) {
        let pixelOffset = col * 4
        
        guard topOffset + pixelOffset + 2 < topData.count,
              bottomOffset + pixelOffset + 2 < bottomData.count else {
          continue
        }
        
        let topR = Int(topData[topOffset + pixelOffset])
        let topG = Int(topData[topOffset + pixelOffset + 1])
        let topB = Int(topData[topOffset + pixelOffset + 2])
        
        let bottomR = Int(bottomData[bottomOffset + pixelOffset])
        let bottomG = Int(bottomData[bottomOffset + pixelOffset + 1])
        let bottomB = Int(bottomData[bottomOffset + pixelOffset + 2])
        
        // Use euclidean distance for color matching
        let rDiff = topR - bottomR
        let gDiff = topG - bottomG
        let bDiff = topB - bottomB
        let distance = sqrt(Double(rDiff * rDiff + gDiff * gDiff + bDiff * bDiff))
        
        totalDiff += Int(distance)
        totalPixels += 1
      }
    }
    
    // Convert to similarity score (0-1)
    // Max euclidean distance for RGB is sqrt(255^2 * 3) ≈ 441
    let avgDiff = totalPixels > 0 ? Double(totalDiff) / Double(totalPixels) : 441.0
    let similarity = max(0, 1.0 - (avgDiff / 441.0))
    
    return similarity
  }
}
