import Foundation
@testable import SnipSnap

final class MockCaptureService: NSObject, CaptureServiceProtocol {

  // MARK: - Call counts

  var startFullScreenRecordingCallCount = 0
  var startWindowRecordingCallCount = 0
  var startRegionRecordingCallCount = 0
  var stopRecordingCallCount = 0
  var captureRegionScreenshotCallCount = 0
  var captureWindowScreenshotCallCount = 0
  var captureFullScreenScreenshotCallCount = 0
  var requestScreenRecordingPermissionCallCount = 0
  var statusCallCount = 0
  var recordClickEventCallCount = 0
  var recordKeyEventCallCount = 0

  // MARK: - Captured arguments

  var lastSettings: CaptureServiceSettings?
  var lastWindowID: UInt32?
  var lastRegion: (x: Double, y: Double, width: Double, height: Double)?
  var lastClickEvent: (x: Double, y: Double, time: Double)?
  var lastKeyEvent: (text: String, time: Double)?

  // MARK: - Configurable results

  var startFullScreenRecordingResult: (String?, String?) = (nil, nil)
  var startWindowRecordingResult: (String?, String?) = (nil, nil)
  var startRegionRecordingResult: (String?, String?) = (nil, nil)
  var stopRecordingResult: (String?, String?) = (nil, nil)
  var captureRegionScreenshotResult: (String?, String?) = (nil, nil)
  var captureWindowScreenshotResult: (String?, String?) = (nil, nil)
  var captureFullScreenScreenshotResult: (String?, String?) = (nil, nil)
  var requestScreenRecordingPermissionResult: (Bool, String?) = (false, nil)
  var statusResult = CaptureServiceStatus()

  // MARK: - Protocol conformance

  func startFullScreenRecording(settings: CaptureServiceSettings, reply: @escaping (String?, String?) -> Void) {
    startFullScreenRecordingCallCount += 1
    lastSettings = settings
    reply(startFullScreenRecordingResult.0, startFullScreenRecordingResult.1)
  }

  func startWindowRecording(settings: CaptureServiceSettings, windowID: UInt32, reply: @escaping (String?, String?) -> Void) {
    startWindowRecordingCallCount += 1
    lastSettings = settings
    lastWindowID = windowID
    reply(startWindowRecordingResult.0, startWindowRecordingResult.1)
  }

  func startRegionRecording(settings: CaptureServiceSettings, regionX: Double, regionY: Double, regionWidth: Double, regionHeight: Double, reply: @escaping (String?, String?) -> Void) {
    startRegionRecordingCallCount += 1
    lastSettings = settings
    lastRegion = (regionX, regionY, regionWidth, regionHeight)
    reply(startRegionRecordingResult.0, startRegionRecordingResult.1)
  }

  func stopRecording(reply: @escaping (String?, String?) -> Void) {
    stopRecordingCallCount += 1
    reply(stopRecordingResult.0, stopRecordingResult.1)
  }

  func captureRegionScreenshot(reply: @escaping (String?, String?) -> Void) {
    captureRegionScreenshotCallCount += 1
    reply(captureRegionScreenshotResult.0, captureRegionScreenshotResult.1)
  }

  func captureWindowScreenshot(reply: @escaping (String?, String?) -> Void) {
    captureWindowScreenshotCallCount += 1
    reply(captureWindowScreenshotResult.0, captureWindowScreenshotResult.1)
  }

  func captureFullScreenScreenshot(reply: @escaping (String?, String?) -> Void) {
    captureFullScreenScreenshotCallCount += 1
    reply(captureFullScreenScreenshotResult.0, captureFullScreenScreenshotResult.1)
  }

  func requestScreenRecordingPermission(reply: @escaping (Bool, String?) -> Void) {
    requestScreenRecordingPermissionCallCount += 1
    reply(requestScreenRecordingPermissionResult.0, requestScreenRecordingPermissionResult.1)
  }

  func status(reply: @escaping (CaptureServiceStatus) -> Void) {
    statusCallCount += 1
    reply(statusResult)
  }

  func recordClickEvent(x: Double, y: Double, time: Double, reply: @escaping () -> Void) {
    recordClickEventCallCount += 1
    lastClickEvent = (x, y, time)
    reply()
  }

  func recordKeyEvent(text: String, time: Double, reply: @escaping () -> Void) {
    recordKeyEventCallCount += 1
    lastKeyEvent = (text, time)
    reply()
  }

  // MARK: - Reset

  func reset() {
    startFullScreenRecordingCallCount = 0
    startWindowRecordingCallCount = 0
    startRegionRecordingCallCount = 0
    stopRecordingCallCount = 0
    captureRegionScreenshotCallCount = 0
    captureWindowScreenshotCallCount = 0
    captureFullScreenScreenshotCallCount = 0
    requestScreenRecordingPermissionCallCount = 0
    statusCallCount = 0
    recordClickEventCallCount = 0
    recordKeyEventCallCount = 0

    lastSettings = nil
    lastWindowID = nil
    lastRegion = nil
    lastClickEvent = nil
    lastKeyEvent = nil

    startFullScreenRecordingResult = (nil, nil)
    startWindowRecordingResult = (nil, nil)
    startRegionRecordingResult = (nil, nil)
    stopRecordingResult = (nil, nil)
    captureRegionScreenshotResult = (nil, nil)
    captureWindowScreenshotResult = (nil, nil)
    captureFullScreenScreenshotResult = (nil, nil)
    requestScreenRecordingPermissionResult = (false, nil)
    statusResult = CaptureServiceStatus()
  }
}
