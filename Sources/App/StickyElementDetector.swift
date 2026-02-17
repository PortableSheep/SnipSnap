import Foundation
import CoreGraphics

/// Detects and removes sticky headers/footers from scroll capture frames.
/// Sticky elements are regions that remain pixel-identical across all frames
/// (e.g., fixed navigation bars, floating toolbars).
enum StickyElementDetector {

  struct StickyRegions {
    /// Height in pixels of the sticky header (0 if none detected).
    let headerHeight: Int
    /// Height in pixels of the sticky footer (0 if none detected).
    let footerHeight: Int
  }

  /// Maximum strip height to scan for sticky elements (pixels).
  private static let maxScanHeight = 200

  /// Per-pixel channel tolerance for "identical" comparison.
  private static let pixelTolerance: Int = 3

  /// Minimum number of frames required to reliably detect sticky elements.
  private static let minimumFrames = 3

  /// Detect sticky header and footer regions across a set of capture frames.
  /// A region is "sticky" if the same pixel strip appears in ALL frames.
  static func detect(in images: [CGImage]) -> StickyRegions {
    guard images.count >= minimumFrames else {
      return StickyRegions(headerHeight: 0, footerHeight: 0)
    }

    let width = images[0].width
    let height = images[0].height
    let scanHeight = min(maxScanHeight, height / 4)

    // Extract top strips from all frames
    let topStrips = images.compactMap { extractTopRows($0, rowCount: scanHeight) }
    guard topStrips.count == images.count else {
      return StickyRegions(headerHeight: 0, footerHeight: 0)
    }

    // Extract bottom strips from all frames
    let bottomStrips = images.compactMap { extractBottomRows($0, rowCount: scanHeight) }
    guard bottomStrips.count == images.count else {
      return StickyRegions(headerHeight: 0, footerHeight: 0)
    }

    // Find sticky header: count how many top rows are identical across ALL frames
    let headerHeight = findStickyHeight(strips: topStrips, width: width, scanHeight: scanHeight)

    // Find sticky footer: count how many bottom rows are identical across ALL frames
    let footerHeight = findStickyHeight(strips: bottomStrips, width: width, scanHeight: scanHeight)

    if headerHeight > 0 || footerHeight > 0 {
      debugLog("StickyElementDetector: header=\(headerHeight)px, footer=\(footerHeight)px")
    }

    return StickyRegions(headerHeight: headerHeight, footerHeight: footerHeight)
  }

  /// Crop sticky headers/footers from intermediate frames (preserve in first and last).
  /// Returns new images with sticky regions removed from frames 1..<(count-1).
  static func cropStickyRegions(
    from images: [CGImage],
    sticky: StickyRegions
  ) -> [CGImage] {
    guard images.count >= 2 else { return images }
    guard sticky.headerHeight > 0 || sticky.footerHeight > 0 else { return images }

    var result: [CGImage] = []
    result.reserveCapacity(images.count)

    for (i, image) in images.enumerated() {
      if i == 0 || i == images.count - 1 {
        // Keep first and last frame intact
        result.append(image)
      } else {
        // Crop intermediate frames
        let cropY = sticky.headerHeight
        let cropHeight = image.height - sticky.headerHeight - sticky.footerHeight
        guard cropHeight > 0,
              let cropped = image.cropping(to: CGRect(
                x: 0,
                y: cropY,
                width: image.width,
                height: cropHeight
              )) else {
          result.append(image)
          continue
        }
        result.append(cropped)
      }
    }

    return result
  }

  // MARK: - Private

  private static func findStickyHeight(strips: [Data], width: Int, scanHeight: Int) -> Int {
    let bytesPerRow = width * 4
    let reference = strips[0]
    var stickyRows = 0

    for row in 0..<scanHeight {
      let rowOffset = row * bytesPerRow
      var allMatch = true

      for stripIdx in 1..<strips.count {
        let strip = strips[stripIdx]
        guard rowOffset + bytesPerRow <= reference.count,
              rowOffset + bytesPerRow <= strip.count else {
          allMatch = false
          break
        }

        if !rowsMatch(a: reference, b: strip, offset: rowOffset, width: width) {
          allMatch = false
          break
        }
      }

      if allMatch {
        stickyRows = row + 1
      } else {
        break  // Sticky region must be contiguous from the edge
      }
    }

    return stickyRows
  }

  private static func rowsMatch(a: Data, b: Data, offset: Int, width: Int) -> Bool {
    // Sample pixels across the row for speed
    let step = max(1, width / 100)
    for x in stride(from: 0, to: width, by: step) {
      let px = offset + x * 4
      guard px + 2 < a.count, px + 2 < b.count else { return false }

      if abs(Int(a[px]) - Int(b[px])) > pixelTolerance ||
         abs(Int(a[px + 1]) - Int(b[px + 1])) > pixelTolerance ||
         abs(Int(a[px + 2]) - Int(b[px + 2])) > pixelTolerance {
        return false
      }
    }
    return true
  }

  private static func extractTopRows(_ image: CGImage, rowCount: Int) -> Data? {
    let actualRows = min(rowCount, image.height)
    guard let cropped = image.cropping(to: CGRect(x: 0, y: 0, width: image.width, height: actualRows)) else {
      return nil
    }
    return extractPixelData(cropped)
  }

  private static func extractBottomRows(_ image: CGImage, rowCount: Int) -> Data? {
    let actualRows = min(rowCount, image.height)
    let startY = image.height - actualRows
    guard let cropped = image.cropping(to: CGRect(x: 0, y: startY, width: image.width, height: actualRows)) else {
      return nil
    }
    return extractPixelData(cropped)
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
}
