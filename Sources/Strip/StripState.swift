import Foundation

@MainActor
final class StripState: ObservableObject {
  private enum Keys {
    static let dockPosition = "strip.dockPosition"
    static let isVisible = "strip.isVisible"
  }

  @Published var dockPosition: StripDockPosition {
    didSet {
      UserDefaults.standard.set(dockPosition.rawValue, forKey: Keys.dockPosition)
    }
  }

  @Published var isVisible: Bool {
    didSet {
      UserDefaults.standard.set(isVisible, forKey: Keys.isVisible)
    }
  }

  // Session scoping (not persisted): used for “show recent from this session”.
  @Published private(set) var sessionStartDate: Date = Date()

  // Prevent accidental thumbnail opens immediately after moving/docking the strip.
  @Published private(set) var suppressOpensUntil: Date? = nil

  init() {
    let raw = UserDefaults.standard.string(forKey: Keys.dockPosition)
    dockPosition = StripDockPosition(rawValue: raw ?? "left") ?? .left
    // Default to hidden - strip auto-shows when captures exist
    isVisible = UserDefaults.standard.object(forKey: Keys.isVisible) as? Bool ?? false
  }

  func startNewSession() {
    sessionStartDate = Date()
  }

  func suppressItemOpens(for seconds: TimeInterval = 0.35) {
    suppressOpensUntil = Date().addingTimeInterval(seconds)
  }

  var canOpenItemsNow: Bool {
    guard let until = suppressOpensUntil else { return true }
    return Date() >= until
  }
}
