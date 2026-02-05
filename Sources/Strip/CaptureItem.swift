import Foundation

struct CaptureItem: Identifiable, Hashable {
  enum Kind: String, Codable {
    case image
    case video
  }

  let id: String
  let kind: Kind
  let url: URL
  let createdAt: Date

  init(url: URL, kind: Kind, createdAt: Date) {
    self.id = url.path
    self.kind = kind
    self.url = url
    self.createdAt = createdAt
  }
}
