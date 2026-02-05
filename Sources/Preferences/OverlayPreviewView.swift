import SwiftUI

struct OverlayPreviewView: View {
  @ObservedObject var prefs: OverlayPreferencesStore

  var body: some View {
    ZStack {
      RoundedRectangle(cornerRadius: 8)
        .fill(Color.black.opacity(0.08))

      Canvas { context, size in
        // Mock a pointer location.
        let p = CGPoint(x: size.width * 0.5, y: size.height * 0.4)

        if prefs.showClickOverlay {
          let base: CGFloat = 8
          let gap: CGFloat = 8
          let progress: CGFloat = 0.65

          let r1 = base + progress * 14
          let r2 = r1 + gap

          let color = prefs.clickColor
          let stroke1 = StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round)
          let stroke2 = StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round)

          context.stroke(
            Path(ellipseIn: CGRect(x: p.x - r1, y: p.y - r1, width: r1 * 2, height: r1 * 2)),
            with: .color(color.opacity(0.9)),
            style: stroke1
          )

          context.stroke(
            Path(ellipseIn: CGRect(x: p.x - r2, y: p.y - r2, width: r2 * 2, height: r2 * 2)),
            with: .color(color.opacity(0.75)),
            style: stroke2
          )
        }
      }
      .padding(8)

      if prefs.showKeystrokeHUD {
        let hud = Text("⌘⇧A")
          .font(.system(size: 10, weight: .semibold, design: .rounded))
          .foregroundStyle(Color.white.opacity(0.95))
          .padding(.horizontal, 8)
          .padding(.vertical, 4)
          .background(Color.black.opacity(0.6))
          .clipShape(RoundedRectangle(cornerRadius: 6))

        switch prefs.hudPlacement {
        case .bottomCenter:
          hud
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            .padding(.bottom, 8)
        case .topCenter:
          hud
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .padding(.top, 8)
        case .bottomLeft:
          hud
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
            .padding([.bottom, .leading], 8)
        case .bottomRight:
          hud
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
            .padding([.bottom, .trailing], 8)
        case .topLeft:
          hud
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding([.top, .leading], 8)
        case .topRight:
          hud
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
            .padding([.top, .trailing], 8)
        }
      }
    }
  }
}
