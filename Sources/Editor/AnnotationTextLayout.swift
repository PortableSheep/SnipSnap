import AppKit
import SwiftUI

struct AnnotationTextLayout {
  static let highlightPadding = CGSize(width: 8, height: 6)
  static let calloutPadding = CGSize(width: 14, height: 12)

  let size: CGSize
  private let storage: NSTextStorage
  private let manager: NSLayoutManager
  private let container: NSTextContainer

  init(text: String, fontSize: CGFloat, color: Color, width: CGFloat? = nil) {
    storage = NSTextStorage(string: text, attributes: [
      .font: NSFont.systemFont(ofSize: fontSize, weight: .semibold),
      .foregroundColor: NSColor(color)
    ])
    manager = NSLayoutManager()
    manager.usesFontLeading = true
    container = NSTextContainer(size: CGSize(
      width: width.map { max(1, $0) } ?? CGFloat.greatestFiniteMagnitude,
      height: CGFloat.greatestFiniteMagnitude
    ))
    container.lineFragmentPadding = 0
    storage.addLayoutManager(manager)
    manager.addTextContainer(container)
    manager.ensureLayout(for: container)
    let used = manager.usedRect(for: container)
    let extra = manager.extraLineFragmentUsedRect
    size = CGSize(
      width: ceil(width.map { max(1, $0) } ?? used.maxX),
      height: ceil(max(used.maxY, extra.maxY))
    )
  }

  func draw(in context: CGContext, at origin: CGPoint, clippingTo clip: CGRect? = nil) {
    context.saveGState()
    defer { context.restoreGState() }
    if let clip { context.clip(to: clip) }
    NSGraphicsContext.saveGraphicsState()
    defer { NSGraphicsContext.restoreGraphicsState() }
    NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: true)
    let range = manager.glyphRange(for: container)
    manager.drawBackground(forGlyphRange: range, at: origin)
    manager.drawGlyphs(forGlyphRange: range, at: origin)
  }

  static func textBounds(_ text: TextAnnotation) -> CGRect {
    let layout = AnnotationTextLayout(text: text.text, fontSize: text.fontSize, color: text.color)
    let padding = text.highlighted ? highlightPadding : .zero
    return CGRect(origin: text.position, size: CGSize(
      width: layout.size.width + padding.width * 2,
      height: layout.size.height + padding.height * 2
    ))
  }

  static func calloutTextRect(_ callout: CalloutAnnotation) -> CGRect {
    CGRect(
      x: callout.rect.minX + calloutPadding.width,
      y: callout.rect.minY + calloutPadding.height,
      width: max(0, callout.rect.width - calloutPadding.width * 2),
      height: max(0, callout.rect.height - calloutPadding.height * 2)
    )
  }

  static func draw(_ text: TextAnnotation, in context: CGContext) {
    let layout = AnnotationTextLayout(text: text.text, fontSize: text.fontSize, color: text.color)
    let padding = text.highlighted ? highlightPadding : .zero
    if text.highlighted {
      context.saveGState()
      context.setFillColor(NSColor(text.highlightColor.opacity(text.highlightOpacity)).cgColor)
      context.addPath(CGPath(
        roundedRect: textBounds(text), cornerWidth: 10, cornerHeight: 10, transform: nil
      ))
      context.fillPath()
      context.restoreGState()
    }
    layout.draw(in: context, at: CGPoint(
      x: text.position.x + padding.width, y: text.position.y + padding.height
    ))
  }

  static func drawText(in callout: CalloutAnnotation, context: CGContext) {
    let rect = calloutTextRect(callout)
    guard rect.width > 0, rect.height > 0 else { return }
    let layout = AnnotationTextLayout(
      text: callout.text, fontSize: callout.fontSize, color: callout.textColor, width: rect.width
    )
    layout.draw(in: context, at: rect.origin, clippingTo: rect)
  }
}
