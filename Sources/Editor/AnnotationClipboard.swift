import AppKit

/// Editable annotations carried alongside the rendered image on the pasteboard, so they
/// can be pasted into another SnipSnap editor while other apps still receive the image.
enum AnnotationClipboard {
  static let type = NSPasteboard.PasteboardType("com.snipsnap.annotations")

  static func encode(_ annotations: [Annotation]) throws -> Data {
    try JSONEncoder().encode(annotations.map(EditorProjectAnnotation.init))
  }

  static func decode(_ data: Data) throws -> [Annotation] {
    try JSONDecoder().decode([EditorProjectAnnotation].self, from: data).map { try $0.annotation() }
  }

  static func annotations(from pasteboard: NSPasteboard = .general) -> [Annotation]? {
    guard let data = pasteboard.data(forType: type),
          let annotations = try? decode(data), !annotations.isEmpty else { return nil }
    return annotations
  }
}
