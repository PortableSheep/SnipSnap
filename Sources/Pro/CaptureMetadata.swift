import Foundation

struct CaptureMetadata: Codable, Hashable {
  static let currentSchemaVersion = 1

  var schemaVersion: Int = Self.currentSchemaVersion
  var createdAt: Date

  /// Full recognized text (best-effort). Nil means “not indexed yet”.
  var ocrText: String?

  /// Coarse OCR blocks (normalized bounding boxes in image coordinates).
  var ocrBlocks: [OCRBlock]?

  /// Smart-redaction suggestions derived from OCR blocks.
  var redactionCandidates: [RedactionCandidate]?
}

struct OCRBlock: Codable, Hashable {
  /// Normalized bounding box in Vision coordinates (origin bottom-left).
  var boundingBox: NormalizedRect
  var text: String
}

struct NormalizedRect: Codable, Hashable {
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
}

enum RedactionKind: String, Codable, Hashable {
  case email
  case creditCard
  case phoneNumber
  case ssn
  case ipAddress
  case token
  case address
  case dateOfBirth
  case accountNumber
  case privateKey
}


struct RedactionCandidate: Codable, Hashable {
  var kind: RedactionKind
  var matchedText: String
  /// Bounding box is coarse (block-level) for now.
  var boundingBox: NormalizedRect
}
