import Foundation

// Overlay settings are sent from the main app to the capture agent.
// Keep this type small + Codable.
struct CaptureAgentOverlaySettings: Codable {
  var showClickOverlay: Bool
  var showKeystrokeHUD: Bool
  var showCursor: Bool
  var hudPlacementRaw: String

  // RGBA 0..1
  var ringColorR: Double
  var ringColorG: Double
  var ringColorB: Double
  var ringColorA: Double
}
