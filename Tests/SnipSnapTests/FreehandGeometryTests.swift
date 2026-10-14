import AppKit
import SwiftUI
import Testing
@testable import SnipSnap

@MainActor
@Suite("Freehand smoothing")
struct FreehandGeometryTests {
  private let samples = [
    CGPoint(x: 20, y: 100), CGPoint(x: 100, y: 20), CGPoint(x: 180, y: 100)
  ]

  private func stroke(
    _ points: [CGPoint], highlighter: Bool = false, width: CGFloat = 4
  ) -> FreehandAnnotation {
    FreehandAnnotation(
      points: points, stroke: .init(color: .white, lineWidth: width),
      isHighlighter: highlighter
    )
  }

  private func elements(_ path: CGPath) -> [(type: CGPathElementType, points: [CGPoint])] {
    var result: [(type: CGPathElementType, points: [CGPoint])] = []
    path.applyWithBlock { pointer in
      let element = pointer.pointee
      let count: Int
      switch element.type {
      case .moveToPoint, .addLineToPoint: count = 1
      case .addQuadCurveToPoint: count = 2
      case .addCurveToPoint: count = 3
      case .closeSubpath: count = 0
      @unknown default: count = 0
      }
      result.append((element.type, Array(UnsafeBufferPointer(start: element.points, count: count))))
    }
    return result
  }

