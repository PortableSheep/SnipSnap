@preconcurrency import AVFoundation
@preconcurrency import CoreFoundation
import Foundation
@preconcurrency import ImageIO
import UniformTypeIdentifiers

enum GIFExportError: Error {
  case failedToCreateDestination
}

final class GIFExporter {
  struct Options {
    var maxPixelSize: CGFloat = 960
    var targetFPS: Double = 12
    var maxFrames: Int = 600
  }

  func exportVideo(at inputURL: URL, to outputURL: URL, options: Options = Options()) async throws {
    let asset = AVAsset(url: inputURL)

    // Ensure tracks are loaded.
    _ = try await asset.load(.tracks)

    let durationSeconds = try await asset.load(.duration).seconds
    if durationSeconds <= 0 {
      // Create an empty-ish GIF? For now: just no-op.
      return
    }

    let effectiveFPS: Double = {
      let ideal = options.targetFPS
      let cap = Double(options.maxFrames) / max(0.001, durationSeconds)
      return max(1.0, min(ideal, cap))
    }()

    let frameCount = max(1, Int(floor(durationSeconds * effectiveFPS)))
    let step = 1.0 / effectiveFPS

    var times: [NSValue] = []
    times.reserveCapacity(frameCount)
    for i in 0..<frameCount {
      let t = Double(i) * step
      times.append(NSValue(time: CMTime(seconds: t, preferredTimescale: 600)))
    }

    let dest = try createDestination(url: outputURL)

    // GIF container properties
    let gifProps: [CFString: Any] = [
      kCGImagePropertyGIFDictionary: [
        kCGImagePropertyGIFLoopCount: 0, // 0 = loop forever
      ],
    ]
    CGImageDestinationSetProperties(dest, gifProps as CFDictionary)

    let generator = AVAssetImageGenerator(asset: asset)
    generator.appliesPreferredTrackTransform = true
    generator.maximumSize = CGSize(width: options.maxPixelSize, height: options.maxPixelSize)
    generator.requestedTimeToleranceBefore = .zero
    generator.requestedTimeToleranceAfter = .zero

    // Frame properties
    let delay = 1.0 / effectiveFPS
    let frameProps: [CFString: Any] = [
      kCGImagePropertyGIFDictionary: [
        kCGImagePropertyGIFDelayTime: delay,
      ],
    ]

    let totalFrames = times.count
    try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
      var index = 0
      var finished = false

      generator.generateCGImagesAsynchronously(forTimes: times) { _, cgImage, _, result, error in
        if finished { return }

        if let error {
          finished = true
          cont.resume(throwing: error)
          return
        }

        guard result == .succeeded, let cgImage else {
          // Skip frames that fail; don’t crash export.
          index += 1
          if index >= totalFrames {
            finished = true
            if CGImageDestinationFinalize(dest) {
              cont.resume(returning: ())
            } else {
              cont.resume(throwing: GIFExportError.failedToCreateDestination)
            }
          }
          return
        }

        CGImageDestinationAddImage(dest, cgImage, frameProps as CFDictionary)
        index += 1

        if index >= totalFrames {
          finished = true
          if CGImageDestinationFinalize(dest) {
            cont.resume(returning: ())
          } else {
            cont.resume(throwing: GIFExportError.failedToCreateDestination)
          }
        }
      }
    }
  }

  private func createDestination(url: URL) throws -> CGImageDestination {
    // Ensure parent folder exists.
    let dir = url.deletingLastPathComponent()
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

    guard let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.gif.identifier as CFString, 0, nil) else {
      throw GIFExportError.failedToCreateDestination
    }
    return dest
  }
}
