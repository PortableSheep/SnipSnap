import AppKit
import CoreGraphics
import CoreText
import Foundation
import SwiftUI
import UniformTypeIdentifiers

enum EditorRenderer {
  /// Renders the base annotated image (without device frame or background)
  static func renderAnnotatedCGImage(doc: AnnotationDocument) -> CGImage? {
    let w = Int(doc.imageSize.width)
    let h = Int(doc.imageSize.height)

    guard let ctx = CGContext(
      data: nil,
      width: w,
      height: h,
      bitsPerComponent: 8,
      bytesPerRow: 0,
      space: CGColorSpaceCreateDeviceRGB(),
      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else {
      return nil
    }

    ctx.interpolationQuality = .high

    // Base image
    ctx.draw(doc.cgImage, in: CGRect(x: 0, y: 0, width: CGFloat(w), height: CGFloat(h)))

    // Blur/pixelate should be applied under other overlays.
    for a in doc.annotations {
      if case .blur = a {
        draw(annotation: a, in: ctx)
      }
    }

    // Collect all spotlights and draw them as a single combined dimming layer
    let spotlights = doc.annotations.compactMap { a -> SpotlightAnnotation? in
      if case .spotlight(let sp) = a { return sp }
      return nil
    }
    if !spotlights.isEmpty {
      drawCombinedSpotlights(spotlights, imageSize: doc.imageSize, in: ctx)
    }

    // Draw all other overlays (skip blur and spotlight, already drawn)
    for a in doc.annotations {
      if case .blur = a { continue }
      if case .spotlight = a { continue }
      draw(annotation: a, in: ctx)
    }

    return ctx.makeImage()
  }

  /// Renders the final export image with device frame and background
  static func renderFinalExport(doc: AnnotationDocument) -> CGImage? {
    guard let annotatedImage = renderAnnotatedCGImage(doc: doc) else { return nil }

    // If no background or device frame, return simple annotated image
    if doc.backgroundStyle == .none && doc.deviceFrame == .none {
      return annotatedImage
    }

    let imageW = CGFloat(annotatedImage.width)
    let imageH = CGFloat(annotatedImage.height)
    let padding = doc.backgroundStyle != .none ? doc.backgroundPadding : 0
    let cornerRadius = doc.backgroundCornerRadius
    let hasDeviceFrame = doc.deviceFrame != .none

    // Calculate device frame dimensions if applicable
    let (frameImageRect, frameRect, totalSize) = calculateFrameDimensions(
      imageSize: CGSize(width: imageW, height: imageH),
      deviceFrame: doc.deviceFrame,
      padding: padding
    )

    let finalW = Int(totalSize.width)
    let finalH = Int(totalSize.height)

    guard let ctx = CGContext(
      data: nil,
      width: finalW,
      height: finalH,
      bitsPerComponent: 8,
      bytesPerRow: 0,
      space: CGColorSpaceCreateDeviceRGB(),
      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else {
      return nil
    }

    ctx.interpolationQuality = .high

    // Draw background
    drawBackground(doc: doc, size: totalSize, in: ctx)

    // Draw shadow under the content (if enabled)
    if doc.backgroundShadowEnabled && doc.backgroundStyle != .none {
      ctx.saveGState()
      let shadowRect = hasDeviceFrame ? frameRect : frameImageRect
      ctx.setShadow(
        offset: CGSize(width: 0, height: -4),
        blur: doc.backgroundShadowRadius,
        color: CGColor(gray: 0, alpha: doc.backgroundShadowOpacity)
      )
      let shadowPath = CGPath(roundedRect: shadowRect, cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil)
      ctx.addPath(shadowPath)
      ctx.setFillColor(CGColor.white)
      ctx.fillPath()
      ctx.restoreGState()
    }

    // Draw device frame or rounded image
    if hasDeviceFrame {
      drawDeviceFrame(
        frame: doc.deviceFrame,
        frameColor: doc.deviceFrameColor,
        customColor: doc.deviceFrameCustomColor,
        frameRect: frameRect,
        imageRect: frameImageRect,
        image: annotatedImage,
        in: ctx
      )
    } else {
      // Just draw the image with rounded corners
      ctx.saveGState()
      let clipPath = CGPath(roundedRect: frameImageRect, cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil)
      ctx.addPath(clipPath)
      ctx.clip()
      ctx.draw(annotatedImage, in: frameImageRect)
      ctx.restoreGState()
    }

    return ctx.makeImage()
  }

  /// Calculate frame dimensions based on device type
  private static func calculateFrameDimensions(
    imageSize: CGSize,
    deviceFrame: DeviceFrame,
    padding: CGFloat
  ) -> (imageRect: CGRect, frameRect: CGRect, totalSize: CGSize) {
    let imageW = imageSize.width
    let imageH = imageSize.height

    if deviceFrame == .none {
      let totalW = imageW + padding * 2
      let totalH = imageH + padding * 2
      let imageRect = CGRect(x: padding, y: padding, width: imageW, height: imageH)
      return (imageRect, imageRect, CGSize(width: totalW, height: totalH))
    }

    // Calculate bezel sizes based on device type
    let bezelSize: (top: CGFloat, bottom: CGFloat, left: CGFloat, right: CGFloat)
    switch deviceFrame {
    case .none:
      bezelSize = (0, 0, 0, 0)
    case .iPhonePro, .iPhoneProMax, .iPhoneSE:
      let bezelWidth = imageW * 0.04
      bezelSize = (bezelWidth * 2, bezelWidth * 2, bezelWidth, bezelWidth)
    case .iPadPro11, .iPadPro13:
      let bezelWidth = imageW * 0.025
      bezelSize = (bezelWidth, bezelWidth, bezelWidth, bezelWidth)
    case .macBookPro14, .macBookAir:
      let topBezel = imageH * 0.03  // Notch/camera area
      let bottomBezel = imageH * 0.08  // Keyboard hinge
      let sideBezel = imageW * 0.02
      bezelSize = (topBezel, bottomBezel, sideBezel, sideBezel)
    case .studioDisplay:
      let bezelWidth = imageW * 0.015
      let bottomBezel = imageH * 0.04  // Stand/chin
      bezelSize = (bezelWidth, bottomBezel, bezelWidth, bezelWidth)
    case .browser:
      let topBar = min(36, imageH * 0.04)
      bezelSize = (topBar, 2, 2, 2)
    case .window:
      let titleBar = min(28, imageH * 0.035)
      bezelSize = (titleBar, 2, 2, 2)
    }

    let frameW = imageW + bezelSize.left + bezelSize.right
    let frameH = imageH + bezelSize.top + bezelSize.bottom
    let totalW = frameW + padding * 2
    let totalH = frameH + padding * 2

    let frameRect = CGRect(x: padding, y: padding, width: frameW, height: frameH)
    let imageRect = CGRect(
      x: padding + bezelSize.left,
      y: padding + bezelSize.bottom,  // CGContext is flipped
      width: imageW,
      height: imageH
    )

    return (imageRect, frameRect, CGSize(width: totalW, height: totalH))
  }

  /// Draw the background
  private static func drawBackground(doc: AnnotationDocument, size: CGSize, in ctx: CGContext) {
    let rect = CGRect(origin: .zero, size: size)

    switch doc.backgroundStyle {
    case .none:
      // Transparent
      ctx.setFillColor(CGColor(gray: 0, alpha: 0))
      ctx.fill(rect)

    case .solid:
      ctx.setFillColor(cgColor(doc.backgroundColor))
      ctx.fill(rect)

    case .gradient:
      let colors = [cgColor(doc.backgroundGradientStart), cgColor(doc.backgroundGradientEnd)] as CFArray
      guard let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1]) else { return }

      switch doc.backgroundGradientDirection {
      case .topToBottom:
        ctx.drawLinearGradient(gradient, start: CGPoint(x: size.width / 2, y: size.height), end: CGPoint(x: size.width / 2, y: 0), options: [])
      case .leftToRight:
        ctx.drawLinearGradient(gradient, start: CGPoint(x: 0, y: size.height / 2), end: CGPoint(x: size.width, y: size.height / 2), options: [])
      case .topLeftToBottomRight:
        ctx.drawLinearGradient(gradient, start: CGPoint(x: 0, y: size.height), end: CGPoint(x: size.width, y: 0), options: [])
      case .radial:
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let radius = max(size.width, size.height) * 0.7
        ctx.drawRadialGradient(gradient, startCenter: center, startRadius: 0, endCenter: center, endRadius: radius, options: .drawsAfterEndLocation)
      }

    case .mesh:
      // Simplified mesh - create a 4-color gradient effect
      let colors = [
        cgColor(doc.backgroundGradientStart),
        cgColor(doc.backgroundGradientEnd),
        cgColor(doc.backgroundGradientStart.opacity(0.8)),
        cgColor(doc.backgroundGradientEnd.opacity(0.8))
      ] as CFArray
      guard let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 0.33, 0.66, 1]) else { return }
      ctx.drawLinearGradient(gradient, start: CGPoint(x: 0, y: size.height), end: CGPoint(x: size.width, y: 0), options: [])
      
