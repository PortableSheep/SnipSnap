import AppKit
import Combine
import SwiftUI

@MainActor
final class OverlayPreferencesStore: ObservableObject {
  private enum Keys {
    static let showClickOverlay = "prefs.overlay.showClick"
    static let showKeystrokeHUD = "prefs.overlay.showKeys"
    static let showCursor = "prefs.overlay.showCursor"
    static let hudPlacement = "prefs.overlay.hudPlacement"

    static let clickColorR = "prefs.overlay.clickColor.r"
    static let clickColorG = "prefs.overlay.clickColor.g"
    static let clickColorB = "prefs.overlay.clickColor.b"
    static let clickColorA = "prefs.overlay.clickColor.a"
  }

  @Published var showClickOverlay: Bool {
    didSet { UserDefaults.standard.set(showClickOverlay, forKey: Keys.showClickOverlay) }
  }

  @Published var showKeystrokeHUD: Bool {
    didSet { UserDefaults.standard.set(showKeystrokeHUD, forKey: Keys.showKeystrokeHUD) }
  }

  @Published var showCursor: Bool {
    didSet { UserDefaults.standard.set(showCursor, forKey: Keys.showCursor) }
  }

  @Published var hudPlacement: HUDPlacement {
    didSet { UserDefaults.standard.set(hudPlacement.rawValue, forKey: Keys.hudPlacement) }
  }

  @Published var clickColor: Color {
    didSet { persistClickColor(clickColor) }
  }

  init() {
    showClickOverlay = UserDefaults.standard.object(forKey: Keys.showClickOverlay) as? Bool ?? true
    showKeystrokeHUD = UserDefaults.standard.object(forKey: Keys.showKeystrokeHUD) as? Bool ?? true
    showCursor = UserDefaults.standard.object(forKey: Keys.showCursor) as? Bool ?? true

    let rawPlacement = UserDefaults.standard.string(forKey: Keys.hudPlacement)
    hudPlacement = HUDPlacement(rawValue: rawPlacement ?? HUDPlacement.bottomCenter.rawValue) ?? .bottomCenter

    clickColor = Self.loadClickColor()
  }

  func clickCGColor() -> CGColor {
    let ns = NSColor(clickColor)
      .usingColorSpace(.deviceRGB) ?? .white
    return CGColor(red: ns.redComponent, green: ns.greenComponent, blue: ns.blueComponent, alpha: ns.alphaComponent)
  }

  private func persistClickColor(_ color: Color) {
    let ns = NSColor(color).usingColorSpace(.deviceRGB) ?? .white
    UserDefaults.standard.set(Double(ns.redComponent), forKey: Keys.clickColorR)
    UserDefaults.standard.set(Double(ns.greenComponent), forKey: Keys.clickColorG)
    UserDefaults.standard.set(Double(ns.blueComponent), forKey: Keys.clickColorB)
    UserDefaults.standard.set(Double(ns.alphaComponent), forKey: Keys.clickColorA)
  }

  private static func loadClickColor() -> Color {
    let r = UserDefaults.standard.object(forKey: Keys.clickColorR) as? Double
    let g = UserDefaults.standard.object(forKey: Keys.clickColorG) as? Double
    let b = UserDefaults.standard.object(forKey: Keys.clickColorB) as? Double
    let a = UserDefaults.standard.object(forKey: Keys.clickColorA) as? Double

    if let r, let g, let b {
      return Color(.sRGB, red: r, green: g, blue: b, opacity: a ?? 1.0)
    }
    return Color.white
  }
}
