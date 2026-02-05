import Foundation

enum RedactionDetector {
  static func detect(in ocrBlocks: [OCRBlock]) -> [RedactionCandidate] {
    var out: [RedactionCandidate] = []

    for block in ocrBlocks {
      let text = block.text

      for match in matches(of: Patterns.email, in: text) {
        out.append(.init(kind: .email, matchedText: match, boundingBox: block.boundingBox))
      }

      for match in matches(of: Patterns.creditCard, in: text) {
        out.append(.init(kind: .creditCard, matchedText: match, boundingBox: block.boundingBox))
      }

      for match in matches(of: Patterns.tokenLike, in: text) {
        out.append(.init(kind: .token, matchedText: match, boundingBox: block.boundingBox))
      }
    }

    // Basic de-dupe
    return Array(Set(out)).sorted { $0.kind.rawValue < $1.kind.rawValue }
  }

  private enum Patterns {
    // Simple + practical patterns; we can expand later.
    static let email = "[A-Z0-9._%+-]+@[A-Z0-9.-]+\\.[A-Z]{2,}" // case-insensitive
    static let creditCard = "(?:\\b\\d[ -]*?){13,19}\\b"
    static let tokenLike = "\\b[A-Za-z0-9_\\-]{24,}\\b"
  }

  private static func matches(of pattern: String, in text: String) -> [String] {
    let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
    let range = NSRange(text.startIndex..<text.endIndex, in: text)
    let matches = regex?.matches(in: text, options: [], range: range) ?? []
    return matches.compactMap { m in
      guard let r = Range(m.range, in: text) else { return nil }
      return String(text[r])
    }
  }
}
