import AppKit
import Foundation

enum AnnotationSelectionGeometry {
  static func intersecting(_ rect: CGRect, annotations: [Annotation]) -> Set<UUID> {
    let selectionRect = rect.standardized.insetBy(dx: -0.5, dy: -0.5)
    return Set(annotations.filter { bounds(of: $0).intersects(selectionRect) }.map(\.id))
  }

  static func bounds(of annotation: Annotation) -> CGRect {
    switch annotation {
    case .rect(let value): return value.rect.standardized
    case .ellipse(let value): return value.rect.standardized
    case .line(let value):
      return expandedBounds(
        between: value.start, and: value.end, by: value.stroke.lineWidth / 2
      )
    case .arrow(let value):
      let geometry = ArrowGeometry(value)
      var bounds = geometry.path.boundingBoxOfPath
      if value.headStyle != .none {
        bounds = bounds.union(geometry.headPath.boundingBoxOfPath)
      }
      return bounds
        .insetBy(dx: -value.stroke.lineWidth / 2, dy: -value.stroke.lineWidth / 2)
        .standardized
    case .freehand(let value): return FreehandGeometry(value).bounds.standardized
    case .text(let value): return AnnotationTextLayout.textBounds(value).standardized
    case .callout(let value): return CalloutGeometry(value).bounds.standardized
    case .blur(let value): return value.rect.standardized
    case .spotlight(let value): return value.rect.standardized
    case .step(let value):
      return centered(value.center, radius: value.radius)
    case .counter(let value):
      return centered(value.center, radius: value.radius)
    case .measurement(let value):
      let line = expandedBounds(between: value.start, and: value.end, by: 10)
      let fontSize = max(14, value.stroke.lineWidth * 3.5)
      let labelWidth = CGFloat(value.formattedMeasurement.count) * fontSize * 0.6 + 16
      let (position, _) = value.labelPosition(estimatedLabelWidth: labelWidth)
      return line.union(CGRect(
        x: position.x - labelWidth / 2, y: position.y - 15,
        width: labelWidth, height: 30
      )).standardized
    case .emoji(let value):
      return centered(value.position, radius: value.size / 2)
    case .imageLayer(let value): return value.rect.standardized
    case .loupe(let value): return value.bounds
    }
  }

  private static func centered(_ center: CGPoint, radius: CGFloat) -> CGRect {
    CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
  }

  private static func expandedBounds(between start: CGPoint, and end: CGPoint, by padding: CGFloat) -> CGRect {
    CGRect(
      x: min(start.x, end.x), y: min(start.y, end.y),
      width: abs(end.x - start.x), height: abs(end.y - start.y)
    ).insetBy(dx: -padding, dy: -padding).standardized
  }
}