  private func render(scale: CGFloat = 1, _ draw: (CGContext) -> Void) throws -> NSBitmapImageRep {
    let context = try #require(CGContext(
      data: nil, width: 240, height: 180, bitsPerComponent: 8, bytesPerRow: 0,
      space: CGColorSpaceCreateDeviceRGB(),
      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ))
    context.translateBy(x: 0, y: 180)
    context.scaleBy(x: scale, y: -scale)
    draw(context)
    return NSBitmapImageRep(cgImage: try #require(context.makeImage()))
  }

  private func withDocument(_ body: (AnnotationDocument) throws -> Void) throws {
    let url = FileManager.default.temporaryDirectory
      .appendingPathComponent("freehand-\(UUID().uuidString).png")
    let source = try render { _ in }
    try #require(source.representation(using: .png, properties: [:])).write(to: url)
    defer { try? FileManager.default.removeItem(at: url) }
    try body(AnnotationDocument(sourceURL: url))
  }

  @Test("Midpoint smoothing rounds a corner without moving endpoints or raw samples")
  func roundedCorner() {
    let annotation = stroke(samples)
    let geometry = FreehandGeometry(annotation)
    let pathElements = elements(geometry.path)
    #expect(pathElements.map(\.type) == [.moveToPoint, .addLineToPoint, .addQuadCurveToPoint, .addLineToPoint])
    #expect(pathElements[0].points == [samples[0]])
    #expect(pathElements[1].points == [CGPoint(x: 60, y: 60)])
    #expect(pathElements[2].points == [samples[1], CGPoint(x: 140, y: 60)])
    #expect(geometry.path.currentPoint == samples[2])
    #expect(geometry.path.boundingBoxOfPath.minY == 40)
    #expect(geometry.annotation.points == samples)
  }

  @Test("Quadratic segments meet with matching tangents and do not overshoot samples")
  func continuousTangents() {
    let points = samples + [CGPoint(x: 190, y: 35), CGPoint(x: 210, y: 120)]
    let geometry = FreehandGeometry(stroke(points))
    let quadratics = elements(geometry.path).filter { $0.type == .addQuadCurveToPoint }
    for pair in zip(quadratics, quadratics.dropFirst()) {
      let join = pair.0.points[1]
      let incoming = CGPoint(x: join.x - pair.0.points[0].x, y: join.y - pair.0.points[0].y)
      let outgoing = CGPoint(x: pair.1.points[0].x - join.x, y: pair.1.points[0].y - join.y)
      #expect(incoming == outgoing)
    }
    let bounds = geometry.path.boundingBoxOfPath
    #expect(bounds.minX >= 20 && bounds.maxX <= 210)
    #expect(bounds.minY >= 20 && bounds.maxY <= 120)
    #expect(geometry.bounds == bounds.insetBy(dx: -2, dy: -2))
  }

  @Test("Highlighter geometry stays a polyline with its original translucent style")
  func highlighterUnchanged() throws {
    let geometry = FreehandGeometry(stroke(samples, highlighter: true, width: 16))
    #expect(elements(geometry.path).map(\.type) == [.moveToPoint, .addLineToPoint, .addLineToPoint])
    #expect(geometry.path.boundingBoxOfPath.minY == 20)
    let bitmap = try render { geometry.draw(in: $0) }
    let alpha = try #require(bitmap.colorAt(x: 60, y: 60)?.alphaComponent)
    #expect(abs(alpha - 0.4) < 0.01)
  }

  @Test("Empty, single-point and repeated samples are safe; two points remain straight")
  func shortStrokes() {
    let point = samples[0]
    for points in [[], [point], [point, point, point]] {
      let geometry = FreehandGeometry(stroke(points))
      #expect(geometry.path.isEmpty)
      #expect(!geometry.contains(point, tolerance: 10))
    }
    let straight = FreehandGeometry(stroke([samples[0], samples[2]]))
    #expect(elements(straight.path).map(\.type) == [.moveToPoint, .addLineToPoint])
    let repeated = FreehandGeometry(stroke([samples[0], samples[0], samples[1], samples[1], samples[2]]))
    #expect(repeated.path == FreehandGeometry(stroke(samples)).path)
  }

  @Test("Selection follows the smoothed curve rather than the original sharp corner")
  func hitTesting() {
    let geometry = FreehandGeometry(stroke(samples))
    #expect(geometry.contains(CGPoint(x: 100, y: 40), tolerance: 2))
    #expect(!geometry.contains(samples[1], tolerance: 2))
    #expect(geometry.contains(samples[0], tolerance: 2))
    #expect(geometry.contains(samples[2], tolerance: 2))
    let broad = FreehandGeometry(stroke(samples, width: 30))
    #expect(broad.contains(CGPoint(x: 100, y: 50), tolerance: 2))
  }

  @Test("Preview and export use identical smooth and highlighter raster output")
  func exportMatchesPreview() throws {
    try withDocument { doc in
      for highlighter in [false, true] {
        let annotation = stroke(samples, highlighter: highlighter, width: highlighter ? 16 : 4)
        doc.annotations = [.freehand(annotation)]
        let export = NSBitmapImageRep(cgImage: try #require(EditorRenderer.renderAnnotatedCGImage(doc: doc)))
        let preview = try render { FreehandGeometry(annotation).draw(in: $0) }
        var matches = true
        for y in 0..<180 {
          for x in 0..<240 where export.colorAt(x: x, y: y) != preview.colorAt(x: x, y: y) {
            matches = false
          }
        }
        #expect(matches)
      }
    }
  }

  @Test("Zoom scales the smooth path and stroke together")
  func zoom() throws {
    for scale in [CGFloat(0.5), 1, 1.2] {
      let geometry = FreehandGeometry(stroke(samples))
      let bitmap = try render(scale: scale) { geometry.draw(in: $0) }
      #expect((bitmap.colorAt(x: Int(100 * scale), y: Int(40 * scale))?.alphaComponent ?? 0) > 0.5)
      #expect((bitmap.colorAt(x: Int(100 * scale), y: Int(20 * scale))?.alphaComponent ?? 0) == 0)
    }
  }

  @Test("Appending live samples keeps completed curve segments unchanged")
  func stablePreview() {
    let before = elements(FreehandGeometry(stroke(samples)).path)
    let after = elements(FreehandGeometry(stroke(samples + [CGPoint(x: 210, y: 30)])).path)
    for index in 0..<(before.count - 1) {
      #expect(before[index].type == after[index].type)
      #expect(before[index].points == after[index].points)
    }
  }

  @Test("A completed stroke retains its preview path and is one undoable edit")
  func strokeLifecycle() throws {
    try withDocument { doc in
      doc.markSaved()
      doc.beginFreehandStroke(at: samples[0], isHighlighter: false)
      doc.continueFreehandStroke(to: samples[0])
      doc.continueFreehandStroke(to: samples[1])
      doc.continueFreehandStroke(to: samples[2])
      let active = try #require(doc.activeFreehandStroke)
      #expect(active.points == samples)
      doc.commitFreehandStroke()
      #expect(doc.activeFreehandStroke == nil)
      #expect(doc.selectedAnnotation == .freehand(active))
      #expect(doc.hasUnsavedChanges)
      doc.undo()
      #expect(doc.annotations.isEmpty)
      #expect(!doc.hasUnsavedChanges)
      doc.redo()
      #expect(doc.annotations == [.freehand(active)])
      #expect(FreehandGeometry(active).path == FreehandGeometry(stroke(samples)).path)
    }
  }

  @Test("Dense strokes remain finite and preserve every distinct sample")
  func denseStroke() {
    let points = (0..<2000).map {
      CGPoint(x: CGFloat($0) * 0.2, y: 50 + sin(CGFloat($0) * 0.15) * 10)
    }
    let geometry = FreehandGeometry(stroke(points))
    #expect(elements(geometry.path).count == points.count + 1)
    #expect(geometry.path.currentPoint == points.last)
    #expect(geometry.bounds.minX.isFinite && geometry.bounds.maxY.isFinite)
    #expect(geometry.path.boundingBoxOfPath.minY >= 40)
    #expect(geometry.path.boundingBoxOfPath.maxY <= 60)
  }

  @Test("Recognition identifies lines, rectangles, and ellipses without accepting highlighters")
  func recognizesBasicShapes() {
    let linePoints = (0...10).map {
      CGPoint(x: CGFloat($0) * 10, y: 20 + sin(CGFloat($0)) * 0.5)
    }
    let rectanglePoints = [
      CGPoint(x: 20, y: 20), CGPoint(x: 60, y: 20), CGPoint(x: 100, y: 20),
      CGPoint(x: 100, y: 55), CGPoint(x: 100, y: 90), CGPoint(x: 60, y: 90),
      CGPoint(x: 20, y: 90), CGPoint(x: 20, y: 55), CGPoint(x: 20, y: 20)
    ]
    let ellipsePoints = (0...32).map { index -> CGPoint in
      let angle = CGFloat(index) / 32 * 2 * .pi
      return CGPoint(x: 60 + cos(angle) * 40, y: 50 + sin(angle) * 25)
    }

    #expect(FreehandShapeRecognition.recognize(stroke(linePoints)) == .line)
    #expect(FreehandShapeRecognition.recognize(stroke(rectanglePoints)) == .rectangle)
    #expect(FreehandShapeRecognition.recognize(stroke(ellipsePoints)) == .ellipse)
    #expect(FreehandShapeRecognition.recognize(stroke(linePoints, highlighter: true)) == nil)
    #expect(FreehandShapeRecognition.recognize(stroke(samples)) == nil)
  }

  @Test("Shape conversion is reversible, undoable, and retains the original samples")
  func reversibleRecognition() throws {
    try withDocument { doc in
      let original = stroke([
        CGPoint(x: 30, y: 30), CGPoint(x: 70, y: 30), CGPoint(x: 110, y: 31)
      ])
      doc.annotations = [.freehand(original)]
      doc.select(original.id)

      doc.recognizeSelectedFreehandShape()
      guard case .freehand(let recognized) = doc.selectedAnnotation else {
        Issue.record("Expected recognized freehand annotation")
        return
      }
      #expect(recognized.recognizedShape == .line)
      #expect(recognized.points == original.points)
      #expect(FreehandGeometry(recognized).path.currentPoint == original.points.last)

      doc.restoreSelectedFreehandStroke()
      guard case .freehand(let restored) = doc.selectedAnnotation else {
        Issue.record("Expected restored freehand annotation")
        return
      }
      #expect(restored.recognizedShape == nil)
      #expect(restored.points == original.points)
      doc.undo()
      guard case .freehand(let undone) = doc.selectedAnnotation else {
        Issue.record("Expected undo to restore recognized shape")
        return
      }
      #expect(undone.recognizedShape == .line)
    }
  }
}
