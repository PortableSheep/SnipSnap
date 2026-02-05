import AppKit
import CoreFoundation
import Foundation

final class CaptureAgentClient: @unchecked Sendable {
  private let agentBundleID = "com.snipsnap.SnipsnapCaptureAgent"
  private let portName = CaptureAgentIPC.portName

  func requestScreenRecordingPermission() async throws -> Bool {
    let resp = try await send(.init(command: .requestScreenRecordingPermission, overlaySettings: nil))
    return resp.ok
  }

  func startFullScreenRecording(settings: CaptureAgentOverlaySettings) async throws {
    _ = try await send(.init(command: .startFullScreenRecording, overlaySettings: settings))
  }

  func startWindowRecording(settings: CaptureAgentOverlaySettings) async throws {
    _ = try await send(.init(command: .startWindowRecording, overlaySettings: settings))
  }

  func startRegionRecording(settings: CaptureAgentOverlaySettings) async throws {
    _ = try await send(.init(command: .startRegionRecording, overlaySettings: settings))
  }

  func startRegionRecording(settings: CaptureAgentOverlaySettings, region: CGRect) async throws {
    let payload = RectPayload(rect: region)
    _ = try await send(.init(command: .startRegionRecording, overlaySettings: settings, regionRect: payload))
  }

  func stopRecording() async throws -> URL? {
    let resp = try await send(.init(command: .stopRecording, overlaySettings: nil))
    if let p = resp.lastCapturePath { return URL(fileURLWithPath: p) }
    return nil
  }

  func captureRegionScreenshot() async throws -> URL {
    let resp = try await send(.init(command: .captureRegionScreenshot, overlaySettings: nil))
    guard let p = resp.lastCapturePath else { throw CaptureAgentClientError.invalidResponse }
    return URL(fileURLWithPath: p)
  }

  func captureWindowScreenshot() async throws -> URL {
    let resp = try await send(.init(command: .captureWindowScreenshot, overlaySettings: nil))
    guard let p = resp.lastCapturePath else { throw CaptureAgentClientError.invalidResponse }
    return URL(fileURLWithPath: p)
  }

  func status() async throws -> (isRecording: Bool, lastCaptureURL: URL?, lastRecordingError: String?) {
    let resp = try await send(.init(command: .status, overlaySettings: nil))
    let rec = resp.isRecording ?? false
    let url = resp.lastCapturePath.map { URL(fileURLWithPath: $0) }
    return (rec, url, resp.lastRecordingError)
  }

  private func send(_ request: CaptureAgentRequest) async throws -> CaptureAgentResponse {
    // Best-effort auto-launch.
    // NOTE: When running from Xcode, LaunchServices often resolves the bundle identifier
    // to an older installed app in /Applications. That can lead to IPC decoding failures
    // ("bad request") if the installed Capture Agent is a different version.
    let preferredAgentURL = preferredAgentBundleURL()

    await MainActor.run {
      // If we're running from DerivedData and there's a mismatched agent already running,
      // terminate it so we can launch the sibling agent from the same build products dir.
      if isLikelyRunningFromXcodeBuildProducts(), let preferredAgentURL {
        let preferred = preferredAgentURL.standardizedFileURL
        let running = NSRunningApplication.runningApplications(withBundleIdentifier: agentBundleID)
        let hasPreferredRunning = running.contains { $0.bundleURL?.standardizedFileURL == preferred }
        if !hasPreferredRunning {
          for app in running {
            _ = app.terminate()
          }
        }
      }

      if !isAgentReachable() {
        let url = resolveAgentBundleURL(preferred: preferredAgentURL)
        if let url {
          let config = NSWorkspace.OpenConfiguration()
          config.activates = false
          NSWorkspace.shared.openApplication(at: url, configuration: config) { _, _ in }
        }
      }
    }

    // Wait briefly for the agent to start and register its message port.
    if !isAgentReachable() {
      for _ in 0..<20 {
        try? await Task.sleep(nanoseconds: 150_000_000)
        if isAgentReachable() { break }
      }
    }

    // If the agent is hung (receive timeout), restart it once and retry.
    return try await withCheckedThrowingContinuation { cont in
      DispatchQueue.global(qos: .userInitiated).async {
        do {
          do {
            let resp = try self.sendSync(request)
            cont.resume(returning: resp)
          } catch let CaptureAgentClientError.sendFailed(status) where status == -3 {
            // Receive timeout: the message port exists but the agent didn't respond.
            // Best-effort: restart the agent and retry once.
            Task { @MainActor in
              self.restartAgentIfRunning()
              let url = self.resolveAgentBundleURL(preferred: preferredAgentURL)
              if let url {
                let config = NSWorkspace.OpenConfiguration()
                config.activates = false
                NSWorkspace.shared.openApplication(at: url, configuration: config) { _, _ in }
              }
            }

            // Give it a moment to relaunch.
            try? Thread.sleep(forTimeInterval: 0.6)
            let resp = try self.sendSync(request)
            cont.resume(returning: resp)
          }
        } catch {
          cont.resume(throwing: error)
        }
      }
    }
  }

