import Foundation

enum PreferencesPage: String, CaseIterable, Identifiable {
  case general
  case overlays
  case shortcuts
  case about

  var id: String { rawValue }

  var title: String {
    switch self {
    case .general: return "General"
    case .overlays: return "Overlays"
    case .shortcuts: return "Shortcuts"
    case .about: return "About"
    }
  }

  var icon: String {
    switch self {
    case .general: return "gearshape"
    case .overlays: return "cursorarrow.click.2"
    case .shortcuts: return "keyboard"
    case .about: return "info.circle"
    }
  }
}
