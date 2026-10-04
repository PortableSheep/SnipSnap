import AppKit
import SwiftUI

/// Interactive crop box drawn over the editor canvas while `doc.isCropping`.
/// Drag inside to move, drag the handles to resize, drag outside to draw a new box.
struct CropOverlayView: View {
  @ObservedObject var doc: AnnotationDocument
  /// Where the full image is drawn in view coordinates.
  let imageRect: CGRect

  private enum Mode: Equatable {
    case move
    case create
    case handle(dx: Int, dy: Int)
  }

  @State private var mode: Mode?
  @State private var startCrop: CGRect = .zero

  private static let handleHitRadius: CGFloat = 12
  private static let minSize: CGFloat = 8

  private var scale: CGFloat { imageRect.width / max(1, doc.imageSize.width) }

  private func toView(_ r: CGRect) -> CGRect {
    CGRect(
      x: imageRect.minX + r.minX * scale,
      y: imageRect.minY + r.minY * scale,
      width: r.width * scale,
      height: r.height * scale
    )
  }

  private func toImage(_ p: CGPoint) -> CGPoint {
    CGPoint(
      x: min(max(0, (p.x - imageRect.minX) / scale), doc.imageSize.width),
      y: min(max(0, (p.y - imageRect.minY) / scale), doc.imageSize.height)
    )
  }

  var body: some View {
    let box = toView(doc.pendingCrop.standardized)
    ZStack {
      Canvas { context, size in
        var shade = Path(CGRect(origin: .zero, size: size))
        shade.addRect(box)
        context.fill(shade, with: .color(.black.opacity(0.55)), style: FillStyle(eoFill: true))

        var grid = Path()
        for i in 1...2 {
          let x = box.minX + box.width * CGFloat(i) / 3
          let y = box.minY + box.height * CGFloat(i) / 3
          grid.move(to: CGPoint(x: x, y: box.minY)); grid.addLine(to: CGPoint(x: x, y: box.maxY))
          grid.move(to: CGPoint(x: box.minX, y: y)); grid.addLine(to: CGPoint(x: box.maxX, y: y))
        }
        context.stroke(grid, with: .color(.white.opacity(0.35)), lineWidth: 0.75)
        context.stroke(Path(box), with: .color(.white), lineWidth: 1.5)

        for (dx, dy) in Self.handles {
          let c = Self.handlePoint(dx: dx, dy: dy, in: box)
          let isCorner = dx != 0 && dy != 0
          let size = isCorner ? CGSize(width: 12, height: 12) : (dx == 0 ? CGSize(width: 20, height: 6) : CGSize(width: 6, height: 20))
          let r = CGRect(x: c.x - size.width / 2, y: c.y - size.height / 2, width: size.width, height: size.height)
          context.fill(Path(roundedRect: r, cornerRadius: 2), with: .color(.white))
          context.stroke(Path(roundedRect: r, cornerRadius: 2), with: .color(.black.opacity(0.35)), lineWidth: 0.5)
        }
      }
      .contentShape(Rectangle())
      .gesture(dragGesture(box: box))

      VStack {
        Spacer()
        cropBar
          .padding(.bottom, 20)
      }
    }
  }

  private var cropBar: some View {
    let r = AnnotationDocument.normalizedCrop(doc.pendingCrop, in: doc.imageSize) ?? doc.fullImageRect
    return HStack(spacing: 10) {
      Image(systemName: "crop")
        .foregroundStyle(.secondary)
      Text("\(Int(r.width)) × \(Int(r.height))")
        .font(.system(size: 12, weight: .semibold).monospacedDigit())
      Divider().frame(height: 16)
      Button("Reset") { doc.pendingCrop = doc.fullImageRect }
        .help("Select the whole image")
      Button("Cancel") { doc.cancelCrop() }
        .help("Cancel (Esc)")
      Button("Apply") { doc.applyCrop() }
        .buttonStyle(.borderedProminent)
        .help("Apply crop (Return)")
    }
    .controlSize(.small)
    .padding(.horizontal, 14)
    .padding(.vertical, 8)
    .background(.regularMaterial, in: Capsule())
    .overlay(Capsule().strokeBorder(Color.primary.opacity(0.1)))
    .shadow(color: .black.opacity(0.25), radius: 10, y: 4)
  }

  private static let handles: [(Int, Int)] = [(-1, -1), (0, -1), (1, -1), (1, 0), (1, 1), (0, 1), (-1, 1), (-1, 0)]

  private static func handlePoint(dx: Int, dy: Int, in box: CGRect) -> CGPoint {
    CGPoint(
      x: dx < 0 ? box.minX : (dx > 0 ? box.maxX : box.midX),
      y: dy < 0 ? box.minY : (dy > 0 ? box.maxY : box.midY)
    )
  }

  private func hitMode(at p: CGPoint, box: CGRect) -> Mode {
    for (dx, dy) in Self.handles {
      let h = Self.handlePoint(dx: dx, dy: dy, in: box)
      if abs(h.x - p.x) <= Self.handleHitRadius && abs(h.y - p.y) <= Self.handleHitRadius {
        return .handle(dx: dx, dy: dy)
      }
    }
    return box.contains(p) ? .move : .create
  }

  private func dragGesture(box: CGRect) -> some Gesture {
    DragGesture(minimumDistance: 0)
      .onChanged { v in
        if mode == nil {
          mode = hitMode(at: v.startLocation, box: box)
          startCrop = doc.pendingCrop.standardized
        }
        guard let mode else { return }
        let dx = v.translation.width / scale
        let dy = v.translation.height / scale
        let bounds = doc.fullImageRect
        switch mode {
        case .move:
          var r = startCrop.offsetBy(dx: dx, dy: dy)
          r.origin.x = min(max(r.minX, 0), bounds.width - r.width)
          r.origin.y = min(max(r.minY, 0), bounds.height - r.height)
          doc.pendingCrop = r
        case .create:
          let a = toImage(v.startLocation)
          let b = toImage(v.location)
          doc.pendingCrop = CGRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(a.x - b.x), height: abs(a.y - b.y))
        case .handle(let hx, let hy):
          var minX = startCrop.minX, maxX = startCrop.maxX
          var minY = startCrop.minY, maxY = startCrop.maxY
          if hx < 0 { minX = min(max(0, minX + dx), maxX - Self.minSize) }
          if hx > 0 { maxX = max(min(bounds.width, maxX + dx), minX + Self.minSize) }
          if hy < 0 { minY = min(max(0, minY + dy), maxY - Self.minSize) }
          if hy > 0 { maxY = max(min(bounds.height, maxY + dy), minY + Self.minSize) }
          doc.pendingCrop = CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
        }
      }
      .onEnded { _ in
        if mode == .create {
          let r = doc.pendingCrop
          if r.width < Self.minSize || r.height < Self.minSize { doc.pendingCrop = startCrop }
        }
        mode = nil
      }
  }
}
