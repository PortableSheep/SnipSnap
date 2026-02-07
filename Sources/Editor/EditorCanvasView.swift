import AppKit
import Foundation
import SwiftUI

struct EditorCanvasView: View {
  @ObservedObject var doc: AnnotationDocument

  @State private var dragStartImagePoint: CGPoint? = nil
  @State private var dragCurrentImagePoint: CGPoint? = nil
  @State private var movingStartPoint: CGPoint? = nil

  @State private var activeSelectInteraction: SelectInteraction? = nil
  @State private var originalSelectedAtDragStart: Annotation? = nil

  @State private var isShiftDown: Bool = false

  var body: some View {
    GeometryReader { geo in
      ZStack {
        // Background checker
        Color.black.opacity(0.02)

        Canvas { context, size in
          drawBaseImage(context: &context, size: size)
          drawAnnotations(context: &context, size: size)
          drawInProgress(context: &context, size: size)
        }
        .gesture(dragGesture(in: geo.size))
        .simultaneousGesture(tapGesture(in: geo.size))

        overlayTextAnnotations(viewSize: geo.size)

        if doc.pendingTextInput != nil {
          Color.black.opacity(0.28)
            .ignoresSafeArea()
            .onTapGesture {
              doc.cancelPendingTextInput()
            }
        }
      }
      .onAppear {
        NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { event in
          isShiftDown = event.modifierFlags.contains(.shift)
          return event
        }
      }
    }
  }

  private func drawBaseImage(context: inout GraphicsContext, size: CGSize) {
    let baseImageRect = fitRect(imageSize: doc.imageSize, in: size)
    let scale = baseImageRect.width / doc.imageSize.width
    
    // Calculate dimensions
    let titleBarHeight: CGFloat = doc.showMacWindow ? 28 * scale : 0
    let windowMargin: CGFloat = doc.showMacWindow ? 8 * scale : 0
    let backgroundPadding = doc.backgroundStyle != .none ? doc.backgroundPadding * scale : 0
    
    // Total frame includes background padding around everything
    let totalFrameRect = CGRect(
      x: baseImageRect.minX - backgroundPadding,
      y: baseImageRect.minY - backgroundPadding - titleBarHeight,
      width: baseImageRect.width + backgroundPadding * 2,
      height: baseImageRect.height + backgroundPadding * 2 + titleBarHeight
    )
    
    // Window chrome sits inside the background padding
    let windowRect = totalFrameRect.insetBy(dx: backgroundPadding, dy: backgroundPadding)
    
    // Screenshot area is inside the window (below title bar, with margin)
    let imageRect = CGRect(
      x: windowRect.minX + windowMargin,
      y: windowRect.minY + titleBarHeight + windowMargin,
      width: windowRect.width - windowMargin * 2,
      height: windowRect.height - titleBarHeight - windowMargin * 2
    )
    
    // Draw background FIRST (behind everything) if enabled
    if doc.backgroundStyle != .none {
      switch doc.backgroundStyle {
      case .none:
        break
        
      case .solid:
        context.fill(Path(totalFrameRect), with: .color(doc.backgroundColor))
        
      case .gradient:
        let gradient = Gradient(colors: [doc.backgroundGradientStart, doc.backgroundGradientEnd])
        let startPoint: CGPoint
        let endPoint: CGPoint
        
        switch doc.backgroundGradientDirection {
        case .topToBottom:
          startPoint = CGPoint(x: totalFrameRect.midX, y: totalFrameRect.minY)
          endPoint = CGPoint(x: totalFrameRect.midX, y: totalFrameRect.maxY)
        case .leftToRight:
          startPoint = CGPoint(x: totalFrameRect.minX, y: totalFrameRect.midY)
          endPoint = CGPoint(x: totalFrameRect.maxX, y: totalFrameRect.midY)
        case .topLeftToBottomRight:
          startPoint = CGPoint(x: totalFrameRect.minX, y: totalFrameRect.minY)
          endPoint = CGPoint(x: totalFrameRect.maxX, y: totalFrameRect.maxY)
        case .radial:
          startPoint = CGPoint(x: totalFrameRect.midX, y: totalFrameRect.midY)
          endPoint = CGPoint(x: totalFrameRect.maxX, y: totalFrameRect.midY)
        }
        
        context.fill(Path(totalFrameRect), with: .linearGradient(gradient, startPoint: startPoint, endPoint: endPoint))
        
      case .mesh:
        let gradient = Gradient(colors: [doc.backgroundGradientStart, doc.backgroundGradientEnd])
        let startPoint = CGPoint(x: totalFrameRect.minX, y: totalFrameRect.minY)
        let endPoint = CGPoint(x: totalFrameRect.maxX, y: totalFrameRect.maxY)
        context.fill(Path(totalFrameRect), with: .linearGradient(gradient, startPoint: startPoint, endPoint: endPoint))
        
      case .wallpaper:
        if let wallpaper = doc.getWallpaper(),
           let cgImage = wallpaper.cgImage(forProposedRect: nil, context: nil, hints: nil) {
          context.draw(Image(decorative: cgImage, scale: 1.0), in: totalFrameRect)
        } else {
          context.fill(Path(totalFrameRect), with: .color(.gray.opacity(0.2)))
        }
      }
      
      // Draw shadow if enabled (shadow of window or image)
      if doc.backgroundShadowEnabled {
        let shadowTargetRect = doc.showMacWindow ? windowRect : baseImageRect
        context.drawLayer { ctx in
          ctx.addFilter(.shadow(color: .black.opacity(doc.backgroundShadowOpacity), radius: doc.backgroundShadowRadius * scale))
          ctx.fill(Path(shadowTargetRect), with: .color(.white))
        }
      }
    }
    
    // Draw macOS window frame OVER the background
    if doc.showMacWindow {
      let cornerRadius: CGFloat = 10 * scale
      
      // Window background with rounded corners
      let windowColor = doc.macWindowColor
      context.fill(
        Path(roundedRect: windowRect, cornerRadius: cornerRadius),
        with: .color(windowColor)
      )
      
      // Title bar at the TOP
      let titleBarRect = CGRect(
        x: windowRect.minX,
        y: windowRect.minY,
        width: windowRect.width,
        height: titleBarHeight
      )
      
      // Round only the top corners of title bar
      let titleBarPath = Path { path in
        path.move(to: CGPoint(x: titleBarRect.minX, y: titleBarRect.maxY))
        path.addLine(to: CGPoint(x: titleBarRect.minX, y: titleBarRect.minY + cornerRadius))
        path.addArc(center: CGPoint(x: titleBarRect.minX + cornerRadius, y: titleBarRect.minY + cornerRadius),
                    radius: cornerRadius,
                    startAngle: .degrees(180),
                    endAngle: .degrees(270),
                    clockwise: false)
        path.addLine(to: CGPoint(x: titleBarRect.maxX - cornerRadius, y: titleBarRect.minY))
        path.addArc(center: CGPoint(x: titleBarRect.maxX - cornerRadius, y: titleBarRect.minY + cornerRadius),
                    radius: cornerRadius,
                    startAngle: .degrees(270),
                    endAngle: .degrees(0),
                    clockwise: false)
        path.addLine(to: CGPoint(x: titleBarRect.maxX, y: titleBarRect.maxY))
        path.closeSubpath()
      }
      
      context.fill(titleBarPath, with: .color(windowColor.opacity(0.96)))
      
      // Traffic lights at top left
      let lightRadius: CGFloat = 6 * scale
      let lightY = titleBarRect.minY + titleBarHeight / 2
      let lightColors: [Color] = [
        Color(red: 1, green: 0.38, blue: 0.35),  // Red
        Color(red: 1, green: 0.78, blue: 0.25),  // Yellow
        Color(red: 0.15, green: 0.8, blue: 0.25)  // Green
      ]
      for (i, color) in lightColors.enumerated() {
        let x = windowRect.minX + 14 * scale + CGFloat(i) * 20 * scale
        let circleRect = CGRect(
          x: x - lightRadius,
          y: lightY - lightRadius,
          width: lightRadius * 2,
          height: lightRadius * 2
        )
        context.fill(Path(ellipseIn: circleRect), with: .color(color))
      }
    }
    
    // Draw the actual screenshot image (properly positioned)
    let finalImageRect = doc.showMacWindow ? imageRect : baseImageRect
    context.draw(Image(decorative: doc.cgImage, scale: 1), in: finalImageRect)
  }

