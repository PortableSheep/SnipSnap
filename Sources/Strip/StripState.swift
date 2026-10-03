import Foundation

@MainActor
final class StripState: ObservableObject {
  private enum Keys {
    static let dockPosition = "strip.dockPosition"
    static let isVisible = "strip.isVisible"
    static let autoHideEnabled = "strip.autoHideEnabled"
    static let showOnStartup = "strip.showOnStartup"
    static let verticalDockFraction = "strip.verticalDockFraction"
    static let horizontalDockFraction = "strip.horizontalDockFraction"
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

  @Published var autoHideEnabled: Bool {
    didSet {
      UserDefaults.standard.set(autoHideEnabled, forKey: Keys.autoHideEnabled)
    }
  }

  @Published var showOnStartup: Bool {
    didSet {
      UserDefaults.standard.set(showOnStartup, forKey: Keys.showOnStartup)
    }
  }

  var verticalDockFraction: CGFloat {
    didSet {
      UserDefaults.standard.set(verticalDockFraction, forKey: Keys.verticalDockFraction)
    }
  }

  var horizontalDockFraction: CGFloat {
    didSet {
      UserDefaults.standard.set(horizontalDockFraction, forKey: Keys.horizontalDockFraction)
    }
  }

  /// Runtime-only: whether the strip is currently slid off-screen.
  @Published var isAutoHidden: Bool = false

  // Session scoping (not persisted): used for “show recent from this session”.
  @Published private(set) var sessionStartDate: Date = Date()

  // Prevent accidental thumbnail opens immediately after moving/docking the strip.
  @Published private(set) var suppressOpensUntil: Date? = nil

  init() {
    let raw = UserDefaults.standard.string(forKey: Keys.dockPosition)
    dockPosition = StripDockPosition(rawValue: raw ?? "left") ?? .left
    // Default to visible - auto-hide handles getting out of the way
    isVisible = UserDefaults.standard.object(forKey: Keys.isVisible) as? Bool ?? true
    autoHideEnabled = UserDefaults.standard.object(forKey: Keys.autoHideEnabled) as? Bool ?? true
    showOnStartup = UserDefaults.standard.object(forKey: Keys.showOnStartup) as? Bool ?? true
    verticalDockFraction = Self.loadDockFraction(forKey: Keys.verticalDockFraction)
    horizontalDockFraction = Self.loadDockFraction(forKey: Keys.horizontalDockFraction)
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

  private static func loadDockFraction(forKey key: String) -> CGFloat {
    guard UserDefaults.standard.object(forKey: key) != nil else { return 0.5 }
    return CGFloat(UserDefaults.standard.double(forKey: key)).clamped(to: 0...1)
  }
}

private extension CGFloat {
  func clamped(to range: ClosedRange<CGFloat>) -> CGFloat {
    Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
  }
}
