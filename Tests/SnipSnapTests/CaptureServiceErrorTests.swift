import AppKit
import Foundation
import Testing
@testable import SnipSnap

@Suite("CaptureServiceError")
struct CaptureServiceErrorTests {

  @Test("connectionFailed contains the provided message")
  func connectionFailedDescription() {
    let error = CaptureServiceError.connectionFailed("timeout after 5s")
    let description = error.errorDescription
    #expect(description != nil)
    #expect(description!.contains("timeout after 5s"))
    #expect(description!.contains("Failed to connect to Capture Service"))
  }

  @Test("invalidResponse has a non-nil localized description")
  func invalidResponseDescription() {
    let error = CaptureServiceError.invalidResponse
    #expect(error.errorDescription != nil)
  }

  @Test("remoteError passes through the message as the description")
  func remoteErrorDescription() {
    let message = "Screen recording permission denied"
    let error = CaptureServiceError.remoteError(message)
    #expect(error.errorDescription == message)
  }
}

@Suite("CaptureServiceSettings.from()")
struct CaptureServiceSettingsFromTests {

  @Test("Maps all parameters correctly")
  func mapsAllParameters() {
    let settings = CaptureServiceSettings.from(
      showClickOverlay: false,
      showKeystrokeHUD: true,
      showCursor: false,
      hudPlacement: .bottomCenter,
      clickColor: .red
    )

    #expect(settings.showClickOverlay == false)
    #expect(settings.showKeystrokeHUD == true)
    #expect(settings.showCursor == false)
    #expect(settings.hudPlacementRaw == HUDPlacement.bottomCenter.rawValue)
  }

  @Test("White color produces RGBA (1, 1, 1, 1)")
  func whiteColorComponents() {
    let settings = CaptureServiceSettings.from(
      showClickOverlay: true,
      showKeystrokeHUD: true,
      showCursor: true,
      hudPlacement: .bottomCenter,
      clickColor: .white
    )

    #expect(settings.ringColorR == 1.0)
    #expect(settings.ringColorG == 1.0)
    #expect(settings.ringColorB == 1.0)
    #expect(settings.ringColorA == 1.0)
  }
}

@Suite("CaptureServiceConstants")
struct CaptureServiceConstantsTests {

  @Test("serviceName equals expected Mach service identifier")
  func serviceNameValue() {
    #expect(CaptureServiceConstants.serviceName == "com.snipsnap.CaptureService")
  }
}
