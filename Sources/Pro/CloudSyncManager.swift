import Foundation

final class CloudSyncManager {
  enum CloudSyncError: Error {
    case iCloudDriveUnavailable
  }

  private let fm = FileManager.default

  func iCloudDriveFolderURL() -> URL? {
    // Best-effort, non-sandbox approach: iCloud Drive “CloudDocs” folder.
    // (If/when you add iCloud entitlements, switch to `url(forUbiquityContainerIdentifier:)`.)
    let home = fm.homeDirectoryForCurrentUser
    let cloudDocs = home
      .appendingPathComponent("Library", isDirectory: true)
      .appendingPathComponent("Mobile Documents", isDirectory: true)
      .appendingPathComponent("com~apple~CloudDocs", isDirectory: true)

    guard fm.fileExists(atPath: cloudDocs.path) else { return nil }

    let appFolder = cloudDocs.appendingPathComponent("SnipSnap", isDirectory: true)
    try? fm.createDirectory(at: appFolder, withIntermediateDirectories: true)
    return appFolder
  }

  func mirrorToICloudDrive(captureURL: URL, metadataStore: CaptureMetadataStore) throws -> URL {
    guard let destDir = iCloudDriveFolderURL() else {
      throw CloudSyncError.iCloudDriveUnavailable
    }

    let destCaptureURL = destDir.appendingPathComponent(captureURL.lastPathComponent)
    try replaceFile(at: destCaptureURL, with: captureURL)

    // Mirror sidecar if present.
    let sidecar = metadataStore.sidecarURL(for: captureURL)
    if fm.fileExists(atPath: sidecar.path) {
      let destSidecarURL = destDir.appendingPathComponent(sidecar.lastPathComponent)
      try replaceFile(at: destSidecarURL, with: sidecar)
    }

    return destCaptureURL
  }

  func mirroredCaptureURLIfPresent(for captureURL: URL) -> URL? {
    guard let destDir = iCloudDriveFolderURL() else { return nil }
    let candidate = destDir.appendingPathComponent(captureURL.lastPathComponent)
    guard fm.fileExists(atPath: candidate.path) else { return nil }
    return candidate
  }

  private func replaceFile(at destination: URL, with source: URL) throws {
    if fm.fileExists(atPath: destination.path) {
      try fm.removeItem(at: destination)
    }
    try fm.copyItem(at: source, to: destination)
  }
}