  private func drawAnnotations(context: inout GraphicsContext, size: CGSize) {
    let baseImageRect = fitRect(imageSize: doc.imageSize, in: size)
    let scale = baseImageRect.width / doc.imageSize.width
    
    // Calculate where the actual image is positioned
    let titleBarHeight: CGFloat = doc.showMacWindow ? 28 * scale : 0
    let windowMargin: CGFloat = doc.showMacWindow ? 8 * scale : 0
    let backgroundPadding = doc.backgroundStyle != .none ? doc.backgroundPadding * scale : 0
    
    // Annotations are drawn relative to where the screenshot actually is
    let actualImageRect: CGRect
    if doc.showMacWindow {
      // Image is inside window (below title bar, with margin), window is inside background padding
      actualImageRect = CGRect(
        x: baseImageRect.minX + windowMargin,
        y: baseImageRect.minY + titleBarHeight + windowMargin,
        width: baseImageRect.width - windowMargin * 2,
        height: baseImageRect.height - windowMargin * 2
      )
    } else {
      // Image is just at base position
      actualImageRect = baseImageRect
    }

    // Blur/pixelate first (underlays)
    for a in doc.annotations {
      if case .blur = a {
        draw(annotation: a, context: &context, scale: scale, offset: actualImageRect.origin)
      }
    }

    // Collect all spotlights and draw them as a single combined dimming layer
    let spotlights = doc.annotations.compactMap { a -> SpotlightAnnotation? in
      if case .spotlight(let sp) = a { return sp }
      return nil
    }
    if !spotlights.isEmpty {
      drawCombinedSpotlights(spotlights, context: &context, scale: scale, offset: actualImageRect.origin)
    }

    // Then all other overlays (skip spotlights, already drawn)
    for a in doc.annotations {
      if case .blur = a { continue }
      if case .spotlight = a { continue }
      draw(annotation: a, context: &context, scale: scale, offset: actualImageRect.origin)
    }

    // Selection outline always on top
    if let sel = doc.selectedID, let a = doc.annotations.first(where: { $0.id == sel }) {
      drawSelection(for: a, context: &context, scale: scale, offset: actualImageRect.origin)
    }

    // Draw redaction suggestion indicators
    drawRedactionSuggestions(context: &context, scale: scale, offset: actualImageRect.origin)
  }

  /// Draws dashed outlines around detected sensitive areas
  private func drawRedactionSuggestions(context: inout GraphicsContext, scale: CGFloat, offset: CGPoint) {
    guard !doc.suggestedRedactions.isEmpty else { return }

    for suggestion in doc.suggestedRedactions {
      let r = suggestion.rect
      let scaled = CGRect(
        x: offset.x + r.minX * scale,
        y: offset.y + r.minY * scale,
        width: r.width * scale,
        height: r.height * scale
      )

      // Dashed orange border
      context.stroke(
        Path(roundedRect: scaled, cornerRadius: 4),
        with: .color(.orange),
        style: StrokeStyle(lineWidth: 2, dash: [6, 4])
      )

      // Semi-transparent orange fill
      context.fill(
        Path(roundedRect: scaled, cornerRadius: 4),
        with: .color(.orange.opacity(0.1))
      )
    }
  }

  /// Draws all spotlights as a single dimming layer with multiple cutouts
  private func drawCombinedSpotlights(_ spotlights: [SpotlightAnnotation], context: inout GraphicsContext, scale: CGFloat, offset: CGPoint) {
    guard !spotlights.isEmpty else { return }

    let fullRect = CGRect(
      x: offset.x,
      y: offset.y,
      width: doc.imageSize.width * scale,
      height: doc.imageSize.height * scale
    )

    // Start with the full rect as the dimming area
    var dimmingPath = Path(fullRect)

    // Use the maximum dimming opacity from all spotlights
    let maxOpacity = spotlights.map(\.dimmingOpacity).max() ?? 0.5

    // Add cutouts for each spotlight
    for sp in spotlights {
      let spotRect = CGRect(
        x: offset.x + sp.rect.minX * scale,
        y: offset.y + sp.rect.minY * scale,
        width: sp.rect.width * scale,
        height: sp.rect.height * scale
      )

      let cutoutPath: Path
      switch sp.shape {
      case .rectangle:
        cutoutPath = Path(spotRect)
      case .roundedRect:
        cutoutPath = Path(roundedRect: spotRect, cornerRadius: 12)
      case .ellipse:
        cutoutPath = Path(ellipseIn: spotRect)
      }

      dimmingPath.addPath(cutoutPath)
    }

    // Draw the combined dimming layer with all cutouts using even-odd fill
    context.fill(dimmingPath, with: .color(.black.opacity(maxOpacity)), style: .init(eoFill: true))

    // Draw borders for each spotlight
    for sp in spotlights {
      if let borderStroke = sp.borderStroke {
        let spotRect = CGRect(
          x: offset.x + sp.rect.minX * scale,
          y: offset.y + sp.rect.minY * scale,
          width: sp.rect.width * scale,
          height: sp.rect.height * scale
        )

        let borderPath: Path
        switch sp.shape {
        case .rectangle:
          borderPath = Path(spotRect)
        case .roundedRect:
          borderPath = Path(roundedRect: spotRect, cornerRadius: 12)
        case .ellipse:
          borderPath = Path(ellipseIn: spotRect)
        }

        context.stroke(borderPath, with: .color(borderStroke.color), lineWidth: borderStroke.lineWidth * scale)
      }
    }
  }

  private func drawInProgress(context: inout GraphicsContext, size: CGSize) {
    // If we're moving/resizing an existing annotation, don't show tool previews.
    guard activeSelectInteraction == nil else { return }
    guard let start = dragStartImagePoint, let curr = dragCurrentImagePoint else { return }

    let baseImageRect = fitRect(imageSize: doc.imageSize, in: size)
    let scale = baseImageRect.width / doc.imageSize.width
    
    // Calculate where the actual image is positioned
    let titleBarHeight: CGFloat = doc.showMacWindow ? 28 * scale : 0
    let windowMargin: CGFloat = doc.showMacWindow ? 8 * scale : 0
    
    let actualImageRect: CGRect
    if doc.showMacWindow {
      actualImageRect = CGRect(
        x: baseImageRect.minX + windowMargin,
        y: baseImageRect.minY + titleBarHeight + windowMargin,
        width: baseImageRect.width - windowMargin * 2,
        height: baseImageRect.height - windowMargin * 2
      )
    } else {
      actualImageRect = baseImageRect
    }
    
    let offset = actualImageRect.origin

    if let tool = ToolRegistry.tool(for: doc.tool), tool.capabilities.contains(.usesDrag), let preview = tool.preview(doc: doc, start: start, current: curr, isShiftDown: isShiftDown) {
      draw(annotation: preview, context: &context, scale: scale, offset: offset)
    }
  }

  private func tapGesture(in size: CGSize) -> some Gesture {
    TapGesture()
      .onEnded {
        let _ = size
        // noop; selection handled by drag start for now
      }
  }

  private func dragGesture(in size: CGSize) -> some Gesture {
    DragGesture(minimumDistance: 0)
      .onChanged { value in
        let imgPoint = viewToImage(point: value.location, viewSize: size)

        if dragStartImagePoint == nil {
          // Double-click on text/callout opens an inline editor.
          let clickCount = NSApp.currentEvent?.clickCount ?? 1
          if clickCount == 2,
             let hitID = hitTest(point: imgPoint),
             let a = doc.annotations.first(where: { $0.id == hitID }) {
            switch a {
            case .text(let t):
              doc.selectedID = hitID
              doc.pendingTextInput = .init(
                kind: .text,
                positionOrRect: .position(t.position),
                initialText: t.text,
                targetAnnotationID: t.id,
                removeTargetOnCancel: false
              )
              return
            case .callout(let c):
              doc.selectedID = hitID
              doc.pendingTextInput = .init(
                kind: .callout,
                positionOrRect: .rect(c.rect),
                initialText: c.text,
                targetAnnotationID: c.id,
                removeTargetOnCancel: false
              )
              return
            default:
              break
            }
          }

          dragStartImagePoint = imgPoint
          dragCurrentImagePoint = imgPoint

          // Universal behavior: clicking an existing annotation selects it (and allows move/resize)
          // even if a drawing tool is currently active.
          if let hitID = hitTest(point: imgPoint), let a = doc.annotations.first(where: { $0.id == hitID }) {
            doc.selectedID = hitID
            movingStartPoint = imgPoint
            originalSelectedAtDragStart = a
            if let hit = hitTestHandle(point: imgPoint, annotation: a, viewSize: size) {
              activeSelectInteraction = .handle(hit)
            } else {
              activeSelectInteraction = .move
            }
            return
          }

          switch doc.tool {
          case .select:
            // If user grabbed a handle on the currently-selected annotation, resize that.
            if let sel = doc.selectedID, let a = doc.annotations.first(where: { $0.id == sel }), let hit = hitTestHandle(point: imgPoint, annotation: a, viewSize: size) {
              activeSelectInteraction = .handle(hit)
              originalSelectedAtDragStart = a
              movingStartPoint = imgPoint
            } else {
              doc.selectedID = hitTest(point: imgPoint)
              movingStartPoint = imgPoint
              if let sel = doc.selectedID, let a = doc.annotations.first(where: { $0.id == sel }) {
                activeSelectInteraction = .move
                originalSelectedAtDragStart = a
              } else {
                activeSelectInteraction = nil
                originalSelectedAtDragStart = nil
              }
            }
          default:
            if let tool = ToolRegistry.tool(for: doc.tool) {
              let res = tool.begin(doc: doc, at: imgPoint, isShiftDown: isShiftDown)
              if res == .handled {
                dragStartImagePoint = nil
                dragCurrentImagePoint = nil
              }
            }
          }
          return
        }

        dragCurrentImagePoint = imgPoint

        // Handle freehand drawing continuation
        if doc.tool == .freehand, doc.activeFreehandStroke != nil {
          doc.continueFreehandStroke(to: imgPoint)
          return
        }

        if let sel = doc.selectedID, let start = movingStartPoint {
          guard sel == doc.selectedID else { return }
          guard let interaction = activeSelectInteraction else { return }

          switch interaction {
          case .move:
            let delta = CGPoint(x: imgPoint.x - start.x, y: imgPoint.y - start.y)
            movingStartPoint = imgPoint
            doc.beginEditSessionIfNeeded()
            doc.updateSelectedInSession { a in
              applyMove(delta: delta, annotation: &a)
            }

          case .handle(let h):
            guard let original = originalSelectedAtDragStart else { return }
            doc.beginEditSessionIfNeeded()
            doc.updateSelectedInSession { a in
              applyHandleDrag(handle: h, current: imgPoint, original: original, annotation: &a)
            }
          }
        }
      }
      .onEnded { value in
        let imgEnd = viewToImage(point: value.location, viewSize: size)

        defer {
          dragStartImagePoint = nil
          dragCurrentImagePoint = nil
          movingStartPoint = nil
          activeSelectInteraction = nil
          originalSelectedAtDragStart = nil
          doc.endEditSession()
        }

        // Commit freehand stroke if active
        if doc.tool == .freehand, doc.activeFreehandStroke != nil {
          doc.commitFreehandStroke()
          return
        }

        guard let start = dragStartImagePoint else { return }

        // If we were moving/resizing an existing annotation, never commit the active tool.
        if activeSelectInteraction != nil {
          return
        }

        switch doc.tool {
        default:
          if let tool = ToolRegistry.tool(for: doc.tool), tool.capabilities.contains(.usesDrag) {
            tool.commit(doc: doc, start: start, end: imgEnd, isShiftDown: isShiftDown)
          }
        }
      }
  }

