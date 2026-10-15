import CoreGraphics
import Foundation

struct CalloutGeometry {
  private let rect: CGRect
  private let tailTip: CGPoint?

  init(_ callout: CalloutAnnotation) {
    rect = callout.rect.standardized
    tailTip = callout.tailTip
  }

  var outlinePath: CGPath {
    let radius = min(14, min(rect.width, rect.height) / 2)
    guard let tip = tailTip, !rect.contains(tip), rect.width > 0, rect.height > 0 else {
      return CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
    }
    let corners = [
      CGPoint(x: rect.maxX, y: rect.minY), CGPoint(x: rect.maxX, y: rect.maxY),
      CGPoint(x: rect.minX, y: rect.maxY), CGPoint(x: rect.minX, y: rect.minY)
    ]
    let starts = [
      CGPoint(x: rect.minX + radius, y: rect.minY),
      CGPoint(x: rect.maxX, y: rect.minY + radius),
      CGPoint(x: rect.maxX - radius, y: rect.maxY),
      CGPoint(x: rect.minX, y: rect.maxY - radius)
    ]
    let ends = [
      CGPoint(x: rect.maxX - radius, y: rect.minY),
      CGPoint(x: rect.maxX, y: rect.maxY - radius),
      CGPoint(x: rect.minX + radius, y: rect.maxY),
      CGPoint(x: rect.minX, y: rect.minY + radius)
    ]
    let outwardDistances = [
      rect.minY - tip.y, tip.x - rect.maxX, tip.y - rect.maxY, rect.minX - tip.x
    ]
    let side = outwardDistances.indices.max { outwardDistances[$0] < outwardDistances[$1] } ?? 0
    let path = CGMutablePath()
    path.move(to: starts[0])
    for index in 0..<4 {
      if index == side {
        let start = starts[index]
        let end = ends[index]
        let dx = end.x - start.x
        let dy = end.y - start.y
        let length = hypot(dx, dy)
        if length > 0 {
          let halfWidth = min(10, length / 2)
          let projection = ((tip.x - start.x) * dx + (tip.y - start.y) * dy) / length
          let center = min(length - halfWidth, max(halfWidth, projection))
          path.addLine(to: CGPoint(
            x: start.x + dx / length * (center - halfWidth),
            y: start.y + dy / length * (center - halfWidth)
          ))
          path.addLine(to: tip)
          path.addLine(to: CGPoint(
            x: start.x + dx / length * (center + halfWidth),
            y: start.y + dy / length * (center + halfWidth)
          ))
        }
      }
      path.addLine(to: ends[index])
      path.addQuadCurve(to: starts[(index + 1) % 4], control: corners[index])
    }
    path.closeSubpath()
    return path
  }

  var bounds: CGRect {
    outlinePath.boundingBoxOfPath
  }

  func contains(_ point: CGPoint, tolerance: CGFloat = 0) -> Bool {
    if outlinePath.contains(point) { return true }
    guard tolerance > 0 else { return false }
    return outlinePath.copy(
      strokingWithWidth: tolerance * 2, lineCap: .round, lineJoin: .round, miterLimit: 2
    ).contains(point)
  }
}
