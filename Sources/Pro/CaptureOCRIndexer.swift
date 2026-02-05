import Foundation
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

  func indexImage(at url: URL) async throws -> Result {
    let cgImage = try loadCGImage(url: url)

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
