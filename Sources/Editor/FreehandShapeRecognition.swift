import CoreGraphics
import Foundation

enum FreehandShapeRecognition {
  static func recognize(_ annotation: FreehandAnnotation) -> RecognizedFreehandShape? {
    guard !annotation.isHighlighter else { return nil }
    var points: [CGPoint] = []
    for point in annotation.points where points.last != point {
      points.append(point)
    }
    guard points.count >= 3 else { return nil }

    let first = points[0]
    let last = points[points.count - 1]
    let rect = bounds(of: points)
    let diagonal = hypot(rect.width, rect.height)
    guard diagonal >= 12 else { return nil }

    if points.count >= 3 {
      let length = hypot(last.x - first.x, last.y - first.y)
      if length >= 12 {
        let lineDX = last.x - first.x
        let lineDY = last.y - first.y
        var maxDeviation: CGFloat = 0
        for point in points {
          let crossProduct = lineDX * (first.y - point.y) -
            (first.x - point.x) * lineDY
          maxDeviation = max(maxDeviation, abs(crossProduct) / length)
        }
        let pathLength = zip(points, points.dropFirst()).reduce(CGFloat.zero) {
          $0 + hypot($1.1.x - $1.0.x, $1.1.y - $1.0.y)
        }
        if maxDeviation <= max(2.5, length * 0.035), pathLength / length <= 1.12 {
          return .line
        }
      }
    }

    let closureDistance = hypot(first.x - last.x, first.y - last.y)
    guard points.count >= 8, closureDistance <= max(8, diagonal * 0.14),
          rect.width >= 8, rect.height >= 8 else { return nil }

    let ellipseError = ellipseRadialError(points, rect: rect)
    let rectangleError = rectangleEdgeError(points, rect: rect)
    if ellipseError <= 0.12, ellipseError + 0.015 < rectangleError {
      return .ellipse
    }
    if rectangleError <= 0.075 {
      return .rectangle
    }
    if ellipseError <= 0.12 {
      return .ellipse
    }
    return nil
  }

  private static func bounds(of points: [CGPoint]) -> CGRect {
    let xs = points.map(\.x)
    let ys = points.map(\.y)
    guard let minX = xs.min(), let maxX = xs.max(),
          let minY = ys.min(), let maxY = ys.max() else { return .zero }
    return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
  }

  private static func ellipseRadialError(_ points: [CGPoint], rect: CGRect) -> CGFloat {
    let rx = rect.width / 2
    let ry = rect.height / 2
    let errors = points.map { point in
      abs(hypot((point.x - rect.midX) / rx, (point.y - rect.midY) / ry) - 1)
    }
    return errors.reduce(0, +) / CGFloat(errors.count)
  }

  private static func rectangleEdgeError(_ points: [CGPoint], rect: CGRect) -> CGFloat {
    let sides = points.map { point -> Int in
      let distances = [
        abs(point.y - rect.minY), abs(point.x - rect.maxX),
        abs(point.y - rect.maxY), abs(point.x - rect.minX)
      ]
      return distances.enumerated().min(by: { $0.element < $1.element })?.offset ?? 0
    }
    guard Set(sides).count == 4 else { return .infinity }
    let errors = points.map { point in
      [abs(point.y - rect.minY), abs(point.x - rect.maxX),
       abs(point.y - rect.maxY), abs(point.x - rect.minX)].min() ?? .infinity
    }
    let diagonal = hypot(rect.width, rect.height)
    return errors.reduce(0, +) / CGFloat(errors.count) / diagonal
  }
}
