import Testing
import SwiftUI
@testable import SnipSnap

private func cleanupOverlayDefaults() {
    let keys = [
        "prefs.overlay.showClick", "prefs.overlay.showKeys", "prefs.overlay.showCursor",
        "prefs.overlay.hudPlacement", "prefs.overlay.clickColor.r", "prefs.overlay.clickColor.g",
        "prefs.overlay.clickColor.b", "prefs.overlay.clickColor.a"
    ]
    for key in keys { UserDefaults.standard.removeObject(forKey: key) }
}

private func cleanupProDefaults() {
    let keys = [
        "prefs.pro.enableOCRIndexing", "prefs.pro.enableCloudSync", "prefs.pro.enableSmartRedaction"
    ]
    for key in keys { UserDefaults.standard.removeObject(forKey: key) }
}

// MARK: - OverlayPreferencesStore Tests

@Suite("OverlayPreferencesStore")
struct OverlayPreferencesStoreTests {

    @Test @MainActor
    func defaultValues() {
        defer { cleanupOverlayDefaults() }
        let store = OverlayPreferencesStore()

        #expect(store.showClickOverlay == true)
        #expect(store.showKeystrokeHUD == true)
        #expect(store.showCursor == true)
        #expect(store.hudPlacement == .bottomCenter)
    }

    @Test @MainActor
    func showClickOverlayPersistsToUserDefaults() {
        defer { cleanupOverlayDefaults() }
        let store = OverlayPreferencesStore()

        store.showClickOverlay = false
        #expect(UserDefaults.standard.bool(forKey: "prefs.overlay.showClick") == false)

        store.showClickOverlay = true
        #expect(UserDefaults.standard.bool(forKey: "prefs.overlay.showClick") == true)
    }

    @Test @MainActor
    func showKeystrokeHUDPersistsToUserDefaults() {
        defer { cleanupOverlayDefaults() }
        let store = OverlayPreferencesStore()

        store.showKeystrokeHUD = false
        #expect(UserDefaults.standard.bool(forKey: "prefs.overlay.showKeys") == false)

        store.showKeystrokeHUD = true
        #expect(UserDefaults.standard.bool(forKey: "prefs.overlay.showKeys") == true)
    }

    @Test @MainActor
    func valuesSurviveStoreRecreation() {
        defer { cleanupOverlayDefaults() }

        let original = OverlayPreferencesStore()
        original.showClickOverlay = false
        original.showKeystrokeHUD = false
        original.showCursor = false
        original.hudPlacement = .topCenter

        let restored = OverlayPreferencesStore()
        #expect(restored.showClickOverlay == false)
        #expect(restored.showKeystrokeHUD == false)
        #expect(restored.showCursor == false)
        #expect(restored.hudPlacement == .topCenter)
    }
}

// MARK: - ProPreferencesStore Tests

@Suite("ProPreferencesStore")
struct ProPreferencesStoreTests {

    @Test @MainActor
    func defaultValues() {
        defer { cleanupProDefaults() }
        let store = ProPreferencesStore()

        #expect(store.enableOCRIndexing == true)
        #expect(store.enableCloudSync == false)
        #expect(store.enableSmartRedaction == true)
    }

    @Test @MainActor
    func enableCloudSyncPersistsToUserDefaults() {
        defer { cleanupProDefaults() }
        let store = ProPreferencesStore()

        store.enableCloudSync = true
        #expect(UserDefaults.standard.bool(forKey: "prefs.pro.enableCloudSync") == true)

        store.enableCloudSync = false
        #expect(UserDefaults.standard.bool(forKey: "prefs.pro.enableCloudSync") == false)
    }

    @Test @MainActor
    func valuesSurviveStoreRecreation() {
        defer { cleanupProDefaults() }

        let original = ProPreferencesStore()
        original.enableOCRIndexing = false
        original.enableCloudSync = true
        original.enableSmartRedaction = false

        let restored = ProPreferencesStore()
        #expect(restored.enableOCRIndexing == false)
        #expect(restored.enableCloudSync == true)
        #expect(restored.enableSmartRedaction == false)
    }
}
