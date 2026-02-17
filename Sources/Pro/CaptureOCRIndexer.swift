import Foundation
import CoreGraphics
import ImageIO
import Vision

enum CaptureOCRIndexerError: Error {
  case failedToLoadImage
}

final class CaptureOCRIndexer {
  struct Result {
    var fullText: String
    var blocks: [OCRBlock]
  }

  /// Max pixel area before switching to tiled OCR (roughly 2560×3000).
  private static let tiledThreshold = 8_000_000

  /// Max width used when downscaling for tiled OCR.
  private static let tiledMaxWidth = 1440

  /// Tile height in (downscaled) pixels for tiled OCR.
  private static let tileHeight = 1000

  func indexImage(at url: URL) async throws -> Result {
    let cgImage = try loadCGImage(url: url)

    let pixels = cgImage.width * cgImage.height
    if pixels > Self.tiledThreshold {
      return try await indexImageTiled(cgImage)
    }
    return try await indexImageDirect(cgImage)
  }

  // MARK: - Direct OCR (normal-sized images)

  private func indexImageDirect(_ cgImage: CGImage) async throws -> Result {
    return try await withCheckedThrowingContinuation { cont in
      let request = VNRecognizeTextRequest { req, err in
        if let err {
          cont.resume(throwing: err)
          return
        }

        let observations = (req.results as? [VNRecognizedTextObservation]) ?? []
        var blocks: [OCRBlock] = []
        blocks.reserveCapacity(observations.count)

        let strings: [String] = observations.compactMap { obs in
          guard let candidate = obs.topCandidates(1).first else { return nil }
          let bb = obs.boundingBox
          blocks.append(
            OCRBlock(
              boundingBox: NormalizedRect(
                x: Double(bb.origin.x),
                y: Double(bb.origin.y),
                width: Double(bb.size.width),
                height: Double(bb.size.height)
              ),
              text: candidate.string
            )
          )
          return candidate.string
        }

        cont.resume(returning: Result(fullText: strings.joined(separator: "\n"), blocks: blocks))
      }

      request.recognitionLevel = .accurate
      request.usesLanguageCorrection = true
      request.minimumTextHeight = 0.02

      let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
      do {
        try handler.perform([request])
      } catch {
        cont.resume(throwing: error)
      }
    }
  }

  // MARK: - Tiled OCR (large / scrolling-capture images)

  private func indexImageTiled(_ cgImage: CGImage) async throws -> Result {
    let img = downscale(cgImage, maxWidth: Self.tiledMaxWidth) ?? cgImage
    let totalW = img.width
    let totalH = img.height
    let tileH = Self.tileHeight

    var allBlocks: [OCRBlock] = []
    var allStrings: [String] = []

    var y = 0
    while y < totalH {
      let h = min(tileH, totalH - y)
      guard let tile = img.cropping(to: CGRect(x: 0, y: y, width: totalW, height: h)) else {
        y += tileH
        continue
      }

      let tileResult = try await runOCROnTile(tile)

      // Convert bounding boxes from tile-relative to full-image normalized coords.
      // Vision uses bottom-left origin; CGImage.cropping uses top-left origin.
      for block in tileResult.blocks {
        let bb = block.boundingBox
        let adjustedBB = NormalizedRect(
          x: bb.x,
          y: (Double(totalH - y - h) + bb.y * Double(h)) / Double(totalH),
          width: bb.width,
          height: bb.height * Double(h) / Double(totalH)
        )
        allBlocks.append(OCRBlock(boundingBox: adjustedBB, text: block.text))
      }
      allStrings.append(tileResult.fullText)
      y += tileH
    }

    return Result(fullText: allStrings.joined(separator: "\n"), blocks: allBlocks)
  }

  private func runOCROnTile(_ tile: CGImage) async throws -> Result {
    return try await withCheckedThrowingContinuation { cont in
      let request = VNRecognizeTextRequest { req, err in
        if let err {
          cont.resume(throwing: err)
          return
        }

        let observations = (req.results as? [VNRecognizedTextObservation]) ?? []
        var blocks: [OCRBlock] = []
        blocks.reserveCapacity(observations.count)

        let strings: [String] = observations.compactMap { obs in
          guard let candidate = obs.topCandidates(1).first else { return nil }
          let bb = obs.boundingBox
          blocks.append(
            OCRBlock(
              boundingBox: NormalizedRect(
                x: Double(bb.origin.x),
                y: Double(bb.origin.y),
                width: Double(bb.size.width),
                height: Double(bb.size.height)
              ),
              text: candidate.string
            )
          )
          return candidate.string
        }

        cont.resume(returning: Result(fullText: strings.joined(separator: "\n"), blocks: blocks))
      }

      // .fast + no language correction is sufficient for PII pattern detection
      // and keeps per-tile time well under 1s.
      request.recognitionLevel = .fast
      request.usesLanguageCorrection = false

      let handler = VNImageRequestHandler(cgImage: tile, options: [:])
      do {
        try handler.perform([request])
      } catch {
        cont.resume(throwing: error)
      }
    }
  }

  // MARK: - Helpers

  private func downscale(_ image: CGImage, maxWidth: Int) -> CGImage? {
    guard image.width > maxWidth else { return image }
    let scale = Double(maxWidth) / Double(image.width)
    let newW = maxWidth
    let newH = Int(Double(image.height) * scale)
    guard let ctx = CGContext(
      data: nil, width: newW, height: newH,
      bitsPerComponent: 8, bytesPerRow: 0,
      space: CGColorSpaceCreateDeviceRGB(),
      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else { return nil }
    ctx.interpolationQuality = .high
    ctx.draw(image, in: CGRect(x: 0, y: 0, width: newW, height: newH))
    return ctx.makeImage()
  }

  private func loadCGImage(url: URL) throws -> CGImage {
    guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else {
      throw CaptureOCRIndexerError.failedToLoadImage
    }
    let opts: [CFString: Any] = [kCGImageSourceShouldCache: false]
    guard let img = CGImageSourceCreateImageAtIndex(src, 0, opts as CFDictionary) else {
      throw CaptureOCRIndexerError.failedToLoadImage
    }
    return img
  }
}
