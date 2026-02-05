import Foundation

enum CaptureAgentIPC {
  static let portName = "com.snipsnap.SnipsnapCaptureAgent.port"
}

enum CaptureAgentCommand: String, Codable {
  case startFullScreenRecording
  case startWindowRecording
  case startRegionRecording
  case stopRecording
  case captureRegionScreenshot
  case captureWindowScreenshot
  case requestScreenRecordingPermission
  case status
}

struct CaptureAgentRequest: Codable {
  var command: CaptureAgentCommand
  var overlaySettings: CaptureAgentOverlaySettings? = nil
  var regionRect: RectPayload? = nil
}

struct CaptureAgentResponse: Codable {
  var ok: Bool
  var error: String? = nil
  var lastCapturePath: String? = nil
  var isRecording: Bool? = nil

  // If a recording terminates unexpectedly, the agent can report a best-effort reason.
  var lastRecordingError: String? = nil

  // Diagnostics (optional)
  var agentBundleID: String? = nil
  var agentAppPath: String? = nil
  var screenRecordingPreflight: Bool? = nil

  // Code signing diagnostics (optional)
  var teamIdentifier: String? = nil
  var cdHashHex: String? = nil
}

struct RectPayload: Codable {
  var x: Double
  var y: Double
  var width: Double
  var height: Double

  init(rect: CGRect) {
    self.x = rect.origin.x
    self.y = rect.origin.y
    self.width = rect.size.width
    self.height = rect.size.height
  }

  var cgRect: CGRect { CGRect(x: x, y: y, width: width, height: height) }
}