  private enum SelectInteraction {
    case move
    case handle(HandleHit)
  }

  private enum HandleKind: Hashable {
    case rect(RectHandle)
    case arrowStart
    case arrowEnd
    case lineStart
    case lineEnd
    case measurementStart
    case measurementEnd
    case measurementLabel
  }

  private enum RectHandle: CaseIterable {
    case topLeft, top, topRight
    case right
    case bottomRight, bottom, bottomLeft
    case left

    var affectsLeft: Bool {
      switch self {
      case .topLeft, .left, .bottomLeft: return true
      default: return false
      }
    }

    var affectsRight: Bool {
      switch self {
      case .topRight, .right, .bottomRight: return true
      default: return false
      }
    }

    var affectsTop: Bool {
      switch self {
      case .topLeft, .top, .topRight: return true
      default: return false
      }
    }

    var affectsBottom: Bool {
      switch self {
      case .bottomLeft, .bottom, .bottomRight: return true
      default: return false
      }
    }
  }

  private struct HandleHit: Hashable {
    var kind: HandleKind
  }

  private func fitRect(imageSize: CGSize, in viewSize: CGSize) -> CGRect {
    // Calculate total size including background padding and window frame
    let padding = doc.backgroundStyle != .none ? doc.backgroundPadding : 0
    let titleBarHeight: CGFloat = doc.showMacWindow ? 28 : 0
    let windowMargin: CGFloat = doc.showMacWindow ? 8 : 0
    
    let totalWidth = imageSize.width + (padding * 2) + (windowMargin * 2)
    let totalHeight = imageSize.height + (padding * 2) + (windowMargin * 2) + titleBarHeight
    
    let scale = min(viewSize.width / totalWidth, viewSize.height / totalHeight)
    let w = imageSize.width * scale
    let h = imageSize.height * scale
    let x = (viewSize.width - w) / 2
    let y = (viewSize.height - h) / 2
    return CGRect(x: x, y: y, width: w, height: h)
  }

  private func viewToImage(point: CGPoint, viewSize: CGSize) -> CGPoint {
    let baseImageRect = fitRect(imageSize: doc.imageSize, in: viewSize)
    let scale = baseImageRect.width / doc.imageSize.width
    
    // Calculate where the actual image is positioned
    let titleBarHeight: CGFloat = doc.showMacWindow ? 28 * scale : 0
    let windowMargin: CGFloat = doc.showMacWindow ? 8 * scale : 0
    
    let actualImageRect: CGRect
    if doc.showMacWindow {
      actualImageRect = CGRect(
        x: baseImageRect.minX + windowMargin,
        y: baseImageRect.minY + titleBarHeight + windowMargin,
        width: baseImageRect.width - windowMargin * 2,
        height: baseImageRect.height - windowMargin * 2
      )
    } else {
      actualImageRect = baseImageRect
    }
    
    let p = CGPoint(x: (point.x - actualImageRect.minX) / scale, y: (point.y - actualImageRect.minY) / scale)
    return CGPoint(x: max(0, min(doc.imageSize.width, p.x)), y: max(0, min(doc.imageSize.height, p.y)))
  }

  private func imageToView(point: CGPoint, viewSize: CGSize) -> CGPoint {
    let baseImageRect = fitRect(imageSize: doc.imageSize, in: viewSize)
    let scale = baseImageRect.width / doc.imageSize.width
    
    // Calculate where the actual image is positioned
    let titleBarHeight: CGFloat = doc.showMacWindow ? 28 * scale : 0
    let windowMargin: CGFloat = doc.showMacWindow ? 8 * scale : 0
    
    let actualImageRect: CGRect
    if doc.showMacWindow {
      actualImageRect = CGRect(
        x: baseImageRect.minX + windowMargin,
        y: baseImageRect.minY + titleBarHeight + windowMargin,
        width: baseImageRect.width - windowMargin * 2,
        height: baseImageRect.height - windowMargin * 2
      )
    } else {
      actualImageRect = baseImageRect
    }
    
    return CGPoint(x: actualImageRect.minX + point.x * scale, y: actualImageRect.minY + point.y * scale)
  }

  // Tool preview/commit math lives in ToolRegistry.

