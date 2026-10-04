import Foundation

final class CaptureMetadataStore: Sendable {
  init() {}

  func sidecarURL(for captureURL: URL) -> URL {
    // Keep sidecar next to the capture for portability / easy sync.
    // e.g. MyShot.png -> MyShot.png.snipsnap.json
    captureURL.appendingPathExtension("snipsnap").appendingPathExtension("json")
  }

  func load(for captureURL: URL) -> CaptureMetadata? {
    let url = sidecarURL(for: captureURL)
    guard let data = try? Data(contentsOf: url) else { return nil }
    let decoder = JSONDecoder()
    return try? decoder.decode(CaptureMetadata.self, from: data)
  }

  func save(_ metadata: CaptureMetadata, for captureURL: URL) throws {
    let url = sidecarURL(for: captureURL)
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    let data = try encoder.encode(metadata)

    // Atomic write to avoid partial files if we crash mid-write.
    try data.write(to: url, options: [.atomic])
  }

  private static let updateLock = NSLock()

  /// Serialized read-modify-write so concurrent writers (OCR, source context) don't drop each other's fields.
  func update(for captureURL: URL, default makeDefault: () -> CaptureMetadata, _ mutate: (inout CaptureMetadata) -> Void) throws {
    Self.updateLock.lock()
    defer { Self.updateLock.unlock() }
    var meta = load(for: captureURL) ?? makeDefault()
    mutate(&meta)
    try save(meta, for: captureURL)
  }

  func isIndexed(for captureURL: URL) -> Bool {
    if let meta = load(for: captureURL), let text = meta.ocrText {
      return !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    return false
  }
}
