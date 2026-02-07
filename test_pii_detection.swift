#!/usr/bin/env swift

import Foundation

// Minimal test structure
struct NormalizedRect: Codable, Hashable {
  var x: Double
  var y: Double
  var width: Double
  var height: Double
}

struct OCRBlock: Codable, Hashable {
  var boundingBox: NormalizedRect
  var text: String
}

enum RedactionKind: String, Codable, Hashable {
  case email, creditCard, phoneNumber, ssn, ipAddress, token, address, dateOfBirth, accountNumber, privateKey
}

struct RedactionCandidate: Codable, Hashable {
  var kind: RedactionKind
  var matchedText: String
  var boundingBox: NormalizedRect
}

// Test PII detection patterns
let testCases: [(String, RedactionKind?)] = [
  // Emails
  ("My email is john@example.com", .email),
  ("Contact test.user+tag@company.co.uk", .email),
  
  // Credit cards
  ("Card: 4532-1488-0343-6467", .creditCard),
  ("5425 2334 3010 9903", .creditCard),
  ("378282246310005", .creditCard),
  
  // Phone numbers
  ("Call me at (555) 123-4567", .phoneNumber),
  ("+1-555-123-4567", .phoneNumber),
  ("555.123.4567", .phoneNumber),
  
  // SSN
  ("SSN: 123-45-6789", .ssn),
  ("123 45 6789", .ssn),
  
  // IP addresses
  ("Server: 192.168.1.1", .ipAddress),
  ("10.0.0.255", .ipAddress),
  
  // Tokens/API keys
  ("API_KEY: sk_live_51H7xAbCd2efGhIjKlM", .token),
  ("ghp_1234567890abcdefghijklmnopqr", .token),
  
  // AWS keys
  ("AKIAIOSFODNN7EXAMPLE", .token),
  
  // Street addresses
  ("123 Main Street", .address),
  ("4567 Oak Ave", .address),
  
  // Dates of birth
  ("DOB: 03/15/1985", .dateOfBirth),
  ("12-25-1990", .dateOfBirth),
  
  // Account numbers
  ("Account: 123456789012", .accountNumber),
  
  // Private keys
  ("-----BEGIN PRIVATE KEY-----", .privateKey),
  ("-----BEGIN RSA PRIVATE KEY-----", .privateKey),
  
  // URLs with tokens
  ("https://api.example.com?token=abc123xyz", .token),
  
  // Should NOT match
  ("Just some normal text", nil),
  ("123 is a number", nil),
  ("test@", nil),
]

print("🔍 Testing PII Detection Patterns\n")
print("=" * 60)

var passed = 0
var failed = 0

for (text, expectedKind) in testCases {
  let patterns = [
    ("email", "[A-Z0-9._%+-]+@[A-Z0-9.-]+\\.[A-Z]{2,}"),
    ("creditCard", "(?:\\b\\d[ -]*?){13,19}\\b"),
    ("phoneNumber", "(?:\\+?1[-\\s.]?)?\\(?[0-9]{3}\\)?[-\\s.]?[0-9]{3}[-\\s.]?[0-9]{4}"),
    ("ssn", "\\b\\d{3}[-\\s]?\\d{2}[-\\s]?\\d{4}\\b"),
    ("ipAddress", "\\b(?:[0-9]{1,3}\\.){3}[0-9]{1,3}\\b"),
    ("token", "\\b[A-Za-z0-9_\\-]{24,}\\b"),
    ("address", "\\b\\d{1,5}\\s+[A-Z][a-z]+(?:\\s+[A-Z][a-z]+)*\\s+(?:Street|St|Avenue|Ave|Road|Rd|Boulevard|Blvd|Lane|Ln|Drive|Dr|Court|Ct|Circle|Cir)\\b"),
    ("dateOfBirth", "\\b(?:0?[1-9]|1[0-2])[/-](?:0?[1-9]|[12][0-9]|3[01])[/-](?:19|20)\\d{2}\\b"),
    ("accountNumber", "\\b\\d{8,17}\\b"),
    ("privateKey", "-----BEGIN(?:\\s+RSA)?\\s+PRIVATE\\s+KEY-----"),
  ]
  
  var foundMatch = false
  var matchedKind: String? = nil
  
  for (kind, pattern) in patterns {
    if let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) {
      let range = NSRange(text.startIndex..<text.endIndex, in: text)
      if regex.firstMatch(in: text, options: [], range: range) != nil {
        foundMatch = true
        matchedKind = kind
        break
      }
    }
  }
  
  let expected = expectedKind?.rawValue ?? "none"
  let actual = matchedKind ?? "none"
  
  if (foundMatch && expectedKind != nil) || (!foundMatch && expectedKind == nil) {
    print("✅ \"\(text)\"")
    print("   Expected: \(expected), Got: \(actual)")
    passed += 1
  } else {
    print("❌ \"\(text)\"")
    print("   Expected: \(expected), Got: \(actual)")
    failed += 1
  }
  print("")
}

print("=" * 60)
print("\nResults: \(passed) passed, \(failed) failed")

exit(failed > 0 ? 1 : 0)
