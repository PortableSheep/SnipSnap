import Combine
import Foundation

enum BoardTheme: String, CaseIterable, Identifiable, Codable {
  case glass
  case cork
  case felt
  case paper

  var id: String { rawValue }

  var label: String {
    switch self {
    case .glass: return "Dark Glass"
    case .cork: return "Cork"
    case .felt: return "Felt"
    case .paper: return "Paper"
    }
  }
}

enum HotCorner: String, CaseIterable, Identifiable {
  case none
  case topLeft
  case topRight
  case bottomLeft
  case bottomRight

  var id: String { rawValue }

  var label: String {
    switch self {
    case .none: return "Off"
    case .topLeft: return "Top Left"
    case .topRight: return "Top Right"
    case .bottomLeft: return "Bottom Left"
    case .bottomRight: return "Bottom Right"
    }
  }

  /// Key suffix used by the Dock's own hot corner defaults (`wvous-<x>-corner`).
  var dockKey: String? {
    switch self {
    case .none: return nil
    case .topLeft: return "tl"
    case .topRight: return "tr"
    case .bottomLeft: return "bl"
    case .bottomRight: return "br"
    }
  }
}

@MainActor
final class BoardPreferencesStore: ObservableObject {
  static let shared = BoardPreferencesStore()

  private enum Keys {
    static let theme = "board.theme"
    static let tiltCards = "board.tiltCards"
    static let clickBackgroundToClose = "board.clickBackgroundToClose"
    static let fetchLinkPreviews = "board.fetchLinkPreviews"
    static let captureBrowserContext = "board.captureBrowserContext"
    static let ocrBoardCards = "board.ocrBoardCards"
    static let pinsHidden = "board.pinsHidden"
    static let hotCorner = "board.hotCorner"
    static let hotCornerDelay = "board.hotCornerDelay"
  }

  private let defaults: UserDefaults

  @Published var theme: BoardTheme { didSet { defaults.set(theme.rawValue, forKey: Keys.theme) } }
  @Published var tiltCards: Bool { didSet { defaults.set(tiltCards, forKey: Keys.tiltCards) } }
  @Published var clickBackgroundToClose: Bool { didSet { defaults.set(clickBackgroundToClose, forKey: Keys.clickBackgroundToClose) } }
  @Published var fetchLinkPreviews: Bool { didSet { defaults.set(fetchLinkPreviews, forKey: Keys.fetchLinkPreviews) } }
  @Published var captureBrowserContext: Bool { didSet { defaults.set(captureBrowserContext, forKey: Keys.captureBrowserContext) } }
  @Published var ocrBoardCards: Bool { didSet { defaults.set(ocrBoardCards, forKey: Keys.ocrBoardCards) } }
  @Published var pinsHidden: Bool { didSet { defaults.set(pinsHidden, forKey: Keys.pinsHidden) } }
  @Published var hotCorner: HotCorner { didSet { defaults.set(hotCorner.rawValue, forKey: Keys.hotCorner) } }
  @Published var hotCornerDelay: Double { didSet { defaults.set(hotCornerDelay, forKey: Keys.hotCornerDelay) } }

  init(defaults: UserDefaults = .standard) {
    self.defaults = defaults
    defaults.register(defaults: [
      Keys.theme: BoardTheme.glass.rawValue,
      Keys.tiltCards: true,
      Keys.clickBackgroundToClose: false,
      Keys.fetchLinkPreviews: true,
      Keys.captureBrowserContext: false,
      Keys.ocrBoardCards: true,
      Keys.pinsHidden: false,
      Keys.hotCorner: HotCorner.none.rawValue,
      Keys.hotCornerDelay: 0.25,
    ])
    theme = BoardTheme(rawValue: defaults.string(forKey: Keys.theme) ?? "") ?? .glass
    tiltCards = defaults.bool(forKey: Keys.tiltCards)
    clickBackgroundToClose = defaults.bool(forKey: Keys.clickBackgroundToClose)
    fetchLinkPreviews = defaults.bool(forKey: Keys.fetchLinkPreviews)
    captureBrowserContext = defaults.bool(forKey: Keys.captureBrowserContext)
    ocrBoardCards = defaults.bool(forKey: Keys.ocrBoardCards)
    pinsHidden = defaults.bool(forKey: Keys.pinsHidden)
    hotCorner = HotCorner(rawValue: defaults.string(forKey: Keys.hotCorner) ?? "") ?? .none
    hotCornerDelay = defaults.double(forKey: Keys.hotCornerDelay)
  }

  /// Returns true if macOS already has a system hot-corner action on this corner.
  func systemHotCornerConflict(for corner: HotCorner) -> Bool {
    guard let key = corner.dockKey,
          let dock = UserDefaults(suiteName: "com.apple.dock") else { return false }
    let action = dock.integer(forKey: "wvous-\(key)-corner")
    // 0 and 1 both mean "no action".
    return action > 1
  }
}
