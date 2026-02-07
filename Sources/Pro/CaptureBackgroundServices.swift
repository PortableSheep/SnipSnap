import Foundation

final class CaptureBackgroundServices {
  private let proPrefs: ProPreferencesStore
  private let metadataStore: CaptureMetadataStore

  private let cloud = CloudSyncManager()

  init(proPrefs: ProPreferencesStore, metadataStore: CaptureMetadataStore) {
    self.proPrefs = proPrefs
    self.metadataStore = metadataStore
  }

  @MainActor
  func handleLibraryItems(_ items: [CaptureItem]) {
    if proPrefs.enableOCRIndexing {
      for item in items where item.kind == .image {
        scheduleOCRIfNeeded(for: item.url, createdAt: item.createdAt)
      }
    }

    if proPrefs.enableCloudSync {
      for item in items {
        mirrorToICloudBestEffort(item.url)
      }
    }
  }

  @MainActor
  private func scheduleOCRIfNeeded(for url: URL, createdAt: Date) {
    guard !metadataStore.isIndexed(for: url) else { return }

    let shouldDetectRedactions = proPrefs.enableSmartRedaction

    let metadataStore = metadataStore

    Task.detached(priority: .utility) {
      do {
        let ocr = CaptureOCRIndexer()
        let result = try await ocr.indexImage(at: url)
        let redactions = shouldDetectRedactions ? RedactionDetector.detect(in: result.blocks) : nil

        var meta = metadataStore.load(for: url) ?? CaptureMetadata(createdAt: createdAt)
        meta.ocrText = result.fullText
        meta.ocrBlocks = result.blocks
        meta.redactionCandidates = redactions
        try metadataStore.save(meta, for: url)
      } catch {
        // Best-effort; OCR failures shouldn't surface to the user.
      }
    }
  }

  private func mirrorToICloudBestEffort(_ url: URL) {
    let metadataStore = metadataStore
    Task.detached(priority: .utility) {
      do {
        let cloud = CloudSyncManager()
        _ = try cloud.mirrorToICloudDrive(captureURL: url, metadataStore: metadataStore)
      } catch {
        // Best-effort; no alerts from background sync.
      }
    }
  }
}
