import Foundation

// MARK: - XPC Protocol

/// Protocol for the SnipSnap Capture XPC Service.
/// This replaces the CFMessagePort-based IPC with proper XPC communication.
///
/// XPC advantages:
/// - Single bundle = single TCC permission entry
/// - Automatic lifecycle management by launchd
/// - Crash isolation without manual restart logic
/// - Type-safe protocol instead of JSON encoding/decoding
@objc(CaptureServiceProtocol)
public protocol CaptureServiceProtocol {
  /// Start fullscreen recording with the given overlay settings.
  func startFullScreenRecording(
    settings: CaptureServiceSettings,
    reply: @escaping (String?, String?) -> Void  // (capturePath, errorMessage)
  )

  /// Start window recording with a specific window ID.
  /// The window selection UI runs in the main app; only the window ID is passed here.
  func startWindowRecording(
    settings: CaptureServiceSettings,
    windowID: UInt32,
    reply: @escaping (String?, String?) -> Void
  )

  /// Start region recording, optionally with a pre-selected region.
  func startRegionRecording(
    settings: CaptureServiceSettings,
    regionX: Double,
    regionY: Double,
    regionWidth: Double,
    regionHeight: Double,
    reply: @escaping (String?, String?) -> Void
  )

  /// Stop the current recording.
  func stopRecording(reply: @escaping (String?, String?) -> Void)

  /// Capture a region screenshot (interactive selection).
  func captureRegionScreenshot(reply: @escaping (String?, String?) -> Void)

  /// Capture a window screenshot (interactive selection).
  func captureWindowScreenshot(reply: @escaping (String?, String?) -> Void)

  /// Capture a fullscreen screenshot.
  func captureFullScreenScreenshot(reply: @escaping (String?, String?) -> Void)

  /// Request/check screen recording permission.
  func requestScreenRecordingPermission(reply: @escaping (Bool, String?) -> Void)

  /// Get current status.
  func status(reply: @escaping (CaptureServiceStatus) -> Void)

  /// Record a mouse click event (sent from main app which has event tap permissions).
  /// x, y are in screen coordinates, time is CACurrentMediaTime().
  func recordClickEvent(x: Double, y: Double, time: Double, reply: @escaping () -> Void)

  /// Record a keystroke event (sent from main app which has event tap permissions).
  /// text is the key character(s), time is CACurrentMediaTime().
  func recordKeyEvent(text: String, time: Double, reply: @escaping () -> Void)
}

// MARK: - Data Transfer Objects

/// Settings for overlay rendering during capture.
/// Must be NSObject subclass and conform to NSSecureCoding for XPC transport.
@objc(CaptureServiceSettings)
public final class CaptureServiceSettings: NSObject, NSSecureCoding {
  public static var supportsSecureCoding: Bool { true }

  @objc public var showClickOverlay: Bool = true
  @objc public var showKeystrokeHUD: Bool = true
  @objc public var showCursor: Bool = true
  @objc public var hudPlacementRaw: String = "bottomCenter"
  @objc public var ringColorR: Double = 1.0
  @objc public var ringColorG: Double = 1.0
  @objc public var ringColorB: Double = 1.0
  @objc public var ringColorA: Double = 1.0

  public override init() {
    super.init()
  }

  public init(
    showClickOverlay: Bool,
    showKeystrokeHUD: Bool,
    showCursor: Bool,
    hudPlacementRaw: String,
    ringColorR: Double,
    ringColorG: Double,
    ringColorB: Double,
    ringColorA: Double
  ) {
    self.showClickOverlay = showClickOverlay
    self.showKeystrokeHUD = showKeystrokeHUD
    self.showCursor = showCursor
    self.hudPlacementRaw = hudPlacementRaw
    self.ringColorR = ringColorR
    self.ringColorG = ringColorG
    self.ringColorB = ringColorB
    self.ringColorA = ringColorA
    super.init()
  }

  public required init?(coder: NSCoder) {
    showClickOverlay = coder.decodeBool(forKey: "showClickOverlay")
    showKeystrokeHUD = coder.decodeBool(forKey: "showKeystrokeHUD")
    showCursor = coder.decodeBool(forKey: "showCursor")
    hudPlacementRaw = coder.decodeObject(of: NSString.self, forKey: "hudPlacementRaw") as String? ?? "bottomCenter"
    ringColorR = coder.decodeDouble(forKey: "ringColorR")
    ringColorG = coder.decodeDouble(forKey: "ringColorG")
    ringColorB = coder.decodeDouble(forKey: "ringColorB")
    ringColorA = coder.decodeDouble(forKey: "ringColorA")
    super.init()
  }

  public func encode(with coder: NSCoder) {
    coder.encode(showClickOverlay, forKey: "showClickOverlay")
    coder.encode(showKeystrokeHUD, forKey: "showKeystrokeHUD")
    coder.encode(showCursor, forKey: "showCursor")
    coder.encode(hudPlacementRaw as NSString, forKey: "hudPlacementRaw")
    coder.encode(ringColorR, forKey: "ringColorR")
    coder.encode(ringColorG, forKey: "ringColorG")
    coder.encode(ringColorB, forKey: "ringColorB")
    coder.encode(ringColorA, forKey: "ringColorA")
  }
}

/// Status response from the capture service.
@objc(CaptureServiceStatus)
public final class CaptureServiceStatus: NSObject, NSSecureCoding {
  public static var supportsSecureCoding: Bool { true }

  @objc public var isRecording: Bool = false
  @objc public var lastCapturePath: String?
  @objc public var lastRecordingError: String?
  @objc public var screenRecordingPermissionGranted: Bool = false

  public override init() {
    super.init()
  }

  public init(
    isRecording: Bool,
    lastCapturePath: String?,
    lastRecordingError: String?,
    screenRecordingPermissionGranted: Bool
  ) {
    self.isRecording = isRecording
    self.lastCapturePath = lastCapturePath
    self.lastRecordingError = lastRecordingError
    self.screenRecordingPermissionGranted = screenRecordingPermissionGranted
    super.init()
  }

  public required init?(coder: NSCoder) {
    isRecording = coder.decodeBool(forKey: "isRecording")
    lastCapturePath = coder.decodeObject(of: NSString.self, forKey: "lastCapturePath") as String?
    lastRecordingError = coder.decodeObject(of: NSString.self, forKey: "lastRecordingError") as String?
    screenRecordingPermissionGranted = coder.decodeBool(forKey: "screenRecordingPermissionGranted")
    super.init()
  }

  public func encode(with coder: NSCoder) {
    coder.encode(isRecording, forKey: "isRecording")
    coder.encode(lastCapturePath as NSString?, forKey: "lastCapturePath")
    coder.encode(lastRecordingError as NSString?, forKey: "lastRecordingError")
    coder.encode(screenRecordingPermissionGranted, forKey: "screenRecordingPermissionGranted")
  }
}

// MARK: - Service Identifiers

public enum CaptureServiceConstants {
  /// The Mach service name for the XPC service.
  /// This must match the bundle identifier of the XPC service.
  public static let serviceName = "com.snipsnap.CaptureService"
}
