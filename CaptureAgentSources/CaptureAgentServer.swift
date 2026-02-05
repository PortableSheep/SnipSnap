import AppKit
import CoreFoundation
import CoreGraphics
import Foundation
import ScreenCaptureKit
import Security

@available(macOS 13.0, *)
final class CaptureAgentServer {
  private let screenRecorder = ScreenCaptureKitRecorder()
  private let regionRecorder = SystemScreencaptureRecorder()
  private lazy var screenshotter = SystemScreencaptureScreenshotter(capturesDirURL: Self.capturesDirURL())

  @MainActor
  private func ensureScreenRecordingAccess() async throws {
    // Use the more reliable async check first
    if await ScreenRecordingPermission.checkAccess() { return }

    // Fallback to sync check with prompt
    if ScreenRecordingPermission.hasAccess(prompt: false) { return }

    // Trigger the system prompt (if eligible) and ensure the app shows up in Settings.
    NSApp.activate(ignoringOtherApps: true)
    _ = ScreenRecordingPermission.hasAccess(prompt: true)

    // Check again with the more reliable async method
    if await ScreenRecordingPermission.checkAccess() { return }

    // If still not granted, open Settings so the user can enable it.
    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
      NSWorkspace.shared.open(url)
    }

    throw NSError(
      domain: "SnipSnapCaptureAgent",
      code: 1,
      userInfo: [NSLocalizedDescriptionKey: "Screen Recording permission not granted. Enable it for SnipSnap Capture Agent and relaunch."]
    )
  }

  func start() {
    // IMPORTANT: Do not run the message port on the main thread.
    // The CFMessagePort callback is synchronous; if it blocks the main thread
    // while waiting for @MainActor capture work, it will deadlock and time out.
    let thread = Thread { [weak self] in
      guard let self else { return }

      var context = CFMessagePortContext(
        version: 0,
        info: UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque()),
        retain: nil,
        release: nil,
        copyDescription: nil
      )

      let callback: CFMessagePortCallBack = { _, msgid, data, info in
        guard let info else { return nil }
        let server = Unmanaged<CaptureAgentServer>.fromOpaque(info).takeUnretainedValue()
        return server.handle(messageID: msgid, data: data)
      }

      guard let port = CFMessagePortCreateLocal(nil, CaptureAgentIPC.portName as CFString, callback, &context, nil) else {
        return
      }

      let source = CFMessagePortCreateRunLoopSource(nil, port, 0)
      CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)

      // Keep the port and runloop alive.
      withExtendedLifetime(port) {
        CFRunLoopRun()
      }
    }

    thread.name = "SnipSnapCaptureAgent.CFMessagePort"
    thread.start()
  }

  private func handle(messageID: Int32, data: CFData?) -> Unmanaged<CFData>? {
    guard let data = data as Data? else {
      return Unmanaged.passRetained(Data("{\"ok\":false,\"error\":\"missing data\"}".utf8) as CFData)
    }

    let req: CaptureAgentRequest
    do {
      req = try JSONDecoder().decode(CaptureAgentRequest.self, from: data)
    } catch {
      // Most commonly caused by an app/agent mismatch (e.g. old Capture Agent still installed).
      // Give the user something actionable instead of the opaque "bad request".
      let msg = "bad request: \(error.localizedDescription). If you recently updated SnipSnap, make sure SnipSnap Capture Agent is updated too (quit both apps, replace both app bundles, then relaunch)."
      let json = "{\"ok\":false,\"error\":\"\(msg.replacingOccurrences(of: "\\\"", with: "\\\\\\\""))\"}"
      return Unmanaged.passRetained(Data(json.utf8) as CFData)
    }

    let sema = DispatchSemaphore(value: 0)
    var response = CaptureAgentResponse(ok: false, error: "unknown", lastCapturePath: nil)

    Task { @MainActor in
      do {
        response = try await self.performOnMain(req)
      } catch {
        response = CaptureAgentResponse(ok: false, error: String(describing: error), lastCapturePath: nil)
      }
      sema.signal()
    }

    _ = sema.wait(timeout: .now() + 60)

    let out = (try? JSONEncoder().encode(response)) ?? Data("{\"ok\":false,\"error\":\"encode failed\"}".utf8)
    return Unmanaged.passRetained(out as CFData)
  }

  @MainActor
  private func performOnMain(_ req: CaptureAgentRequest) async throws -> CaptureAgentResponse {
    switch req.command {
    case .startFullScreenRecording:
      try await ensureScreenRecordingAccess()
      if let settings = req.overlaySettings {
        applyOverlaySettings(settings)
      }
      screenRecorder.lastErrorMessage = nil
      try await screenRecorder.start(regionRectInScreenPoints: nil)
      return .init(ok: true, error: nil, lastCapturePath: screenRecorder.lastRecordingURL?.path)

    case .startWindowRecording:
      try await ensureScreenRecordingAccess()
      if let settings = req.overlaySettings {
        applyOverlaySettings(settings)
      }

      regionRecorder.lastErrorMessage = nil

      // Window-pick via screencapture -J window (interactive window selection).
      NSApp.activate(ignoringOtherApps: true)
      NSRunningApplication.current.activate(options: [.activateAllWindows, .activateIgnoringOtherApps])
      try await regionRecorder.start(interactiveSelection: true)

      try? await Task.sleep(nanoseconds: 350_000_000)
      if !regionRecorder.isRecording {
        let msg = regionRecorder.lastErrorMessage ?? "Window recording ended immediately"
        throw NSError(domain: "SnipSnapCaptureAgent", code: 3, userInfo: [NSLocalizedDescriptionKey: msg])
      }

      return .init(ok: true, error: nil, lastCapturePath: regionRecorder.lastRecordingURL?.path)

    case .startRegionRecording:
      try await ensureScreenRecordingAccess()
      if let settings = req.overlaySettings {
        applyOverlaySettings(settings)
      }

      screenRecorder.lastErrorMessage = nil

      let regionRect = req.regionRect?.cgRect

      // Use ScreenCaptureKit with a cropped region if provided.
      try await screenRecorder.start(regionRectInScreenPoints: regionRect)

      // Best-effort early surface if capture fails quickly.
      try? await Task.sleep(nanoseconds: 350_000_000)
      if !screenRecorder.isRecording {
        let msg = screenRecorder.lastErrorMessage ?? "Region recording ended immediately"
        throw NSError(domain: "SnipSnapCaptureAgent", code: 2, userInfo: [NSLocalizedDescriptionKey: msg])
      }

      return .init(ok: true, error: nil, lastCapturePath: screenRecorder.lastRecordingURL?.path)

    case .stopRecording:
      if screenRecorder.isRecording {
        try await screenRecorder.stop()
        return .init(ok: true, error: nil, lastCapturePath: screenRecorder.lastRecordingURL?.path)
      }
      if regionRecorder.isRecording {
        try await regionRecorder.stop()
        return .init(ok: true, error: nil, lastCapturePath: regionRecorder.lastRecordingURL?.path)
      }
      return .init(ok: false, error: "not recording", lastCapturePath: nil)

    case .captureRegionScreenshot:
      try await ensureScreenRecordingAccess()
      let url = try await screenshotter.captureRegion()
      return .init(ok: true, error: nil, lastCapturePath: url.path)

    case .captureWindowScreenshot:
      try await ensureScreenRecordingAccess()
      let url = try await screenshotter.captureWindow()
      return .init(ok: true, error: nil, lastCapturePath: url.path)

    case .requestScreenRecordingPermission:
      // After `tccutil reset ScreenCapture`, macOS often removes the UI row until
      // the app requests access again. This command exists solely to trigger that.
      NSApp.activate(ignoringOtherApps: true)
      _ = ScreenRecordingPermission.hasAccess(prompt: true)

      let preflight = ScreenRecordingPermission.hasAccess(prompt: false)
      if !preflight {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
          NSWorkspace.shared.open(url)
        }
      }
      return .init(ok: preflight, error: preflight ? nil : "not granted", lastCapturePath: nil, isRecording: nil)

    case .status:
      let isRecording = screenRecorder.isRecording || regionRecorder.isRecording
      let last = screenRecorder.lastRecordingURL?.path ?? regionRecorder.lastRecordingURL?.path
      let bundleID = Bundle.main.bundleIdentifier
      let appPath = Bundle.main.bundleURL.path
      let preflight = ScreenRecordingPermission.hasAccess(prompt: false)

      let lastErr = screenRecorder.lastErrorMessage ?? regionRecorder.lastErrorMessage

      let signing = Self.signingDiagnostics()
      return .init(
        ok: true,
        error: nil,
        lastCapturePath: last,
        isRecording: isRecording,
        lastRecordingError: lastErr,
        agentBundleID: bundleID,
        agentAppPath: appPath,
        screenRecordingPreflight: preflight,
        teamIdentifier: signing.teamIdentifier,
        cdHashHex: signing.cdHashHex
      )
    }
  }

  private struct SigningDiagnostics {
    var teamIdentifier: String?
    var cdHashHex: String?
  }

  private static func signingDiagnostics() -> SigningDiagnostics {
    var code: SecCode?
    let selfStatus = SecCodeCopySelf([], &code)
    guard selfStatus == errSecSuccess, let code else {
      return SigningDiagnostics(teamIdentifier: nil, cdHashHex: nil)
    }

    var staticCode: SecStaticCode?
    let staticStatus = SecCodeCopyStaticCode(code, [], &staticCode)
    guard staticStatus == errSecSuccess, let staticCode else {
      return SigningDiagnostics(teamIdentifier: nil, cdHashHex: nil)
    }

    var infoCF: CFDictionary?
    let infoStatus = SecCodeCopySigningInformation(staticCode, SecCSFlags(rawValue: kSecCSSigningInformation), &infoCF)
    guard infoStatus == errSecSuccess, let infoCF else {
      return SigningDiagnostics(teamIdentifier: nil, cdHashHex: nil)
    }

    let info = infoCF as NSDictionary
    let teamID = info[kSecCodeInfoTeamIdentifier] as? String

    var cdHashHex: String?
    if let cdHashData = info[kSecCodeInfoUnique] as? Data {
      cdHashHex = cdHashData.map { String(format: "%02x", $0) }.joined()
    } else if let cdHashNSData = info[kSecCodeInfoUnique] as? NSData {
      let data = cdHashNSData as Data
      cdHashHex = data.map { String(format: "%02x", $0) }.joined()
    }

    return SigningDiagnostics(teamIdentifier: teamID, cdHashHex: cdHashHex)
  }

  private func applyOverlaySettings(_ settings: CaptureAgentOverlaySettings) {
    screenRecorder.showClickOverlay = settings.showClickOverlay
    screenRecorder.showKeystrokeHUD = settings.showKeystrokeHUD
    screenRecorder.previewOverlaysDuringRecording = settings.previewOverlaysDuringRecording
    screenRecorder.showCursor = settings.showCursor
    screenRecorder.hudPlacement = HUDPlacement(rawValue: settings.hudPlacementRaw) ?? .bottomCenter
    screenRecorder.excludeSnipSnapUIFromRecording = settings.excludeSnipSnapUIFromRecording
    screenRecorder.clickRingColor = CGColor(
      red: settings.ringColorR,
      green: settings.ringColorG,
      blue: settings.ringColorB,
      alpha: settings.ringColorA
    )

    // Region recording uses the system `screencapture` tool; we can still provide
    // click/key visibility via a lightweight preview overlay window.
    regionRecorder.showClickOverlay = settings.showClickOverlay
    regionRecorder.showKeystrokeHUD = settings.showKeystrokeHUD
    regionRecorder.previewOverlaysDuringRecording = settings.previewOverlaysDuringRecording
    regionRecorder.showCursor = settings.showCursor
    regionRecorder.hudPlacement = HUDPlacement(rawValue: settings.hudPlacementRaw) ?? .bottomCenter
    regionRecorder.clickRingColor = CGColor(
      red: settings.ringColorR,
      green: settings.ringColorG,
      blue: settings.ringColorB,
      alpha: settings.ringColorA
    )
  }

  private static func capturesDirURL() -> URL {
    let fm = FileManager.default
    let appSupport = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
    let dir = appSupport
      .appendingPathComponent("SnipSnap", isDirectory: true)
      .appendingPathComponent("captures", isDirectory: true)
    try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir
  }
}
