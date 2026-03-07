import Foundation
import Testing
@testable import SnipSnap

@Suite("CaptureServiceSettings NSSecureCoding")
struct CaptureServiceSettingsCodingTests {

  private func roundTrip(_ original: CaptureServiceSettings) throws -> CaptureServiceSettings {
    let data = try NSKeyedArchiver.archivedData(withRootObject: original, requiringSecureCoding: true)
    let decoded = try #require(
      try NSKeyedUnarchiver.unarchivedObject(ofClass: CaptureServiceSettings.self, from: data)
    )
    return decoded
  }

  @Test("Default values survive round-trip")
  func defaultValuesRoundTrip() throws {
    let original = CaptureServiceSettings()
    let decoded = try roundTrip(original)

    #expect(decoded.showClickOverlay == true)
    #expect(decoded.showKeystrokeHUD == true)
    #expect(decoded.showCursor == true)
    #expect(decoded.hudPlacementRaw == "bottomCenter")
    #expect(decoded.ringColorR == 1.0)
    #expect(decoded.ringColorG == 1.0)
    #expect(decoded.ringColorB == 1.0)
    #expect(decoded.ringColorA == 1.0)
  }

  @Test("Custom values survive round-trip")
  func customValuesRoundTrip() throws {
    let original = CaptureServiceSettings(
      showClickOverlay: false,
      showKeystrokeHUD: false,
      showCursor: false,
      hudPlacementRaw: "topLeft",
      ringColorR: 0.25,
      ringColorG: 0.5,
      ringColorB: 0.75,
      ringColorA: 0.1
    )
    let decoded = try roundTrip(original)

    #expect(decoded.showClickOverlay == false)
    #expect(decoded.showKeystrokeHUD == false)
    #expect(decoded.showCursor == false)
    #expect(decoded.hudPlacementRaw == "topLeft")
    #expect(decoded.ringColorR == 0.25)
    #expect(decoded.ringColorG == 0.5)
    #expect(decoded.ringColorB == 0.75)
    #expect(decoded.ringColorA == 0.1)
  }

  @Test("supportsSecureCoding is true")
  func supportsSecureCoding() {
    #expect(CaptureServiceSettings.supportsSecureCoding == true)
  }
}

@Suite("CaptureServiceStatus NSSecureCoding")
struct CaptureServiceStatusCodingTests {

  private func roundTrip(_ original: CaptureServiceStatus) throws -> CaptureServiceStatus {
    let data = try NSKeyedArchiver.archivedData(withRootObject: original, requiringSecureCoding: true)
    let decoded = try #require(
      try NSKeyedUnarchiver.unarchivedObject(ofClass: CaptureServiceStatus.self, from: data)
    )
    return decoded
  }

  @Test("Default values survive round-trip")
  func defaultValuesRoundTrip() throws {
    let original = CaptureServiceStatus()
    let decoded = try roundTrip(original)

    #expect(decoded.isRecording == false)
    #expect(decoded.lastCapturePath == nil)
    #expect(decoded.lastRecordingError == nil)
    #expect(decoded.screenRecordingPermissionGranted == false)
  }

  @Test("All fields populated survive round-trip")
  func allFieldsPopulatedRoundTrip() throws {
    let original = CaptureServiceStatus(
      isRecording: true,
      lastCapturePath: "/tmp/capture.mov",
      lastRecordingError: "Permission denied",
      screenRecordingPermissionGranted: true
    )
    let decoded = try roundTrip(original)

    #expect(decoded.isRecording == true)
    #expect(decoded.lastCapturePath == "/tmp/capture.mov")
    #expect(decoded.lastRecordingError == "Permission denied")
    #expect(decoded.screenRecordingPermissionGranted == true)
  }

  @Test("Nil optionals survive round-trip")
  func nilOptionalsRoundTrip() throws {
    let original = CaptureServiceStatus(
      isRecording: true,
      lastCapturePath: nil,
      lastRecordingError: nil,
      screenRecordingPermissionGranted: true
    )
    let decoded = try roundTrip(original)

    #expect(decoded.isRecording == true)
    #expect(decoded.lastCapturePath == nil)
    #expect(decoded.lastRecordingError == nil)
    #expect(decoded.screenRecordingPermissionGranted == true)
  }

  @Test("supportsSecureCoding is true")
  func supportsSecureCoding() {
    #expect(CaptureServiceStatus.supportsSecureCoding == true)
  }
}
