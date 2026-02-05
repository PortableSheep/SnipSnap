@preconcurrency import AVFoundation
import AppKit
import CoreGraphics
import Foundation

enum RecorderError: Error {
  case alreadyRecording
  case notRecording
  case cancelled
  case failedToStart(String)
  case failedToStop(String)
  case appSupportDirUnavailable
}

/// Minimal first slice: use macOS built-in `screencapture` to record a video.
///
/// This is intentionally a stepping stone. The “full native” next step is to replace this with
/// ScreenCaptureKit + AVAssetWriter for tighter control, better overlays, and audio.
final class SystemScreencaptureRecorder: Recording, @unchecked Sendable {
  private var process: Process?
  private(set) var lastRecordingURL: URL?

  var lastErrorMessage: String?

  private var didRequestStop: Bool = false
  private var processStartTime: CFTimeInterval?

  private var rawMovURL: URL?

  private var stderrPipe: Pipe?
  private var stderrBuffer: String = ""
  private let stderrQueue = DispatchQueue(label: "SnipSnap.SystemScreencaptureRecorder.stderr")

  // Optional live overlays while recording (also serves as a "recording is active" affordance).
  private let overlays = OverlayEventTap()

  // Overlay settings (wired from Preferences via CaptureAgent).
  var showClickOverlay: Bool = true
  var showKeystrokeHUD: Bool = true
  var clickRingColor: CGColor = CGColor(red: 1, green: 1, blue: 1, alpha: 1)
  var hudPlacement: HUDPlacement = .bottomCenter
  var showCursor: Bool = true

  var isRecording: Bool {
    process?.isRunning == true
  }

  func start() async throws {
    try await start(interactiveSelection: false)
  }

  func start(interactiveSelection: Bool) async throws {
    if isRecording { throw RecorderError.alreadyRecording }
    lastErrorMessage = nil
    didRequestStop = false
    processStartTime = nil

    // On macOS 26+, `-v` (video) cannot be combined with `-i` (interactive selection).
    // However, `-v -J window` still lets the user pick a window to record (CleanShot-style).
    // When interactiveSelection is true we start in window-selection mode.

    // `screencapture -v` produces a QuickTime movie; keep it as a real .mov,
    // then transcode to .mp4 for cross-platform sharing.
    let outURL = try Self.makeRecordingMOVURL()

    let p = Process()
    p.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")

    // Flags:
    // -v video recording
    // -J window starts interactive capture in window-only mode
    // -C include cursor
    // -k show mouse clicks (best-effort; varies by macOS)
    // -x no UI sounds
    var args: [String] = ["-v"]
    if interactiveSelection {
      args.append(contentsOf: ["-J", "window"])
    }

    // If we're showing overlays, use our own drawing. Otherwise fall back to system `-k`.
    if !showClickOverlay {
      // No overlays enabled - use system click indicator
      args.append("-k")
    }

    if showCursor {
      args.append("-C")  // Include cursor
    }
    args.append(contentsOf: ["-x", outURL.path])
    p.arguments = args

    p.standardInput = nil
    p.standardOutput = nil

    // Capture stderr so we can show useful errors (permission denied, cancellation, etc.).
    let errPipe = Pipe()
    p.standardError = errPipe
    stderrPipe = errPipe
    stderrBuffer = ""

    errPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
      let data = handle.availableData
      guard !data.isEmpty else { return }
      if let s = String(data: data, encoding: .utf8), !s.isEmpty {
        self?.stderrQueue.async {
          self?.stderrBuffer.append(s)
        }
      }
    }

    do {
      try p.run()
    } catch {
      throw RecorderError.failedToStart(String(describing: error))
    }

    func installTerminationHandler(on proc: Process) {
      proc.terminationHandler = { [weak self] finished in
        guard let self else { return }

        // If we asked it to stop, don't treat termination as an error.
        if self.didRequestStop { return }

        // If it exits with status 0 unexpectedly, still surface a hint.
        if finished.terminationStatus == 0 {
          self.lastErrorMessage = "Region recording ended"
          return
        }

        let errText: String = self.stderrQueue.sync {
          self.stderrBuffer.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if !errText.isEmpty {
          self.lastErrorMessage = errText
        } else if finished.terminationStatus == 1 {
          self.lastErrorMessage = "cancelled"
        } else {
          self.lastErrorMessage = "screencapture exited with status \(finished.terminationStatus)"
        }
      }
    }

    process = p
    lastRecordingURL = outURL
    rawMovURL = outURL
    processStartTime = CACurrentMediaTime()

    // Track premature termination so status callers can surface useful diagnostics.
    installTerminationHandler(on: p)

    // Guard against immediate failures (bad flags, permission errors, etc.).
    // This helps prevent the main app from thinking it's recording when `screencapture` exited.
    func finalizeImmediateExit(_ proc: Process) async throws {
      // Stop reading stderr.
      stderrPipe?.fileHandleForReading.readabilityHandler = nil

      let errText: String = await withCheckedContinuation { cont in
        stderrQueue.async { [stderrBuffer] in
          cont.resume(returning: stderrBuffer.trimmingCharacters(in: .whitespacesAndNewlines))
        }
      }

      process = nil

      DispatchQueue.main.async { [overlays] in
        overlays.stop()
      }

      if proc.terminationStatus == 1 {
        self.lastErrorMessage = errText.isEmpty ? "cancelled" : errText
        throw RecorderError.cancelled
      }

      let msg = errText.isEmpty
        ? "screencapture exited with status \(proc.terminationStatus)"
        : errText
      self.lastErrorMessage = msg
      throw RecorderError.failedToStart(msg)
    }

    // Allow more time for interactive selection: the user may take a while to draw the region.
    // For interactive mode, 2 seconds; for fullscreen just 250ms.
    let startGrace: UInt64 = interactiveSelection ? 2_000_000_000 : 250_000_000
    try? await Task.sleep(nanoseconds: startGrace)

    // If the process exits before the grace period, it indicates a failure.
    if p.isRunning == false {
      try await finalizeImmediateExit(p)
    }
  }

