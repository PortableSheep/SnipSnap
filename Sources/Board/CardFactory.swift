import AppKit
import Foundation
import UniformTypeIdentifiers

/// Builds Board cards from captures, pasteboards (clipboard / drag & drop) and notes.
/// Cards returned here are not yet added to the store.
@MainActor
final class CardFactory {
  enum Size {
    static let imageWidth: CGFloat = 240
    static let link = CGSize(width: 260, height: 104)
    static let linkWithPreview = CGSize(width: 260, height: 214)
    static let text = CGSize(width: 240, height: 150)
    static let note = CGSize(width: 200, height: 170)
  }

  private let store: BoardStore
  private let tilt: () -> Bool

  init(store: BoardStore, tilt: @escaping () -> Bool = { true }) {
    self.store = store
    self.tilt = tilt
  }

  private func jitter() -> Double {
    tilt() ? Double.random(in: -2.2...2.2) : 0
  }

  static func imageCardSize(for pixelSize: CGSize) -> CGSize {
    guard pixelSize.width > 0, pixelSize.height > 0 else { return CGSize(width: Size.imageWidth, height: 160) }
    let height = Size.imageWidth * pixelSize.height / pixelSize.width
    return CGSize(width: Size.imageWidth, height: min(360, max(90, height)))
  }

  // MARK: - Captures

  /// Card for an existing SnipSnap capture. Copies the image (annotated version if present)
  /// so the card survives the capture being deleted.
  /// - Parameter renderedImage: PNG data to use instead of the file (e.g. the editor's current render).
  func captureCard(captureURL: URL, metadata: CaptureMetadata?, at origin: CGPoint, source: SourceContext? = nil, renderedImage: Data? = nil) throws -> BoardCard {
    let annotated = captureURL.deletingPathExtension().appendingPathExtension("annotated.png")
    let imageURL = renderedImage != nil ? annotated
      : FileManager.default.fileExists(atPath: annotated.path) ? annotated : captureURL

    var card = BoardCard(kind: .capture, frame: CodableRect(x: origin.x, y: origin.y, width: Size.imageWidth, height: 160))
    let imported = try renderedImage.map { try store.importImage(data: $0, cardID: card.id) }
      ?? store.importImage(at: imageURL, cardID: card.id)
    card.imageAsset = imported.asset
    card.thumbAsset = imported.thumb
    card.frame = CodableRect(CGRect(origin: origin, size: Self.imageCardSize(for: imported.pixelSize)))
    card.rotation = jitter()

    let created = metadata?.createdAt
      ?? (try? captureURL.resourceValues(forKeys: [.creationDateKey]).creationDate)
      ?? Date()
    let src = CardSource(
      appName: metadata?.sourceAppName ?? source?.appName,
      bundleID: metadata?.sourceBundleID ?? source?.bundleID,
      pageURL: metadata?.sourceURL ?? source?.pageURL,
      pageTitle: metadata?.sourcePageTitle ?? source?.pageTitle,
      originalCaptureFilename: captureURL.lastPathComponent,
      capturedAt: created
    )
    card.source = src
    if let pageTitle = src.pageTitle { card.title = pageTitle }

    // Annotated images may contain new text, so only reuse OCR from the original.
    if imageURL == captureURL, let text = metadata?.ocrText, !text.isEmpty {
      card.ocrText = text
      card.detectedItems = Self.detectedItems(ocrText: text, pageURL: src.pageURL)
    }
    return card
  }

  static func detectedItems(ocrText: String?, pageURL: URL?) -> [DetectedItem] {
    var items: [DetectedItem] = []
    if let pageURL, ["http", "https"].contains(pageURL.scheme?.lowercased() ?? "") {
      items.append(DetectedItem(kind: .link, value: pageURL.absoluteString))
    }
    for item in TextDetector.detect(in: ocrText ?? "") where !items.contains(item) {
      items.append(item)
    }
    return items
  }

  // MARK: - Simple cards

  func noteCard(at origin: CGPoint, text: String = "", colorHex: String? = nil) -> BoardCard {
    var card = BoardCard(kind: .note, frame: CodableRect(CGRect(origin: origin, size: Size.note)))
    card.text = text
    card.colorHex = colorHex ?? BoardPalette.noteColors[0]
    card.rotation = jitter()
    return card
  }

