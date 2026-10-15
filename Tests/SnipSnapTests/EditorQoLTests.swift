import AppKit
import Carbon
import SwiftUI
import Testing
@testable import SnipSnap

@MainActor
@Suite("Editor keyboard and clipboard QoL")
struct EditorQoLTests {
  private func withDocument(_ body: (AnnotationDocument) throws -> Void) throws {
    let url = FileManager.default.temporaryDirectory
      .appendingPathComponent("qol-\(UUID().uuidString).png")
    let bitmap = try #require(NSBitmapImageRep(
      bitmapDataPlanes: nil, pixelsWide: 64, pixelsHigh: 64,
      bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
      isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    ))
    let data = try #require(bitmap.representation(using: .png, properties: [:]))
    try data.write(to: url)
    defer { try? FileManager.default.removeItem(at: url) }
    try body(AnnotationDocument(sourceURL: url))
  }

  private func rect(_ r: CGRect) -> RectAnnotation {
    RectAnnotation(
      rect: r,
      stroke: StrokeStyleModel(color: Color(.sRGB, red: 1, green: 0, blue: 0, opacity: 1), lineWidth: 3),
      fill: FillStyleModel(color: Color(.sRGB, red: 0, green: 0, blue: 1, opacity: 0.5), enabled: true)
    )
  }

  private func rectValue(_ annotation: Annotation?) -> CGRect? {
    if case .rect(let r) = annotation { return r.rect }
    return nil
  }

  @Test("Loupe source includes redactions so magnifying can't reveal hidden pixels")
  func loupeSourceIsRedacted() throws {
    try withDocument { doc in
      #expect(doc.loupeSourceImage === doc.cgImage)
      doc.annotations = [.blur(BlurAnnotation(rect: CGRect(x: 0, y: 0, width: 64, height: 64), mode: .redact, amount: 10))]
      let source = doc.loupeSourceImage
      #expect(source !== doc.cgImage)
      let pixel = try #require(NSBitmapImageRep(cgImage: source).colorAt(x: 32, y: 32))
      #expect(pixel.alphaComponent > 0.99)
      #expect(pixel.brightnessComponent < 0.01)
      #expect(doc.loupeSourceImage === source)
    }
  }

  @Test("Stored colors round-trip in sRGB")
  func storedColorRoundTrip() throws {
    let original = NSColor(srgbRed: 0.2, green: 0.6, blue: 0.9, alpha: 0.75)
    let stored = try StoredColor(Color(nsColor: original))
    let restored = try #require(NSColor(stored.color).usingColorSpace(.sRGB))
    #expect(abs(restored.redComponent - 0.2) < 0.002)
    #expect(abs(restored.greenComponent - 0.6) < 0.002)
    #expect(abs(restored.blueComponent - 0.9) < 0.002)
    #expect(abs(restored.alphaComponent - 0.75) < 0.002)
  }

  @Test("Arrow keys map to image-space directions")
  func nudgeDirections() {
    #expect(EditorWindowController.nudgeDirection(keyCode: UInt16(kVK_LeftArrow)) == CGPoint(x: -1, y: 0))
    #expect(EditorWindowController.nudgeDirection(keyCode: UInt16(kVK_UpArrow)) == CGPoint(x: 0, y: -1))
    #expect(EditorWindowController.nudgeDirection(keyCode: UInt16(kVK_DownArrow)) == CGPoint(x: 0, y: 1))
    #expect(EditorWindowController.nudgeDirection(keyCode: UInt16(kVK_ANSI_A)) == nil)
  }

  @Test("Rapid nudges move the selection and coalesce into one undo step")
  func nudgeCoalesces() throws {
    try withDocument { doc in
      let a = rect(CGRect(x: 10, y: 10, width: 20, height: 20))
      doc.annotations = [.rect(a)]
      doc.selectedID = a.id
      let start = Date()
      doc.nudgeSelected(by: CGPoint(x: 1, y: 0), now: start)
      doc.nudgeSelected(by: CGPoint(x: 10, y: 0), now: start.addingTimeInterval(0.2))
      doc.nudgeSelected(by: CGPoint(x: 0, y: -1), now: start.addingTimeInterval(0.4))
      #expect(rectValue(doc.annotations.first)?.origin == CGPoint(x: 21, y: 9))
      doc.undo()
      #expect(rectValue(doc.annotations.first)?.origin == CGPoint(x: 10, y: 10))
    }
  }

  @Test("Nudges separated by a pause are separate undo steps")
  func nudgeSeparatesAfterPause() throws {
    try withDocument { doc in
      let a = rect(CGRect(x: 10, y: 10, width: 20, height: 20))
      doc.annotations = [.rect(a)]
      doc.selectedID = a.id
      let start = Date()
      doc.nudgeSelected(by: CGPoint(x: 1, y: 0), now: start)
      doc.nudgeSelected(by: CGPoint(x: 1, y: 0), now: start.addingTimeInterval(2))
      doc.undo()
      #expect(rectValue(doc.annotations.first)?.origin == CGPoint(x: 11, y: 10))
    }
  }

  @Test("Nudging without a selection does nothing")
  func nudgeWithoutSelection() throws {
    try withDocument { doc in
      let a = rect(CGRect(x: 10, y: 10, width: 20, height: 20))
      doc.annotations = [.rect(a)]
      doc.nudgeSelected(by: CGPoint(x: 5, y: 5))
      #expect(rectValue(doc.annotations.first)?.origin == CGPoint(x: 10, y: 10))
    }
  }

  @Test("Annotation clipboard payload round-trips")
  func clipboardRoundTrip() throws {
    let a = Annotation.rect(rect(CGRect(x: 1, y: 2, width: 3, height: 4)))
    let decoded = try AnnotationClipboard.decode(AnnotationClipboard.encode([a]))
    #expect(decoded.count == 1)
    #expect(decoded.first?.id == a.id)
    #expect(rectValue(decoded.first) == CGRect(x: 1, y: 2, width: 3, height: 4))
  }

  @Test("Image copy carries selected annotations on the same pasteboard item")
  func imageCopyIncludesAnnotations() throws {
    let pasteboard = NSPasteboard(name: NSPasteboard.Name("snipsnap-qol-\(UUID().uuidString)"))
    defer { pasteboard.releaseGlobally() }
    let bitmap = try #require(NSBitmapImageRep(
      bitmapDataPlanes: nil, pixelsWide: 4, pixelsHigh: 4,
      bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
      isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    ))
    let image = try #require(bitmap.cgImage)
    let a = Annotation.rect(rect(CGRect(x: 1, y: 2, width: 3, height: 4)))
    try ImageClipboard.copy(
      image: image,
      additionalData: [AnnotationClipboard.type: AnnotationClipboard.encode([a])],
      to: pasteboard
    )
    #expect(pasteboard.pasteboardItems?.count == 1)
    #expect(pasteboard.data(forType: .png) != nil)
    #expect(AnnotationClipboard.annotations(from: pasteboard)?.first?.id == a.id)
  }

  @Test("Pasting creates new copies that cascade on repeated paste")
  func pasteCascades() throws {
    try withDocument { doc in
      let a = rect(CGRect(x: 10, y: 10, width: 20, height: 20))
      doc.annotations = [.rect(a)]
      doc.pasteAnnotations([.rect(a)], pasteboardChangeCount: 7)
      doc.pasteAnnotations([.rect(a)], pasteboardChangeCount: 7)
      #expect(doc.annotations.count == 3)
      #expect(Set(doc.annotations.map(\.id)).count == 3)
      #expect(rectValue(doc.annotations[1])?.origin == CGPoint(x: 22, y: 22))
      #expect(rectValue(doc.annotations[2])?.origin == CGPoint(x: 34, y: 34))
      #expect(doc.selectedIDs == [doc.annotations[2].id])
      doc.undo()
      #expect(doc.annotations.count == 2)
    }
  }

  @Test("Pasting into a document without the originals keeps their position")
  func pasteIntoOtherDocument() throws {
    try withDocument { doc in
      let a = rect(CGRect(x: 10, y: 10, width: 20, height: 20))
      doc.pasteAnnotations([.rect(a)], pasteboardChangeCount: 3)
      #expect(rectValue(doc.annotations.first)?.origin == CGPoint(x: 10, y: 10))
      #expect(doc.annotations.first?.id != a.id)
    }
  }

  @Test("Translate moves every point of composite annotations")
  func translateComposite() {
    var callout = Annotation.callout(CalloutAnnotation(
      rect: CGRect(x: 0, y: 0, width: 10, height: 10), text: "Hi",
      stroke: StrokeStyleModel(), fill: FillStyleModel(), textColor: .white, fontSize: 12,
      tailTip: CGPoint(x: 20, y: 20)
    ))
    callout.translate(by: CGPoint(x: 5, y: -5))
    guard case .callout(let c) = callout else { Issue.record("Expected callout"); return }
    #expect(c.rect.origin == CGPoint(x: 5, y: -5))
    #expect(c.tailTip == CGPoint(x: 25, y: 15))
  }

  @Test("Cheatsheet documents every editor tool shortcut")
  func cheatsheetCoversTools() {
    let keys = Set(EditorShortcutSection.all.first { $0.title == "Tools" }?.shortcuts.map(\.keys) ?? [])
    #expect(keys == Set(["V", "H", "R", "O", "L", "A", "M", "T", "C", "B", "S", "N", "E", "D"]))
  }
}
