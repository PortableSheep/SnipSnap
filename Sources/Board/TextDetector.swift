import Foundation

/// Extracts links, email addresses and phone numbers from free text (e.g. OCR output).
///
/// Note: OCR text can't recover hidden hrefs and may mangle URLs that were
/// truncated or wrapped across lines; results are best-effort.
enum TextDetector {
  private static let detector: NSDataDetector? = {
    let types: NSTextCheckingResult.CheckingType = [.link, .phoneNumber]
    return try? NSDataDetector(types: types.rawValue)
  }()

  static func detect(in text: String, limit: Int = 20) -> [DetectedItem] {
    guard let detector, !text.isEmpty else { return [] }
    var seen = Set<String>()
    var items: [DetectedItem] = []

    let range = NSRange(text.startIndex..., in: text)
    detector.enumerateMatches(in: text, options: [], range: range) { match, _, stop in
      guard let match else { return }
      var item: DetectedItem?
      switch match.resultType {
      case .link:
        guard let url = match.url else { break }
        if url.scheme == "mailto" {
          let email = url.absoluteString.replacingOccurrences(of: "mailto:", with: "")
          // Skip things like "user@10.0.0.4" (ssh targets) — require an alphabetic TLD.
          if let tld = email.split(separator: ".").last, tld.count >= 2, tld.allSatisfy(\.isLetter) {
            item = DetectedItem(kind: .email, value: email)
          }
        } else if let scheme = url.scheme, ["http", "https"].contains(scheme) {
          item = DetectedItem(kind: .link, value: url.absoluteString)
        }
      case .phoneNumber:
        if let phone = match.phoneNumber {
          item = DetectedItem(kind: .phone, value: phone)
        }
      default:
        break
      }

      if let item, seen.insert("\(item.kind.rawValue):\(item.value.lowercased())").inserted {
        items.append(item)
        if items.count >= limit { stop.pointee = true }
      }
    }
    return items
  }

  /// Returns a URL if the whole string is a single web URL (used for clipboard/drops).
  static func singleWebURL(in text: String) -> URL? {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty, !trimmed.contains(where: { $0.isWhitespace }) else { return nil }
    if let url = URL(string: trimmed), let scheme = url.scheme?.lowercased(),
       ["http", "https"].contains(scheme), url.host != nil {
      return url
    }
    if trimmed.hasPrefix("www."), let url = URL(string: "https://\(trimmed)"), url.host != nil {
      return url
    }
    return nil
  }
}