  func textCard(_ text: String, at origin: CGPoint, source: SourceContext?) -> BoardCard {
    var card = BoardCard(kind: .text, frame: CodableRect(CGRect(origin: origin, size: Size.text)))
    card.text = text
    card.source = source?.asCardSource()
    card.detectedItems = TextDetector.detect(in: text)
    card.rotation = jitter()
    return card
  }

  func linkCard(_ url: URL, title: String?, at origin: CGPoint, source: SourceContext?) -> BoardCard {
    var card = BoardCard(kind: .link, frame: CodableRect(CGRect(origin: origin, size: Size.link)))
    card.url = url
    card.title = title ?? (url.isFileURL ? url.lastPathComponent : nil)
    card.source = source?.asCardSource()
    card.rotation = jitter()
    return card
  }

  func imageCard(fileURL: URL, at origin: CGPoint, source: SourceContext?) throws -> BoardCard {
    var card = BoardCard(kind: .capture, frame: CodableRect(x: origin.x, y: origin.y, width: Size.imageWidth, height: 160))
    let imported = try store.importImage(at: fileURL, cardID: card.id)
    card.imageAsset = imported.asset
    card.thumbAsset = imported.thumb
    card.frame = CodableRect(CGRect(origin: origin, size: Self.imageCardSize(for: imported.pixelSize)))
    card.source = source?.asCardSource(originalCaptureFilename: fileURL.lastPathComponent)
    card.rotation = jitter()
    return card
  }

  func imageCard(data: Data, at origin: CGPoint, source: SourceContext?) throws -> BoardCard {
    var card = BoardCard(kind: .capture, frame: CodableRect(x: origin.x, y: origin.y, width: Size.imageWidth, height: 160))
    let imported = try store.importImage(data: data, cardID: card.id)
    card.imageAsset = imported.asset
    card.thumbAsset = imported.thumb
    card.frame = CodableRect(CGRect(origin: origin, size: Self.imageCardSize(for: imported.pixelSize)))
    card.source = source?.asCardSource()
    card.rotation = jitter()
    return card
  }

  // MARK: - Pasteboard (clipboard + drag & drop)

  /// Pasteboard types the Board accepts for drops.
  static let acceptedTypes: [NSPasteboard.PasteboardType] = [.fileURL, .URL, .png, .tiff, .string]

  /// Converts pasteboard contents into cards. Priority: image files, image data, URLs, text.
  func cards(from pasteboard: NSPasteboard, at origin: CGPoint, source: SourceContext?) -> [BoardCard] {
    var result: [BoardCard] = []
    var cursor = origin
    func nextOrigin() -> CGPoint {
      defer { cursor = CGPoint(x: cursor.x + 28, y: cursor.y + 28) }
      return cursor
    }

    let fileURLs = (pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL]) ?? []
    if !fileURLs.isEmpty {
      for url in fileURLs.prefix(20) {
        if Self.isImageFile(url), let card = try? imageCard(fileURL: url, at: nextOrigin(), source: source) {
          result.append(card)
        } else {
          result.append(linkCard(url, title: url.lastPathComponent, at: nextOrigin(), source: source))
        }
      }
      return result
    }

    if let data = pasteboard.data(forType: .png) ?? pasteboard.data(forType: .tiff),
       let card = try? imageCard(data: data, at: nextOrigin(), source: source) {
      return [card]
    }

    let urls = ((pasteboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL]) ?? [])
      .filter { ["http", "https"].contains($0.scheme?.lowercased() ?? "") }
    if let url = urls.first {
      let title = pasteboard.string(forType: NSPasteboard.PasteboardType("public.url-name"))
      return [linkCard(url, title: title, at: nextOrigin(), source: source)]
    }

    if let string = pasteboard.string(forType: .string)?.trimmingCharacters(in: .whitespacesAndNewlines), !string.isEmpty {
      if let url = TextDetector.singleWebURL(in: string) {
        return [linkCard(url, title: nil, at: nextOrigin(), source: source)]
      }
      return [textCard(string, at: nextOrigin(), source: source)]
    }

    return result
  }

  static func isImageFile(_ url: URL) -> Bool {
    guard let type = UTType(filenameExtension: url.pathExtension.lowercased()) else { return false }
    return type.conforms(to: .image)
  }
}
