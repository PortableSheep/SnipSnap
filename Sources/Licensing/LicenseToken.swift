import CryptoKit
import Foundation

struct LicenseToken: Codable {
  var product: String
  var email: String?
  var issuedAt: Int?
  var features: [String]?

  static let expectedProduct = "snipsnap-pro"

  static func verifyAndDecode(_ token: String) -> LicenseToken? {
    // Token format: base64url(payload).base64url(signature)
    let parts = token.split(separator: ".")
    guard parts.count == 2 else { return nil }

    guard let payloadData = Data(base64URLEncoded: String(parts[0])) else { return nil }
    guard let sigData = Data(base64URLEncoded: String(parts[1])) else { return nil }

    // Public key (Curve25519) for production signing.
    // Replace with your real public key when you start issuing licenses.
    // NOTE: This is intentionally a placeholder; without a matching private key, tokens won't validate.
    let publicKeyBase64 = "REPLACE_ME_PUBLIC_KEY_BASE64"

    guard publicKeyBase64 != "REPLACE_ME_PUBLIC_KEY_BASE64" else { return nil }
    guard let pubData = Data(base64Encoded: publicKeyBase64) else { return nil }

    do {
      let pub = try Curve25519.Signing.PublicKey(rawRepresentation: pubData)
      guard pub.isValidSignature(sigData, for: payloadData) else { return nil }

      let decoded = try JSONDecoder().decode(LicenseToken.self, from: payloadData)
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
