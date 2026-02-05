import CoreFoundation
import Foundation

// Minimal copies of the shared IPC schema so we can run this as a standalone script.

enum CaptureAgentCommand: String, Codable {
  case startFullScreenRecording
  case startRegionRecording
  case stopRecording
  case captureRegionScreenshot
  case captureWindowScreenshot
  case requestScreenRecordingPermission
  case status
}

struct CaptureAgentRequest: Codable {
  var command: CaptureAgentCommand
  var overlaySettings: [String: Double]?
}

struct CaptureAgentResponse: Codable {
  var ok: Bool
  var error: String?
  var lastCapturePath: String?
  var isRecording: Bool?

  var agentBundleID: String?
  var agentAppPath: String?
  var screenRecordingPreflight: Bool?

  var teamIdentifier: String?
  var cdHashHex: String?
}

let portName = "com.snipsnap.SnipsnapCaptureAgent.port" as CFString

guard let remote = CFMessagePortCreateRemote(nil, portName) else {
  fputs("AGENT_UNREACHABLE\n", stderr)
  exit(2)
}

func send(_ req: CaptureAgentRequest, timeout: Double = 2.0) throws -> CaptureAgentResponse {
  let data = try JSONEncoder().encode(req) as CFData
  var outData: Unmanaged<CFData>?

  let status = CFMessagePortSendRequest(
    remote,
    0,
    data,
    timeout,
    max(5.0, timeout),
    CFRunLoopMode.defaultMode.rawValue,
    &outData
  )

  guard status == kCFMessagePortSuccess else {
    throw NSError(domain: "CFMessagePortSendRequest", code: Int(status))
  }

  guard let cf = outData?.takeRetainedValue() else {
    throw NSError(domain: "CFMessagePortSendRequest", code: -1, userInfo: [NSLocalizedDescriptionKey: "Missing response data"])
  }

  return try JSONDecoder().decode(CaptureAgentResponse.self, from: (cf as Data))
}

// 1) Status
print("Sending status…")
fflush(stdout)
let statusResp = try send(.init(command: .status, overlaySettings: nil))
print("STATUS:\n\(String(data: try JSONEncoder().encode(statusResp), encoding: .utf8) ?? String(describing: statusResp))")

// Optional: explicitly request Screen Recording permission (useful after tccutil reset).
if ProcessInfo.processInfo.environment["REQUEST_PERMISSION"] == "1" {
  print("Requesting Screen Recording permission…")
  fflush(stdout)
  let permResp = try send(.init(command: .requestScreenRecordingPermission, overlaySettings: nil), timeout: 10.0)
  print("PERMISSION:\n\(String(data: try JSONEncoder().encode(permResp), encoding: .utf8) ?? String(describing: permResp))")

  print("Re-checking status…")
  fflush(stdout)
  let status2 = try send(.init(command: .status, overlaySettings: nil))
  print("STATUS2:\n\(String(data: try JSONEncoder().encode(status2), encoding: .utf8) ?? String(describing: status2))")
}

// 2) Optional start/stop recording (set RUN_RECORDING_TEST=1 to enable)
if ProcessInfo.processInfo.environment["RUN_RECORDING_TEST"] == "1" {
  print("Sending startFullScreenRecording…")
  fflush(stdout)
  let startResp = try send(.init(command: .startFullScreenRecording, overlaySettings: nil), timeout: 5.0)
  print("START:\n\(String(data: try JSONEncoder().encode(startResp), encoding: .utf8) ?? String(describing: startResp))")

  // Briefly record, then stop.
  Thread.sleep(forTimeInterval: 1.0)

  print("Sending stopRecording…")
  fflush(stdout)
  let stopResp = try send(.init(command: .stopRecording, overlaySettings: nil), timeout: 10.0)
  print("STOP:\n\(String(data: try JSONEncoder().encode(stopResp), encoding: .utf8) ?? String(describing: stopResp))")
}