  func stop() async throws {
    guard let p = process, p.isRunning else {
      process = nil
      throw RecorderError.notRecording
    }

    didRequestStop = true

    // SIGINT so screencapture finalizes the movie.
    kill(p.processIdentifier, SIGINT)

    // Wait for the process to fully terminate so the movie container is finalized.
    let deadline = Date().addingTimeInterval(10.0)
    while p.isRunning && Date() < deadline {
      try? await Task.sleep(nanoseconds: 100_000_000)
    }

    if p.isRunning {
      // Best-effort cleanup.
      kill(p.processIdentifier, SIGTERM)
      try? await Task.sleep(nanoseconds: 250_000_000)
    }

    // Stop reading stderr.
    stderrPipe?.fileHandleForReading.readabilityHandler = nil

    let overlays = self.overlays
    DispatchQueue.main.async {
      overlays.stop()
    }

    if p.isRunning {
      process = nil
      throw RecorderError.failedToStop("screencapture did not terminate")
    }

    // Ensure any queued stderr text is flushed.
    let errText: String = await withCheckedContinuation { cont in
      stderrQueue.async { [stderrBuffer] in
        cont.resume(returning: stderrBuffer.trimmingCharacters(in: .whitespacesAndNewlines))
      }
    }

    process = nil

    // Non-zero exits usually mean cancellation or permission issues.
    if p.terminationStatus != 0 {
      let msg = errText.isEmpty ? "screencapture exited with status \(p.terminationStatus)" : errText
      throw RecorderError.failedToStop(msg)
    }

    // Convert the finalized .mov to .mp4 for broad compatibility.
    if let movURL = rawMovURL {
      let mp4URL = movURL.deletingPathExtension().appendingPathExtension("mp4")
      do {
        try await Self.convertMOVToMP4(inputURL: movURL, outputURL: mp4URL)
        lastRecordingURL = mp4URL
        rawMovURL = nil
        try? FileManager.default.removeItem(at: movURL)
      } catch {
        // If conversion fails, keep the original .mov so the user still has a recording.
        lastRecordingURL = movURL
        rawMovURL = nil
      }
    }
  }

  private static func makeRecordingMOVURL() throws -> URL {
    let fm = FileManager.default

    guard let appSupport = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
      throw RecorderError.appSupportDirUnavailable
    }

    let dir = appSupport
      .appendingPathComponent("SnipSnap", isDirectory: true)
      .appendingPathComponent("captures", isDirectory: true)

    try fm.createDirectory(at: dir, withIntermediateDirectories: true)

    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    let ts = formatter.string(from: Date()).replacingOccurrences(of: ":", with: "-")

    return dir.appendingPathComponent("recording_\(ts).mov")
  }

  private static func convertMOVToMP4(inputURL: URL, outputURL: URL) async throws {
    let asset = AVAsset(url: inputURL)
    _ = try await asset.load(.tracks)

    guard let export = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetHighestQuality) else {
      throw RecorderError.failedToStop("Failed to create export session")
    }

    guard export.supportedFileTypes.contains(.mp4) else {
      throw RecorderError.failedToStop("MP4 export not supported for this recording")
    }

    try? FileManager.default.createDirectory(at: outputURL.deletingLastPathComponent(), withIntermediateDirectories: true)
    try? FileManager.default.removeItem(at: outputURL)

    export.outputURL = outputURL
    export.outputFileType = .mp4

    try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
      export.exportAsynchronously {
        switch export.status {
        case .completed:
          cont.resume(returning: ())
        case .failed:
          cont.resume(throwing: export.error ?? RecorderError.failedToStop("MP4 export failed"))
        case .cancelled:
          cont.resume(throwing: export.error ?? CancellationError())
        default:
          cont.resume(throwing: export.error ?? RecorderError.failedToStop("MP4 export failed"))
        }
      }
    }
  }
}
