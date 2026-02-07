import Combine
import Foundation

@MainActor
final class ProPreferencesStore: ObservableObject {
  @Published var enableOCRIndexing: Bool {
    didSet { UserDefaults.standard.set(enableOCRIndexing, forKey: Keys.enableOCRIndexing) }
  }

  @Published var enableCloudSync: Bool {
    didSet { UserDefaults.standard.set(enableCloudSync, forKey: Keys.enableCloudSync) }
  }

  @Published var enableSmartRedaction: Bool {
    didSet { UserDefaults.standard.set(enableSmartRedaction, forKey: Keys.enableSmartRedaction) }
  }

  private enum Keys {
    static let enableOCRIndexing = "prefs.pro.enableOCRIndexing"
    static let enableCloudSync = "prefs.pro.enableCloudSync"
    static let enableSmartRedaction = "prefs.pro.enableSmartRedaction"
  }

  init() {
    enableOCRIndexing = UserDefaults.standard.object(forKey: Keys.enableOCRIndexing) as? Bool ?? true
    enableCloudSync = UserDefaults.standard.object(forKey: Keys.enableCloudSync) as? Bool ?? false
    enableSmartRedaction = UserDefaults.standard.object(forKey: Keys.enableSmartRedaction) as? Bool ?? true
  }
}
