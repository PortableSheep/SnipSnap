import CoreGraphics
import Foundation

enum LoupeGeometry {
  static func magnificationTransform(center: CGPoint, magnification: CGFloat) -> CGAffineTransform {
    CGAffineTransform(
      a: magnification, b: 0, c: 0, d: magnification,
      tx: center.x * (1 - magnification),
      ty: center.y * (1 - magnification)
    )
  }

  static func contains(_ point: CGPoint, loupe: LoupeAnnotation, tolerance: CGFloat = 0) -> Bool {
    hypot(point.x - loupe.center.x, point.y - loupe.center.y) <= loupe.radius + tolerance
  }
}
