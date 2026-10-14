import AppKit
import SwiftUI
import Testing
@testable import SnipSnap

@MainActor
@Suite("Marquee selection geometry")
struct AnnotationSelectionGeometryTests {
  @Test("Intersections include stroke extent and exclude annotations outside the marquee")
  func intersection() {
    let verticalLine = Annotation.line(LineAnnotation(
      start: CGPoint(x: 40, y: 10), end: CGPoint(x: 40, y: 90),
      stroke: .init(color: .white, lineWidth: 8)
    ))
    let rectangle = Annotation.rect(RectAnnotation(
      rect: CGRect(x: 100, y: 100, width: 25, height: 20),
      stroke: .init(), fill: .init()
    ))
    let outside = Annotation.emoji(EmojiAnnotation(
      position: CGPoint(x: 220, y: 150), emoji: "x", size: 32
    ))
    let ids = AnnotationSelectionGeometry.intersecting(
      CGRect(x: 34, y: 45, width: 12, height: 8),
      annotations: [verticalLine, rectangle, outside]
    )
    #expect(ids == [verticalLine.id])
  }

  @Test("Curved arrow bounds include its bend and highlighter bounds include stroke width")
  func pathBounds() {
    let arrow = Annotation.arrow(ArrowAnnotation(
      start: CGPoint(x: 10, y: 100), end: CGPoint(x: 190, y: 100),
      stroke: .init(color: .white, lineWidth: 4), headStyle: .filled,
      bendPoint: CGPoint(x: 100, y: 15)
    ))
    let highlighter = Annotation.freehand(FreehandAnnotation(
      points: [CGPoint(x: 220, y: 40), CGPoint(x: 260, y: 40)],
      stroke: .init(color: .yellow, lineWidth: 24), isHighlighter: true
    ))

    let arrowBounds = AnnotationSelectionGeometry.bounds(of: arrow)
    let markerBounds = AnnotationSelectionGeometry.bounds(of: highlighter)
    #expect(arrowBounds.minY < 20)
    #expect(arrowBounds.maxY > 100)
    #expect(markerBounds.minY == 28)
    #expect(markerBounds.maxY == 52)
    #expect(AnnotationSelectionGeometry.intersecting(
      CGRect(x: 96, y: 10, width: 8, height: 10), annotations: [arrow, highlighter]
    ) == [arrow.id])
    #expect(AnnotationSelectionGeometry.intersecting(
      CGRect(x: 220, y: 27, width: 2, height: 2), annotations: [arrow, highlighter]
    ) == [highlighter.id])
  }

  @Test("Zero-width vertical geometry and label-only measurements remain selectable")
  func degenerateBounds() {
    let line = Annotation.line(LineAnnotation(
      start: CGPoint(x: 50, y: 10), end: CGPoint(x: 50, y: 90),
      stroke: .init(color: .white, lineWidth: 2)
    ))
    let measurementValue = MeasurementAnnotation(
      start: CGPoint(x: 100, y: 50), end: CGPoint(x: 100, y: 51),
      unit: .pixels, stroke: .init()
    )
    let measurement = Annotation.measurement(measurementValue)
    let lineBounds = AnnotationSelectionGeometry.bounds(of: line)
    #expect(lineBounds.width == 2)
    #expect(lineBounds.height == 82)

    let measurementBounds = AnnotationSelectionGeometry.bounds(of: measurement)
    let labelWidth = CGFloat(measurementValue.formattedMeasurement.count) * 14 * 0.6 + 16
    let (labelPosition, _) = measurementValue.labelPosition(estimatedLabelWidth: labelWidth)
    let labelRect = CGRect(
      x: labelPosition.x - labelWidth / 2, y: labelPosition.y - 15,
      width: labelWidth, height: 30
    )
    #expect(AnnotationSelectionGeometry.intersecting(labelRect, annotations: [measurement]) == [measurement.id])
    #expect(!measurementBounds.isNull)
  }

  @Test("Empty and edge-touching marquee selection behaves deterministically")
  func emptyAndTouching() {
    let item = Annotation.emoji(EmojiAnnotation(
      position: CGPoint(x: 30, y: 30), emoji: "✨", size: 20
    ))
    #expect(AnnotationSelectionGeometry.intersecting(.zero, annotations: [item]).isEmpty)
    #expect(AnnotationSelectionGeometry.intersecting(
      CGRect(x: 39.5, y: 20, width: 5, height: 20), annotations: [item]
    ) == [item.id])
  }

  @Test("Loupe bounds and hit geometry follow the circular lens")
  func loupeGeometry() {
    let loupe = LoupeAnnotation(
      center: CGPoint(x: 80, y: 60), radius: 24, magnification: 3
    )
    let annotation = Annotation.loupe(loupe)

    #expect(AnnotationSelectionGeometry.bounds(of: annotation) == CGRect(
      x: 56, y: 36, width: 48, height: 48
    ))
    #expect(LoupeGeometry.contains(CGPoint(x: 104, y: 60), loupe: loupe))
    #expect(!LoupeGeometry.contains(CGPoint(x: 104, y: 61), loupe: loupe))
    #expect(AnnotationSelectionGeometry.intersecting(
      CGRect(x: 101, y: 55, width: 8, height: 8), annotations: [annotation]
    ) == [loupe.id])

    let transform = LoupeGeometry.magnificationTransform(
      center: loupe.center, magnification: loupe.magnification
    )
    #expect(transform.a * loupe.center.x + transform.tx == loupe.center.x)
    #expect(transform.a * 90 + transform.tx == 110)
    #expect(transform.d * 60 + transform.ty == loupe.center.y)
  }

  @Test("Callout tail contributes to selection bounds and hit testing")
  func calloutTailGeometry() {
    let callout = CalloutAnnotation(
      rect: CGRect(x: 20, y: 30, width: 100, height: 60), text: "Note",
      stroke: .init(color: .white, lineWidth: 2), fill: .init(color: .black, enabled: true),
      textColor: .white, fontSize: 16, tailTip: CGPoint(x: 65, y: 125)
    )
    let geometry = CalloutGeometry(callout)

    #expect(geometry.bounds.minY == 30)
    #expect(geometry.bounds.maxY == 125)
    #expect(geometry.contains(CGPoint(x: 65, y: 125)))
    #expect(!geometry.contains(CGPoint(x: 10, y: 120)))
    #expect(AnnotationSelectionGeometry.intersecting(
      CGRect(x: 60, y: 118, width: 10, height: 10),
      annotations: [.callout(callout)]
    ) == [callout.id])
  }
}