  private func draw(annotation: Annotation, context: inout GraphicsContext, scale: CGFloat, offset: CGPoint) {
    switch annotation {
    case .rect(let r):
      let vr = CGRect(
        x: offset.x + r.rect.minX * scale,
        y: offset.y + r.rect.minY * scale,
        width: r.rect.width * scale,
        height: r.rect.height * scale
      )
      if r.fill.enabled {
        context.fill(Path(vr), with: .color(r.fill.color))
      }
      context.stroke(Path(vr), with: .color(r.stroke.color), lineWidth: r.stroke.lineWidth * scale)

    case .arrow(let a):
      let s = CGPoint(x: offset.x + a.start.x * scale, y: offset.y + a.start.y * scale)
      let e = CGPoint(x: offset.x + a.end.x * scale, y: offset.y + a.end.y * scale)
      let lw = a.stroke.lineWidth * scale
      let dx = e.x - s.x
      let dy = e.y - s.y
      let len = max(0.0001, hypot(dx, dy))
      let ux = dx / len
      let uy = dy / len

      // Arrowhead sizing
      var headLen: CGFloat = max(12, lw * 4)
      headLen = min(headLen, len * 0.55)
      let headWidth: CGFloat = headLen * 0.6
      let perpX = -uy
      let perpY = ux

      let base = CGPoint(x: e.x - ux * headLen, y: e.y - uy * headLen)
      let left = CGPoint(x: base.x + perpX * headWidth, y: base.y + perpY * headWidth)
      let right = CGPoint(x: base.x - perpX * headWidth, y: base.y - perpY * headWidth)

      // Shaft should stop at the head base for cleaner joins
      let shaftEnd = (a.headStyle == .none) ? e : base
      var shaft = Path()
      shaft.move(to: s)
      shaft.addLine(to: shaftEnd)
      context.stroke(shaft, with: .color(a.stroke.color), style: .init(lineWidth: lw, lineCap: .round, lineJoin: .round))

      switch a.headStyle {
      case .open:
        var head = Path()
        head.move(to: left)
        head.addLine(to: e)
        head.addLine(to: right)
        context.stroke(head, with: .color(a.stroke.color), style: .init(lineWidth: max(1, lw * 0.85), lineCap: .round, lineJoin: .round))

      case .filled:
        var head = Path()
        head.move(to: e)
        head.addLine(to: left)
        head.addLine(to: right)
        head.closeSubpath()
        context.fill(head, with: .color(a.stroke.color))

      case .none:
        break
      }

    case .text:
      // Text is rendered as a SwiftUI overlay (see overlayTextAnnotations).
      break

    case .callout(let c):
      let vr = CGRect(
        x: offset.x + c.rect.minX * scale,
        y: offset.y + c.rect.minY * scale,
        width: c.rect.width * scale,
        height: c.rect.height * scale
      )
      if c.fill.enabled {
        context.fill(Path(roundedRect: vr, cornerRadius: 14), with: .color(c.fill.color))
      }
      context.stroke(Path(roundedRect: vr, cornerRadius: 14), with: .color(c.stroke.color), lineWidth: c.stroke.lineWidth * scale)
      // Callout text is rendered as a SwiftUI overlay (see overlayTextAnnotations).

    case .blur(let b):
      // Live view: filter the underlying source region and paint back.
      // For "redact" mode, just draw a black rectangle
      if b.mode == .redact {
        let vr = CGRect(
          x: offset.x + b.rect.minX * scale,
          y: offset.y + b.rect.minY * scale,
          width: b.rect.width * scale,
          height: b.rect.height * scale
        )
        context.fill(Path(vr), with: .color(.black))
      } else {
        guard let filtered = ImageFilters.filteredRegion(source: doc.cgImage, rect: b.rect, mode: b.mode, amount: b.amount) else {
          break
        }
        let vr = CGRect(
          x: offset.x + b.rect.minX * scale,
          y: offset.y + b.rect.minY * scale,
          width: b.rect.width * scale,
          height: b.rect.height * scale
        )
        context.draw(Image(decorative: filtered, scale: 1), in: vr)
      }

    case .step(let s):
      let c = CGPoint(x: offset.x + s.center.x * scale, y: offset.y + s.center.y * scale)
      let r = s.radius * scale
      let circleRect = CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)
      context.fill(Path(ellipseIn: circleRect), with: .color(s.fillColor))
      context.stroke(Path(ellipseIn: circleRect), with: .color(s.borderColor), lineWidth: max(1, s.borderWidth * scale))
      // Step number is rendered as a SwiftUI overlay (see overlayTextAnnotations).

    case .measurement(let m):
      let s = CGPoint(x: offset.x + m.start.x * scale, y: offset.y + m.start.y * scale)
      let e = CGPoint(x: offset.x + m.end.x * scale, y: offset.y + m.end.y * scale)
      let lw = m.stroke.lineWidth * scale

      // Main measurement line
      var line = Path()
      line.move(to: s)
      line.addLine(to: e)
      context.stroke(line, with: .color(m.stroke.color), style: .init(lineWidth: lw, lineCap: .round))

      // Extension lines (perpendicular caps)
      let angle = atan2(e.y - s.y, e.x - s.x)
      let perpAngle = angle + .pi / 2

      if m.showExtensionLines {
        let capLength: CGFloat = 12 * scale

        var caps = Path()
        caps.move(to: CGPoint(x: s.x + cos(perpAngle) * capLength, y: s.y + sin(perpAngle) * capLength))
        caps.addLine(to: CGPoint(x: s.x - cos(perpAngle) * capLength, y: s.y - sin(perpAngle) * capLength))
        caps.move(to: CGPoint(x: e.x + cos(perpAngle) * capLength, y: e.y + sin(perpAngle) * capLength))
        caps.addLine(to: CGPoint(x: e.x - cos(perpAngle) * capLength, y: e.y - sin(perpAngle) * capLength))
        context.stroke(caps, with: .color(m.stroke.color), style: .init(lineWidth: lw, lineCap: .round))
      }

      // Check if label needs offset (small measurement)
      let midPoint = CGPoint(x: (s.x + e.x) / 2, y: (s.y + e.y) / 2)
      let fontSize = max(12, m.stroke.lineWidth * 3.5 * scale)
      let estimatedLabelWidth = CGFloat(m.formattedMeasurement.count) * fontSize * 0.6 + 16
      let measurementLengthScaled = m.pixelDistance * scale
      let needsOffset = measurementLengthScaled < estimatedLabelWidth + 20

      if needsOffset {
        // Draw leader line from midpoint to where label will be
        let offsetDistance: CGFloat = 35 * scale + fontSize
        let offsetDir: CGFloat = (perpAngle > 0 && perpAngle < .pi) ? 1 : -1
        let labelCenter = CGPoint(
          x: midPoint.x + cos(perpAngle) * offsetDistance * offsetDir,
          y: midPoint.y + sin(perpAngle) * offsetDistance * offsetDir
        )

        // Dashed leader line
        var leader = Path()
        leader.move(to: labelCenter)
        leader.addLine(to: midPoint)
        context.stroke(leader, with: .color(.black.opacity(0.6)), style: .init(lineWidth: 1.5, lineCap: .round, dash: [4, 3]))

        // Small dot at measurement midpoint
        let dotRadius: CGFloat = 3
        context.fill(Path(ellipseIn: CGRect(x: midPoint.x - dotRadius, y: midPoint.y - dotRadius, width: dotRadius * 2, height: dotRadius * 2)), with: .color(.black.opacity(0.75)))
      }
      // Measurement label is rendered as a SwiftUI overlay (see overlayTextAnnotations).

    case .line(let l):
      let s = CGPoint(x: offset.x + l.start.x * scale, y: offset.y + l.start.y * scale)
      let e = CGPoint(x: offset.x + l.end.x * scale, y: offset.y + l.end.y * scale)
      let lw = l.stroke.lineWidth * scale
      var line = Path()
      line.move(to: s)
      line.addLine(to: e)
      context.stroke(line, with: .color(l.stroke.color), style: .init(lineWidth: lw, lineCap: .round))

    case .freehand(let f):
      guard f.points.count >= 2 else { break }
      var path = Path()
      let firstPt = CGPoint(x: offset.x + f.points[0].x * scale, y: offset.y + f.points[0].y * scale)
      path.move(to: firstPt)
      for pt in f.points.dropFirst() {
        let vpt = CGPoint(x: offset.x + pt.x * scale, y: offset.y + pt.y * scale)
        path.addLine(to: vpt)
      }
      let lw = f.stroke.lineWidth * scale
      let opacity: Double = f.isHighlighter ? 0.4 : 1.0
      context.stroke(path, with: .color(f.stroke.color.opacity(opacity)), style: .init(lineWidth: lw, lineCap: .round, lineJoin: .round))

    case .spotlight(let sp):
      // Draw dimming overlay with cutout for spotlight area
      let fullRect = CGRect(
        x: offset.x,
        y: offset.y,
        width: doc.imageSize.width * scale,
        height: doc.imageSize.height * scale
      )
      let spotRect = CGRect(
        x: offset.x + sp.rect.minX * scale,
        y: offset.y + sp.rect.minY * scale,
        width: sp.rect.width * scale,
        height: sp.rect.height * scale
      )

      // Create shape for the spotlight cutout
      let cutoutPath: Path
      switch sp.shape {
      case .rectangle:
        cutoutPath = Path(spotRect)
      case .roundedRect:
        cutoutPath = Path(roundedRect: spotRect, cornerRadius: 12)
      case .ellipse:
        cutoutPath = Path(ellipseIn: spotRect)
      }

      // Full rect minus cutout
      var dimmingPath = Path(fullRect)
      dimmingPath.addPath(cutoutPath)
      context.fill(dimmingPath, with: .color(.black.opacity(sp.dimmingOpacity)), style: .init(eoFill: true))

      // Optional border around spotlight
      if let borderStroke = sp.borderStroke {
        context.stroke(cutoutPath, with: .color(borderStroke.color), lineWidth: borderStroke.lineWidth * scale)
      }

    case .counter(let c):
      let center = CGPoint(x: offset.x + c.center.x * scale, y: offset.y + c.center.y * scale)
      let r = c.radius * scale
      let circleRect = CGRect(x: center.x - r, y: center.y - r, width: r * 2, height: r * 2)
      context.fill(Path(ellipseIn: circleRect), with: .color(c.fillColor))
      context.stroke(Path(ellipseIn: circleRect), with: .color(c.borderColor), lineWidth: max(1, c.borderWidth * scale))
      // Counter label is rendered as a SwiftUI overlay (see overlayTextAnnotations).

    case .emoji:
      // Emoji is rendered as a SwiftUI overlay (see overlayTextAnnotations).
      break
    }
  }

  @ViewBuilder
  private func overlayTextAnnotations(viewSize: CGSize) -> some View {
    let rect = fitRect(imageSize: doc.imageSize, in: viewSize)
    let scale = rect.width / doc.imageSize.width
    let pending = doc.pendingTextInput
    let editingID = pending?.targetAnnotationID

    ZStack(alignment: .topLeading) {
      ForEach(doc.annotations, id: \.id) { a in
        switch a {
        case .text(let t):
          Group {
            if pending?.kind == .text, editingID == t.id {
              EmptyView()
            } else {
              let pos = CGPoint(x: rect.origin.x + t.position.x * scale, y: rect.origin.y + t.position.y * scale)
              Group {
                if t.highlighted {
                  Text(t.text)
                    .font(.system(size: t.fontSize * scale, weight: .semibold))
                    .foregroundStyle(t.color)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .background(t.highlightColor.opacity(t.highlightOpacity))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                } else {
                  Text(t.text)
                    .font(.system(size: t.fontSize * scale, weight: .semibold))
                    .foregroundStyle(t.color)
                }
              }
              .offset(x: pos.x, y: pos.y)
            }
          }

        case .callout(let c):
          Group {
            if pending?.kind == .callout, editingID == c.id {
              EmptyView()
            } else {
              let vr = CGRect(
                x: rect.origin.x + c.rect.minX * scale,
                y: rect.origin.y + c.rect.minY * scale,
                width: c.rect.width * scale,
                height: c.rect.height * scale
              )
              let inset = vr.insetBy(dx: 14, dy: 12)
              Text(c.text)
                .font(.system(size: c.fontSize * scale, weight: .semibold))
                .foregroundStyle(c.textColor)
                .frame(width: inset.width, height: inset.height, alignment: .topLeading)
                .offset(x: inset.minX, y: inset.minY)
            }
          }

        case .step(let s):
          let center = CGPoint(x: rect.origin.x + s.center.x * scale, y: rect.origin.y + s.center.y * scale)
          let r = s.radius * scale
          Text(String(s.number))
            .font(.system(size: max(10, r * 0.9), weight: .semibold))
            .foregroundStyle(s.textColor)
            .position(x: center.x, y: center.y)

        case .counter(let c):
          let center = CGPoint(x: rect.origin.x + c.center.x * scale, y: rect.origin.y + c.center.y * scale)
          let r = c.radius * scale
          Text(c.value)
            .font(.system(size: max(10, r * 0.85), weight: .bold))
            .foregroundStyle(c.textColor)
            .position(x: center.x, y: center.y)

        case .emoji(let e):
          let pos = CGPoint(x: rect.origin.x + e.position.x * scale, y: rect.origin.y + e.position.y * scale)
          Text(e.emoji)
            .font(.system(size: e.size * scale))
            .position(x: pos.x, y: pos.y)

        case .measurement(let m):
          MeasurementLabelView(measurement: m, rect: rect, scale: scale)

        default:
          EmptyView()
        }
      }

      // Draw active freehand stroke while drawing
      if let activeStroke = doc.activeFreehandStroke, activeStroke.points.count >= 2 {
        Canvas { ctx, size in
          var path = Path()
          let firstPt = CGPoint(x: rect.origin.x + activeStroke.points[0].x * scale, y: rect.origin.y + activeStroke.points[0].y * scale)
          path.move(to: firstPt)
          for pt in activeStroke.points.dropFirst() {
            let vpt = CGPoint(x: rect.origin.x + pt.x * scale, y: rect.origin.y + pt.y * scale)
            path.addLine(to: vpt)
          }
          let lw = activeStroke.stroke.lineWidth * scale
          let opacity: Double = activeStroke.isHighlighter ? 0.4 : 1.0
          ctx.stroke(path, with: .color(activeStroke.stroke.color.opacity(opacity)), style: .init(lineWidth: lw, lineCap: .round, lineJoin: .round))
        }
        .allowsHitTesting(false)
      }

      if let pending, let targetID = pending.targetAnnotationID {
        InlineTextEditorOverlay(
          doc: doc,
          pending: pending,
          targetID: targetID,
          rect: rect,
          scale: scale
        )
      }
    }
    .frame(width: viewSize.width, height: viewSize.height, alignment: .topLeading)
    .allowsHitTesting(doc.pendingTextInput != nil)
  }

  // Arrowheads are drawn inline in the arrow case for better joins.

  private func drawSelection(for annotation: Annotation, context: inout GraphicsContext, scale: CGFloat, offset: CGPoint) {
    let dash: [CGFloat] = [6, 4]
    let stroke = StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round, miterLimit: 2, dash: dash, dashPhase: 0)

    switch annotation {
    case .step(let s):
      let c = CGPoint(x: offset.x + s.center.x * scale, y: offset.y + s.center.y * scale)
      let r = s.radius * scale
      let rr = CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)
      context.stroke(Path(ellipseIn: rr), with: .color(.blue.opacity(0.85)), style: stroke)

      // Steps: no resize handles for now.

    case .measurement(let m):
      let s = CGPoint(x: offset.x + m.start.x * scale, y: offset.y + m.start.y * scale)
      let e = CGPoint(x: offset.x + m.end.x * scale, y: offset.y + m.end.y * scale)
      var p = Path(); p.move(to: s); p.addLine(to: e)
      context.stroke(p, with: .color(.blue.opacity(0.85)), style: stroke)
      drawHandle(at: s, context: &context)
      drawHandle(at: e, context: &context)

    case .arrow(let a):
      let s = CGPoint(x: offset.x + a.start.x * scale, y: offset.y + a.start.y * scale)
      let e = CGPoint(x: offset.x + a.end.x * scale, y: offset.y + a.end.y * scale)
      var p = Path(); p.move(to: s); p.addLine(to: e)
      context.stroke(p, with: .color(.blue.opacity(0.85)), style: stroke)
      drawHandle(at: s, context: &context)
      drawHandle(at: e, context: &context)

    case .rect(let r):
      let vr = CGRect(x: offset.x + r.rect.minX * scale, y: offset.y + r.rect.minY * scale, width: r.rect.width * scale, height: r.rect.height * scale)
      context.stroke(Path(vr), with: .color(.blue.opacity(0.85)), style: stroke)
      drawRectHandles(rect: vr, context: &context)

    case .callout(let c):
      let vr = CGRect(x: offset.x + c.rect.minX * scale, y: offset.y + c.rect.minY * scale, width: c.rect.width * scale, height: c.rect.height * scale)
      context.stroke(Path(roundedRect: vr, cornerRadius: 14), with: .color(.blue.opacity(0.85)), style: stroke)
      drawRectHandles(rect: vr, context: &context)

    case .blur(let b):
      let vr = CGRect(x: offset.x + b.rect.minX * scale, y: offset.y + b.rect.minY * scale, width: b.rect.width * scale, height: b.rect.height * scale)
      context.stroke(Path(vr), with: .color(.blue.opacity(0.85)), style: stroke)
      drawRectHandles(rect: vr, context: &context)

    case .text(let t):
      let pos = CGPoint(x: offset.x + t.position.x * scale, y: offset.y + t.position.y * scale)
      let font = NSFont.systemFont(ofSize: t.fontSize * scale, weight: .semibold)
      let attrs: [NSAttributedString.Key: Any] = [.font: font]
      let m = (t.text as NSString).size(withAttributes: attrs)
      let r = CGRect(x: pos.x - 6, y: pos.y - 6, width: m.width + 12, height: m.height + 12)
      context.stroke(Path(roundedRect: r, cornerRadius: 10), with: .color(.blue.opacity(0.85)), style: stroke)

    case .line(let l):
      let s = CGPoint(x: offset.x + l.start.x * scale, y: offset.y + l.start.y * scale)
      let e = CGPoint(x: offset.x + l.end.x * scale, y: offset.y + l.end.y * scale)
      var p = Path(); p.move(to: s); p.addLine(to: e)
      context.stroke(p, with: .color(.blue.opacity(0.85)), style: stroke)
      drawHandle(at: s, context: &context)
      drawHandle(at: e, context: &context)

    case .freehand(let f):
      guard f.points.count >= 2 else { break }
      // Draw bounding box around freehand stroke
      let xs = f.points.map { $0.x }
      let ys = f.points.map { $0.y }
      let minX = (xs.min() ?? 0) * scale + offset.x
      let maxX = (xs.max() ?? 0) * scale + offset.x
      let minY = (ys.min() ?? 0) * scale + offset.y
      let maxY = (ys.max() ?? 0) * scale + offset.y
      let boundingRect = CGRect(x: minX - 4, y: minY - 4, width: maxX - minX + 8, height: maxY - minY + 8)
      context.stroke(Path(boundingRect), with: .color(.blue.opacity(0.85)), style: stroke)

    case .spotlight(let sp):
      let vr = CGRect(x: offset.x + sp.rect.minX * scale, y: offset.y + sp.rect.minY * scale, width: sp.rect.width * scale, height: sp.rect.height * scale)
      context.stroke(Path(vr), with: .color(.blue.opacity(0.85)), style: stroke)
      drawRectHandles(rect: vr, context: &context)

    case .counter(let c):
      let center = CGPoint(x: offset.x + c.center.x * scale, y: offset.y + c.center.y * scale)
      let r = c.radius * scale
      let rr = CGRect(x: center.x - r, y: center.y - r, width: r * 2, height: r * 2)
      context.stroke(Path(ellipseIn: rr), with: .color(.blue.opacity(0.85)), style: stroke)

    case .emoji(let e):
      let pos = CGPoint(x: offset.x + e.position.x * scale, y: offset.y + e.position.y * scale)
      let halfSize = e.size * scale / 2
      let r = CGRect(x: pos.x - halfSize, y: pos.y - halfSize, width: e.size * scale, height: e.size * scale)
      context.stroke(Path(roundedRect: r, cornerRadius: 8), with: .color(.blue.opacity(0.85)), style: stroke)
    }
  }

  private func drawRectHandles(rect: CGRect, context: inout GraphicsContext) {
    let points: [CGPoint] = [
      CGPoint(x: rect.minX, y: rect.minY),
      CGPoint(x: rect.midX, y: rect.minY),
      CGPoint(x: rect.maxX, y: rect.minY),
      CGPoint(x: rect.maxX, y: rect.midY),
      CGPoint(x: rect.maxX, y: rect.maxY),
      CGPoint(x: rect.midX, y: rect.maxY),
      CGPoint(x: rect.minX, y: rect.maxY),
      CGPoint(x: rect.minX, y: rect.midY)
    ]
    for p in points {
      drawHandle(at: p, context: &context)
    }
  }

  private func drawHandle(at point: CGPoint, context: inout GraphicsContext) {
    let s: CGFloat = 8
    let r = CGRect(x: point.x - s / 2, y: point.y - s / 2, width: s, height: s)
    context.fill(Path(roundedRect: r, cornerRadius: 2), with: .color(.white))
    context.stroke(Path(roundedRect: r, cornerRadius: 2), with: .color(.blue.opacity(0.9)), lineWidth: 1.5)
  }

  private func hitTestHandle(point: CGPoint, annotation: Annotation, viewSize: CGSize) -> HandleHit? {
    // Hit in image coordinates, but handle size should be ~constant in view pixels.
    let rect = fitRect(imageSize: doc.imageSize, in: viewSize)
    let scale = rect.width / doc.imageSize.width
    let hitRadiusImg: CGFloat = 10 / max(0.0001, scale)

    func near(_ p: CGPoint) -> Bool {
      hypot(point.x - p.x, point.y - p.y) <= hitRadiusImg
    }

    switch annotation {
    case .arrow(let a):
      if near(a.start) { return HandleHit(kind: .arrowStart) }
      if near(a.end) { return HandleHit(kind: .arrowEnd) }
      return nil

    case .rect(let r):
      return hitRectHandle(point: point, rect: r.rect, hitRadiusImg: hitRadiusImg)
        .map { HandleHit(kind: .rect($0)) }

    case .callout(let c):
      return hitRectHandle(point: point, rect: c.rect, hitRadiusImg: hitRadiusImg)
        .map { HandleHit(kind: .rect($0)) }

    case .blur(let b):
      return hitRectHandle(point: point, rect: b.rect, hitRadiusImg: hitRadiusImg)
        .map { HandleHit(kind: .rect($0)) }

    case .measurement(let m):
      // Check label hit first (it's on top visually)
      let fontSize: CGFloat = max(14, m.stroke.lineWidth * 3.5)
      let estimatedLabelWidth = CGFloat(m.formattedMeasurement.count) * fontSize * 0.6 + 16
      let (labelPos, _) = m.labelPosition(estimatedLabelWidth: estimatedLabelWidth)
      let labelHitRadius = max(hitRadiusImg, 25)
      if hypot(point.x - labelPos.x, point.y - labelPos.y) <= labelHitRadius {
        return HandleHit(kind: .measurementLabel)
      }
      if near(m.start) { return HandleHit(kind: .measurementStart) }
      if near(m.end) { return HandleHit(kind: .measurementEnd) }
      return nil

    case .line(let l):
      if near(l.start) { return HandleHit(kind: .lineStart) }
      if near(l.end) { return HandleHit(kind: .lineEnd) }
      return nil

    case .spotlight(let sp):
      return hitRectHandle(point: point, rect: sp.rect, hitRadiusImg: hitRadiusImg)
        .map { HandleHit(kind: .rect($0)) }

    default:
      return nil
    }
  }

  private func hitRectHandle(point: CGPoint, rect: CGRect, hitRadiusImg: CGFloat) -> RectHandle? {
    let candidates: [(RectHandle, CGPoint)] = [
      (.topLeft, CGPoint(x: rect.minX, y: rect.minY)),
      (.top, CGPoint(x: rect.midX, y: rect.minY)),
      (.topRight, CGPoint(x: rect.maxX, y: rect.minY)),
      (.right, CGPoint(x: rect.maxX, y: rect.midY)),
      (.bottomRight, CGPoint(x: rect.maxX, y: rect.maxY)),
      (.bottom, CGPoint(x: rect.midX, y: rect.maxY)),
      (.bottomLeft, CGPoint(x: rect.minX, y: rect.maxY)),
      (.left, CGPoint(x: rect.minX, y: rect.midY))
    ]
    for (h, p) in candidates {
      if hypot(point.x - p.x, point.y - p.y) <= hitRadiusImg {
        return h
      }
    }
    return nil
  }

  private func applyHandleDrag(handle: HandleHit, current: CGPoint, original: Annotation, annotation: inout Annotation) {
    // Use the geometry from `original` as the baseline (no cumulative drift).
    let bounds = CGRect(x: 0, y: 0, width: doc.imageSize.width, height: doc.imageSize.height)
    let minSize: CGFloat = 8

    func clampRect(_ r: CGRect) -> CGRect {
      var rr = r
      if rr.width < minSize { rr.size.width = minSize }
      if rr.height < minSize { rr.size.height = minSize }
      rr = rr.standardized
      rr.origin.x = max(bounds.minX, min(bounds.maxX - rr.width, rr.origin.x))
      rr.origin.y = max(bounds.minY, min(bounds.maxY - rr.height, rr.origin.y))
      rr.size.width = min(bounds.maxX - rr.minX, rr.width)
      rr.size.height = min(bounds.maxY - rr.minY, rr.height)
      return rr
    }

    switch (handle.kind, original, annotation) {
    case (.arrowStart, .arrow(let o), .arrow(var a)):
      var newStart = current
      if isShiftDown {
        newStart = snap45(from: o.end, to: current)
      }
      a.start = newStart
      annotation = .arrow(a)

    case (.arrowEnd, .arrow(let o), .arrow(var a)):
      var newEnd = current
      if isShiftDown {
        newEnd = snap45(from: o.start, to: current)
      }
      a.end = newEnd
      annotation = .arrow(a)

    case (.rect(let h), .rect(let o), .rect(var r)):
      r.rect = clampRect(resizedRect(from: o.rect, handle: h, to: current, constrainSquare: isShiftDown))
      annotation = .rect(r)

    case (.rect(let h), .callout(let o), .callout(var c)):
      c.rect = clampRect(resizedRect(from: o.rect, handle: h, to: current, constrainSquare: false))
      annotation = .callout(c)

    case (.rect(let h), .blur(let o), .blur(var b)):
      b.rect = clampRect(resizedRect(from: o.rect, handle: h, to: current, constrainSquare: false))
      annotation = .blur(b)

    case (.measurementStart, .measurement(let o), .measurement(var m)):
      var newStart = current
      if isShiftDown {
        newStart = snap45(from: o.end, to: current)
      }
      m.start = newStart
      annotation = .measurement(m)

    case (.measurementEnd, .measurement(let o), .measurement(var m)):
      var newEnd = current
      if isShiftDown {
        newEnd = snap45(from: o.start, to: current)
      }
      m.end = newEnd
      annotation = .measurement(m)

    case (.measurementLabel, .measurement(let o), .measurement(var m)):
      // Calculate the offset from the default label position
      let defaultMidpoint = o.midpoint
      m.labelOffset = CGPoint(x: current.x - defaultMidpoint.x, y: current.y - defaultMidpoint.y)
      annotation = .measurement(m)

    case (.lineStart, .line(let o), .line(var l)):
      var newStart = current
      if isShiftDown {
        newStart = snap45(from: o.end, to: current)
      }
      l.start = newStart
      annotation = .line(l)

    case (.lineEnd, .line(let o), .line(var l)):
      var newEnd = current
      if isShiftDown {
        newEnd = snap45(from: o.start, to: current)
      }
      l.end = newEnd
      annotation = .line(l)

    case (.rect(let h), .spotlight(let o), .spotlight(var sp)):
      sp.rect = clampRect(resizedRect(from: o.rect, handle: h, to: current, constrainSquare: isShiftDown))
      annotation = .spotlight(sp)

    default:
      break
    }
  }

  private func resizedRect(from original: CGRect, handle: RectHandle, to point: CGPoint, constrainSquare: Bool) -> CGRect {
    var minX = original.minX
    var maxX = original.maxX
    var minY = original.minY
    var maxY = original.maxY

    if handle.affectsLeft { minX = point.x }
    if handle.affectsRight { maxX = point.x }
    if handle.affectsTop { minY = point.y }
    if handle.affectsBottom { maxY = point.y }

    var r = CGRect(x: min(minX, maxX), y: min(minY, maxY), width: abs(maxX - minX), height: abs(maxY - minY))

    if constrainSquare {
      // Keep square by growing/shrinking based on the larger delta, anchored at opposite side.
      let size = max(r.width, r.height)
      let isLeft = handle.affectsLeft && !handle.affectsRight
      let isTop = handle.affectsTop && !handle.affectsBottom
      if isLeft {
        r.origin.x = original.maxX - size
      }
      if isTop {
        r.origin.y = original.maxY - size
      }
      r.size = CGSize(width: size, height: size)
    }

    return r
  }

  private func hitTest(point: CGPoint) -> UUID? {
    // Simple hit-test: prefer top-most.
    for a in doc.annotations.reversed() {
      switch a {
      case .rect(let r):
        if r.rect.insetBy(dx: -8, dy: -8).contains(point) { return r.id }
      case .callout(let c):
        if c.rect.insetBy(dx: -8, dy: -8).contains(point) { return c.id }
      case .arrow(let ar):
        if distancePointToSegment(p: point, a: ar.start, b: ar.end) <= 10 { return ar.id }
      case .text(let t):
        let approx = CGRect(x: t.position.x, y: t.position.y - t.fontSize, width: max(20, CGFloat(t.text.count) * t.fontSize * 0.6), height: t.fontSize * 1.2)
        if approx.insetBy(dx: -10, dy: -10).contains(point) { return t.id }

      case .blur(let b):
        if b.rect.insetBy(dx: -8, dy: -8).contains(point) { return b.id }

      case .step(let s):
        if hypot(point.x - s.center.x, point.y - s.center.y) <= (s.radius + 8) { return s.id }

      case .measurement(let m):
        // Check the line
        if distancePointToSegment(p: point, a: m.start, b: m.end) <= 10 { return m.id }
        // Check the label (which may be offset)
        let fontSize: CGFloat = max(14, m.stroke.lineWidth * 3.5)
        let estimatedLabelWidth = CGFloat(m.formattedMeasurement.count) * fontSize * 0.6 + 16
        let (labelPos, _) = m.labelPosition(estimatedLabelWidth: estimatedLabelWidth)
        if hypot(point.x - labelPos.x, point.y - labelPos.y) <= 30 { return m.id }

      case .line(let l):
        if distancePointToSegment(p: point, a: l.start, b: l.end) <= 10 { return l.id }

      case .freehand(let f):
        // Check distance to the path
        for i in 0..<(f.points.count - 1) {
          if distancePointToSegment(p: point, a: f.points[i], b: f.points[i + 1]) <= max(10, f.stroke.lineWidth / 2) {
            return f.id
          }
        }

      case .spotlight(let sp):
        if sp.rect.insetBy(dx: -8, dy: -8).contains(point) { return sp.id }

      case .counter(let c):
        if hypot(point.x - c.center.x, point.y - c.center.y) <= (c.radius + 8) { return c.id }

      case .emoji(let e):
        let approx = CGRect(x: e.position.x - e.size / 2, y: e.position.y - e.size / 2, width: e.size, height: e.size)
        if approx.insetBy(dx: -10, dy: -10).contains(point) { return e.id }
      }
    }
    return nil
  }

  private func distancePointToSegment(p: CGPoint, a: CGPoint, b: CGPoint) -> CGFloat {
    let ap = CGPoint(x: p.x - a.x, y: p.y - a.y)
    let ab = CGPoint(x: b.x - a.x, y: b.y - a.y)
    let ab2 = ab.x * ab.x + ab.y * ab.y
    if ab2 == 0 { return hypot(ap.x, ap.y) }
    var t = (ap.x * ab.x + ap.y * ab.y) / ab2
    t = max(0, min(1, t))
    let proj = CGPoint(x: a.x + ab.x * t, y: a.y + ab.y * t)
    return hypot(p.x - proj.x, p.y - proj.y)
  }

  private func applyMove(delta: CGPoint, annotation: inout Annotation) {
    switch annotation {
    case .rect(var r):
      r.rect = r.rect.offsetBy(dx: delta.x, dy: delta.y)
      annotation = .rect(r)
    case .callout(var c):
      c.rect = c.rect.offsetBy(dx: delta.x, dy: delta.y)
      annotation = .callout(c)
    case .arrow(var a):
      a.start = CGPoint(x: a.start.x + delta.x, y: a.start.y + delta.y)
      a.end = CGPoint(x: a.end.x + delta.x, y: a.end.y + delta.y)
      annotation = .arrow(a)
    case .text(var t):
      t.position = CGPoint(x: t.position.x + delta.x, y: t.position.y + delta.y)
      annotation = .text(t)

    case .blur(var b):
      b.rect = b.rect.offsetBy(dx: delta.x, dy: delta.y)
      annotation = .blur(b)

    case .step(var s):
      s.center = CGPoint(x: s.center.x + delta.x, y: s.center.y + delta.y)
      annotation = .step(s)

    case .measurement(var m):
      m.start = CGPoint(x: m.start.x + delta.x, y: m.start.y + delta.y)
      m.end = CGPoint(x: m.end.x + delta.x, y: m.end.y + delta.y)
      annotation = .measurement(m)

    case .line(var l):
      l.start = CGPoint(x: l.start.x + delta.x, y: l.start.y + delta.y)
      l.end = CGPoint(x: l.end.x + delta.x, y: l.end.y + delta.y)
      annotation = .line(l)

    case .freehand(var f):
      f.points = f.points.map { CGPoint(x: $0.x + delta.x, y: $0.y + delta.y) }
      annotation = .freehand(f)

    case .spotlight(var sp):
      sp.rect = sp.rect.offsetBy(dx: delta.x, dy: delta.y)
      annotation = .spotlight(sp)

    case .counter(var c):
      c.center = CGPoint(x: c.center.x + delta.x, y: c.center.y + delta.y)
      annotation = .counter(c)

    case .emoji(var e):
      e.position = CGPoint(x: e.position.x + delta.x, y: e.position.y + delta.y)
      annotation = .emoji(e)
    }
  }
}

