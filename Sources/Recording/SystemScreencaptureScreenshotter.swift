import Foundation

enum ScreenshotCaptureError: Error {
  case cancelled
  case permissionDenied
  case failedToStart(String)
  case failed(Int32)
  case appSupportDirUnavailable
}

/// Uses macOS built-in `screencapture` to take still screenshots.
///
/// We use this for region + window screenshots because it is reliable and provides the native UI.
final class SystemScreencaptureScreenshotter {
  private let capturesDirURL: URL

  init(capturesDirURL: URL) {
    self.capturesDirURL = capturesDirURL
  }

  func captureRegion(delay: TimeInterval = 0) async throws -> URL {
    try await capture(args: ["-i", "-s", "-x"], prefix: "screenshot_region", ext: "png", delay: delay)
  }

  func captureWindow(delay: TimeInterval = 0) async throws -> URL {
    try await capture(args: ["-i", "-w", "-x"], prefix: "screenshot_window", ext: "png", delay: delay)
  }

  func captureFullScreen(delay: TimeInterval = 0) async throws -> URL {
    try await capture(args: ["-m", "-x"], prefix: "screenshot_fullscreen", ext: "png", delay: delay)
  }

  private func capture(args: [String], prefix: String, ext: String, delay: TimeInterval) async throws -> URL {
    if delay > 0 {
      try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
    }
    let outURL = try makeCaptureURL(prefix: prefix, ext: ext)

    let p = Process()
    p.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
    p.arguments = args + [outURL.path]

    p.standardInput = nil
    p.standardOutput = nil
    p.standardError = nil

    do {
      try p.run()
    } catch {
      throw ScreenshotCaptureError.failedToStart(String(describing: error))
    }

    return try await withCheckedThrowingContinuation { (cont: CheckedContinuation<URL, Error>) in
      p.terminationHandler = { proc in
        let status = proc.terminationStatus
        if status == 0 {
          cont.resume(returning: outURL)
        } else if status == 1 {
          // Common exit code when the user cancels the selection.
          cont.resume(throwing: ScreenshotCaptureError.cancelled)
        } else {
          cont.resume(throwing: ScreenshotCaptureError.failed(status))
        }
      }
    }
  }

  private func makeCaptureURL(prefix: String, ext: String) throws -> URL {
    let fm = FileManager.default

    // Ensure directory exists (CaptureLibrary also expects it).
    try fm.createDirectory(at: capturesDirURL, withIntermediateDirectories: true)

    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    let ts = formatter.string(from: Date()).replacingOccurrences(of: ":", with: "-")

    return capturesDirURL.appendingPathComponent("\(prefix)_\(ts).\(ext)")
  }
}
