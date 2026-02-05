import Foundation

enum HUDPlacement: String, CaseIterable, Codable, Identifiable {
  case bottomCenter
  case topCenter
  case bottomLeft
  case bottomRight
  case topLeft
  case topRight

  var id: String { rawValue }

  var label: String {
    switch self {
    case .bottomCenter: return "Bottom Center"
    case .topCenter: return "Top Center"
    case .bottomLeft: return "Bottom Left"
    case .bottomRight: return "Bottom Right"
    case .topLeft: return "Top Left"
    case .topRight: return "Top Right"
    }
  }
}