private struct InlineTextEditorOverlay: View {
  @ObservedObject var doc: AnnotationDocument
  let pending: AnnotationDocument.PendingTextInput
  let targetID: UUID
  let rect: CGRect
  let scale: CGFloat

  @FocusState private var focused: Bool

  private var textBinding: Binding<String> {
    Binding(
      get: {
        guard let a = doc.annotations.first(where: { $0.id == targetID }) else { return "" }
        switch a {
        case .text(let t):
          return t.text
        case .callout(let c):
          return c.text
        default:
          return ""
        }
      },
      set: { newValue in
        // Live updates while typing (no new undo checkpoints per keystroke).
        doc.selectedID = targetID
        doc.updateSelectedInSession { ann in
          guard ann.id == targetID else { return }
          switch ann {
          case .text(var t):
            t.text = newValue
            ann = .text(t)
          case .callout(var c):
            c.text = newValue
            ann = .callout(c)
          default:
            break
          }
        }
      }
    )
  }

  var body: some View {
    Group {
      switch pending.kind {
      case .text:
        inlineTextField
          .offset(x: textFieldOrigin.x, y: textFieldOrigin.y)

      case .callout:
        inlineCalloutField

      default:
        EmptyView()
      }
    }
    .onAppear {
      doc.beginEditSessionIfNeeded()
      DispatchQueue.main.async {
        focused = true
      }
    }
    .onChange(of: pending.id) { _ in
      doc.beginEditSessionIfNeeded()
      DispatchQueue.main.async {
        focused = true
      }
    }
  }

