import Foundation

enum AnnotationAlignment {
  struct Result {
    var offset: CGSize = .zero
    var verticalGuide: CGFloat?
    var horizontalGuide: CGFloat?
  }

  static func snap(bounds: CGRect, targets: [CGRect], tolerance: CGFloat) -> Result {
    guard !bounds.isNull, !bounds.isInfinite else { return Result() }
    let xAnchors = [bounds.minX, bounds.midX, bounds.maxX]
    let yAnchors = [bounds.minY, bounds.midY, bounds.maxY]
    var result = Result()
    var bestX = tolerance
    var bestY = tolerance
    for target in targets where !target.isNull && !target.isInfinite {
      for anchor in xAnchors {
        for position in [target.minX, target.midX, target.maxX] {
          let distance = position - anchor
          if abs(distance) <= bestX {
            bestX = abs(distance)
            result.offset.width = distance
            result.verticalGuide = position
          }
        }
      }
      for anchor in yAnchors {
        for position in [target.minY, target.midY, target.maxY] {
          let distance = position - anchor
          if abs(distance) <= bestY {
            bestY = abs(distance)
            result.offset.height = distance
            result.horizontalGuide = position
          }
        }
      }
    }
    return result
  }
}
