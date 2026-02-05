import Foundation

protocol Recording {
  var isRecording: Bool { get }
  var lastRecordingURL: URL? { get }

  func start() async throws
  func stop() async throws
}
