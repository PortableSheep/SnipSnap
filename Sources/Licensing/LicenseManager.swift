import AppKit
import Foundation

@MainActor
final class LicenseManager: ObservableObject {
  static let shared = LicenseManager()

  @Published private(set) var isProUnlocked: Bool = false
  @Published private(set) var lastValidationError: String? = nil

  private let service = "com.snipsnap.license"
  private let account = "pro"

  private var token: LicenseToken? = nil

  private init() {
    reload()
  }

  func reload() {
    lastValidationError = nil

    #if DEBUG
    if CommandLine.arguments.contains("--pro") {
      isProUnlocked = true
      return
    }
    #endif

    guard let raw = KeychainStore.getString(service: service, account: account) else {
      isProUnlocked = false
      token = nil
      return
    }

    // Developer test keys - works in all builds
    if raw.trimmingCharacters(in: .whitespacesAndNewlines) == "DEV-PRO" ||
       raw.trimmingCharacters(in: .whitespacesAndNewlines) == "SNIPSNAP-PRO-TEST" {
      token = nil
      isProUnlocked = true
      lastValidationError = nil
      return
    }

    if let decoded = LicenseToken.verifyAndDecode(raw) {
      token = decoded
      isProUnlocked = true
    } else {
      token = nil
      isProUnlocked = false
      lastValidationError = "Invalid license key"
    }
  }

  func activate(tokenString: String) -> Bool {
    let trimmed = tokenString.trimmingCharacters(in: .whitespacesAndNewlines)

    // Developer test key - works in all builds for testing
    if trimmed == "DEV-PRO" || trimmed == "SNIPSNAP-PRO-TEST" {
      do {
        try KeychainStore.setString(trimmed, service: service, account: account)
        token = nil
        isProUnlocked = true
        lastValidationError = nil
        return true
      } catch {
        lastValidationError = String(describing: error)
        isProUnlocked = false
        token = nil
        return false
      }
    }

    guard let decoded = LicenseToken.verifyAndDecode(trimmed) else {
      lastValidationError = "Invalid license key"
      isProUnlocked = false
      token = nil
      return false
    }

    do {
      try KeychainStore.setString(trimmed, service: service, account: account)
      token = decoded
      isProUnlocked = true
      lastValidationError = nil
      return true
    } catch {
      lastValidationError = String(describing: error)
      isProUnlocked = false
      token = nil
      return false
    }
  }

  func deactivate() {
    KeychainStore.delete(service: service, account: account)
    token = nil
    isProUnlocked = false
    lastValidationError = nil
  }

  func has(_ feature: ProFeature) -> Bool {
    guard isProUnlocked else { return false }

    // Pay-once own-forever model: Pro unlock grants all Pro features.
    // If later you want per-feature entitlements, read `token?.features` here.
    return true
  }
}
