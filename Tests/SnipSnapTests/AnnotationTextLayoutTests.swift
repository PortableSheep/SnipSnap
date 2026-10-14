import AppKit
import SwiftUI
import Testing
@testable import SnipSnap

@MainActor
@Suite("Annotation text layout")
struct AnnotationTextLayoutTests {
  private func render(
    width: Int = 300, height: Int = 200, _ draw: (CGContext) -> Void
  ) throws -> NSBitmapImageRep {
    let context = try #require(CGContext(
      data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
      space: CGColorSpaceCreateDeviceRGB(),
      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ))
    context.translateBy(x: 0, y: CGFloat(height))
    context.scaleBy(x: 1, y: -1)
    draw(context)
    return NSBitmapImageRep(cgImage: try #require(context.makeImage()))
  }

  private func hasInk(_ bitmap: NSBitmapImageRep, in rect: CGRect) -> Bool {
    let area = rect.integral.intersection(CGRect(
      x: 0, y: 0, width: bitmap.pixelsWide, height: bitmap.pixelsHigh
    ))
    guard !area.isNull, area.width > 0, area.height > 0 else { return false }
    for y in Int(area.minY)..<Int(area.maxY) {
      for x in Int(area.minX)..<Int(area.maxX) {
        if (bitmap.colorAt(x: x, y: y)?.alphaComponent ?? 0) > 0.05 { return true }
      }
    }
    return false
  }

  @Test("Explicit newlines increase measured height without joining line widths")
  func multilineBounds() {
    let single = AnnotationTextLayout(text: "Wide label", fontSize: 24, color: .white)
    let multi = AnnotationTextLayout(text: "Wide label\nSecond", fontSize: 24, color: .white)
    #expect(multi.size.height > single.size.height * 1.8)
    #expect(multi.size.width == single.size.width)
    let trailing = AnnotationTextLayout(text: "Wide label\n", fontSize: 24, color: .white)
    #expect(trailing.size.height > single.size.height)
  }

  @Test("Highlight and hit bounds include the same multiline layout and padding")
  func highlightedBounds() {
    let plain = TextAnnotation(
      position: CGPoint(x: 20, y: 30), text: "One\nTwo", color: .white, fontSize: 24
    )
    var highlighted = plain
    highlighted.highlighted = true
    let bounds = AnnotationTextLayout.textBounds(plain)
    let padded = AnnotationTextLayout.textBounds(highlighted)
    #expect(padded.origin == plain.position)
    #expect(padded.width == bounds.width + 16)
    #expect(padded.height == bounds.height + 12)
    #expect(bounds.height > 40)
  }

  @Test("Text drawing places visible glyphs on both lines at top-left coordinates")
  func drawMultiline() throws {
    let text = TextAnnotation(
      position: CGPoint(x: 20, y: 20), text: "First\nSecond", color: .white, fontSize: 24
    )
    let line = AnnotationTextLayout(text: "First", fontSize: 24, color: .white)
    let image = try render { AnnotationTextLayout.draw(text, in: $0) }
    #expect(hasInk(image, in: CGRect(x: 20, y: 20, width: 100, height: line.size.height)))
    #expect(hasInk(image, in: CGRect(x: 20, y: 20 + line.size.height, width: 100, height: line.size.height)))
    #expect(!hasInk(image, in: CGRect(x: 0, y: 130, width: 300, height: 70)))
  }

  @Test("Callouts wrap to image-coordinate width and clip overflow")
  func wrappedCallout() throws {
    let callout = CalloutAnnotation(
      rect: CGRect(x: 20, y: 20, width: 140, height: 75),
      text: "Several words wrap into multiple lines and overflow the bottom",
      stroke: .init(), fill: .init(), textColor: .white, fontSize: 20
    )
    let rect = AnnotationTextLayout.calloutTextRect(callout)
    let layout = AnnotationTextLayout(
      text: callout.text, fontSize: callout.fontSize, color: .white, width: rect.width
    )
    #expect(layout.size.width == 112)
    #expect(layout.size.height > rect.height)
    let image = try render { AnnotationTextLayout.drawText(in: callout, context: $0) }
    #expect(hasInk(image, in: rect))
    #expect(!hasInk(image, in: CGRect(x: 0, y: rect.maxY, width: 300, height: 200 - rect.maxY)))
    #expect(!hasInk(image, in: CGRect(x: rect.maxX, y: 0, width: 300 - rect.maxX, height: 200)))
  }

  @Test("Narrow callouts never produce inverted text rectangles or leak glyphs")
  func tinyCallout() throws {
    let callout = CalloutAnnotation(
      rect: CGRect(x: 20, y: 20, width: 10, height: 10), text: "Hidden",
      stroke: .init(), fill: .init(), textColor: .white, fontSize: 24
    )
    let rect = AnnotationTextLayout.calloutTextRect(callout)
    #expect(rect.width == 0)
    #expect(rect.height == 0)
    let image = try render { AnnotationTextLayout.drawText(in: callout, context: $0) }
    #expect(!hasInk(image, in: CGRect(x: 0, y: 0, width: 300, height: 200)))
  }

  @Test("Bitmap export and shared canvas text drawing have identical output")
  func exportMatchesSharedLayout() throws {
    let source = try render { _ in }
    let url = FileManager.default.temporaryDirectory
      .appendingPathComponent("text-layout-\(UUID().uuidString).png")
    try #require(source.representation(using: .png, properties: [:])).write(to: url)
    defer { try? FileManager.default.removeItem(at: url) }
    let doc = try AnnotationDocument(sourceURL: url)
    let text = TextAnnotation(
      position: CGPoint(x: 15, y: 15), text: "First line\nSecond line",
      color: .white, fontSize: 24, highlighted: true
    )
    doc.annotations = [.text(text)]
    let export = NSBitmapImageRep(cgImage: try #require(EditorRenderer.renderAnnotatedCGImage(doc: doc)))
    let expected = try render { AnnotationTextLayout.draw(text, in: $0) }
    for y in 0..<200 {
      for x in 0..<300 {
        #expect(export.colorAt(x: x, y: y) == expected.colorAt(x: x, y: y))
      }
    }
  }

  @Test("Unicode, empty input and font changes produce valid layout sizes")
  func layoutEdgeCases() {
    for text in ["", "A\n\nB", "Cafe\u{301}", "\u{1F600}", "\u{05E9}\u{05DC}\u{05D5}\u{05DD}"] {
      let small = AnnotationTextLayout(text: text, fontSize: 12, color: .white)
      let large = AnnotationTextLayout(text: text, fontSize: 36, color: .white)
      #expect(small.size.width.isFinite && small.size.height.isFinite)
      #expect(small.size.width >= 0 && small.size.height > 0)
      #expect(large.size.height >= small.size.height)
    }
  }

  @Test("The native editor wraps with the same metrics and supports text undo")
  func nativeEditorLayout() throws {
    var text = "Several words wrap onto more than one line"
    let host = NSHostingView(rootView: AnnotationTextEditor(
      text: Binding(get: { text }, set: { text = $0 }),
      fontSize: 20, color: .white, wraps: true, onCommit: {}, onCancel: {}
    ).frame(width: 112, height: 100))
    let window = NSWindow(
      contentRect: CGRect(x: 0, y: 0, width: 112, height: 100),
      styleMask: [.borderless], backing: .buffered, defer: false
    )
    window.isReleasedWhenClosed = false
    defer { window.close() }
    window.contentView = host
    host.layoutSubtreeIfNeeded()

    func findEditor(in view: NSView) -> NSTextView? {
      if let editor = view as? NSTextView { return editor }
      for child in view.subviews {
        if let editor = findEditor(in: child) { return editor }
      }
      return nil
    }
    let editor = try #require(findEditor(in: host))
    let manager = try #require(editor.layoutManager)
    let container = try #require(editor.textContainer)
    manager.ensureLayout(for: container)
    #expect(container.lineFragmentPadding == 0)
    #expect(abs(container.containerSize.width - 112) < 1)
    let shared = AnnotationTextLayout(text: text, fontSize: 20, color: .white, width: 112)
    #expect(ceil(manager.usedRect(for: container).height) == shared.size.height)
    #expect(editor.allowsUndo)
    editor.setSelectedRange(NSRange(location: editor.string.utf16.count, length: 0))
    editor.insertNewline(nil)
    #expect(editor.string.hasSuffix("\n"))
    #expect(text.hasSuffix("\n"))
    editor.insertText("Second", replacementRange: editor.selectedRange())
    #expect(text.hasSuffix("\nSecond"))
    editor.breakUndoCoalescing()
    let undo = try #require(editor.undoManager)
    #expect(undo.canUndo)
    let edited = text
    undo.undo()
    #expect(text != edited)
    #expect(text == editor.string)
    undo.redo()
    #expect(text == edited)
  }

  @Test("Zoom scales the editor without changing its model-space wrap width")
  func nativeEditorZoom() throws {
    let text = "Several words wrap onto more than one line"
    let host = NSHostingView(rootView: AnnotationTextEditor(
      text: .constant(text), fontSize: 20, color: .white,
      wraps: true, onCommit: {}, onCancel: {}
    )
      .frame(width: 112, height: 100)
      .scaleEffect(0.5, anchor: .topLeading)
      .frame(width: 56, height: 50, alignment: .topLeading))
    let window = NSWindow(
      contentRect: CGRect(x: 0, y: 0, width: 56, height: 50),
      styleMask: [.borderless], backing: .buffered, defer: false
    )
    window.isReleasedWhenClosed = false
    defer { window.close() }
    window.contentView = host
    host.layoutSubtreeIfNeeded()
    func findEditor(in view: NSView) -> NSTextView? {
      if let editor = view as? NSTextView { return editor }
      return view.subviews.lazy.compactMap { findEditor(in: $0) }.first
    }
    let editor = try #require(findEditor(in: host))
    let manager = try #require(editor.layoutManager)
    let container = try #require(editor.textContainer)
    manager.ensureLayout(for: container)
    #expect(abs(container.containerSize.width - 112) < 1)
    let shared = AnnotationTextLayout(text: text, fontSize: 20, color: .white, width: 112)
    #expect(ceil(manager.usedRect(for: container).height) == shared.size.height)
  }

  @Test("Command-Return commits while Escape cancels the native editor")
  func editingKeys() throws {
    let editor = AnnotationTextEditor.EditingTextView()
    var committed = false
    var cancelled = false
    editor.onCommit = { committed = true }
    editor.onCancel = { cancelled = true }
    func event(keyCode: UInt16, modifiers: NSEvent.ModifierFlags) throws -> NSEvent {
      try #require(NSEvent.keyEvent(
        with: .keyDown, location: .zero, modifierFlags: modifiers,
        timestamp: 0, windowNumber: 0, context: nil,
        characters: "", charactersIgnoringModifiers: "", isARepeat: false, keyCode: keyCode
      ))
    }
    editor.keyDown(with: try event(keyCode: 36, modifiers: .command))
    #expect(committed)
    #expect(!cancelled)
    editor.keyDown(with: try event(keyCode: 53, modifiers: []))
    #expect(cancelled)
  }
}
