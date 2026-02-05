import AppKit
import Foundation
import os.log

private let clientLog = OSLog(subsystem: "com.snipsnap.Snipsnap", category: "CaptureServiceClient")

private func debugLog(_ message: String) {
  let logFile = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("snipsnap-debug.log")
  let timestamp = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
  let line = "[\(timestamp)] \(message)\n"
  if let data = line.data(using: .utf8) {
    if FileManager.default.fileExists(atPath: logFile.path) {
      if let fileHandle = try? FileHandle(forWritingTo: logFile) {
        fileHandle.seekToEndOfFile()
        fileHandle.write(data)
        fileHandle.closeFile()
      }
    } else {
      try? data.write(to: logFile)
    }
  }
}

/// Client for communicating with the CaptureService XPC service.
/// This replaces the old CFMessagePort-based CaptureAgentClient.
@available(macOS 13.0, *)
final class CaptureServiceClient: @unchecked Sendable {
  private var connection: NSXPCConnection?
  private let connectionLock = NSLock()

  deinit {
    connection?.invalidate()
  }

  // MARK: - Public API

  func requestScreenRecordingPermission() async throws -> Bool {
    try await withCheckedThrowingContinuation { continuation in
      getProxy { proxy, error in
        if let error {
          continuation.resume(throwing: error)
          return
        }
        proxy?.requestScreenRecordingPermission { granted, errorMessage in
          if let errorMessage, !granted {
            continuation.resume(throwing: CaptureServiceError.remoteError(errorMessage))
          } else {
            continuation.resume(returning: granted)
          }
        }
      }
    }
  }