    case .wallpaper:
      // Draw desktop wallpaper as background
      if let wallpaper = doc.getWallpaper(),
         let cgImage = wallpaper.cgImage(forProposedRect: nil, context: nil, hints: nil) {
        // Scale wallpaper to fill the canvas while maintaining aspect ratio
        let wallpaperSize = CGSize(width: cgImage.width, height: cgImage.height)
        let scaleX = size.width / wallpaperSize.width
        let scaleY = size.height / wallpaperSize.height
        let scale = max(scaleX, scaleY)
        
        let scaledWidth = wallpaperSize.width * scale
        let scaledHeight = wallpaperSize.height * scale
        
        let x = (size.width - scaledWidth) / 2
        let y = (size.height - scaledHeight) / 2
        
        let drawRect = CGRect(x: x, y: y, width: scaledWidth, height: scaledHeight)
        ctx.draw(cgImage, in: drawRect)
      } else {
        // Fallback to gray if wallpaper can't be loaded
        ctx.setFillColor(CGColor(gray: 0.9, alpha: 1))
        ctx.fill(rect)
      }
    }
  }

  /// Draw device frame
  private static func drawDeviceFrame(
    frame: DeviceFrame,
    frameColor: DeviceFrameColor,
    customColor: Color,
    frameRect: CGRect,
    imageRect: CGRect,
    image: CGImage,
    in ctx: CGContext
  ) {
    let bezelColor: CGColor
    switch frameColor {
    case .black: bezelColor = CGColor(gray: 0.12, alpha: 1)
    case .silver: bezelColor = CGColor(gray: 0.85, alpha: 1)
    case .gold: bezelColor = CGColor(red: 0.87, green: 0.78, blue: 0.65, alpha: 1)
    case .custom: bezelColor = cgColor(customColor)
    }

    switch frame {
    case .none:
      ctx.draw(image, in: imageRect)

    case .iPhonePro, .iPhoneProMax, .iPhoneSE:
      // Draw phone body with rounded corners
      let cornerRadius = min(frameRect.width, frameRect.height) * 0.12
      let framePath = CGPath(roundedRect: frameRect, cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil)

      // Frame body
      ctx.setFillColor(bezelColor)
      ctx.addPath(framePath)
      ctx.fillPath()

      // Screen (slightly inset with rounded corners)
      let screenCornerRadius = cornerRadius * 0.8
      let screenPath = CGPath(roundedRect: imageRect, cornerWidth: screenCornerRadius, cornerHeight: screenCornerRadius, transform: nil)
      ctx.saveGState()
      ctx.addPath(screenPath)
      ctx.clip()
      ctx.draw(image, in: imageRect)
      ctx.restoreGState()

      // Dynamic Island / Notch (for Pro models)
      if frame == .iPhonePro || frame == .iPhoneProMax {
        let islandWidth = imageRect.width * 0.35
        let islandHeight = imageRect.height * 0.035
        let islandRect = CGRect(
          x: imageRect.midX - islandWidth / 2,
          y: imageRect.maxY - islandHeight - 8,
          width: islandWidth,
          height: islandHeight
        )
        let islandPath = CGPath(roundedRect: islandRect, cornerWidth: islandHeight / 2, cornerHeight: islandHeight / 2, transform: nil)
        ctx.setFillColor(CGColor(gray: 0.05, alpha: 1))
        ctx.addPath(islandPath)
        ctx.fillPath()
      }

    case .iPadPro11, .iPadPro13:
      // iPad with rounded corners
      let cornerRadius = min(frameRect.width, frameRect.height) * 0.04
      let framePath = CGPath(roundedRect: frameRect, cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil)

      ctx.setFillColor(bezelColor)
      ctx.addPath(framePath)
      ctx.fillPath()

      // Screen
      let screenCornerRadius = cornerRadius * 0.5
      let screenPath = CGPath(roundedRect: imageRect, cornerWidth: screenCornerRadius, cornerHeight: screenCornerRadius, transform: nil)
      ctx.saveGState()
      ctx.addPath(screenPath)
      ctx.clip()
      ctx.draw(image, in: imageRect)
      ctx.restoreGState()

    case .macBookPro14, .macBookAir:
      // MacBook with display and base
      let displayRect = CGRect(
        x: frameRect.minX,
        y: frameRect.minY + frameRect.height * 0.08,
        width: frameRect.width,
        height: frameRect.height * 0.92
      )
      let baseRect = CGRect(
        x: frameRect.minX - frameRect.width * 0.02,
        y: frameRect.minY,
        width: frameRect.width * 1.04,
        height: frameRect.height * 0.08
      )

      // Display bezel
      let displayCornerRadius = min(displayRect.width, displayRect.height) * 0.02
      let displayPath = CGPath(roundedRect: displayRect, cornerWidth: displayCornerRadius, cornerHeight: displayCornerRadius, transform: nil)
      ctx.setFillColor(bezelColor)
      ctx.addPath(displayPath)
      ctx.fillPath()

      // Base/keyboard area
      let baseCornerRadius: CGFloat = 4
      let basePath = CGPath(roundedRect: baseRect, cornerWidth: baseCornerRadius, cornerHeight: baseCornerRadius, transform: nil)
      ctx.setFillColor(CGColor(gray: 0.75, alpha: 1))
      ctx.addPath(basePath)
      ctx.fillPath()

      // Screen
      ctx.draw(image, in: imageRect)

      // Notch (for MacBook Pro)
      if frame == .macBookPro14 {
        let notchWidth = imageRect.width * 0.15
        let notchHeight = imageRect.height * 0.025
        let notchRect = CGRect(
          x: imageRect.midX - notchWidth / 2,
          y: imageRect.maxY - notchHeight,
          width: notchWidth,
          height: notchHeight
        )
        ctx.setFillColor(bezelColor)
        ctx.fill(notchRect)
      }

    case .studioDisplay:
      // Studio Display with thin bezels and stand
      let displayCornerRadius: CGFloat = 8
      let displayPath = CGPath(roundedRect: frameRect, cornerWidth: displayCornerRadius, cornerHeight: displayCornerRadius, transform: nil)
      ctx.setFillColor(bezelColor)
      ctx.addPath(displayPath)
      ctx.fillPath()

      // Screen
      ctx.draw(image, in: imageRect)

      // Stand (simplified)
      let standWidth = frameRect.width * 0.3
      let standHeight = frameRect.height * 0.15
      let standRect = CGRect(
        x: frameRect.midX - standWidth / 2,
        y: frameRect.minY - standHeight + 4,
        width: standWidth,
        height: standHeight
      )
      ctx.setFillColor(CGColor(gray: 0.7, alpha: 1))
      ctx.fill(standRect)

    case .browser:
      // Browser window with toolbar
      let cornerRadius: CGFloat = 10
      let framePath = CGPath(roundedRect: frameRect, cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil)

      // Window background
      ctx.setFillColor(CGColor(gray: 0.95, alpha: 1))
      ctx.addPath(framePath)
      ctx.fillPath()

      // Title bar
      let titleBarRect = CGRect(
        x: frameRect.minX,
        y: frameRect.maxY - 36,
        width: frameRect.width,
        height: 36
      )
      ctx.setFillColor(CGColor(gray: 0.92, alpha: 1))
      ctx.fill(titleBarRect)

      // Traffic lights
      let lightRadius: CGFloat = 6
      let lightY = titleBarRect.midY
      let lightColors: [CGColor] = [
        CGColor(red: 1, green: 0.38, blue: 0.35, alpha: 1),  // Red
        CGColor(red: 1, green: 0.78, blue: 0.25, alpha: 1),  // Yellow
        CGColor(red: 0.15, green: 0.8, blue: 0.25, alpha: 1)  // Green
      ]
      for (i, color) in lightColors.enumerated() {
        let x = frameRect.minX + 16 + CGFloat(i) * 20
        ctx.setFillColor(color)
        ctx.fillEllipse(in: CGRect(x: x - lightRadius, y: lightY - lightRadius, width: lightRadius * 2, height: lightRadius * 2))
      }

      // URL bar
      let urlBarRect = CGRect(
        x: frameRect.minX + 80,
        y: titleBarRect.minY + 8,
        width: frameRect.width - 160,
        height: 20
      )
      ctx.setFillColor(CGColor(gray: 0.98, alpha: 1))
      let urlBarPath = CGPath(roundedRect: urlBarRect, cornerWidth: 4, cornerHeight: 4, transform: nil)
      ctx.addPath(urlBarPath)
      ctx.fillPath()

      // Content
      ctx.draw(image, in: imageRect)

    case .window:
      // macOS window
      let cornerRadius: CGFloat = 10
      let framePath = CGPath(roundedRect: frameRect, cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil)

      // Window background
      ctx.setFillColor(CGColor(gray: 0.97, alpha: 1))
      ctx.addPath(framePath)
      ctx.fillPath()

      // Title bar
      let titleBarRect = CGRect(
        x: frameRect.minX,
        y: frameRect.maxY - 28,
        width: frameRect.width,
        height: 28
      )
      ctx.setFillColor(CGColor(gray: 0.95, alpha: 1))
      ctx.fill(titleBarRect)

      // Traffic lights
      let lightRadius: CGFloat = 6
      let lightY = titleBarRect.midY
      let lightColors: [CGColor] = [
        CGColor(red: 1, green: 0.38, blue: 0.35, alpha: 1),
        CGColor(red: 1, green: 0.78, blue: 0.25, alpha: 1),
        CGColor(red: 0.15, green: 0.8, blue: 0.25, alpha: 1)
      ]
      for (i, color) in lightColors.enumerated() {
        let x = frameRect.minX + 14 + CGFloat(i) * 20
        ctx.setFillColor(color)
        ctx.fillEllipse(in: CGRect(x: x - lightRadius, y: lightY - lightRadius, width: lightRadius * 2, height: lightRadius * 2))
      }

      // Content
      ctx.draw(image, in: imageRect)
    }
  }

  static func copyToClipboard(doc: AnnotationDocument) {
    guard let cg = renderFinalExport(doc: doc) else { return }
    let img = NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))

    NSPasteboard.general.clearContents()
    NSPasteboard.general.writeObjects([img])
  }

  static func exportPNGNextToSource(doc: AnnotationDocument) throws -> URL {
    guard let cg = renderFinalExport(doc: doc) else {
      throw NSError(domain: "SnipSnap", code: 10, userInfo: [NSLocalizedDescriptionKey: "Failed to render export"])
    }

    let outURL = doc.sourceURL
      .deletingPathExtension()
      .appendingPathExtension("annotated.png")

    let rep = NSBitmapImageRep(cgImage: cg)
    guard let data = rep.representation(using: .png, properties: [:]) else {
      throw NSError(domain: "SnipSnap", code: 11, userInfo: [NSLocalizedDescriptionKey: "Failed to encode PNG"])
    }
    try data.write(to: outURL, options: [.atomic])
    return outURL
  }

  // MARK: - Extended Export Options

  enum ExportFormat: String, CaseIterable, Identifiable {
    case png
    case jpeg
    case tiff
    case heic

    var id: String { rawValue }

    var label: String {
      switch self {
      case .png: return "PNG"
      case .jpeg: return "JPEG"
      case .tiff: return "TIFF"
      case .heic: return "HEIC"
      }
    }

    var fileExtension: String { rawValue }

    var utType: UTType {
      switch self {
      case .png: return .png
      case .jpeg: return .jpeg
      case .tiff: return .tiff
      case .heic: return .heic
      }
    }

    var bitmapType: NSBitmapImageRep.FileType {
      switch self {
      case .png: return .png
      case .jpeg: return .jpeg
      case .tiff: return .tiff
      case .heic: return .png  // HEIC needs special handling
      }
    }
  }

  /// Export to a specific format with quality option
  static func export(doc: AnnotationDocument, format: ExportFormat, quality: CGFloat = 0.9) throws -> Data {
    guard let cg = renderFinalExport(doc: doc) else {
      throw NSError(domain: "SnipSnap", code: 10, userInfo: [NSLocalizedDescriptionKey: "Failed to render export"])
    }

    let rep = NSBitmapImageRep(cgImage: cg)

    var properties: [NSBitmapImageRep.PropertyKey: Any] = [:]
    if format == .jpeg {
      properties[.compressionFactor] = quality
    }

    // HEIC requires special handling via CIContext
    if format == .heic {
      let ciImage = CIImage(cgImage: cg)
      let context = CIContext()
      guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
            let data = context.heifRepresentation(of: ciImage, format: .RGBA8, colorSpace: colorSpace, options: [kCGImageDestinationLossyCompressionQuality as CIImageRepresentationOption: quality]) else {
        throw NSError(domain: "SnipSnap", code: 12, userInfo: [NSLocalizedDescriptionKey: "Failed to encode HEIC"])
      }
      return data
    }

    guard let data = rep.representation(using: format.bitmapType, properties: properties) else {
      throw NSError(domain: "SnipSnap", code: 11, userInfo: [NSLocalizedDescriptionKey: "Failed to encode \(format.label)"])
    }
    return data
  }

  /// Export with save panel
  static func exportWithSavePanel(doc: AnnotationDocument, format: ExportFormat, quality: CGFloat = 0.9) throws -> URL? {
    let data = try export(doc: doc, format: format, quality: quality)

    let savePanel = NSSavePanel()
    savePanel.allowedContentTypes = [format.utType]
    savePanel.nameFieldStringValue = doc.sourceURL
      .deletingPathExtension()
      .appendingPathExtension("annotated")
      .appendingPathExtension(format.fileExtension)
      .lastPathComponent

    guard savePanel.runModal() == .OK, let url = savePanel.url else {
      return nil
    }

    try data.write(to: url, options: [.atomic])
    return url
  }

  /// Get NSImage for sharing services
  static func renderNSImage(doc: AnnotationDocument) -> NSImage? {
    guard let cg = renderFinalExport(doc: doc) else { return nil }
    return NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
  }

  /// Share using system share sheet
  static func share(doc: AnnotationDocument, from view: NSView) {
    guard let image = renderNSImage(doc: doc) else { return }

    let picker = NSSharingServicePicker(items: [image])
    picker.show(relativeTo: .zero, of: view, preferredEdge: .minY)
  }

  /// Quick share to specific service
  static func shareToService(doc: AnnotationDocument, serviceName: NSSharingService.Name) {
    guard let image = renderNSImage(doc: doc) else { return }
    guard let service = NSSharingService(named: serviceName) else { return }
    service.perform(withItems: [image])
  }

  private static func draw(annotation: Annotation, in ctx: CGContext) {
    switch annotation {
    case .rect(let r):
      drawRect(r, in: ctx)
    case .line(let l):
      drawLine(l, in: ctx)
    case .arrow(let a):
      drawArrow(a, in: ctx)
    case .freehand(let f):
      drawFreehand(f, in: ctx)
    case .text(let t):
      drawText(t, in: ctx)
    case .callout(let c):
      drawCallout(c, in: ctx)
    case .blur(let b):
      drawBlur(b, in: ctx)
    case .spotlight(let sp):
      drawSpotlight(sp, imageSize: ctx.boundingBoxOfClipPath.size, in: ctx)
    case .step(let s):
      drawStep(s, in: ctx)
    case .counter(let c):
      drawCounter(c, in: ctx)
    case .emoji(let e):
      drawEmoji(e, in: ctx)
    case .measurement(let m):
      drawMeasurement(m, in: ctx)
    }
  }

  private static func cgColor(_ color: Color, alpha: CGFloat = 1) -> CGColor {
    let ns = NSColor(color).usingColorSpace(.deviceRGB) ?? .white
    return CGColor(red: ns.redComponent, green: ns.greenComponent, blue: ns.blueComponent, alpha: ns.alphaComponent * alpha)
  }

  private static func drawRect(_ r: RectAnnotation, in ctx: CGContext) {
    if r.fill.enabled {
      ctx.setFillColor(cgColor(r.fill.color))
      ctx.fill(r.rect)
    }

    ctx.setStrokeColor(cgColor(r.stroke.color))
    ctx.setLineWidth(r.stroke.lineWidth)
    ctx.stroke(r.rect)
  }

  private static func drawArrow(_ a: ArrowAnnotation, in ctx: CGContext) {
    ctx.setStrokeColor(cgColor(a.stroke.color))
    ctx.setLineWidth(a.stroke.lineWidth)
    ctx.setLineCap(.round)

    ctx.move(to: a.start)
    ctx.addLine(to: a.end)
    ctx.strokePath()

    // Arrow head
    if a.headStyle == .none { return }

    let angle = atan2(a.end.y - a.start.y, a.end.x - a.start.x)
    let headLen: CGFloat = max(12, a.stroke.lineWidth * 3)
    let headAngle: CGFloat = .pi / 8

    let p1 = CGPoint(
      x: a.end.x - headLen * cos(angle - headAngle),
      y: a.end.y - headLen * sin(angle - headAngle)
    )
    let p2 = CGPoint(
      x: a.end.x - headLen * cos(angle + headAngle),
      y: a.end.y - headLen * sin(angle + headAngle)
    )

    ctx.setLineJoin(.round)

    switch a.headStyle {
    case .open:
      ctx.move(to: p1)
      ctx.addLine(to: a.end)
      ctx.addLine(to: p2)
      ctx.strokePath()
    case .filled:
      ctx.setFillColor(cgColor(a.stroke.color))
      ctx.beginPath()
      ctx.move(to: a.end)
      ctx.addLine(to: p1)
      ctx.addLine(to: p2)
      ctx.closePath()
      ctx.fillPath()
    case .none:
      break
    }
  }

  private static func drawText(_ t: TextAnnotation, in ctx: CGContext) {
    let font = CTFontCreateWithName("SFProText-Semibold" as CFString, t.fontSize, nil)
    let attrs: [NSAttributedString.Key: Any] = [
      kCTFontAttributeName as NSAttributedString.Key: font,
      kCTForegroundColorAttributeName as NSAttributedString.Key: cgColor(t.color)
    ]

    let attributed = NSAttributedString(string: t.text, attributes: attrs)
    let line = CTLineCreateWithAttributedString(attributed)
    let bounds = CTLineGetBoundsWithOptions(line, [])

    let padX: CGFloat = 10
    let padY: CGFloat = 6

    if t.highlighted {
      let rect = CGRect(
        x: t.position.x - padX,
        y: t.position.y - bounds.height - padY,
        width: bounds.width + padX * 2,
        height: bounds.height + padY * 2
      )
      ctx.setFillColor(cgColor(t.highlightColor, alpha: t.highlightOpacity))
      let path = CGPath(roundedRect: rect, cornerWidth: 10, cornerHeight: 10, transform: nil)
      ctx.addPath(path)
      ctx.fillPath()
    }

    ctx.saveGState()
    // CoreText baseline draw
    ctx.textMatrix = .identity
    ctx.translateBy(x: t.position.x, y: t.position.y)
    ctx.scaleBy(x: 1, y: -1)
    CTLineDraw(line, ctx)
    ctx.restoreGState()
  }

  private static func drawCallout(_ c: CalloutAnnotation, in ctx: CGContext) {
    let path = CGPath(roundedRect: c.rect, cornerWidth: 14, cornerHeight: 14, transform: nil)

    if c.fill.enabled {
      ctx.setFillColor(cgColor(c.fill.color))
      ctx.addPath(path)
      ctx.fillPath()
    }

    ctx.setStrokeColor(cgColor(c.stroke.color))
    ctx.setLineWidth(c.stroke.lineWidth)
    ctx.addPath(path)
    ctx.strokePath()

    // Text in padding area
    let inset = c.rect.insetBy(dx: 14, dy: 12)

    let font = CTFontCreateWithName("SFProText-Semibold" as CFString, c.fontSize, nil)
    let attrs: [NSAttributedString.Key: Any] = [
      kCTFontAttributeName as NSAttributedString.Key: font,
      kCTForegroundColorAttributeName as NSAttributedString.Key: cgColor(c.textColor)
    ]

    let attributed = NSAttributedString(string: c.text, attributes: attrs)
    let line = CTLineCreateWithAttributedString(attributed)
    let bounds = CTLineGetBoundsWithOptions(line, [])

    ctx.saveGState()
    ctx.textMatrix = .identity
    ctx.translateBy(x: inset.minX, y: inset.minY + bounds.height)
    ctx.scaleBy(x: 1, y: -1)
    CTLineDraw(line, ctx)
    ctx.restoreGState()
  }

  private static func drawBlur(_ b: BlurAnnotation, in ctx: CGContext) {
    // For "redact" mode, just draw a black rectangle
    if b.mode == .redact {
      ctx.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 1))
      ctx.fill(b.rect)
      return
    }
    
    // Export: apply filter to the corresponding region.
    // We cannot access the original source here directly from ctx; callers draw base image first.
    // So we rely on ctx's current contents by snapshotting after base draw.
    // Practically: just re-draw from a filtered source when possible.
    // Note: This implementation is best-effort; if ctx doesn't have image snapshot, skip.

    guard let snapshot = ctx.makeImage() else { return }
    guard let filtered = ImageFilters.filteredRegion(source: snapshot, rect: b.rect, mode: b.mode, amount: b.amount) else { return }
    ctx.draw(filtered, in: b.rect)
  }

  private static func drawStep(_ s: StepAnnotation, in ctx: CGContext) {
    let circleRect = CGRect(x: s.center.x - s.radius, y: s.center.y - s.radius, width: s.radius * 2, height: s.radius * 2)

    ctx.setFillColor(cgColor(s.fillColor))
    ctx.fillEllipse(in: circleRect)

    ctx.setStrokeColor(cgColor(s.borderColor))
    ctx.setLineWidth(s.borderWidth)
    ctx.strokeEllipse(in: circleRect)

    let fontSize = max(10, s.radius * 0.9)
    let font = CTFontCreateWithName("SFProText-Semibold" as CFString, fontSize, nil)
    let attrs: [NSAttributedString.Key: Any] = [
      kCTFontAttributeName as NSAttributedString.Key: font,
      kCTForegroundColorAttributeName as NSAttributedString.Key: cgColor(s.textColor)
    ]

    let str = NSAttributedString(string: String(s.number), attributes: attrs)
    let line = CTLineCreateWithAttributedString(str)
    let bounds = CTLineGetBoundsWithOptions(line, [])

    ctx.saveGState()
    ctx.textMatrix = .identity
    // Center baseline inside circle.
    let x = s.center.x - bounds.width / 2
    let y = s.center.y + bounds.height / 2
    ctx.translateBy(x: x, y: y)
    ctx.scaleBy(x: 1, y: -1)
    CTLineDraw(line, ctx)
    ctx.restoreGState()
  }

  private static func drawMeasurement(_ m: MeasurementAnnotation, in ctx: CGContext) {
    let strokeColor = cgColor(m.stroke.color)
    ctx.setStrokeColor(strokeColor)
    ctx.setLineWidth(m.stroke.lineWidth)
    ctx.setLineCap(.round)

    // Main measurement line
    ctx.move(to: m.start)
    ctx.addLine(to: m.end)
    ctx.strokePath()

    // Extension lines (perpendicular caps at each end)
    let angle = atan2(m.end.y - m.start.y, m.end.x - m.start.x)
    let perpAngle = angle + .pi / 2

    if m.showExtensionLines {
      let capLength: CGFloat = 12

      // Start cap
      let startCap1 = CGPoint(
        x: m.start.x + cos(perpAngle) * capLength,
        y: m.start.y + sin(perpAngle) * capLength
      )
      let startCap2 = CGPoint(
        x: m.start.x - cos(perpAngle) * capLength,
        y: m.start.y - sin(perpAngle) * capLength
      )
      ctx.move(to: startCap1)
      ctx.addLine(to: startCap2)
      ctx.strokePath()

      // End cap
      let endCap1 = CGPoint(
        x: m.end.x + cos(perpAngle) * capLength,
        y: m.end.y + sin(perpAngle) * capLength
      )
      let endCap2 = CGPoint(
        x: m.end.x - cos(perpAngle) * capLength,
        y: m.end.y - sin(perpAngle) * capLength
      )
      ctx.move(to: endCap1)
      ctx.addLine(to: endCap2)
      ctx.strokePath()
    }

    // Measurement label
    let midPoint = m.midpoint

    let fontSize: CGFloat = max(14, m.stroke.lineWidth * 3.5)
    let font = CTFontCreateWithName("SFProText-Semibold" as CFString, fontSize, nil)
    let textColor = cgColor(m.stroke.color)

    let attrs: [NSAttributedString.Key: Any] = [
      kCTFontAttributeName as NSAttributedString.Key: font,
      kCTForegroundColorAttributeName as NSAttributedString.Key: textColor
    ]

    let text = m.formattedMeasurement
    let attributed = NSAttributedString(string: text, attributes: attrs)
    let line = CTLineCreateWithAttributedString(attributed)
    let bounds = CTLineGetBoundsWithOptions(line, [])

    let padX: CGFloat = 8
    let padY: CGFloat = 4
    let labelWidth = bounds.width + padX * 2
    let labelHeight = bounds.height + padY * 2

    // Use the model's labelPosition method (handles both auto-offset and manual drag)
    let (labelCenter, needsLeader) = m.labelPosition(estimatedLabelWidth: labelWidth)

    // Draw leader line if offset (auto or manual)
    if needsLeader {
      ctx.saveGState()
      ctx.setStrokeColor(CGColor(gray: 0, alpha: 0.6))
      ctx.setLineWidth(1.5)
      ctx.setLineDash(phase: 0, lengths: [4, 3])

      // Simple straight dashed line for cleaner look
      ctx.move(to: labelCenter)
      ctx.addLine(to: midPoint)
      ctx.strokePath()

      // Small dot at measurement midpoint
      ctx.setFillColor(CGColor(gray: 0, alpha: 0.75))
      let dotRadius: CGFloat = 3
      ctx.fillEllipse(in: CGRect(
        x: midPoint.x - dotRadius,
        y: midPoint.y - dotRadius,
        width: dotRadius * 2,
        height: dotRadius * 2
      ))

      ctx.restoreGState()
      ctx.setStrokeColor(strokeColor)
      ctx.setLineWidth(m.stroke.lineWidth)
    }

    // Background pill for readability
    let bgRect = CGRect(
      x: labelCenter.x - bounds.width / 2 - padX,
      y: labelCenter.y - bounds.height / 2 - padY - 4,
      width: labelWidth,
      height: labelHeight
    )

    ctx.setFillColor(CGColor(gray: 0, alpha: 0.75))
    let bgPath = CGPath(roundedRect: bgRect, cornerWidth: 6, cornerHeight: 6, transform: nil)
    ctx.addPath(bgPath)
    ctx.fillPath()

    // Draw text
    ctx.saveGState()
    ctx.textMatrix = .identity
    ctx.translateBy(x: labelCenter.x - bounds.width / 2, y: labelCenter.y + bounds.height / 4)
    ctx.scaleBy(x: 1, y: -1)
    CTLineDraw(line, ctx)
    ctx.restoreGState()
  }

  // MARK: - New Annotation Types

  private static func drawLine(_ l: LineAnnotation, in ctx: CGContext) {
    ctx.setStrokeColor(cgColor(l.stroke.color))
    ctx.setLineWidth(l.stroke.lineWidth)
    ctx.setLineCap(.round)

    ctx.move(to: l.start)
    ctx.addLine(to: l.end)
    ctx.strokePath()
  }

  private static func drawFreehand(_ f: FreehandAnnotation, in ctx: CGContext) {
    guard f.points.count >= 2 else { return }

    ctx.setStrokeColor(cgColor(f.stroke.color, alpha: f.isHighlighter ? 0.4 : 1.0))
    ctx.setLineWidth(f.stroke.lineWidth)
    ctx.setLineCap(.round)
    ctx.setLineJoin(.round)

    ctx.move(to: f.points[0])
    for point in f.points.dropFirst() {
      ctx.addLine(to: point)
    }
    ctx.strokePath()
  }

  /// Draws all spotlights as a single dimming layer with multiple cutouts
  private static func drawCombinedSpotlights(_ spotlights: [SpotlightAnnotation], imageSize: CGSize, in ctx: CGContext) {
    guard !spotlights.isEmpty else { return }

    let fullRect = CGRect(origin: .zero, size: imageSize)

    ctx.saveGState()

    // Add cutouts for each spotlight
    for sp in spotlights {
      switch sp.shape {
      case .rectangle:
        ctx.addRect(sp.rect)
      case .roundedRect:
        let path = CGPath(roundedRect: sp.rect, cornerWidth: 12, cornerHeight: 12, transform: nil)
        ctx.addPath(path)
      case .ellipse:
        ctx.addEllipse(in: sp.rect)
      }
    }

    // Add the full rect and use even-odd rule to create the "everything except spotlights" area
    ctx.addRect(fullRect)

    // Use the maximum dimming opacity from all spotlights
    let maxOpacity = spotlights.map(\.dimmingOpacity).max() ?? 0.5
    ctx.setFillColor(CGColor(gray: 0, alpha: maxOpacity))
    ctx.fillPath(using: .evenOdd)

    ctx.restoreGState()

    // Draw borders for each spotlight
    for sp in spotlights {
      if let borderStroke = sp.borderStroke {
        ctx.setStrokeColor(cgColor(borderStroke.color))
        ctx.setLineWidth(borderStroke.lineWidth)

        switch sp.shape {
        case .rectangle:
          ctx.stroke(sp.rect)
        case .roundedRect:
          let path = CGPath(roundedRect: sp.rect, cornerWidth: 12, cornerHeight: 12, transform: nil)
          ctx.addPath(path)
          ctx.strokePath()
        case .ellipse:
          ctx.strokeEllipse(in: sp.rect)
        }
      }
    }
  }

  private static func drawSpotlight(_ sp: SpotlightAnnotation, imageSize: CGSize, in ctx: CGContext) {
    // Fill entire area with dimming
    let fullRect = CGRect(origin: .zero, size: imageSize)

    ctx.saveGState()

    // Set up clip for the spotlight cutout
    switch sp.shape {
    case .rectangle:
      ctx.addRect(sp.rect)
    case .roundedRect:
      let path = CGPath(roundedRect: sp.rect, cornerWidth: 12, cornerHeight: 12, transform: nil)
      ctx.addPath(path)
    case .ellipse:
      ctx.addEllipse(in: sp.rect)
    }

    // Add the full rect and use even-odd rule to create the "everything except spotlight" area
    ctx.addRect(fullRect)

    ctx.setFillColor(CGColor(gray: 0, alpha: sp.dimmingOpacity))
    ctx.fillPath(using: .evenOdd)

    ctx.restoreGState()

    // Optional border around spotlight
    if let borderStroke = sp.borderStroke {
      ctx.setStrokeColor(cgColor(borderStroke.color))
      ctx.setLineWidth(borderStroke.lineWidth)

      switch sp.shape {
      case .rectangle:
        ctx.stroke(sp.rect)
      case .roundedRect:
        let path = CGPath(roundedRect: sp.rect, cornerWidth: 12, cornerHeight: 12, transform: nil)
        ctx.addPath(path)
        ctx.strokePath()
      case .ellipse:
        ctx.strokeEllipse(in: sp.rect)
      }
    }
  }

  private static func drawCounter(_ c: CounterAnnotation, in ctx: CGContext) {
    let circleRect = CGRect(
      x: c.center.x - c.radius,
      y: c.center.y - c.radius,
      width: c.radius * 2,
      height: c.radius * 2
    )

    // Fill
    ctx.setFillColor(cgColor(c.fillColor))
    ctx.fillEllipse(in: circleRect)

    // Border
    ctx.setStrokeColor(cgColor(c.borderColor))
    ctx.setLineWidth(c.borderWidth)
    ctx.strokeEllipse(in: circleRect)

    // Text (value)
    let font = CTFontCreateWithName("SFProText-Bold" as CFString, c.radius * 0.9, nil)
    let attrs: [NSAttributedString.Key: Any] = [
      kCTFontAttributeName as NSAttributedString.Key: font,
      kCTForegroundColorAttributeName as NSAttributedString.Key: cgColor(c.textColor)
    ]
    let attributed = NSAttributedString(string: c.value, attributes: attrs)
    let line = CTLineCreateWithAttributedString(attributed)
    let bounds = CTLineGetBoundsWithOptions(line, [])

    ctx.saveGState()
    ctx.textMatrix = .identity
    ctx.translateBy(x: c.center.x - bounds.width / 2, y: c.center.y + bounds.height / 3)
    ctx.scaleBy(x: 1, y: -1)
    CTLineDraw(line, ctx)
    ctx.restoreGState()
  }

  private static func drawEmoji(_ e: EmojiAnnotation, in ctx: CGContext) {
    // Use a system font that supports emoji
    let font = CTFontCreateWithName("AppleColorEmoji" as CFString, e.size, nil)
    let attrs: [NSAttributedString.Key: Any] = [
      kCTFontAttributeName as NSAttributedString.Key: font
    ]
    let attributed = NSAttributedString(string: e.emoji, attributes: attrs)
    let line = CTLineCreateWithAttributedString(attributed)
    let bounds = CTLineGetBoundsWithOptions(line, [])

    ctx.saveGState()
    ctx.textMatrix = .identity
    ctx.translateBy(x: e.position.x - bounds.width / 2, y: e.position.y + bounds.height / 3)
    ctx.scaleBy(x: 1, y: -1)
    CTLineDraw(line, ctx)
    ctx.restoreGState()
  }
}
