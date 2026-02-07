import Foundation

enum RedactionDetector {
  static func detect(in ocrBlocks: [OCRBlock]) -> [RedactionCandidate] {
    var out: [RedactionCandidate] = []

    for block in ocrBlocks {
      let text = block.text

      // Email addresses
      for match in matches(of: Patterns.email, in: text) {
        out.append(.init(kind: .email, matchedText: match, boundingBox: block.boundingBox))
      }

      // Credit card numbers
      for match in matches(of: Patterns.creditCard, in: text) {
        // Additional validation: check Luhn algorithm
        if isValidCreditCard(match) {
          out.append(.init(kind: .creditCard, matchedText: match, boundingBox: block.boundingBox))
        }
      }

      // Phone numbers (various formats)
      for match in matches(of: Patterns.phoneNumber, in: text) {
        out.append(.init(kind: .phoneNumber, matchedText: match, boundingBox: block.boundingBox))
      }

      // Social Security Numbers (US)
      for match in matches(of: Patterns.ssn, in: text) {
        out.append(.init(kind: .ssn, matchedText: match, boundingBox: block.boundingBox))
      }

      // IP addresses
      for match in matches(of: Patterns.ipAddress, in: text) {
        out.append(.init(kind: .ipAddress, matchedText: match, boundingBox: block.boundingBox))
      }

      // API keys / tokens (long alphanumeric strings)
      for match in matches(of: Patterns.tokenLike, in: text) {
        out.append(.init(kind: .token, matchedText: match, boundingBox: block.boundingBox))
      }

      // Street addresses (basic pattern)
      for match in matches(of: Patterns.streetAddress, in: text) {
        out.append(.init(kind: .address, matchedText: match, boundingBox: block.boundingBox))
      }

      // Dates of birth (various formats)
      for match in matches(of: Patterns.dateOfBirth, in: text) {
        out.append(.init(kind: .dateOfBirth, matchedText: match, boundingBox: block.boundingBox))
      }

      // Account numbers
      for match in matches(of: Patterns.accountNumber, in: text) {
        out.append(.init(kind: .accountNumber, matchedText: match, boundingBox: block.boundingBox))
      }

      // URLs with authentication tokens
      for match in matches(of: Patterns.urlWithToken, in: text) {
        out.append(.init(kind: .token, matchedText: match, boundingBox: block.boundingBox))
      }

      // AWS keys
      for match in matches(of: Patterns.awsAccessKey, in: text) {
        out.append(.init(kind: .token, matchedText: match, boundingBox: block.boundingBox))
      }

      // Private keys
      for match in matches(of: Patterns.privateKey, in: text) {
        out.append(.init(kind: .privateKey, matchedText: match, boundingBox: block.boundingBox))
      }
    }

    // Dedupe and sort
    return Array(Set(out)).sorted { $0.kind.rawValue < $1.kind.rawValue }
  }

  private enum Patterns {
    // Email addresses
    static let email = "[A-Z0-9._%+-]+@[A-Z0-9.-]+\\.[A-Z]{2,}"
    
    // Credit cards (13-19 digits with optional spaces/dashes)
    static let creditCard = "(?:\\b\\d[ -]*?){13,19}\\b"
    
    // Phone numbers (US/international formats)
    static let phoneNumber = "(?:\\+?1[-\\s.]?)?\\(?[0-9]{3}\\)?[-\\s.]?[0-9]{3}[-\\s.]?[0-9]{4}"
    
    // Social Security Numbers (XXX-XX-XXXX)
    static let ssn = "\\b\\d{3}[-\\s]?\\d{2}[-\\s]?\\d{4}\\b"
    
    // IP addresses (IPv4)
    static let ipAddress = "\\b(?:[0-9]{1,3}\\.){3}[0-9]{1,3}\\b"
    
    // API keys and tokens (24+ chars of alphanumeric/underscore/dash)
    static let tokenLike = "\\b[A-Za-z0-9_\\-]{24,}\\b"
    
    // Street addresses (number followed by words)
    static let streetAddress = "\\b\\d{1,5}\\s+[A-Z][a-z]+(?:\\s+[A-Z][a-z]+)*\\s+(?:Street|St|Avenue|Ave|Road|Rd|Boulevard|Blvd|Lane|Ln|Drive|Dr|Court|Ct|Circle|Cir)\\b"
    
    // Dates of birth (MM/DD/YYYY, DD-MM-YYYY, etc.)
    static let dateOfBirth = "\\b(?:0?[1-9]|1[0-2])[/-](?:0?[1-9]|[12][0-9]|3[01])[/-](?:19|20)\\d{2}\\b"
    
    // Account numbers (8-17 digits)
    static let accountNumber = "\\b\\d{8,17}\\b"
    
    // URLs with tokens (http://example.com?token=...)
    static let urlWithToken = "https?://[^\\s]+[?&](?:token|key|api_key|access_token|auth)=[A-Za-z0-9_\\-]+"
    
    // AWS Access Keys (AKIA followed by 16 chars)
    static let awsAccessKey = "\\bAKIA[A-Z0-9]{16}\\b"
    
    // Private keys (BEGIN PRIVATE KEY, etc.)
    static let privateKey = "-----BEGIN(?:\\s+RSA)?\\s+PRIVATE\\s+KEY-----"
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

  /// Luhn algorithm validation for credit card numbers
  private static func isValidCreditCard(_ text: String) -> Bool {
    let digits = text.replacingOccurrences(of: "[\\s-]", with: "", options: .regularExpression)
    
    // Must be 13-19 digits
    guard digits.count >= 13 && digits.count <= 19,
          digits.allSatisfy({ $0.isNumber }) else {
      return false
    }
    
    // Luhn check
    var sum = 0
    var isEven = false
    
    for char in digits.reversed() {
      guard let digit = Int(String(char)) else { return false }
      var current = digit
      
      if isEven {
        current *= 2
        if current > 9 {
          current -= 9
        }
      }
      
      sum += current
      isEven.toggle()
    }
    
    return sum % 10 == 0
  }
}
