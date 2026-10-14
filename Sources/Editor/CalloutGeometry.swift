import CoreGraphics
import Foundation

struct CalloutGeometry {
  private enum Side: Equatable {
    case top, right, bottom, left
  }

  private let rect: CGRect
  private let tailTip: CGPoint?
  private let side: Side?
  private let baseStart: CGPoint?
  private let baseEnd: CGPoint?

  init(_ callout: CalloutAnnotation) {
    rect = callout.rect.standardized
    tailTip = callout.tailTip

    guard let tip = callout.tailTip, rect.width > 0, rect.height > 0 else {
      side = nil
      baseStart = nil
      baseEnd = nil
      return
    }

    let inset = min(14, min(rect.width, rect.height) / 2)
    let sides: [(CGFloat, Side, CGPoint)] = [
      (abs(tip.y - rect.minY), .top,
       CGPoint(x: min(max(tip.x, rect.minX + inset), rect.maxX - inset), y: rect.minY)),
      (abs(tip.x - rect.maxX), .right,
       CGPoint(x: rect.maxX, y: min(max(tip.y, rect.minY + inset), rect.maxY - inset))),
      (abs(tip.y - rect.maxY), .bottom,
       CGPoint(x: min(max(tip.x, rect.minX + inset), rect.maxX - inset), y: rect.maxY)),
      (abs(tip.x - rect.minX), .left,
       CGPoint(x: rect.minX, y: min(max(tip.y, rect.minY + inset), rect.maxY - inset)))
    ]
    let (_, chosenSide, anchor) = sides.min { $0.0 < $1.0 }!
    side = chosenSide
    let halfWidth = min(10, min(rect.width, rect.height) / 4)
    let tangent = chosenSide == .top || chosenSide == .bottom
      ? CGPoint(x: 1, y: 0) : CGPoint(x: 0, y: 1)
    baseStart = CGPoint(x: anchor.x - tangent.x * halfWidth, y: anchor.y - tangent.y * halfWidth)
    baseEnd = CGPoint(x: anchor.x + tangent.x * halfWidth, y: anchor.y + tangent.y * halfWidth)
  }

  var outlinePath: CGPath {
    guard let baseStart, let baseEnd, let tailTip, let side else {
      return CGPath(roundedRect: rect, cornerWidth: 14, cornerHeight: 14, transform: nil)
    }
    let radius = min(14, min(rect.width, rect.height) / 2)
    let path = CGMutablePath()
    path.move(to: baseEnd)

    switch side {
    case .top:
      path.addLine(to: CGPoint(x: rect.maxX - radius, y: rect.minY))
      path.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.minY + radius), control: CGPoint(x: rect.maxX, y: rect.minY))
      path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - radius))
      path.addQuadCurve(to: CGPoint(x: rect.maxX - radius, y: rect.maxY), control: CGPoint(x: rect.maxX, y: rect.maxY))
      path.addLine(to: CGPoint(x: rect.minX + radius, y: rect.maxY))
      path.addQuadCurve(to: CGPoint(x: rect.minX, y: rect.maxY - radius), control: CGPoint(x: rect.minX, y: rect.maxY))
      path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + radius))
      path.addQuadCurve(to: CGPoint(x: rect.minX + radius, y: rect.minY), control: CGPoint(x: rect.minX, y: rect.minY))
    case .right:
      path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - radius))
      path.addQuadCurve(to: CGPoint(x: rect.maxX - radius, y: rect.maxY), control: CGPoint(x: rect.maxX, y: rect.maxY))
      path.addLine(to: CGPoint(x: rect.minX + radius, y: rect.maxY))
      path.addQuadCurve(to: CGPoint(x: rect.minX, y: rect.maxY - radius), control: CGPoint(x: rect.minX, y: rect.maxY))
      path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + radius))
      path.addQuadCurve(to: CGPoint(x: rect.minX + radius, y: rect.minY), control: CGPoint(x: rect.minX, y: rect.minY))
      path.addLine(to: CGPoint(x: rect.maxX - radius, y: rect.minY))
      path.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.minY + radius), control: CGPoint(x: rect.maxX, y: rect.minY))
    case .bottom:
      path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - radius))
      path.addQuadCurve(to: CGPoint(x: rect.maxX - radius, y: rect.maxY), control: CGPoint(x: rect.maxX, y: rect.maxY))
      path.addLine(to: CGPoint(x: rect.minX + radius, y: rect.maxY))
      path.addQuadCurve(to: CGPoint(x: rect.minX, y: rect.maxY - radius), control: CGPoint(x: rect.minX, y: rect.maxY))
      path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + radius))
      path.addQuadCurve(to: CGPoint(x: rect.minX + radius, y: rect.minY), control: CGPoint(x: rect.minX, y: rect.minY))
      path.addLine(to: CGPoint(x: rect.maxX - radius, y: rect.minY))
      path.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.minY + radius), control: CGPoint(x: rect.maxX, y: rect.minY))
    case .left:
      path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY - radius))
      path.addQuadCurve(to: CGPoint(x: rect.minX + radius, y: rect.maxY), control: CGPoint(x: rect.minX, y: rect.maxY))
      path.addLine(to: CGPoint(x: rect.maxX - radius, y: rect.maxY))
      path.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.maxY - radius), control: CGPoint(x: rect.maxX, y: rect.maxY))
      path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + radius))
      path.addQuadCurve(to: CGPoint(x: rect.maxX - radius, y: rect.minY), control: CGPoint(x: rect.maxX, y: rect.minY))
      path.addLine(to: CGPoint(x: rect.minX + radius, y: rect.minY))
      path.addQuadCurve(to: CGPoint(x: rect.minX, y: rect.minY + radius), control: CGPoint(x: rect.minX, y: rect.minY))
    }
    path.addLine(to: baseStart)
    path.addLine(to: tailTip)
    path.closeSubpath()
    return path
  }

  var bounds: CGRect {
    guard let baseStart, let baseEnd, let tailTip else { return rect }
    let points = [baseStart, baseEnd, tailTip]
    let minX = points.map(\.x).min()!
    let maxX = points.map(\.x).max()!
    let minY = points.map(\.y).min()!
    let maxY = points.map(\.y).max()!
    return rect.union(CGRect(
      x: minX, y: minY, width: maxX - minX, height: maxY - minY
    ))
  }

  func contains(_ point: CGPoint, tolerance: CGFloat = 0) -> Bool {
    if rect.insetBy(dx: -tolerance, dy: -tolerance).contains(point) { return true }
    return outlinePath.contains(point)
  }
}
