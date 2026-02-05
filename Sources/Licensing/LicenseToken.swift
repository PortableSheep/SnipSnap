import CryptoKit
import Foundation

struct LicenseToken: Codable {
  var kid: String?  // Key ID for key rotation support
  var product: String
  var email: String?
  var issuedAt: Int?
  var features: [String]?

  static let expectedProduct = "snipsnap-pro"

  // Public keys indexed by key ID. Add new keys here when rotating.
  // Old keys remain so existing licenses continue to work.
  // Format: "kid": "base64-encoded-32-byte-ed25519-public-key"
  private static let publicKeys: [String: String] = [
    // Default key (v1) - replace REPLACE_ME with your actual public key from generate-keys
    "v1": "REPLACE_ME_PUBLIC_KEY_BASE64"
    // When rotating keys, add new entry:
    // "v2": "new-public-key-base64"
  ]

  static func verifyAndDecode(_ token: String) -> LicenseToken? {
    // Token format: base64url(payload).base64url(signature)
    let parts = token.split(separator: ".")
    guard parts.count == 2 else { return nil }

    guard let payloadData = Data(base64URLEncoded: String(parts[0])) else { return nil }
    guard let sigData = Data(base64URLEncoded: String(parts[1])) else { return nil }

    // Decode payload first to get kid
    let decoded: LicenseToken
    do {
      decoded = try JSONDecoder().decode(LicenseToken.self, from: payloadData)
    } catch {
      return nil
    }

    // Look up public key by kid (default to "v1" for backwards compatibility)
    let kid = decoded.kid ?? "v1"
    guard let publicKeyBase64 = publicKeys[kid] else {
      return nil  // Unknown key ID
    }

    // Check for placeholder
    guard publicKeyBase64 != "REPLACE_ME_PUBLIC_KEY_BASE64" else { return nil }
    guard let pubData = Data(base64Encoded: publicKeyBase64) else { return nil }

    do {
      let pub = try Curve25519.Signing.PublicKey(rawRepresentation: pubData)
      guard pub.isValidSignature(sigData, for: payloadData) else { return nil }

      guard decoded.product == expectedProduct else { return nil }
      return decoded

    } catch {
      return nil
    }
  }
}

extension Data {
  init?(base64URLEncoded: String) {
    var s = base64URLEncoded
      .replacingOccurrences(of: "-", with: "+")
      .replacingOccurrences(of: "_", with: "/")

    let pad = 4 - (s.count % 4)
    if pad < 4 {
      s += String(repeating: "=", count: pad)
    }

    self.init(base64Encoded: s)
  }
}