  private var inlineTextField: some View {
    let (fontSize, color, highlighted, highlightColor, highlightOpacity) = currentTextStyle

    return Group {
      if #available(macOS 13.0, *) {
        TextField("Text", text: textBinding, axis: .vertical)
          .lineLimit(1...4)
      } else {
        TextField("Text", text: textBinding)
      }
    }
    .focused($focused)
    .font(.system(size: fontSize, weight: .semibold))
    .foregroundStyle(color)
    .textFieldStyle(.plain)
    // Keep the inline editor only as wide as the content (clamped to the image bounds).
    .frame(width: textFieldWidth, alignment: .leading)
    .fixedSize(horizontal: true, vertical: false)
    .padding(.horizontal, 8)
    .padding(.vertical, 6)
    .background(
      Group {
        if highlighted {
          highlightColor.opacity(highlightOpacity)
        } else {
          Color.black.opacity(0.25)
        }
      }
    )
    .clipShape(RoundedRectangle(cornerRadius: 10))
    .overlay(
      RoundedRectangle(cornerRadius: 10)
        .strokeBorder(Color.white.opacity(0.35), lineWidth: 1)
    )
    .onSubmit {
      doc.commitPendingTextInput()
    }
    .onExitCommand {
      doc.cancelPendingTextInput()
    }
  }

  private var inlineCalloutField: some View {
    guard let callout = currentCallout else { return AnyView(EmptyView()) }

    let vr = CGRect(
      x: rect.origin.x + callout.rect.minX * scale,
      y: rect.origin.y + callout.rect.minY * scale,
      width: callout.rect.width * scale,
      height: callout.rect.height * scale
    )
    let inset = vr.insetBy(dx: 14, dy: 12)
    let fontSize = callout.fontSize * scale

    let field = Group {
      if #available(macOS 13.0, *) {
        TextField("Text", text: textBinding, axis: .vertical)
          .lineLimit(1...6)
      } else {
        TextField("Text", text: textBinding)
      }
    }
    .focused($focused)
    .font(.system(size: fontSize, weight: .semibold))
    .foregroundStyle(callout.textColor)
    .textFieldStyle(.plain)
    .padding(.horizontal, 4)
    .padding(.vertical, 2)
    .frame(width: inset.width, height: inset.height, alignment: .topLeading)
    .background(Color.black.opacity(0.18))
    .clipShape(RoundedRectangle(cornerRadius: 8))
    .overlay(
      RoundedRectangle(cornerRadius: 8)
        .strokeBorder(Color.white.opacity(0.28), lineWidth: 1)
    )
    .offset(x: inset.minX, y: inset.minY)
    .onSubmit {
      doc.commitPendingTextInput()
    }
    .onExitCommand {
      doc.cancelPendingTextInput()
    }

    return AnyView(field)
  }

  private var textFieldWidth: CGFloat {
    let (fontSize, _, _, _, _) = currentTextStyle
    let font = NSFont.systemFont(ofSize: fontSize, weight: .semibold)

    let raw = textBinding.wrappedValue
    let textForMeasure = raw.isEmpty ? "Text" : raw
    let lines = textForMeasure.split(separator: "\n", omittingEmptySubsequences: false)
    let widestLine = lines
      .map { (String($0) as NSString).size(withAttributes: [.font: font]).width }
      .max() ?? 0

    // The TextField also has horizontal padding; account for that.
    let ideal = max(60, widestLine + 16)

    // Clamp so it never runs off the fitted image rect.
    let availableRight = max(60, rect.maxX - textOrigin.x - 8)
    return min(ideal, availableRight)
  }

  private var textFieldOrigin: CGPoint {
    // If we're near the right edge, shift left so the editor stays in-bounds.
    let x = min(textOrigin.x, rect.maxX - textFieldWidth - 8)
    let clampedX = max(rect.minX + 4, x)
    return CGPoint(x: clampedX, y: textOrigin.y)
  }

  private var textOrigin: CGPoint {
    if let t = currentText {
      return CGPoint(x: rect.origin.x + t.position.x * scale, y: rect.origin.y + t.position.y * scale)
    }
    // Fallback to pending position.
    if case .position(let p) = pending.positionOrRect {
      return CGPoint(x: rect.origin.x + p.x * scale, y: rect.origin.y + p.y * scale)
    }
    return rect.origin
  }

  private var currentText: TextAnnotation? {
    guard let a = doc.annotations.first(where: { $0.id == targetID }) else { return nil }
    if case .text(let t) = a { return t }
    return nil
  }

  private var currentCallout: CalloutAnnotation? {
    guard let a = doc.annotations.first(where: { $0.id == targetID }) else { return nil }
    if case .callout(let c) = a { return c }
    return nil
  }

  private var currentTextStyle: (fontSize: CGFloat, color: Color, highlighted: Bool, highlightColor: Color, highlightOpacity: CGFloat) {
    if let t = currentText {
      return (t.fontSize * scale, t.color, t.highlighted, t.highlightColor, t.highlightOpacity)
    }
    // Fallback to current toolbar settings.
    return (doc.textFontSize * scale, doc.textColor, doc.textHighlighted, .yellow, 0.35)
  }
}

