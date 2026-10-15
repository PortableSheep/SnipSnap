import AppKit
import SwiftUI
import Testing
@testable import SnipSnap

@MainActor
@Suite("Annotation arrangement")
struct EditorArrangeTests {
  private func withDocument(_ body: (AnnotationDocument) throws -> Void) throws {
    let url = FileManager.default.temporaryDirectory
      .appendingPathComponent("arrange-\(UUID().uuidString).png")
    let bitmap = try #require(NSBitmapImageRep(
      bitmapDataPlanes: nil, pixelsWide: 64, pixelsHigh: 64,
      bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
      isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    ))
    try #require(bitmap.representation(using: .png, properties: [:])).write(to: url)
    defer { try? FileManager.default.removeItem(at: url) }
    try body(AnnotationDocument(sourceURL: url))
  }

  private func rect(_ x: CGFloat) -> Annotation {
    .rect(RectAnnotation(
      rect: CGRect(x: x, y: 10, width: 12, height: 8),
      stroke: .init(color: .red, lineWidth: 3),
      fill: .init(color: .blue, enabled: true)
    ))
  }

  @Test("Duplicate creates a topmost independent copy with appearance and geometry intact")
  func duplicate() throws {
    try withDocument { doc in
      let original = ArrowAnnotation(
        start: CGPoint(x: 10, y: 20), end: CGPoint(x: 50, y: 20),
        stroke: .init(color: .purple, lineWidth: 6), headStyle: .open,
        bendPoint: CGPoint(x: 30, y: 5)
      )
      let first = rect(0)
      let last = rect(90)
      doc.annotations = [first, .arrow(original), last]
      doc.selectedID = original.id
      doc.markSaved()

      doc.duplicateSelected()
      let copy = try #require(doc.selectedAnnotation)
      guard case .arrow(let duplicated) = copy else {
        Issue.record("Duplicating an arrow should preserve its annotation type")
        return
      }
      #expect(duplicated.id != original.id)
      #expect(duplicated.start == CGPoint(x: 22, y: 32))
      #expect(duplicated.end == CGPoint(x: 62, y: 32))
      #expect(duplicated.bendPoint == CGPoint(x: 42, y: 17))
      #expect(duplicated.stroke == original.stroke)
      #expect(duplicated.headStyle == original.headStyle)
      #expect(doc.annotations.last?.id == duplicated.id)
      #expect(doc.annotations[1] == .arrow(original))
      #expect(doc.hasUnsavedChanges)

      doc.undo()
      #expect(doc.annotations == [first, .arrow(original), last])
      #expect(!doc.hasUnsavedChanges)
      doc.redo()
      #expect(doc.annotations.count == 4)
      #expect(doc.annotations.last?.id == duplicated.id)
    }
  }

  @Test("Duplicate offsets compound geometry while retaining relative style values")
  func duplicateOffsetForOtherKinds() throws {
    try withDocument { doc in
      let original = TextAnnotation(
        position: CGPoint(x: 5, y: 7), text: "Line\nTwo", color: .white,
        fontSize: 20, highlighted: true, highlightOpacity: 0.6
      )
      doc.annotations = [.text(original)]
      doc.selectedID = original.id
      doc.duplicateSelected()
      guard case .text(let first) = try #require(doc.selectedAnnotation) else {
        Issue.record("Duplicated text should remain text")
        return
      }
      doc.duplicateSelected()
      guard case .text(let second) = try #require(doc.selectedAnnotation) else {
        Issue.record("Duplicated text should remain text")
        return
      }
      #expect(first.id != original.id && second.id != first.id)
      #expect(first.position == CGPoint(x: 17, y: 19))
      #expect(second.position == CGPoint(x: 29, y: 31))
      #expect(second.text == original.text)
      #expect(second.fontSize == original.fontSize)
      #expect(second.highlightOpacity == original.highlightOpacity)
    }
  }

  @Test("Layer commands step and jump within paint order and remain undoable")
  func layerOrder() throws {
    try withDocument { doc in
      let first = rect(0)
      let middle = rect(20)
      let last = rect(40)
      doc.annotations = [first, middle, last]
      doc.selectedID = middle.id
      doc.markSaved()

      doc.moveSelectedForward()
      #expect(doc.annotations == [first, last, middle])
      doc.moveSelectedBackward()
      #expect(doc.annotations == [first, middle, last])
      doc.bringSelectedToFront()
      #expect(doc.annotations == [first, last, middle])
      doc.sendSelectedToBack()
      #expect(doc.annotations == [middle, first, last])
      #expect(doc.selectedID == middle.id)
      #expect(doc.hasUnsavedChanges)

      doc.undo()
      #expect(doc.annotations == [first, last, middle])
      doc.undo()
      #expect(doc.annotations == [first, middle, last])
      doc.undo()
      #expect(doc.annotations == [first, last, middle])
      doc.undo()
      #expect(doc.annotations == [first, middle, last])
      #expect(!doc.hasUnsavedChanges)
      doc.redo()
      #expect(doc.annotations == [first, last, middle])
    }
  }

  @Test("Layer commands are safe at order boundaries and without selection")
  func layerBoundaries() throws {
    try withDocument { doc in
      let only = rect(0)
      doc.annotations = [only]
      doc.selectedID = only.id
      doc.markSaved()
      doc.bringSelectedToFront()
      doc.sendSelectedToBack()
      doc.moveSelectedForward()
      doc.moveSelectedBackward()
      #expect(doc.annotations == [only])
      #expect(!doc.hasUnsavedChanges)

      doc.selectedID = nil
      doc.bringSelectedToFront()
      doc.sendSelectedToBack()
      doc.moveSelectedForward()
      doc.moveSelectedBackward()
      doc.duplicateSelected()
      #expect(doc.annotations == [only])
      #expect(!doc.hasUnsavedChanges)
    }
  }

  @Test("Shift-style selection moves, duplicates, reorders, and deletes a group as one undoable edit")
  func multiSelection() throws {
    try withDocument { doc in
      let first = rect(0)
      let middle = rect(20)
      let last = rect(40)
      doc.annotations = [first, middle, last]
      doc.markSaved()

      doc.select(first.id)
      doc.toggleSelection(last.id)
      #expect(doc.selectedIDs == Set([first.id, last.id]))
      #expect(doc.selectedID == last.id)
      #expect(doc.inspectorTool == nil)
      doc.beginEditSessionIfNeeded()
      doc.updateSelectionInSession { annotation in
        switch annotation {
        case .rect(var shape):
          shape.rect = shape.rect.offsetBy(dx: 5, dy: 7)
          annotation = .rect(shape)
        default:
          break
        }
      }
      doc.endEditSession()
      guard case .rect(let movedFirst) = doc.annotations[0],
            case .rect(let unmovedMiddle) = doc.annotations[1],
            case .rect(let movedLast) = doc.annotations[2] else {
        Issue.record("Expected rectangles after grouped movement")
        return
      }
      #expect(movedFirst.rect.origin == CGPoint(x: 5, y: 17))
      #expect(unmovedMiddle.rect.origin == CGPoint(x: 20, y: 10))
      #expect(movedLast.rect.origin == CGPoint(x: 45, y: 17))

      doc.duplicateSelected()
      #expect(doc.annotations.count == 5)
      let copiedIDs = Set(doc.annotations.suffix(2).map(\.id))
      #expect(copiedIDs.count == 2)
      #expect(doc.selectedIDs == copiedIDs)

      doc.sendSelectedToBack()
      #expect(Set(doc.annotations.prefix(2).map(\.id)) == copiedIDs)
      doc.moveSelectedForward()
      #expect(Set(doc.annotations[1...2].map(\.id)) == copiedIDs)
      doc.bringSelectedToFront()
      #expect(Set(doc.annotations.suffix(2).map(\.id)) == copiedIDs)

      doc.deleteSelected()
      #expect(doc.annotations.map(\.id) == [first.id, middle.id, last.id])
      #expect(doc.selectedIDs.isEmpty)
      doc.undo()
      #expect(doc.annotations.count == 5)
      #expect(Set(doc.annotations.suffix(2).map(\.id)) == copiedIDs)
      #expect(doc.hasUnsavedChanges)
    }
  }

  @Test("Moving a selected group is a single undoable edit")
  func groupMoveUndo() throws {
    try withDocument { doc in
      let first = rect(0)
      let middle = rect(20)
      let last = rect(40)
      doc.annotations = [first, middle, last]
      doc.select(first.id)
      doc.toggleSelection(last.id)
      doc.beginEditSessionIfNeeded()
      doc.updateSelectionInSession { annotation in
        guard case .rect(var shape) = annotation else { return }
        shape.rect = shape.rect.offsetBy(dx: 10, dy: -5)
        annotation = .rect(shape)
      }
      doc.endEditSession()

      guard case .rect(let movedFirst) = doc.annotations[0],
            case .rect(let movedLast) = doc.annotations[2] else {
        Issue.record("Expected rectangles after grouped movement")
        return
      }
      #expect(movedFirst.rect.origin == CGPoint(x: 10, y: 5))
      #expect(movedLast.rect.origin == CGPoint(x: 50, y: 5))
      doc.undo()
      #expect(doc.annotations == [first, middle, last])
      doc.redo()
      guard case .rect(let restoredFirst) = doc.annotations[0],
            case .rect(let restoredLast) = doc.annotations[2] else {
        Issue.record("Expected rectangles after restoring grouped movement")
        return
      }
      #expect(restoredFirst.rect.origin == CGPoint(x: 10, y: 5))
      #expect(restoredLast.rect.origin == CGPoint(x: 50, y: 5))
    }
  }

  @Test("Removing a selected member retains remaining selection and direct selection stays singular")
  func selectionMembership() throws {
    try withDocument { doc in
      let first = rect(0)
      let second = rect(20)
      doc.annotations = [first, second]
      doc.select(first.id)
      doc.toggleSelection(second.id)
      doc.toggleSelection(first.id)
      #expect(doc.selectedIDs == [second.id])
      #expect(doc.selectedID == second.id)
      doc.selectedID = first.id
      #expect(doc.selectedIDs == [first.id])
      doc.selectedID = nil
      #expect(doc.selectedIDs.isEmpty)
    }
  }
}
