import AppKit
import Foundation
import ScreenCaptureKit
import os.log

private let serviceLog = OSLog(subsystem: "com.snipsnap.CaptureService", category: "service")

/// XPC Service delegate that handles incoming connections.
@available(macOS 13.0, *)
final class CaptureServiceDelegate: NSObject, NSXPCListenerDelegate {
  func listener(_ listener: NSXPCListener, shouldAcceptNewConnection newConnection: NSXPCConnection) -> Bool {
    os_log(.info, log: serviceLog, "Accepting new XPC connection")
    
    // Configure the connection's exported interface
    newConnection.exportedInterface = NSXPCInterface(with: CaptureServiceProtocol.self)

    // Register allowed classes for the custom types
    let settingsClasses = NSSet(array: [CaptureServiceSettings.self, NSString.self]) as! Set<AnyHashable>
    let statusClasses = NSSet(array: [CaptureServiceStatus.self, NSString.self]) as! Set<AnyHashable>

    newConnection.exportedInterface?.setClasses(
      settingsClasses,
      for: #selector(CaptureServiceProtocol.startFullScreenRecording(settings:reply:)),
      argumentIndex: 0,
      ofReply: false
    )
    newConnection.exportedInterface?.setClasses(
      settingsClasses,
      for: #selector(CaptureServiceProtocol.startWindowRecording(settings:windowID:reply:)),
      argumentIndex: 0,
      ofReply: false
    )
    newConnection.exportedInterface?.setClasses(
      settingsClasses,
      for: #selector(CaptureServiceProtocol.startRegionRecording(settings:regionX:regionY:regionWidth:regionHeight:reply:)),
      argumentIndex: 0,
      ofReply: false
    )
    newConnection.exportedInterface?.setClasses(
      statusClasses,
      for: #selector(CaptureServiceProtocol.status(reply:)),
      argumentIndex: 0,
      ofReply: true
    )

    // Create and set the exported object
    let service = CaptureService()
    newConnection.exportedObject = service

    // Handle connection invalidation
    newConnection.invalidationHandler = { [weak service] in
      // Clean up if needed
      _ = service
    }

    newConnection.interruptionHandler = {
      // Handle interruption if needed
    }

    newConnection.resume()
    return true
  }
}

/// The actual XPC service implementation.
@available(macOS 13.0, *)
final class CaptureService: NSObject, CaptureServiceProtocol {
  private let screenRecorder = ScreenCaptureKitRecorder()
  private lazy var screenshotter = SystemScreencaptureScreenshotter(capturesDirURL: Self.capturesDirURL())

  // MARK: - Screen Recording Permission

  @MainActor
  private func ensureScreenRecordingAccess() async throws {
    if await ScreenRecordingPermission.checkAccess() { return }
    if ScreenRecordingPermission.hasAccess(prompt: false) { return }

    // Trigger the system prompt
    _ = ScreenRecordingPermission.hasAccess(prompt: true)

    if await ScreenRecordingPermission.checkAccess() { return }

    // Open Settings if still not granted
    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
      NSWorkspace.shared.open(url)
    }