private struct PendingTextOverlay: View {
  @ObservedObject var doc: AnnotationDocument
  let pending: AnnotationDocument.PendingTextInput
  let viewSize: CGSize
  let anchorPoint: CGPoint?

  @State private var text: String
  @FocusState private var isTextFieldFocused: Bool

  init(doc: AnnotationDocument, pending: AnnotationDocument.PendingTextInput, viewSize: CGSize, anchorPoint: CGPoint?) {
    self.doc = doc
    self.pending = pending
    self.viewSize = viewSize
    self.anchorPoint = anchorPoint
    self._text = State(initialValue: pending.initialText)
  }

  var body: some View {
    ZStack {
      if let anchorPoint {
        promptCard
          .position(clampedPromptCenter(near: anchorPoint))
      } else {
        VStack {
          Spacer()
          HStack {
            Spacer()
            promptCard
            Spacer()
          }
          Spacer()
        }
      }
    }
  }

  private var promptCard: some View {
    VStack(alignment: .leading, spacing: 10) {
      Text(pending.kind == .callout ? "Callout" : "Text")
        .font(.system(size: 13, weight: .semibold))

      Group {
        if #available(macOS 13.0, *) {
          TextField("Text", text: $text, axis: .vertical)
            .lineLimit(1...4)
        } else {
          TextField("Text", text: $text)
        }
      }
      .focused($isTextFieldFocused)
      .textFieldStyle(.roundedBorder)
      .frame(maxWidth: .infinity)

      HStack {
        Button("Cancel") { cancel() }
        Spacer()
        Button("Add") { commit() }
          .keyboardShortcut(.defaultAction)
      }
    }
    // Constrain the prompt width so the button-row Spacer can't force a full-width modal.
    .frame(width: 420)
    .padding(14)
    .background(
      RoundedRectangle(cornerRadius: 14)
        .fill(Color(nsColor: .windowBackgroundColor).opacity(0.96))
    )
    .overlay(
      RoundedRectangle(cornerRadius: 14)
        .strokeBorder(Color.black.opacity(0.18), lineWidth: 1)
    )
    .shadow(color: Color.black.opacity(0.25), radius: 18, x: 0, y: 10)
    .onAppear {
      // Make typing immediate without an extra click.
      DispatchQueue.main.async {
        isTextFieldFocused = true
      }
    }
    .onChange(of: pending.id) { _ in
      DispatchQueue.main.async {
        isTextFieldFocused = true
      }
    }
  }

  private func clampedPromptCenter(near anchor: CGPoint) -> CGPoint {
    let promptWidth: CGFloat = 420
    let estimatedHeight: CGFloat = 170
    let margin: CGFloat = 16

    let desired = CGPoint(x: anchor.x, y: anchor.y + 70)

    let minX = (promptWidth / 2) + margin
    let maxX = max(minX, viewSize.width - (promptWidth / 2) - margin)
    let minY = (estimatedHeight / 2) + margin
    let maxY = max(minY, viewSize.height - (estimatedHeight / 2) - margin)

    return CGPoint(
      x: min(max(desired.x, minX), maxX),
      y: min(max(desired.y, minY), maxY)
    )
  }

  private func cancel() {
    doc.cancelPendingTextInput()
  }

  private func commit() {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else {
      cancel()
      return
    }

    doc.pushUndoCheckpoint()

    switch pending.kind {
    case .text:
      if let targetID = pending.targetAnnotationID {
        doc.selectedID = targetID
        doc.updateSelectedMaybeInSession { ann in
          guard ann.id == targetID else { return }
          if case .text(var t) = ann {
            t.text = trimmed
            t.color = doc.textColor
            t.fontSize = doc.textFontSize
            t.highlighted = doc.textHighlighted
            ann = .text(t)
          }
        }
      } else if case .position(let p) = pending.positionOrRect {
        doc.annotations.append(
          .text(
            TextAnnotation(
              position: p,
              text: trimmed,
              color: doc.textColor,
              fontSize: doc.textFontSize,
              highlighted: doc.textHighlighted
            )
          )
        )
        doc.selectedID = doc.annotations.last?.id
      }

    case .callout:
      if let targetID = pending.targetAnnotationID {
        doc.selectedID = targetID
        doc.updateSelectedMaybeInSession { ann in
          guard ann.id == targetID else { return }
          if case .callout(var c) = ann {
            c.text = trimmed
            c.stroke = doc.stroke
            c.fill = doc.fill
            c.textColor = doc.textColor
            c.fontSize = doc.textFontSize
            ann = .callout(c)
          }
        }
      } else if case .rect(let r) = pending.positionOrRect {
        doc.annotations.append(
          .callout(
            CalloutAnnotation(
              rect: r,
              text: trimmed,
              stroke: doc.stroke,
              fill: doc.fill,
              textColor: doc.textColor,
              fontSize: doc.textFontSize
            )
          )
        )
        doc.selectedID = doc.annotations.last?.id
      }

    default:
      break
    }

    doc.pendingTextInput = nil
  }
}

