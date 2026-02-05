import AppKit
import Foundation
import SwiftUI

struct RGBAColor: Codable, Hashable {
  var r: Double
  var g: Double
  var b: Double
  var a: Double

  init(r: Double, g: Double, b: Double, a: Double) {
    self.r = r
    self.g = g
    self.b = b
    self.a = a
  }

  init(nsColor: NSColor) {
    let c = nsColor.usingColorSpace(.deviceRGB) ?? nsColor
    self.r = Double(c.redComponent)
    self.g = Double(c.greenComponent)
    self.b = Double(c.blueComponent)
    self.a = Double(c.alphaComponent)
  }

  func toColor() -> Color {
    Color(NSColor(red: r, green: g, blue: b, alpha: a))
  }
}

extension Color {
  func toRGBA(default fallback: RGBAColor = .init(r: 1, g: 1, b: 1, a: 1)) -> RGBAColor {
    let ns = NSColor(self)
    if let rgb = ns.usingColorSpace(.deviceRGB) {
      return RGBAColor(nsColor: rgb)
    }
    return fallback
  }
}
