import AppKit
import SwiftUI
import Testing
@testable import SnipSnap

@MainActor
@Suite("Editor inspector")
struct EditorInspectorTests {
  private func withDocument(_ body: (AnnotationDocument) throws -> Void) throws {
    let url = FileManager.default.temporaryDirectory
      .appendingPathComponent("inspector-\(UUID().uuidString).png")
    let bitmap = try #require(NSBitmapImageRep(
      bitmapDataPlanes: nil, pixelsWide: 16, pixelsHigh: 16,
      bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
      isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    ))
    let data = try #require(bitmap.representation(using: .png, properties: [:]))
    try data.write(to: url)
    defer { try? FileManager.default.removeItem(at: url) }
    try body(AnnotationDocument(sourceURL: url))
  }

  @Test("Selection controls the inspector without changing the creation tool")
  func selectionOverridesTool() throws {
    try withDocument { doc in
      let text = TextAnnotation(position: .zero, text: "Label", color: .red, fontSize: 36)
      doc.annotations = [.text(text)]
      doc.markSaved()
      doc.tool = .rect
      doc.selectedID = text.id
      #expect(doc.inspectorTool == .text)
      #expect(doc.tool == .rect)
      #expect(doc.textColor == text.color)
      #expect(doc.textFontSize == 36)
      #expect(!doc.hasUnsavedChanges)
      doc.selectedID = nil
      #expect(doc.inspectorTool == .rect)
      #expect(!doc.hasUnsavedChanges)
    }
  }

  @Test("Selecting an image layer never exposes unrelated creation controls")
  func imageSelectionHasNoStyleTool() throws {
    try withDocument { doc in
      let image = ImageLayerAnnotation(rect: CGRect(x: 0, y: 0, width: 8, height: 8), imageData: Data())
      doc.annotations = [.imageLayer(image)]
      doc.tool = .arrow
      doc.selectedID = image.id
      #expect(doc.selectedAnnotation == .imageLayer(image))
      #expect(doc.inspectorTool == nil)
      #expect(doc.tool == .arrow)
    }
  }

  @Test("Every annotation maps to its relevant inspector")
  func annotationMapping() throws {
    let rect = CGRect(x: 0, y: 0, width: 8, height: 8)
    let stroke = StrokeStyleModel()
    let fill = FillStyleModel()
    let cases: [(Annotation, AnnotationTool?)] = [
      (.rect(.init(rect: rect, stroke: stroke, fill: fill)), .rect),
      (.ellipse(.init(rect: rect, stroke: stroke, fill: fill)), .ellipse),
      (.line(.init(start: .zero, end: CGPoint(x: 8, y: 8), stroke: stroke)), .line),
      (.arrow(.init(start: .zero, end: CGPoint(x: 8, y: 8), stroke: stroke, headStyle: .open)), .arrow),
      (.freehand(.init(points: [.zero, CGPoint(x: 8, y: 8)], stroke: stroke)), .freehand),
      (.text(.init(position: .zero, text: "Text", color: .red, fontSize: 28)), .text),
      (.callout(.init(rect: rect, text: "Callout", stroke: stroke, fill: fill, textColor: .red, fontSize: 28)), .callout),
      (.blur(.init(rect: rect, mode: .pixelate, amount: 12)), .blur),
      (.spotlight(.init(rect: rect)), .spotlight),
      (.step(.init(center: .zero, number: 1, radius: 22, fillColor: .red, textColor: .white, borderColor: .white, borderWidth: 3)), .step),
      (.counter(.init(center: .zero, value: "A")), .step),
      (.emoji(.init(position: .zero, emoji: "A")), .emoji),
      (.measurement(.init(start: .zero, end: CGPoint(x: 8, y: 8), unit: .pixels, stroke: stroke)), .measurement),
      (.imageLayer(.init(rect: rect, imageData: Data())), nil)
    ]
    for (annotation, expected) in cases {
      #expect(annotation.inspectorTool == expected)
    }
  }

  @Test("Style synchronization never invokes the control's edit callback")
  func synchronizationIsNotAnEdit() throws {
    try withDocument { doc in
      let first = TextAnnotation(position: .zero, text: "First", color: .red, fontSize: 18)
      let second = TextAnnotation(position: .zero, text: "Second", color: .blue, fontSize: 42)
      let original: [Annotation] = [.text(first), .text(second)]
      doc.annotations = original
      doc.markSaved()
      let editor = EditorView(doc: doc, onClose: {})
      var edits = 0
      let binding = editor.inspectorBinding(\.textFontSize) {
        edits += 1
        doc.updateSelected { annotation in
          if case .text(var text) = annotation {
            text.fontSize = doc.textFontSize
            annotation = .text(text)
          }
        }
      }
      doc.selectedID = first.id
      #expect(binding.wrappedValue == 18)
      doc.selectedID = second.id
      #expect(binding.wrappedValue == 42)
      #expect(edits == 0)
      #expect(doc.annotations == original)
      #expect(!doc.hasUnsavedChanges)
      binding.wrappedValue = 42
      #expect(edits == 0)
      binding.wrappedValue = 50
      #expect(edits == 1)
      #expect(doc.annotations[0] == .text(first))
      #expect(doc.hasUnsavedChanges)
      doc.undo()
      #expect(doc.annotations == original)
      #expect(binding.wrappedValue == 42)
      #expect(!doc.hasUnsavedChanges)
      doc.redo()
      #expect(binding.wrappedValue == 50)
      #expect(edits == 1)
    }
  }

  @Test("Selection and no-op edits preserve undo and redo history")
  func noOpHistory() throws {
    try withDocument { doc in
      let text = TextAnnotation(position: .zero, text: "Label", color: .red, fontSize: 28)
      let original = Annotation.text(text)
      doc.pushUndoCheckpoint()
      doc.annotations.append(original)
      doc.markSaved()
      doc.selectedID = text.id
      doc.updateSelected { _ in }
      doc.undo()
      #expect(doc.annotations.isEmpty)
      #expect(doc.selectedID == nil)
      doc.redo()
      #expect(doc.annotations == [original])
      doc.selectedID = text.id
      doc.updateSelected { annotation in
        if case .text(var t) = annotation {
          t.fontSize = 40
          annotation = .text(t)
        }
      }
      doc.undo()
      doc.updateSelected { _ in }
      doc.redo()
      #expect(doc.textFontSize == 40)
    }
  }

  @Test("Highlighter selection restores base width without changing the stroke")
  func highlighterWidth() throws {
    try withDocument { doc in
      let highlighter = FreehandAnnotation(
        points: [.zero, CGPoint(x: 8, y: 8)],
        stroke: StrokeStyleModel(color: .yellow, lineWidth: 24), isHighlighter: true
      )
      doc.annotations = [.freehand(highlighter)]
      doc.markSaved()
      doc.stroke.lineWidth = 2
      doc.selectedID = highlighter.id
      #expect(doc.stroke.lineWidth == 8)
      #expect(doc.freehandIsHighlighter)
      #expect(doc.annotations == [.freehand(highlighter)])
      #expect(!doc.hasUnsavedChanges)
    }
  }
}