private struct MeasurementLabelView: View {
  let measurement: MeasurementAnnotation
  let rect: CGRect
  let scale: CGFloat

  var body: some View {
    let fontSize = max(12, measurement.stroke.lineWidth * 3.5 * scale)
    let estimatedLabelWidth = CGFloat(measurement.formattedMeasurement.count) * fontSize * 0.6 + 16

    // Get the label position in image coordinates, then convert to view coordinates
    let (imgLabelPos, _) = measurement.labelPosition(estimatedLabelWidth: estimatedLabelWidth / scale)
    let labelPos = CGPoint(
      x: rect.origin.x + imgLabelPos.x * scale,
      y: rect.origin.y + imgLabelPos.y * scale
    )

    Text(measurement.formattedMeasurement)
      .font(.system(size: fontSize, weight: .semibold))
      .foregroundStyle(.white)
      .padding(.horizontal, 8)
      .padding(.vertical, 4)
      .background(Color.black.opacity(0.75))
      .clipShape(RoundedRectangle(cornerRadius: 6))
      .position(x: labelPos.x, y: labelPos.y)
  }
}

private func snap45(from: CGPoint, to: CGPoint) -> CGPoint {
  let dx = to.x - from.x
  let dy = to.y - from.y
  let angle = atan2(dy, dx)
  let step = CGFloat.pi / 4
  let snapped = round(angle / step) * step
  let len = hypot(dx, dy)
  return CGPoint(x: from.x + cos(snapped) * len, y: from.y + sin(snapped) * len)
}
