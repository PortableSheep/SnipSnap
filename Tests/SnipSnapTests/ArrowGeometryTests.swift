import AppKit
import SwiftUI
import Testing
@testable import SnipSnap

@MainActor
@Suite("Curved arrows")
struct ArrowGeometryTests {
  private func arrow(bend: CGPoint? = nil, style: ArrowHeadStyle = .filled) -> ArrowAnnotation {
    ArrowAnnotation(
      start: CGPoint(x: 20, y: 100), end: CGPoint(x: 220, y: 100),
      stroke: StrokeStyleModel(color: .white, lineWidth: 4), headStyle: style, bendPoint: bend
    )
  }

  private func near(_ lhs: CGPoint, _ rhs: CGPoint) -> Bool {
    hypot(lhs.x - rhs.x, lhs.y - rhs.y) < 0.001
  }

  private func render(scale: CGFloat = 1, _ draw: (CGContext) -> Void) throws -> NSBitmapImageRep {
    let context = try #require(CGContext(
      data: nil, width: 300, height: 200, bitsPerComponent: 8, bytesPerRow: 0,
      space: CGColorSpaceCreateDeviceRGB(),
      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ))
    context.translateBy(x: 0, y: 200)
    context.scaleBy(x: scale, y: -scale)
    draw(context)
    return NSBitmapImageRep(cgImage: try #require(context.makeImage()))
  }

  @Test("Existing arrows remain straight with their original head dimensions")
  func straightCompatibility() {
    let a = arrow()
    let geometry = ArrowGeometry(a)
    #expect(a.bendPoint == nil)
    #expect(near(geometry.point(at: 0.5), CGPoint(x: 120, y: 100)))
    #expect(near(geometry.endDirection, CGPoint(x: 1, y: 0)))
    #expect(near(geometry.head.base, CGPoint(x: 204, y: 100)))
    #expect(near(geometry.shaft.currentPoint, geometry.head.base))
    #expect(geometry.path.boundingBoxOfPath.height == 0)
  }

  @Test("The cubic curve passes through the draggable midpoint")
  func midpointInterpolation() {
    for bend in [CGPoint(x: 120, y: 30), CGPoint(x: 160, y: 180), CGPoint(x: 30, y: 80)] {
      let a = arrow(bend: bend)
      let geometry = ArrowGeometry(a)
      #expect(near(geometry.point(at: 0), a.start))
      #expect(near(geometry.point(at: 0.5), bend))
      #expect(near(geometry.point(at: 1), a.end))
    }
  }

  @Test("The arrowhead follows the endpoint tangent and the shaft joins its base")
  func headFollowsTangent() {
    let geometry = ArrowGeometry(arrow(bend: CGPoint(x: 120, y: 30)))
    let direction = geometry.endDirection
    let end = geometry.arrow.end
    let base = geometry.head.base
    let length = hypot(end.x - base.x, end.y - base.y)
    #expect(near(CGPoint(x: (end.x - base.x) / length, y: (end.y - base.y) / length), direction))
    let before = geometry.point(at: 0.99999)
    let tangentLength = hypot(end.x - before.x, end.y - before.y)
    #expect(near(CGPoint(x: (end.x - before.x) / tangentLength, y: (end.y - before.y) / tangentLength), direction))
    #expect(near(geometry.shaft.currentPoint, base))
  }

  @Test("Hit testing follows the curve and includes arrowheads")
  func hitTesting() {
    let geometry = ArrowGeometry(arrow(bend: CGPoint(x: 120, y: 30)))
    #expect(geometry.contains(CGPoint(x: 120, y: 30), tolerance: 10))
    #expect(!geometry.contains(CGPoint(x: 120, y: 100), tolerance: 10))
    #expect(geometry.contains(geometry.head.left, tolerance: 2))
    #expect(geometry.contains(geometry.arrow.end, tolerance: 2))
  }

  @Test("Moving the arrow preserves its bend and endpoint edits preserve bend offset")
  func movement() {
    var a = arrow(bend: CGPoint(x: 120, y: 30))
    a.translate(by: CGPoint(x: 10, y: 20))
    #expect(a.start == CGPoint(x: 30, y: 120))
    #expect(a.end == CGPoint(x: 230, y: 120))
    #expect(a.midpoint == CGPoint(x: 130, y: 50))
    a.moveEndpoint(start: CGPoint(x: 50, y: 140), end: a.end)
    #expect(a.midpoint == CGPoint(x: 140, y: 60))
    #expect(near(ArrowGeometry(a).point(at: 0.5), a.midpoint))
    var straight = arrow()
    straight.moveEndpoint(start: CGPoint(x: 30, y: 50), end: straight.end)
    #expect(straight.bendPoint == nil)
  }

  @Test("Short and coincident endpoints yield finite, bounded heads")
  func degenerateGeometry() {
    for bend in [nil, CGPoint(x: 100, y: 20)] {
      for style in ArrowHeadStyle.allCases {
        var a = arrow(bend: bend, style: style)
        a.end = a.start
        let geometry = ArrowGeometry(a)
        #expect(geometry.head.base.x.isFinite && geometry.head.base.y.isFinite)
        #expect(geometry.shaft.boundingBoxOfPath.width.isFinite)
        #expect(geometry.headPath.boundingBoxOfPath.isInfinite == false)
        if style == .none {
          #expect(geometry.headPath.isEmpty)
          #expect(near(geometry.shaft.currentPoint, a.end))
        }
      }
    }
    var a = arrow()
    a.end = CGPoint(x: 22, y: 100)
    #expect(abs(hypot(ArrowGeometry(a).head.base.x - a.end.x, ArrowGeometry(a).head.base.y - a.end.y) - 1.1) < 0.001)
  }

  @Test("Large bends retain their curve and connect to the head")
  func largeBends() {
    for bend in [CGPoint(x: 120, y: -1000), CGPoint(x: -1000, y: 100), CGPoint(x: 1000, y: 100)] {
      let geometry = ArrowGeometry(arrow(bend: bend))
      #expect(near(geometry.shaft.currentPoint, geometry.head.base))
      #expect(geometry.contains(bend, tolerance: 2))
      #expect(geometry.shaft.boundingBoxOfPath.insetBy(dx: -0.001, dy: -0.001).contains(bend))
      #expect(geometry.shaft.boundingBoxOfPath.width.isFinite)
    }
  }

  @Test("Raster drawing follows the bend at different zoom levels")
  func curvedRasterAndZoom() throws {
    for scale in [CGFloat(0.5), 1, 1.25] {
      let geometry = ArrowGeometry(arrow(bend: CGPoint(x: 120, y: 30)))
      let bitmap = try render(scale: scale) { geometry.draw(in: $0) }
      #expect((bitmap.colorAt(x: Int(120 * scale), y: Int(30 * scale))?.alphaComponent ?? 0) > 0.5)
      #expect((bitmap.colorAt(x: Int(120 * scale), y: Int(100 * scale))?.alphaComponent ?? 0) == 0)
    }
  }

  @Test("Export matches the shared canvas arrow renderer for every head style")
  func exportMatchesCanvas() throws {
    let source = try render { _ in }
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("arrow-render-\(UUID().uuidString).png")
    try #require(source.representation(using: .png, properties: [:])).write(to: url)
    defer { try? FileManager.default.removeItem(at: url) }
    let doc = try AnnotationDocument(sourceURL: url)
    for style in ArrowHeadStyle.allCases {
      let a = arrow(bend: CGPoint(x: 120, y: 30), style: style)
      doc.annotations = [.arrow(a)]
      let export = NSBitmapImageRep(cgImage: try #require(EditorRenderer.renderAnnotatedCGImage(doc: doc)))
      let canvas = try render { ArrowGeometry(a).draw(in: $0) }
      var matching = true
      for y in 0..<200 {
        for x in 0..<300 {
          if export.colorAt(x: x, y: y) != canvas.colorAt(x: x, y: y) {
            matching = false
          }
        }
      }
      #expect(matching)
    }
  }

  @Test("Curve dragging and straightening are undoable without losing styles")
  func undoCurve() throws {
    let bitmap = try #require(NSBitmapImageRep(
      bitmapDataPlanes: nil, pixelsWide: 256, pixelsHigh: 200, bitsPerSample: 8,
      samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
      bytesPerRow: 0, bitsPerPixel: 0
    ))
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("arrow-\(UUID().uuidString).png")
    try #require(bitmap.representation(using: .png, properties: [:])).write(to: url)
    defer { try? FileManager.default.removeItem(at: url) }
    let doc = try AnnotationDocument(sourceURL: url)
    let original = arrow(style: .open)
    doc.annotations = [.arrow(original)]
    doc.selectedID = original.id
    doc.markSaved()
    doc.beginEditSessionIfNeeded()
    for y in [80, 60, 30] {
      doc.updateSelectedInSession { annotation in
        if case .arrow(var a) = annotation {
          a.bendPoint = CGPoint(x: 120, y: y)
          annotation = .arrow(a)
        }
      }
    }
    doc.endEditSession()
    let bent = try #require(doc.selectedAnnotation)
    #expect(doc.hasUnsavedChanges)
    doc.undo()
    #expect(doc.selectedAnnotation == .arrow(original))
    #expect(!doc.hasUnsavedChanges)
    doc.redo()
    #expect(doc.selectedAnnotation == bent)
    doc.updateSelected { annotation in
      if case .arrow(var a) = annotation {
        a.bendPoint = nil
        annotation = .arrow(a)
      }
    }
    #expect(doc.selectedAnnotation == .arrow(original))
    doc.undo()
    #expect(doc.selectedAnnotation == bent)
  }
}
