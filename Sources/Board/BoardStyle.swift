import AppKit
import SwiftUI

extension Color {
  /// Parses `#RRGGBB` / `RRGGBB` (alpha optional as `#RRGGBBAA`).
  init?(boardHex hex: String) {
    var s = hex.trimmingCharacters(in: .whitespaces)
    if s.hasPrefix("#") { s.removeFirst() }
    guard s.count == 6 || s.count == 8, let value = UInt64(s, radix: 16) else { return nil }
    let hasAlpha = s.count == 8
    let r = Double((value >> (hasAlpha ? 24 : 16)) & 0xFF) / 255
    let g = Double((value >> (hasAlpha ? 16 : 8)) & 0xFF) / 255
    let b = Double((value >> (hasAlpha ? 8 : 0)) & 0xFF) / 255
    let a = hasAlpha ? Double(value & 0xFF) / 255 : 1
    self.init(.sRGB, red: r, green: g, blue: b, opacity: a)
  }
}

struct BoardThemeStyle {
  var chromeIsDark: Bool { true }
  var textColor: Color { .white }
  var secondaryTextColor: Color { textColor.opacity(0.62) }
  var cardFace: Color { Color(white: 0.16).opacity(0.92) }
  var cardText: Color { .white }
}

/// Full-bleed backdrop for the corkboard overlay.
struct BoardBackdrop: View {
  var body: some View {
    ZStack {
      VisualEffectBlur(material: .hudWindow, blendingMode: .behindWindow)
      LinearGradient(
        colors: [Color.black.opacity(0.35), Color(red: 0.05, green: 0.07, blue: 0.14).opacity(0.55)],
        startPoint: .topLeading, endPoint: .bottomTrailing
      )
      DotGrid(color: .white.opacity(0.06), spacing: 28)
    }
    .environment(\.colorScheme, .dark)
  }
}

struct VisualEffectBlur: NSViewRepresentable {
  var material: NSVisualEffectView.Material
  var blendingMode: NSVisualEffectView.BlendingMode

  func makeNSView(context: Context) -> NSVisualEffectView {
    let view = NSVisualEffectView()
    view.material = material
    view.blendingMode = blendingMode
    view.state = .active
    return view
  }

  func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
    nsView.material = material
    nsView.blendingMode = blendingMode
  }
}

private struct DotGrid: View {
  let color: Color
  let spacing: CGFloat

  var body: some View {
    Canvas { ctx, size in
      var y: CGFloat = spacing / 2
      while y < size.height {
        var x: CGFloat = spacing / 2
        while x < size.width {
          ctx.fill(Path(ellipseIn: CGRect(x: x - 1, y: y - 1, width: 2, height: 2)), with: .color(color))
          x += spacing
        }
        y += spacing
      }
    }
    .allowsHitTesting(false)
  }
}
