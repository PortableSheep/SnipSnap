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
  let theme: BoardTheme

  /// Tint for chrome (toolbar, zone labels) drawn on top of the backdrop.
  var chromeIsDark: Bool { theme != .paper }

  var textColor: Color { chromeIsDark ? .white : Color(white: 0.12) }
  var secondaryTextColor: Color { textColor.opacity(0.62) }

  /// Paper-like card face used for link/text cards.
  var cardFace: Color {
    switch theme {
    case .glass: return Color(white: 0.16).opacity(0.92)
    case .cork, .felt, .paper: return Color(white: 0.985)
    }
  }

  var cardText: Color {
    theme == .glass ? .white : Color(white: 0.12)
  }

  var usesPushPins: Bool { theme == .cork || theme == .felt }
}

/// Full-bleed backdrop for the corkboard overlay.
struct BoardBackdrop: View {
  let theme: BoardTheme

  var body: some View {
    switch theme {
    case .glass:
      ZStack {
        VisualEffectBlur(material: .hudWindow, blendingMode: .behindWindow)
        LinearGradient(
          colors: [Color.black.opacity(0.35), Color(red: 0.05, green: 0.07, blue: 0.14).opacity(0.55)],
          startPoint: .topLeading, endPoint: .bottomTrailing
        )
        DotGrid(color: .white.opacity(0.06), spacing: 28)
      }
    case .cork:
      ZStack {
        LinearGradient(
          colors: [Color(red: 0.76, green: 0.58, blue: 0.40), Color(red: 0.66, green: 0.47, blue: 0.30)],
          startPoint: .topLeading, endPoint: .bottomTrailing
        )
        Speckle(seed: 7, density: 0.0022, colors: [
          Color(red: 0.45, green: 0.30, blue: 0.17).opacity(0.55),
          Color(red: 0.90, green: 0.75, blue: 0.55).opacity(0.45),
        ])
        RadialGradient(colors: [.clear, .black.opacity(0.28)], center: .center, startRadius: 300, endRadius: 1400)
      }
    case .felt:
      ZStack {
        LinearGradient(
          colors: [Color(red: 0.13, green: 0.30, blue: 0.24), Color(red: 0.08, green: 0.20, blue: 0.17)],
          startPoint: .top, endPoint: .bottom
        )
        Speckle(seed: 3, density: 0.0035, colors: [.white.opacity(0.05), .black.opacity(0.12)])
        RadialGradient(colors: [.clear, .black.opacity(0.35)], center: .center, startRadius: 300, endRadius: 1400)
      }
    case .paper:
      ZStack {
        Color(red: 0.965, green: 0.955, blue: 0.93)
        GridLines(color: Color(red: 0.55, green: 0.65, blue: 0.85).opacity(0.18), spacing: 32)
      }
    }
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

private struct GridLines: View {
  let color: Color
  let spacing: CGFloat

  var body: some View {
    Canvas { ctx, size in
      var path = Path()
      var x: CGFloat = 0
      while x < size.width { path.move(to: CGPoint(x: x, y: 0)); path.addLine(to: CGPoint(x: x, y: size.height)); x += spacing }
      var y: CGFloat = 0
      while y < size.height { path.move(to: CGPoint(x: 0, y: y)); path.addLine(to: CGPoint(x: size.width, y: y)); y += spacing }
      ctx.stroke(path, with: .color(color), lineWidth: 0.5)
    }
    .allowsHitTesting(false)
  }
}

/// Deterministic speckle texture (cheap procedural cork/felt).
private struct Speckle: View {
  let seed: UInt64
  let density: Double
  let colors: [Color]

  var body: some View {
    Canvas { ctx, size in
      var rng = SplitMix64(seed: seed)
      let count = Int(Double(size.width * size.height) * density)
      for i in 0..<count {
        let x = Double(rng.next() % 100_000) / 100_000 * size.width
        let y = Double(rng.next() % 100_000) / 100_000 * size.height
        let r = 0.6 + Double(rng.next() % 100) / 100 * 1.8
        ctx.fill(Path(ellipseIn: CGRect(x: x, y: y, width: r, height: r)), with: .color(colors[i % colors.count]))
      }
    }
    .allowsHitTesting(false)
    .drawingGroup()
  }
}

private struct SplitMix64 {
  var state: UInt64
  init(seed: UInt64) { state = seed }
  mutating func next() -> UInt64 {
    state &+= 0x9E37_79B9_7F4A_7C15
    var z = state
    z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
    z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
    return z ^ (z >> 31)
  }
}

/// A little push-pin head drawn at the top of cards on cork/felt themes.
struct PushPin: View {
  var color: Color = Color(red: 0.92, green: 0.25, blue: 0.25)

  var body: some View {
    ZStack {
      Circle()
        .fill(RadialGradient(colors: [color.opacity(1), color.opacity(0.7)], center: UnitPoint(x: 0.35, y: 0.3), startRadius: 0, endRadius: 9))
        .frame(width: 14, height: 14)
        .shadow(color: .black.opacity(0.45), radius: 1.5, x: 1, y: 2)
      Circle()
        .fill(.white.opacity(0.7))
        .frame(width: 4, height: 4)
        .offset(x: -2.5, y: -2.5)
    }
  }
}
