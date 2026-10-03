import Foundation

enum StripLayout {
  static let thickness: CGFloat = 112
  static let maxLength: CGFloat = 560
  static let margin: CGFloat = 18

  static func dockedFrame(position: StripDockPosition, visible: CGRect,
                          verticalFraction: CGFloat = 0.5, horizontalFraction: CGFloat = 0.5) -> CGRect {
    let horizontalLength = max(260, min(maxLength, visible.width - margin * 2))
    let verticalLength = max(260, min(maxLength, visible.height - margin * 2))
    let x = dockedOrigin(fraction: horizontalFraction, origin: visible.minX, length: visible.width,
                         windowLength: horizontalLength)
    let y = dockedOrigin(fraction: verticalFraction, origin: visible.minY, length: visible.height,
                         windowLength: verticalLength)

    switch position {
    case .left:
      return CGRect(x: visible.minX + margin, y: y,
                    width: thickness, height: verticalLength)
    case .right:
      return CGRect(x: visible.maxX - thickness - margin, y: y,
                    width: thickness, height: verticalLength)
    case .top:
      return CGRect(x: x, y: visible.maxY - thickness - margin,
                    width: horizontalLength, height: thickness)
    case .bottom:
      return CGRect(x: x, y: visible.minY + margin,
                    width: horizontalLength, height: thickness)
    }
  }

  static func tabFrame(position: StripDockPosition, screen: CGRect, visible: CGRect,
                       verticalFraction: CGFloat = 0.5, horizontalFraction: CGFloat = 0.5) -> CGRect {
    let x = dockedOrigin(fraction: horizontalFraction, origin: visible.minX, length: visible.width,
                         windowLength: 44)
    let y = dockedOrigin(fraction: verticalFraction, origin: visible.minY, length: visible.height,
                         windowLength: 44)
    switch position {
    case .left:
      return CGRect(x: screen.minX, y: y, width: 14, height: 44)
    case .right:
      return CGRect(x: screen.maxX - 14, y: y, width: 14, height: 44)
    case .top:
      return CGRect(x: x, y: visible.maxY - 14, width: 44, height: 14)
    case .bottom:
      return CGRect(x: x, y: visible.minY, width: 44, height: 14)
    }
  }

  private static func dockedOrigin(fraction: CGFloat, origin: CGFloat, length: CGFloat,
                                   windowLength: CGFloat) -> CGFloat {
    let centered = origin + length * fraction - windowLength / 2
    return min(max(centered, origin), max(origin, origin + length - windowLength))
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
