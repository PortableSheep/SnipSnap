import AppKit
import SwiftUI

struct FreehandGeometry {
  let annotation: FreehandAnnotation
  let path: CGPath

  init(_ annotation: FreehandAnnotation) {
    self.annotation = annotation
    var points: [CGPoint] = []
    points.reserveCapacity(annotation.points.count)
    for point in annotation.points where points.last != point {
      points.append(point)
    }

    let path = CGMutablePath()
    if let shape = annotation.recognizedShape, !annotation.isHighlighter {
      let bounds = Self.bounds(of: points)
      switch shape {
      case .line:
        if let first = points.first, let last = points.last {
          path.move(to: first)
          path.addLine(to: last)
        }
      case .rectangle:
        path.addRect(bounds)
      case .ellipse:
        path.addEllipse(in: bounds)
      }
    } else if points.count >= 2 {
      path.move(to: points[0])
      if annotation.isHighlighter || points.count == 2 {
        for point in points.dropFirst() {
          path.addLine(to: point)
        }
      } else {
        // Midpoint quadratics stay within the sampled bounds and join with continuous tangents.
        path.addLine(to: Self.midpoint(points[0], points[1]))
        for index in 1..<(points.count - 1) {
          path.addQuadCurve(
            to: Self.midpoint(points[index], points[index + 1]), control: points[index]
          )
        }
        path.addLine(to: points[points.count - 1])
      }
    }
    self.path = path
  }

  private static func midpoint(_ a: CGPoint, _ b: CGPoint) -> CGPoint {
    CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2)
  }

  private static func bounds(of points: [CGPoint]) -> CGRect {
    guard let first = points.first else { return .zero }
    return points.dropFirst().reduce(CGRect(origin: first, size: .zero)) {
      $0.union(CGRect(origin: $1, size: .zero))
    }
  }

  var bounds: CGRect {
    path.boundingBoxOfPath.insetBy(
      dx: -annotation.stroke.lineWidth / 2, dy: -annotation.stroke.lineWidth / 2
    )
  }

  func contains(_ point: CGPoint, tolerance: CGFloat) -> Bool {
    path.copy(
      strokingWithWidth: max(tolerance * 2, annotation.stroke.lineWidth),
      lineCap: .round, lineJoin: .round, miterLimit: 2
    ).contains(point)
  }

  func draw(in context: CGContext) {
    guard !path.isEmpty else { return }
    context.saveGState()
    defer { context.restoreGState() }
    let color = NSColor(annotation.stroke.color)
    context.setStrokeColor(color.withAlphaComponent(
      color.alphaComponent * (annotation.isHighlighter ? 0.4 : 1)
    ).cgColor)
    context.setLineWidth(annotation.stroke.lineWidth)
    context.setLineCap(.round)
    context.setLineJoin(.round)
    context.addPath(path)
    context.strokePath()
  }
}
