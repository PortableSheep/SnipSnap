import Foundation

struct ToolCapabilities: OptionSet {
  let rawValue: Int

  static let usesDrag = ToolCapabilities(rawValue: 1 << 0)
  static let clickOnly = ToolCapabilities(rawValue: 1 << 1)
  static let continuousDraw = ToolCapabilities(rawValue: 1 << 2)  // For freehand drawing
}

enum ToolBeginResult {
  case startDrag
  case handled
}

protocol EditorTool {
  var id: AnnotationTool { get }
  var requiredFeature: ProFeature? { get }
  var capabilities: ToolCapabilities { get }

  /// Called on pointer down.
  func begin(doc: AnnotationDocument, at point: CGPoint, isShiftDown: Bool) -> ToolBeginResult

  /// For drag tools: returns a preview annotation during drag.
  func preview(doc: AnnotationDocument, start: CGPoint, current: CGPoint, isShiftDown: Bool) -> Annotation?

  /// For drag tools: commit on pointer up.
  func commit(doc: AnnotationDocument, start: CGPoint, end: CGPoint, isShiftDown: Bool)
}
