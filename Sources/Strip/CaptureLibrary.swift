import AVFoundation
import AppKit
import Foundation

@MainActor
final class CaptureLibrary: ObservableObject {
  @Published private(set) var items: [CaptureItem] = []

  let metadataStore = CaptureMetadataStore()

  private let capturesDirURL: URL
  private let watcher = DirectoryWatcher()

  private let thumbCache = NSCache<NSString, NSImage>()

  init(capturesDirURL: URL) {
    self.capturesDirURL = capturesDirURL
    refresh()

    watcher.start(url: capturesDirURL) { [weak self] in
      Task { @MainActor in
        self?.refresh()
      }
    }
  }

  func refresh() {
    let fm = FileManager.default

    let urls = (try? fm.contentsOfDirectory(
      at: capturesDirURL,
      includingPropertiesForKeys: [.contentModificationDateKey, .creationDateKey, .isRegularFileKey],
      options: [.skipsHiddenFiles]
    )) ?? []

    let filtered: [CaptureItem] = urls.compactMap { url in
      let ext = url.pathExtension.lowercased()
      let kind: CaptureItem.Kind

      switch ext {
      case "png", "jpg", "jpeg", "heic":
        kind = .image
      case "mov", "mp4", "m4v":
        kind = .video
      default:
        return nil
      }

      let values = try? url.resourceValues(forKeys: [.creationDateKey, .contentModificationDateKey])
      let date = values?.creationDate ?? values?.contentModificationDate ?? Date()
      return CaptureItem(url: url, kind: kind, createdAt: date)
    }

    items = filtered.sorted(by: { $0.createdAt > $1.createdAt })
  }

  func delete(_ item: CaptureItem) throws {
    let fm = FileManager.default

    // Remove the capture file.
    if fm.fileExists(atPath: item.url.path) {
      try fm.removeItem(at: item.url)
    }

    // Remove metadata sidecar if present.
    let sidecar = metadataStore.sidecarURL(for: item.url)
    if fm.fileExists(atPath: sidecar.path) {
      try? fm.removeItem(at: sidecar)
    }

    // Drop cached thumbnail.
    thumbCache.removeAllObjects()

    // Refresh list.
    refresh()
  }

  /// Deletes all captures older than the provided date.
  /// Returns the number of capture files successfully deleted.
  func deleteCaptures(olderThan cutoff: Date) -> Int {
    let toDelete = items.filter { $0.createdAt < cutoff }
    var deleted = 0
    for item in toDelete {
      do {
        try delete(item)
        deleted += 1
      } catch {
        // Best-effort: continue deleting others.
        continue
      }
    }
    refresh()
    return deleted
  }

  func open(_ item: CaptureItem) {
    // Reconcile if the file was deleted/moved outside of SnipSnap.
    if !FileManager.default.fileExists(atPath: item.url.path) {
      refresh()
      NSSound.beep()
      return
    }

    NSWorkspace.shared.open(item.url)
  }

  func metadata(for item: CaptureItem) -> CaptureMetadata? {
    metadataStore.load(for: item.url)
  }

  func thumbnail(for item: CaptureItem, targetPixelSize: CGFloat) -> NSImage? {
    let key = NSString(string: "\(item.url.path)::\(Int(targetPixelSize))")
    if let cached = thumbCache.object(forKey: key) {
      return cached
    }

    let img: NSImage?
    switch item.kind {
    case .image:
      img = NSImage(contentsOf: item.url)
    case .video:
      img = generateVideoThumbnail(url: item.url, targetPixelSize: targetPixelSize)
    }

    if let img {
      thumbCache.setObject(img, forKey: key)
    }
    return img
  }

  private func generateVideoThumbnail(url: URL, targetPixelSize: CGFloat) -> NSImage? {
    let asset = AVAsset(url: url)
    let generator = AVAssetImageGenerator(asset: asset)
    generator.appliesPreferredTrackTransform = true
    generator.maximumSize = CGSize(width: targetPixelSize, height: targetPixelSize)

    do {
      let cg = try generator.copyCGImage(at: .zero, actualTime: nil)
      return NSImage(cgImage: cg, size: .zero)
    } catch {
      return nil
    }
  }
}
