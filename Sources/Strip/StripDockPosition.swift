import Foundation

enum StripDockPosition: String, Codable {
  case left
  case right
  case top
  case bottom

  var isVertical: Bool {
    switch self {
    case .left, .right:
      return true
    case .top, .bottom:
      return false
    }
  }
}
