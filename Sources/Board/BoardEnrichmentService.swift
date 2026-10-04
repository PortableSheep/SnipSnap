import AppKit
import Foundation
import LinkPresentation

/// Fills in derived data for cards after they're added: OCR text + detected links for
/// image cards, detected items for text cards, and title/icon/preview for link cards.
/// Everything is best-effort and never surfaces errors to the user.
@MainActor
final class BoardEnrichmentService {
  private let store: BoardStore
  private let prefs: BoardPreferencesStore
  private var inFlight = Set<UUID>()
  private var providers: [UUID: LPMetadataProvider] = [:]

  init(store: BoardStore, prefs: BoardPreferencesStore) {
    self.store = store
    self.prefs = prefs
  }

  func enrich(_ id: UUID) {
    guard let card = store.card(id), !inFlight.contains(id) else { return }
    switch card.kind {
    case .capture:
      if card.ocrText == nil, prefs.ocrBoardCards, let url = store.imageURL(for: card) {
        runOCR(cardID: id, imageURL: url, pageURL: card.source?.pageURL)
      }
    case .link:
      if prefs.fetchLinkPreviews, let url = card.url, !url.isFileURL, card.faviconAsset == nil {
        fetchLinkMetadata(cardID: id, url: url)
      }
    case .text:
      if card.detectedItems == nil, let text = card.text {
        store.update(id) { $0.detectedItems = TextDetector.detect(in: text) }
      }
    case .note:
      break
    }
  }

  /// Re-runs OCR (e.g. after the image was annotated in the editor).
  func reindex(_ id: UUID) {
    guard let card = store.card(id), card.kind == .capture, prefs.ocrBoardCards,
          let url = store.imageURL(for: card) else { return }
    runOCR(cardID: id, imageURL: url, pageURL: card.source?.pageURL)
  }

  /// Enriches everything that's missing data (called on launch).
  func enrichAll() {
    for card in store.cards { enrich(card.id) }
  }

  private func runOCR(cardID: UUID, imageURL: URL, pageURL: URL?) {
    inFlight.insert(cardID)
    Task { [weak self] in
      let result = await Task.detached(priority: .utility) {
        try? await CaptureOCRIndexer().indexImage(at: imageURL)
      }.value
      guard let self else { return }
      self.inFlight.remove(cardID)
      guard let result else { return }
      let items = CardFactory.detectedItems(ocrText: result.fullText, pageURL: pageURL)
      self.store.update(cardID) { card in
        card.ocrText = result.fullText
        card.detectedItems = items
      }
    }
  }

  private func fetchLinkMetadata(cardID: UUID, url: URL) {
    inFlight.insert(cardID)
    let provider = LPMetadataProvider()
    provider.timeout = 10
    providers[cardID] = provider
    provider.startFetchingMetadata(for: url) { [weak self] metadata, _ in
      Task { @MainActor in
        guard let self else { return }
        self.providers[cardID] = nil
        guard let metadata else {
          self.inFlight.remove(cardID)
          return
        }
        let title = metadata.title
        if let title, !title.isEmpty {
          self.store.update(cardID) { card in
            if card.title == nil || card.title?.isEmpty == true { card.title = title }
          }
        }
        async let icon = Self.loadImage(metadata.iconProvider)
        async let preview = Self.loadImage(metadata.imageProvider)
        let (iconImage, previewImage) = await (icon, preview)
        self.inFlight.remove(cardID)

        let iconName = iconImage.flatMap { self.store.writeImageAsset($0, name: "\(cardID.uuidString)-icon.png") }
        let previewName = previewImage.flatMap { self.store.writeImageAsset($0, name: "\(cardID.uuidString)-preview.png") }
        self.store.update(cardID) { card in
          card.faviconAsset = iconName ?? card.faviconAsset
          if let previewName {
            card.previewAsset = previewName
            // Grow the card to make room for the preview (only if user hasn't resized it).
            if card.frame.height <= CardFactory.Size.link.height {
              card.frame.height = CardFactory.Size.linkWithPreview.height
            }
          }
        }
      }
    }
  }

  private static func loadImage(_ provider: NSItemProvider?) async -> NSImage? {
    guard let provider, provider.canLoadObject(ofClass: NSImage.self) else { return nil }
    return await withCheckedContinuation { cont in
      provider.loadObject(ofClass: NSImage.self) { object, _ in
        cont.resume(returning: object as? NSImage)
      }
    }
  }
}