    throw NSError(
      domain: "CaptureService",
      code: 1,
      userInfo: [NSLocalizedDescriptionKey: "Screen Recording permission not granted. Enable it in System Settings → Privacy & Security → Screen Recording."]
    )
  }

  // MARK: - Protocol Implementation

  func startFullScreenRecording(settings: CaptureServiceSettings, reply: @escaping (String?, String?) -> Void) {
    os_log(.info, log: serviceLog, "startFullScreenRecording called")
    Task { @MainActor in
      do {
        try await ensureScreenRecordingAccess()
        applySettings(settings)
        screenRecorder.lastErrorMessage = nil
        try await screenRecorder.start(regionRectInScreenPoints: nil)
        reply(screenRecorder.lastRecordingURL?.path, nil)
      } catch {
        reply(nil, error.localizedDescription)
      }
    }
  }

  func startWindowRecording(settings: CaptureServiceSettings, windowID: UInt32, reply: @escaping (String?, String?) -> Void) {
    os_log(.info, log: serviceLog, "startWindowRecording called with windowID: %d", windowID)
    Task { @MainActor in
      do {
        try await ensureScreenRecordingAccess()
        applySettings(settings)
        screenRecorder.lastErrorMessage = nil

        try await screenRecorder.start(windowID: CGWindowID(windowID))

        try? await Task.sleep(nanoseconds: 350_000_000)
        if !screenRecorder.isRecording {
          let msg = screenRecorder.lastErrorMessage ?? "Window recording ended immediately"
          reply(nil, msg)
          return
        }

        reply(screenRecorder.lastRecordingURL?.path, nil)
      } catch {
        reply(nil, error.localizedDescription)
      }
    }
  }

  func startRegionRecording(
    settings: CaptureServiceSettings,
    regionX: Double,
    regionY: Double,
    regionWidth: Double,
    regionHeight: Double,
    reply: @escaping (String?, String?) -> Void
  ) {
    os_log(.info, log: serviceLog, "startRegionRecording called: x=%{public}f y=%{public}f w=%{public}f h=%{public}f isRecording=%{public}d",
           regionX, regionY, regionWidth, regionHeight, screenRecorder.isRecording ? 1 : 0)
    Task { @MainActor in
      do {
        try await ensureScreenRecordingAccess()
        applySettings(settings)
        screenRecorder.lastErrorMessage = nil

        let regionRect: CGRect?
        if regionWidth > 0 && regionHeight > 0 {
          regionRect = CGRect(x: regionX, y: regionY, width: regionWidth, height: regionHeight)
          os_log(.info, log: serviceLog, "Using region rect: %{public}@", String(describing: regionRect!))
        } else {
          regionRect = nil
          os_log(.info, log: serviceLog, "No region rect provided, using fullscreen")
        }

        try await screenRecorder.start(regionRectInScreenPoints: regionRect)
        os_log(.info, log: serviceLog, "screenRecorder.start completed, isRecording=%{public}d", screenRecorder.isRecording ? 1 : 0)

        try? await Task.sleep(nanoseconds: 350_000_000)
        if !screenRecorder.isRecording {
          let msg = screenRecorder.lastErrorMessage ?? "Region recording ended immediately"
          os_log(.error, log: serviceLog, "Region recording not running after start: %{public}@", msg)
          reply(nil, msg)
          return
        }

        reply(screenRecorder.lastRecordingURL?.path, nil)
      } catch {
        os_log(.error, log: serviceLog, "startRegionRecording error: %{public}@", error.localizedDescription)
        reply(nil, error.localizedDescription)
      }
    }
  }

  func stopRecording(reply: @escaping (String?, String?) -> Void) {
    Task { @MainActor in
      do {
        if screenRecorder.isRecording {
          try await screenRecorder.stop()
          reply(screenRecorder.lastRecordingURL?.path, nil)
          return
        }
        reply(nil, "Not recording")
      } catch {
        reply(nil, error.localizedDescription)
      }
    }
  }

  func captureRegionScreenshot(reply: @escaping (String?, String?) -> Void) {
    Task { @MainActor in
      do {
        try await ensureScreenRecordingAccess()
        let url = try await screenshotter.captureRegion()
        reply(url.path, nil)
      } catch {
        reply(nil, error.localizedDescription)
      }
    }
  }

  func captureWindowScreenshot(reply: @escaping (String?, String?) -> Void) {
    Task { @MainActor in
      do {
        try await ensureScreenRecordingAccess()
        let url = try await screenshotter.captureWindow()
        reply(url.path, nil)
      } catch {
        reply(nil, error.localizedDescription)
      }
    }
  }

  func requestScreenRecordingPermission(reply: @escaping (Bool, String?) -> Void) {
    Task { @MainActor in
      _ = ScreenRecordingPermission.hasAccess(prompt: true)
      let granted = ScreenRecordingPermission.hasAccess(prompt: false)

      if !granted {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
          NSWorkspace.shared.open(url)
        }
      }

      reply(granted, granted ? nil : "Screen Recording permission not granted")
    }
  }

  func status(reply: @escaping (CaptureServiceStatus) -> Void) {
    Task { @MainActor in
      let isRecording = screenRecorder.isRecording
      let lastPath = screenRecorder.lastRecordingURL?.path
      let lastError = screenRecorder.lastErrorMessage
      let permissionGranted = ScreenRecordingPermission.hasAccess(prompt: false)

      let status = CaptureServiceStatus(
        isRecording: isRecording,
        lastCapturePath: lastPath,
        lastRecordingError: lastError,
        screenRecordingPermissionGranted: permissionGranted
      )
      reply(status)
    }
  }

  func recordClickEvent(x: Double, y: Double, time: Double, reply: @escaping () -> Void) {
    // Forward event from main app to the recorder's overlay system
    screenRecorder.recordExternalClick(x: CGFloat(x), y: CGFloat(y), time: time)
    reply()
  }

  func recordKeyEvent(text: String, time: Double, reply: @escaping () -> Void) {
    // Forward event from main app to the recorder's overlay system
    screenRecorder.recordExternalKey(text: text, time: time)
    reply()
  }

  // MARK: - Private Helpers

  private func applySettings(_ settings: CaptureServiceSettings) {
    // Apply overlay settings to the recorder
    screenRecorder.showClickOverlay = settings.showClickOverlay
    screenRecorder.showKeystrokeHUD = settings.showKeystrokeHUD
    screenRecorder.showCursor = settings.showCursor
    screenRecorder.hudPlacement = HUDPlacement(rawValue: settings.hudPlacementRaw) ?? .bottomCenter
    screenRecorder.clickRingColor = CGColor(
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
