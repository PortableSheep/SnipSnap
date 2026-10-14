import AppKit
import SwiftUI

struct ArrowGeometry {
  let arrow: ArrowAnnotation
  let control1: CGPoint
  let control2: CGPoint

  init(_ arrow: ArrowAnnotation) {
    self.arrow = arrow
    let center = CGPoint(x: (arrow.start.x + arrow.end.x) / 2, y: (arrow.start.y + arrow.end.y) / 2)
    let offset = CGPoint(x: (arrow.midpoint.x - center.x) * 4 / 3, y: (arrow.midpoint.y - center.y) * 4 / 3)
    // Both controls receive the same offset so the curve passes through the handle at t = 0.5.
    control1 = CGPoint(
      x: arrow.start.x + (arrow.end.x - arrow.start.x) / 3 + offset.x,
      y: arrow.start.y + (arrow.end.y - arrow.start.y) / 3 + offset.y
    )
    control2 = CGPoint(
      x: arrow.start.x + (arrow.end.x - arrow.start.x) * 2 / 3 + offset.x,
      y: arrow.start.y + (arrow.end.y - arrow.start.y) * 2 / 3 + offset.y
    )
  }

  func point(at t: CGFloat) -> CGPoint {
    let u = 1 - t
    return CGPoint(
      x: u * u * u * arrow.start.x + 3 * u * u * t * control1.x + 3 * u * t * t * control2.x + t * t * t * arrow.end.x,
      y: u * u * u * arrow.start.y + 3 * u * u * t * control1.y + 3 * u * t * t * control2.y + t * t * t * arrow.end.y
    )
  }

  var path: CGPath { path(through: 1) }

  private func path(through t: CGFloat) -> CGPath {
    let path = CGMutablePath()
    path.move(to: arrow.start)
    if arrow.bendPoint == nil {
      path.addLine(to: point(at: t))
    } else {
      let first = interpolate(arrow.start, control1, t)
      let second = interpolate(control1, control2, t)
      path.addCurve(to: point(at: t), control1: first, control2: interpolate(first, second, t))
    }
    return path
  }

  private func interpolate(_ a: CGPoint, _ b: CGPoint, _ t: CGFloat) -> CGPoint {
    CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t)
  }

  private var samples: [(t: CGFloat, point: CGPoint)] {
    let length = hypot(control1.x - arrow.start.x, control1.y - arrow.start.y) +
      hypot(control2.x - control1.x, control2.y - control1.y) +
      hypot(arrow.end.x - control2.x, arrow.end.y - control2.y)
    let count = max(32, min(1024, Int(ceil(length / 4))))
    return (0...count).map {
      let t = CGFloat($0) / CGFloat(count)
      return (t, point(at: t))
    }
  }

  var endDirection: CGPoint {
    let dx = arrow.end.x - control2.x
    let dy = arrow.end.y - control2.y
    let length = hypot(dx, dy)
    if length > 0.0001 { return CGPoint(x: dx / length, y: dy / length) }
    let fallback = point(at: 0.99)
    let fallbackLength = hypot(arrow.end.x - fallback.x, arrow.end.y - fallback.y)
    guard fallbackLength > 0.0001 else { return CGPoint(x: 1, y: 0) }
    return CGPoint(x: (arrow.end.x - fallback.x) / fallbackLength, y: (arrow.end.y - fallback.y) / fallbackLength)
  }

  var head: (base: CGPoint, left: CGPoint, right: CGPoint) {
    let sample = samples
    let length = zip(sample, sample.dropFirst()).reduce(CGFloat.zero) {
      $0 + hypot($1.1.point.x - $1.0.point.x, $1.1.point.y - $1.0.point.y)
    }
    let headLength = min(max(12, arrow.stroke.lineWidth * 4), length * 0.55)
    let direction = endDirection
    let base = CGPoint(x: arrow.end.x - direction.x * headLength, y: arrow.end.y - direction.y * headLength)
    let width = headLength * 0.6
    return (
      base,
      CGPoint(x: base.x - direction.y * width, y: base.y + direction.x * width),
      CGPoint(x: base.x + direction.y * width, y: base.y - direction.x * width)
    )
  }

  var shaft: CGPath {
    guard arrow.headStyle != .none else { return path }
    let base = head.base
    if arrow.bendPoint == nil {
      let path = CGMutablePath()
      path.move(to: arrow.start)
      path.addLine(to: base)
      return path
    }
    let direction = endDirection
    func projection(_ p: CGPoint) -> CGFloat {
      (p.x - base.x) * direction.x + (p.y - base.y) * direction.y
    }
    let sample = samples
    var parameter: CGFloat = 0
    for index in (0..<(sample.count - 1)).reversed() {
      if projection(sample[index].point) <= 0, projection(sample[index + 1].point) >= 0 {
        var low = sample[index].t
        var high = sample[index + 1].t
        for _ in 0..<20 {
          let mid = (low + high) / 2
          if projection(point(at: mid)) < 0 { low = mid } else { high = mid }
        }
        parameter = (low + high) / 2
        break
      }
    }
    let result = CGMutablePath()
    result.addPath(path(through: parameter))
    result.addLine(to: base)
    return result
  }

  var headPath: CGPath {
    let path = CGMutablePath()
    guard arrow.headStyle != .none else { return path }
    let points = head
    if arrow.headStyle == .filled {
      path.move(to: arrow.end)
      path.addLine(to: points.left)
      path.addLine(to: points.right)
      path.closeSubpath()
    } else {
      path.move(to: points.left)
      path.addLine(to: arrow.end)
      path.addLine(to: points.right)
    }
    return path
  }

  func contains(_ point: CGPoint, tolerance: CGFloat) -> Bool {
    let width = max(tolerance * 2, arrow.stroke.lineWidth)
    if shaft.copy(strokingWithWidth: width, lineCap: .round, lineJoin: .round, miterLimit: 2).contains(point) {
      return true
    }
    if arrow.headStyle == .filled, headPath.contains(point) { return true }
    return arrow.headStyle != .none &&
      headPath.copy(strokingWithWidth: width, lineCap: .round, lineJoin: .round, miterLimit: 2).contains(point)
  }

  func draw(in context: CGContext) {
    context.saveGState()
    defer { context.restoreGState() }
    let color = NSColor(arrow.stroke.color).cgColor
    context.setStrokeColor(color)
    context.setFillColor(color)
    context.setLineWidth(arrow.stroke.lineWidth)
    context.setLineCap(.round)
    context.setLineJoin(.round)
    context.addPath(shaft)
    context.strokePath()
    switch arrow.headStyle {
    case .open:
      context.setLineWidth(max(1, arrow.stroke.lineWidth * 0.85))
      context.addPath(headPath)
      context.strokePath()
    case .filled:
      context.addPath(headPath)
      context.fillPath()
    case .none:
      break
    }
  }
}
