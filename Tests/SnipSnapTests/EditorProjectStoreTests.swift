import AppKit
import SwiftUI
import Testing
@testable import SnipSnap

@MainActor
@Suite("Editable project persistence")
struct EditorProjectStoreTests {
  private func withCapture(_ body: (URL) throws -> Void) throws {
    let url = FileManager.default.temporaryDirectory
      .appendingPathComponent("project-\(UUID().uuidString).png")
    let bitmap = try #require(NSBitmapImageRep(
      bitmapDataPlanes: nil, pixelsWide: 160, pixelsHigh: 120,
      bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
      isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    ))
    try #require(bitmap.representation(using: .png, properties: [:])).write(to: url)
    let projectURL = EditorProjectStore.projectURL(for: url)
    defer {
      try? FileManager.default.removeItem(at: url)
      try? FileManager.default.removeItem(at: projectURL)
    }
    try body(url)
  }

  private func allAnnotationKinds() -> [Annotation] {
    let stroke = StrokeStyleModel(color: Color(red: 0.2, green: 0.4, blue: 0.8, opacity: 0.75), lineWidth: 5)
    let fill = FillStyleModel(color: Color(red: 0.8, green: 0.3, blue: 0.1, opacity: 0.45), enabled: true)
    return [
      .rect(RectAnnotation(rect: CGRect(x: 1, y: 2, width: 30, height: 20), stroke: stroke, fill: fill)),
      .ellipse(EllipseAnnotation(rect: CGRect(x: 4, y: 5, width: 28, height: 18), stroke: stroke, fill: fill)),
      .line(LineAnnotation(start: CGPoint(x: 1, y: 2), end: CGPoint(x: 30, y: 40), stroke: stroke)),
      .arrow(ArrowAnnotation(
        start: CGPoint(x: 3, y: 4), end: CGPoint(x: 60, y: 70), stroke: stroke,
        headStyle: .open, bendPoint: CGPoint(x: 25, y: 20)
      )),
      .freehand(FreehandAnnotation(
        points: [CGPoint(x: 2, y: 4), CGPoint(x: 8, y: 16)], stroke: stroke, isHighlighter: true
      )),
      .text(TextAnnotation(
        position: CGPoint(x: 10, y: 12), text: "Editable\ntext", color: .yellow, fontSize: 24,
        highlighted: true, highlightColor: .orange, highlightOpacity: 0.62
      )),
      .callout(CalloutAnnotation(
        rect: CGRect(x: 8, y: 9, width: 50, height: 32), text: "Callout",
        stroke: stroke, fill: fill, textColor: .green, fontSize: 18,
        tailTip: CGPoint(x: 30, y: 72)
      )),
      .blur(BlurAnnotation(rect: CGRect(x: 3, y: 7, width: 25, height: 15), mode: .redact, amount: 11)),
      .spotlight(SpotlightAnnotation(
        rect: CGRect(x: 12, y: 13, width: 40, height: 35), shape: .ellipse,
        dimmingOpacity: 0.72, borderStroke: stroke
      )),
      .step(StepAnnotation(
        center: CGPoint(x: 40, y: 50), number: 3, mode: .letters, radius: 17,
        fillColor: .red, textColor: .white, borderColor: .black, borderWidth: 2
      )),
      .counter(CounterAnnotation(
        center: CGPoint(x: 44, y: 55), value: "A1", radius: 19,
        fillColor: .blue, textColor: .white, borderColor: .yellow, borderWidth: 3
      )),
      .emoji(EmojiAnnotation(position: CGPoint(x: 60, y: 62), emoji: "🐑", size: 36)),
      .measurement(MeasurementAnnotation(
        start: CGPoint(x: 5, y: 9), end: CGPoint(x: 80, y: 90), unit: .centimeters,
        ppi: 96, baseFontSize: 18, stroke: stroke, showExtensionLines: false,
        labelOffset: CGPoint(x: 11, y: -8)
      )),
      .imageLayer(ImageLayerAnnotation(
        rect: CGRect(x: 20, y: 25, width: 15, height: 17), imageData: Data([0, 1, 2, 255])
      )),
      .loupe(LoupeAnnotation(
        center: CGPoint(x: 90, y: 60), radius: 32, magnification: 3.25
      )),
      .freehand(FreehandAnnotation(
        points: [CGPoint(x: 20, y: 30), CGPoint(x: 40, y: 30), CGPoint(x: 60, y: 30)],
        stroke: stroke, recognizedShape: .line
      ))
    ]
  }

  @Test("Every annotation type, color, crop and layer order round-trip")
  func roundTripAllAnnotations() throws {
    try withCapture { url in
      let original = try AnnotationDocument(sourceURL: url)
      let annotations = allAnnotationKinds()
      original.annotations = annotations
      original.cropRect = CGRect(x: 7, y: 9, width: 100, height: 80)
      try original.saveProject()
      #expect(!original.hasUnsavedChanges)
      #expect(FileManager.default.fileExists(atPath: EditorProjectStore.projectURL(for: url).path))

      let restored = try AnnotationDocument(sourceURL: url)
      #expect(restored.annotations.count == annotations.count)
      #expect(restored.annotations.map(\.id) == annotations.map(\.id))
      #expect(restored.cropRect == original.cropRect)
      #expect(!restored.hasUnsavedChanges)

      guard case .arrow(let arrow) = restored.annotations[3] else {
        Issue.record("Expected arrow at its original layer position")
        return
      }
      #expect(arrow.bendPoint == CGPoint(x: 25, y: 20))
      #expect(arrow.headStyle == .open)
      guard case .text(let text) = restored.annotations[5] else {
        Issue.record("Expected text at its original layer position")
        return
      }
      #expect(text.text == "Editable\ntext")
      #expect(text.fontSize == 24)
      #expect(text.highlightOpacity == 0.62)
      guard case .callout(let callout) = restored.annotations[6] else {
        Issue.record("Expected callout at its original layer position")
        return
      }
      #expect(callout.tailTip == CGPoint(x: 30, y: 72))
      guard case .measurement(let measurement) = restored.annotations[12] else {
        Issue.record("Expected measurement at its original layer position")
        return
      }
      #expect(measurement.unit == .centimeters)
      #expect(measurement.labelOffset == CGPoint(x: 11, y: -8))
      guard case .imageLayer(let imageLayer) = restored.annotations[13] else {
        Issue.record("Expected image layer at the top of paint order")
        return
      }
      #expect(imageLayer.imageData == Data([0, 1, 2, 255]))
      guard case .loupe(let loupe) = restored.annotations[14] else {
        Issue.record("Expected loupe at its original layer position")
        return
      }
      #expect(loupe.center == CGPoint(x: 90, y: 60))
      #expect(loupe.radius == 32)
      #expect(loupe.magnification == 3.25)
      guard case .freehand(let recognizedStroke) = restored.annotations[15] else {
        Issue.record("Expected recognized freehand annotation at its original layer position")
        return
      }
      #expect(recognizedStroke.recognizedShape == .line)
      #expect(recognizedStroke.points == [
        CGPoint(x: 20, y: 30), CGPoint(x: 40, y: 30), CGPoint(x: 60, y: 30)
      ])
    }
  }

  @Test("Saving again atomically replaces project with the latest layer order")
  func saveUpdatesProject() throws {
    try withCapture { url in
      let doc = try AnnotationDocument(sourceURL: url)
      let first = Annotation.emoji(EmojiAnnotation(position: CGPoint(x: 10, y: 10), emoji: "A"))
      let second = Annotation.emoji(EmojiAnnotation(position: CGPoint(x: 20, y: 20), emoji: "B"))
      doc.annotations = [first, second]
      try doc.saveProject()
      doc.annotations = [second, first]
      try doc.saveProject()
      let restored = try AnnotationDocument(sourceURL: url)
      #expect(restored.annotations == [second, first])
    }
  }

  @Test("A missing project starts a clean document without modifying the source")
  func absentSidecar() throws {
    try withCapture { url in
      let originalData = try Data(contentsOf: url)
      let doc = try AnnotationDocument(sourceURL: url)
      #expect(doc.annotations.isEmpty)
      #expect(doc.cropRect == nil)
      #expect(!doc.hasUnsavedChanges)
      #expect(try Data(contentsOf: url) == originalData)
    }
  }

  @Test("Malformed or incompatible projects fail explicitly instead of silently discarding edits")
  func invalidSidecars() throws {
    try withCapture { url in
      let projectURL = EditorProjectStore.projectURL(for: url)
      try Data("{invalid".utf8).write(to: projectURL)
      #expect(throws: (any Error).self) { try AnnotationDocument(sourceURL: url) }

      try JSONEncoder().encode(EditorProject(
        version: 99, sourceFilename: url.lastPathComponent,
        imageSize: CGSize(width: 160, height: 120), cropRect: nil, annotations: []
      )).write(to: projectURL)
      #expect(throws: EditorProjectStoreError.unsupportedVersion(99)) {
        try AnnotationDocument(sourceURL: url)
      }

      try JSONEncoder().encode(EditorProject(
        version: 1, sourceFilename: "another-image.png",
        imageSize: CGSize(width: 160, height: 120), cropRect: nil, annotations: []
      )).write(to: projectURL)
      #expect(throws: EditorProjectStoreError.wrongSource) {
        try AnnotationDocument(sourceURL: url)
      }
    }
  }
}