  func startFullScreenRecording(settings: CaptureServiceSettings) async throws {
    debugLog("startFullScreenRecording called")
    try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
      getProxy { proxy, error in
        if let error {
          debugLog("getProxy error: \(error)")
          continuation.resume(throwing: error)
          return
        }
        debugLog("calling proxy startFullScreenRecording")
        proxy?.startFullScreenRecording(settings: settings) { _, errorMessage in
          debugLog("got reply: errorMessage=\(errorMessage ?? "nil")")
          if let errorMessage {
            continuation.resume(throwing: CaptureServiceError.remoteError(errorMessage))
          } else {
            continuation.resume()
          }
        }
      }
    }
  }

  func startWindowRecording(settings: CaptureServiceSettings, windowID: CGWindowID) async throws {
    debugLog("startWindowRecording called with windowID: \(windowID)")
    try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
      getProxy { proxy, error in
        if let error {
          debugLog("getProxy error: \(error)")
          continuation.resume(throwing: error)
          return
        }
        debugLog("calling proxy startWindowRecording with windowID: \(windowID)")
        proxy?.startWindowRecording(settings: settings, windowID: windowID) { _, errorMessage in
          debugLog("got window recording reply: errorMessage=\(errorMessage ?? "nil")")
          if let errorMessage {
            continuation.resume(throwing: CaptureServiceError.remoteError(errorMessage))
          } else {
            continuation.resume()
          }
        }
      }
    }
  }

  func startRegionRecording(settings: CaptureServiceSettings) async throws {
    try await startRegionRecording(settings: settings, region: nil)
  }

  func startRegionRecording(settings: CaptureServiceSettings, region: CGRect?) async throws {
    try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
      getProxy { proxy, error in
        if let error {
          continuation.resume(throwing: error)
          return
        }

        let x = region?.origin.x ?? 0
        let y = region?.origin.y ?? 0
        let width = region?.width ?? 0
        let height = region?.height ?? 0

        proxy?.startRegionRecording(
          settings: settings,
          regionX: x,
          regionY: y,
          regionWidth: width,
          regionHeight: height
        ) { _, errorMessage in
          if let errorMessage {
            continuation.resume(throwing: CaptureServiceError.remoteError(errorMessage))
          } else {
            continuation.resume()
          }
        }
      }
    }
  }

  func stopRecording() async throws -> URL? {
    try await withCheckedThrowingContinuation { continuation in
      getProxy { proxy, error in
        if let error {
          continuation.resume(throwing: error)
          return
        }
        proxy?.stopRecording { path, errorMessage in
          if let errorMessage, errorMessage.lowercased() != "not recording" {
            continuation.resume(throwing: CaptureServiceError.remoteError(errorMessage))
          } else if let path {
            continuation.resume(returning: URL(fileURLWithPath: path))
          } else {
            continuation.resume(returning: nil)
          }
        }
      }
    }
  }

  func captureRegionScreenshot() async throws -> URL {
    try await withCheckedThrowingContinuation { continuation in
      getProxy { proxy, error in
        if let error {
          continuation.resume(throwing: error)
          return
        }
        proxy?.captureRegionScreenshot { path, errorMessage in
          if let errorMessage {
            continuation.resume(throwing: CaptureServiceError.remoteError(errorMessage))
          } else if let path {
            continuation.resume(returning: URL(fileURLWithPath: path))
          } else {
            continuation.resume(throwing: CaptureServiceError.invalidResponse)
          }
        }
      }
    }
  }

  func captureWindowScreenshot() async throws -> URL {
    try await withCheckedThrowingContinuation { continuation in
      getProxy { proxy, error in
        if let error {
          continuation.resume(throwing: error)
          return
        }
        proxy?.captureWindowScreenshot { path, errorMessage in
          if let errorMessage {
            continuation.resume(throwing: CaptureServiceError.remoteError(errorMessage))
          } else if let path {
            continuation.resume(returning: URL(fileURLWithPath: path))
          } else {
            continuation.resume(throwing: CaptureServiceError.invalidResponse)
          }
        }
      }
    }
  }

  func status() async throws -> (isRecording: Bool, lastCaptureURL: URL?, lastRecordingError: String?) {
    try await withCheckedThrowingContinuation { continuation in
      getProxy { proxy, error in
        if let error {
          continuation.resume(throwing: error)
          return
        }
        proxy?.status { status in
          let url = status.lastCapturePath.map { URL(fileURLWithPath: $0) }
          continuation.resume(returning: (status.isRecording, url, status.lastRecordingError))
        }
      }
    }
  }

  /// Send a click event to be baked into the recording.
  /// Called from main app's event tap which has proper permissions.
  func sendClickEvent(x: Double, y: Double, time: Double) {
    getProxy { proxy, _ in
      proxy?.recordClickEvent(x: x, y: y, time: time) {}
    }
  }

  /// Send a keystroke event to be baked into the recording.
  /// Called from main app's event tap which has proper permissions.
  func sendKeyEvent(text: String, time: Double) {
    getProxy { proxy, _ in
      proxy?.recordKeyEvent(text: text, time: time) {}
    }
  }

  // MARK: - Connection Management

  private func getProxy(completion: @escaping (CaptureServiceProtocol?, Error?) -> Void) {
    connectionLock.lock()
    defer { connectionLock.unlock() }

    if let connection, let proxy = connection.remoteObjectProxy as? CaptureServiceProtocol {
      debugLog("Reusing existing connection")
      completion(proxy, nil)
      return
    }

    debugLog("Creating new XPC connection to: \(CaptureServiceConstants.serviceName)")

    // Create new connection
    let newConnection = NSXPCConnection(serviceName: CaptureServiceConstants.serviceName)
    newConnection.remoteObjectInterface = NSXPCInterface(with: CaptureServiceProtocol.self)

    // Register allowed classes for custom types
    let settingsClasses = NSSet(array: [CaptureServiceSettings.self, NSString.self]) as! Set<AnyHashable>
    let statusClasses = NSSet(array: [CaptureServiceStatus.self, NSString.self]) as! Set<AnyHashable>

    newConnection.remoteObjectInterface?.setClasses(
      settingsClasses,
      for: #selector(CaptureServiceProtocol.startFullScreenRecording(settings:reply:)),
      argumentIndex: 0,
      ofReply: false
    )
    newConnection.remoteObjectInterface?.setClasses(
      settingsClasses,
      for: #selector(CaptureServiceProtocol.startWindowRecording(settings:windowID:reply:)),
      argumentIndex: 0,
      ofReply: false
    )
    newConnection.remoteObjectInterface?.setClasses(
      settingsClasses,
      for: #selector(CaptureServiceProtocol.startRegionRecording(settings:regionX:regionY:regionWidth:regionHeight:reply:)),
      argumentIndex: 0,
      ofReply: false
    )
    newConnection.remoteObjectInterface?.setClasses(
      statusClasses,
      for: #selector(CaptureServiceProtocol.status(reply:)),
      argumentIndex: 0,
      ofReply: true
    )

    newConnection.invalidationHandler = { [weak self] in
      debugLog("XPC connection invalidated")
      self?.connectionLock.lock()
      self?.connection = nil
      self?.connectionLock.unlock()
    }

    newConnection.interruptionHandler = { [weak self] in
      debugLog("XPC connection interrupted")
      // Connection was interrupted, will reconnect on next call
      self?.connectionLock.lock()
      self?.connection = nil
      self?.connectionLock.unlock()
    }

    newConnection.resume()
    self.connection = newConnection

    // Get proxy with error handler
    let proxy = newConnection.remoteObjectProxyWithErrorHandler { error in
      debugLog("XPC error: \(error.localizedDescription)")
      completion(nil, CaptureServiceError.connectionFailed(error.localizedDescription))
    } as? CaptureServiceProtocol

    if let proxy {
      debugLog("Got proxy successfully")
      completion(proxy, nil)
    } else {
      debugLog("Failed to create proxy")
      completion(nil, CaptureServiceError.connectionFailed("Failed to create proxy"))
    }
  }

  /// Invalidate the connection (useful for cleanup or forcing reconnect)
  func invalidate() {
    connectionLock.lock()
    connection?.invalidate()
    connection = nil
    connectionLock.unlock()
  }
}

// MARK: - Errors

enum CaptureServiceError: Error {
  case connectionFailed(String)
  case invalidResponse
  case remoteError(String)
}

extension CaptureServiceError: LocalizedError {
  var errorDescription: String? {
    switch self {
    case .connectionFailed(let message):
      return "Failed to connect to Capture Service: \(message)"
    case .invalidResponse:
      return "Capture Service returned an invalid response."
    case .remoteError(let message):
      return message
    }
  }
}

// MARK: - Settings Conversion Helper

extension CaptureServiceSettings {
  /// Create settings from the overlay preferences and color
  static func from(
    showClickOverlay: Bool,
    showKeystrokeHUD: Bool,
    showCursor: Bool,
    hudPlacement: HUDPlacement,
    clickColor: NSColor
  ) -> CaptureServiceSettings {
    let color = clickColor.usingColorSpace(.deviceRGB) ?? .white
    return CaptureServiceSettings(
      showClickOverlay: showClickOverlay,
      showKeystrokeHUD: showKeystrokeHUD,
      showCursor: showCursor,
      hudPlacementRaw: hudPlacement.rawValue,
      ringColorR: Double(color.redComponent),
      ringColorG: Double(color.greenComponent),
      ringColorB: Double(color.blueComponent),
      ringColorA: Double(color.alphaComponent)
    )
  }
}
