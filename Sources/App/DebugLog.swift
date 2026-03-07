import Foundation
import os.log

/// Shared debug logging for the SnipSnap app.
///
/// In debug builds, messages are written to both OSLog and `~/snipsnap-debug.log`.
/// In release builds, only OSLog output is emitted.
enum DebugLog {

  private static let log = OSLog(subsystem: "com.snipsnap.Snipsnap", category: "Debug")

  private static let logFileURL: URL = {
    FileManager.default.homeDirectoryForCurrentUser
      .appendingPathComponent("snipsnap-debug.log")
  }()

  /// Write a timestamped debug message.
  static func log(_ message: String) {
    os_log(.debug, log: Self.log, "%{public}@", message)

    #if DEBUG
    writeToFile(message)
    #endif
  }

  // MARK: - File Logging (Debug Only)

  private static func writeToFile(_ message: String) {
    let timestamp = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
    let line = "[\(timestamp)] \(message)\n"
    guard let data = line.data(using: .utf8) else { return }

    if FileManager.default.fileExists(atPath: logFileURL.path) {
      if let handle = try? FileHandle(forWritingTo: logFileURL) {
        handle.seekToEndOfFile()
        handle.write(data)
        handle.closeFile()
      }
    } else {
      try? data.write(to: logFileURL)
    }
  }
}

/// Convenience free function so call sites stay concise.
func debugLog(_ message: String) {
  DebugLog.log(message)
}
