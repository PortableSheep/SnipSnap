import CoreGraphics
import Foundation

struct CodableRect: Codable, Hashable {
  var x: Double
  var y: Double
  var width: Double
  var height: Double

  init(x: Double, y: Double, width: Double, height: Double) {
    self.x = x
    self.y = y
    self.width = width
    self.height = height
  }

  init(_ rect: CGRect) {
    self.init(x: rect.origin.x, y: rect.origin.y, width: rect.width, height: rect.height)
  }

  var cgRect: CGRect { CGRect(x: x, y: y, width: width, height: height) }
}

struct BoardViewport: Codable, Hashable {
  var offsetX: Double = 0
  var offsetY: Double = 0
  var scale: Double = 1
}

struct BoardZone: Codable, Identifiable, Hashable {
  var id: UUID = UUID()
  var title: String
  /// Frame in board coordinates (origin top-left).
  var frame: CodableRect
  var colorHex: String
}

enum TodoState: String, Codable, Hashable {
  case open
  case done
}

struct CardSource: Codable, Hashable {
  var appName: String?
  var bundleID: String?
  var pageURL: URL?
  var pageTitle: String?
  var originalCaptureFilename: String?
  var capturedAt: Date
}

struct DetectedItem: Codable, Hashable {
  enum Kind: String, Codable, Hashable {
    case link
    case email
    case phone
  }

  var kind: Kind
  var value: String

  /// URL to open for this item (http link, mailto:, tel:).
  var actionURL: URL? {
    switch kind {
    case .link: return URL(string: value)
    case .email: return URL(string: "mailto:\(value)")
    case .phone:
      let digits = value.filter { $0.isNumber || $0 == "+" }
      return URL(string: "tel:\(digits)")
    }
  }

  var displayText: String {
    guard kind == .link, let url = URL(string: value) else { return value }
    let host = url.host ?? value
    let path = url.path == "/" ? "" : url.path
    let short = host.replacingOccurrences(of: "www.", with: "") + path
    return short.count > 36 ? String(short.prefix(35)) + "…" : short
  }
}

/// Where a popped-out card lives on screen (global AppKit coordinates).
struct PinState: Codable, Hashable {
  var screenFrame: CodableRect
}

struct BoardCard: Codable, Identifiable, Hashable {
  enum Kind: String, Codable, Hashable {
    case capture
    case link
    case text
    case note
  }

  var id: UUID = UUID()
  var kind: Kind

  // Layout (board coordinates, origin top-left).
  var frame: CodableRect
  var rotation: Double = 0
  var zIndex: Int = 0
  var zoneID: UUID?
  var colorHex: String?

  var todo: TodoState?

  // Content
  var title: String?
  var note: String?
  var imageAsset: String?
  var thumbAsset: String?
  var url: URL?
  var faviconAsset: String?
  var previewAsset: String?
  var text: String?

  // Context & derived
  var source: CardSource?
  var ocrText: String?
  var detectedItems: [DetectedItem]?

  var pin: PinState?

  var createdAt: Date = Date()
  var updatedAt: Date = Date()
  var isArchived: Bool = false

  /// Text used for search matching.
  var searchableText: String {
    [title, note, text, url?.absoluteString, ocrText, source?.appName, source?.pageTitle, source?.pageURL?.absoluteString]
      .compactMap { $0 }
      .joined(separator: "\n")
  }

  /// Best text to copy for "Copy Text".
  var copyableText: String? {
    switch kind {
    case .capture: return ocrText
    case .link: return url?.absoluteString
    case .text, .note: return text
    }
  }
}

struct Board: Codable {
  static let currentSchemaVersion = 1

  var schemaVersion: Int = Self.currentSchemaVersion
  var cards: [BoardCard] = []
  var zones: [BoardZone] = []
  var viewport = BoardViewport()
}

enum BoardPalette {
  static let noteColors: [String] = ["#FFE27A", "#FFB3C1", "#A8E6CF", "#A0C4FF", "#E0BBFF", "#FFFFFF"]
  static let zoneColors: [String] = ["#5E9CFF", "#FFB547", "#4CD787", "#C77DFF", "#FF6B6B", "#9AA5B1"]
}
