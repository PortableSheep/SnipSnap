import Foundation

enum StripLayout {
  static let thickness: CGFloat = 112
  static let maxLength: CGFloat = 560
  static let margin: CGFloat = 18

  static func dockedFrame(position: StripDockPosition, visible: CGRect) -> CGRect {
    let horizontalLength = max(260, min(maxLength, visible.width - margin * 2))
    let verticalLength = max(260, min(maxLength, visible.height - margin * 2))

    switch position {
    case .left:
      return CGRect(x: visible.minX + margin, y: visible.midY - verticalLength / 2,
                    width: thickness, height: verticalLength)
    case .right:
      return CGRect(x: visible.maxX - thickness - margin, y: visible.midY - verticalLength / 2,
                    width: thickness, height: verticalLength)
    case .top:
      return CGRect(x: visible.midX - horizontalLength / 2, y: visible.maxY - thickness - margin,
                    width: horizontalLength, height: thickness)
    case .bottom:
      return CGRect(x: visible.midX - horizontalLength / 2, y: visible.minY + margin,
                    width: horizontalLength, height: thickness)
    }
  }

  static func tabFrame(position: StripDockPosition, screen: CGRect, visible: CGRect) -> CGRect {
    switch position {
    case .left:
      return CGRect(x: screen.minX, y: visible.midY - 22, width: 14, height: 44)
    case .right:
      return CGRect(x: screen.maxX - 14, y: visible.midY - 22, width: 14, height: 44)
    case .top:
      return CGRect(x: visible.midX - 22, y: visible.maxY - 14, width: 44, height: 14)
    case .bottom:
      return CGRect(x: visible.midX - 22, y: visible.minY, width: 44, height: 14)
    }
  }

  static func nearestEdge(frame: CGRect, screen: CGRect, visible: CGRect) -> StripDockPosition? {
    let distances: [(StripDockPosition, CGFloat)] = [
      (.left, abs(frame.minX - (screen.minX + margin))),
      (.right, abs(frame.maxX - (screen.maxX - margin))),
      (.top, abs(frame.maxY - (visible.maxY - margin))),
      (.bottom, abs(frame.minY - (visible.minY + margin)))
    ]
    guard let nearest = distances.min(by: { $0.1 < $1.1 }), nearest.1 <= 44 else { return nil }
    return nearest.0
  }
}