  private func isAgentReachable() -> Bool {
    CFMessagePortCreateRemote(nil, portName as CFString) != nil
  }

  private func isLikelyRunningFromXcodeBuildProducts() -> Bool {
    let p = Bundle.main.bundleURL.path
    return p.contains("/DerivedData/") || p.contains("/Build/Products/")
  }

  private func preferredAgentBundleURL() -> URL? {
    // In Xcode, both targets typically build into the same Build Products directory:
    // .../Build/Products/Debug/SnipSnap.app
    // .../Build/Products/Debug/SnipSnapCaptureAgent.app
    let dir = Bundle.main.bundleURL.deletingLastPathComponent()
    let candidate = dir.appendingPathComponent("SnipSnapCaptureAgent.app")
    if FileManager.default.fileExists(atPath: candidate.path) {
      return candidate
    }
    return nil
  }

  private func resolveAgentBundleURL(preferred: URL?) -> URL? {
    if let preferred { return preferred }

    // If we're running a copy from ~/Applications or /Applications, prefer a sibling agent there.
    let sibling = Bundle.main.bundleURL.deletingLastPathComponent().appendingPathComponent("SnipSnapCaptureAgent.app")
    if FileManager.default.fileExists(atPath: sibling.path) {
      return sibling
    }

    // Common dev install locations.
    let homeApps = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications")
    let homeCandidate = homeApps.appendingPathComponent("SnipSnapCaptureAgent.app")
    if FileManager.default.fileExists(atPath: homeCandidate.path) {
      return homeCandidate
    }

    let systemCandidate = URL(fileURLWithPath: "/Applications/SnipSnapCaptureAgent.app")
    if FileManager.default.fileExists(atPath: systemCandidate.path) {
      return systemCandidate
    }

    return NSWorkspace.shared.urlForApplication(withBundleIdentifier: agentBundleID)
  }

  @MainActor
  private func restartAgentIfRunning() {
    let running = NSRunningApplication.runningApplications(withBundleIdentifier: agentBundleID)
    for app in running {
      _ = app.terminate()
    }
  }

  private func sendSync(_ request: CaptureAgentRequest) throws -> CaptureAgentResponse {
    guard let remote = CFMessagePortCreateRemote(nil, portName as CFString) else {
      throw CaptureAgentClientError.agentUnavailable
    }

    let data = try JSONEncoder().encode(request) as CFData

    var outData: Unmanaged<CFData>?
    let status = CFMessagePortSendRequest(
      remote,
      0,
      data,
      2.0,
      60.0,
      CFRunLoopMode.defaultMode.rawValue,
      &outData
    )

    guard status == kCFMessagePortSuccess else {
      throw CaptureAgentClientError.sendFailed(status)
    }

    guard let cf = outData?.takeRetainedValue() else {
      throw CaptureAgentClientError.invalidResponse
    }

    let respData = cf as Data
    guard let resp = try? JSONDecoder().decode(CaptureAgentResponse.self, from: respData) else {
      throw CaptureAgentClientError.invalidResponse
    }

    if resp.ok {
      return resp
    }

    throw CaptureAgentClientError.remoteError(resp.error ?? "unknown error")
  }
}

enum CaptureAgentClientError: Error {
  case agentUnavailable
  case sendFailed(Int32)
  case invalidResponse
  case remoteError(String)
}

extension CaptureAgentClientError: LocalizedError {
  var errorDescription: String? {
    switch self {
    case .agentUnavailable:
      return "SnipSnap Capture Agent isn’t running or couldn’t be found. Make sure ‘SnipSnap Capture Agent.app’ is installed and then relaunch SnipSnap."
    case .sendFailed(let status):
      if status == -3 {
        return "SnipSnap Capture Agent didn’t respond in time (CFMessagePort receive timeout -3). Try quitting ‘SnipSnap Capture Agent’ from Activity Monitor, then relaunch SnipSnap. If you have multiple copies installed, ensure SnipSnap and the Capture Agent are from the same build."
      }
      return "Couldn’t communicate with SnipSnap Capture Agent (CFMessagePort error \(status))."
    case .invalidResponse:
      return "SnipSnap Capture Agent returned an invalid response."
    case .remoteError(let message):
      // Special-case the old opaque error string.
      if message.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "bad request" {
        return "SnipSnap Capture Agent rejected the request (‘bad request’). This usually means SnipSnap and SnipSnap Capture Agent are different versions — update/reinstall both apps, then relaunch."
      }
      return message
    }
  }
}
