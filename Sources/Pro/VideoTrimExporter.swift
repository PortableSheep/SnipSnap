import AVFoundation
import Foundation

enum VideoTrimError: Error {
  case invalidRange
  case exportSessionFailed
  case unsupportedOutputType
}

final class VideoTrimExporter {
  struct Options {
    var startSeconds: Double
    var endSeconds: Double?
  }

  func exportTrimmedVideo(from inputURL: URL, to outputURL: URL, options: Options) async throws {
    let asset = AVAsset(url: inputURL)
    _ = try await asset.load(.tracks)

    let duration = try await asset.load(.duration)
    let durationSeconds = max(0, duration.seconds)

    let start = max(0, options.startSeconds)
    let end = min(options.endSeconds ?? durationSeconds, durationSeconds)

    guard durationSeconds > 0, end > start else {
      throw VideoTrimError.invalidRange
    }

    guard let export = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetHighestQuality) else {
      throw VideoTrimError.exportSessionFailed
    }

    // Match the user's chosen extension when possible.
    let outputType: AVFileType
    switch outputURL.pathExtension.lowercased() {
    case "mp4":
      guard export.supportedFileTypes.contains(.mp4) else { throw VideoTrimError.unsupportedOutputType }
      outputType = .mp4
    case "mov", "m4v":
      guard export.supportedFileTypes.contains(.mov) else { throw VideoTrimError.unsupportedOutputType }
      outputType = .mov
    default:
      // Prefer .mov for macOS workflows, fall back to .mp4 if needed.
      if export.supportedFileTypes.contains(.mov) {
        outputType = .mov
      } else if export.supportedFileTypes.contains(.mp4) {
        outputType = .mp4
      } else {
        throw VideoTrimError.unsupportedOutputType
      }
    }

    // Ensure parent folder exists.
    let dir = outputURL.deletingLastPathComponent()
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

    // Remove existing file if present.
    try? FileManager.default.removeItem(at: outputURL)

    export.outputURL = outputURL
    export.outputFileType = outputType

    let startTime = CMTime(seconds: start, preferredTimescale: 600)
    let endTime = CMTime(seconds: end, preferredTimescale: 600)
    export.timeRange = CMTimeRangeFromTimeToTime(start: startTime, end: endTime)

    try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
      export.exportAsynchronously {
        switch export.status {
        case .completed:
          cont.resume(returning: ())
        case .failed:
          cont.resume(throwing: export.error ?? VideoTrimError.exportSessionFailed)
        case .cancelled:
          cont.resume(throwing: export.error ?? CancellationError())
        default:
          cont.resume(throwing: export.error ?? VideoTrimError.exportSessionFailed)
        }
      }
    }
  }
}
