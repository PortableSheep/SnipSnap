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
  @State private var marqueeBaseSelection: Set<UUID> = []
  @State private var marqueeIsAdditive = false

  @State private var isShiftDown: Bool = false
  
  // Pan gesture state
  @State private var panGestureActive: Bool = false
  @State private var panStartOffset: CGSize = .zero

  var body: some View {
    GeometryReader { geo in
      ZStack {
        // Background checker
        Color.black.opacity(0.02)

        Canvas { context, size in
          let appliedCrop = doc.isCropping ? nil : doc.cropRect.map { cropViewRect($0, size: size) }
          if let appliedCrop, doc.backgroundStyle == .none {
            context.clip(to: Path(appliedCrop))
          }
          drawBaseImage(context: &context, size: size)
          drawAnnotations(context: &context, size: size)
          drawInProgress(context: &context, size: size)
          if let appliedCrop, doc.backgroundStyle != .none {
            var outside = Path(fitRect(imageSize: doc.imageSize, in: size))
            outside.addRect(appliedCrop)
            context.fill(outside, with: .color(.black.opacity(0.6)), style: FillStyle(eoFill: true))
          }
        }
        .gesture(dragGesture(in: geo.size))
        .simultaneousGesture(tapGesture(in: geo.size))
        .simultaneousGesture(magnificationGesture())
        .onContinuousHover { phase in
          // Update cursor based on pan mode
          switch phase {
          case .active:
            if doc.tool == .hand && doc.pendingTextInput == nil {
              NSCursor.openHand.set()
            } else {
              NSCursor.arrow.set()
            }
          case .ended:
            NSCursor.arrow.set()
          }
        }

        // Invisible overlay for scroll-wheel zoom and middle-click pan
        ScrollZoomView(doc: doc, viewSize: geo.size)
          .allowsHitTesting(false)

        overlayTextAnnotations(viewSize: geo.size)

        if doc.isCropping {
          CropOverlayView(doc: doc, imageRect: fitRect(imageSize: doc.imageSize, in: geo.size))
        }

        if doc.pendingTextInput != nil {
          Color.black.opacity(0.28)
            .ignoresSafeArea()
            .onTapGesture {
              doc.commitPendingTextInput()
            }
        }
      }
      .onAppear {
        // Monitor modifier keys
        NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { event in
          isShiftDown = event.modifierFlags.contains(.shift)
          return event
        }
        
      }
    }
  }

  private func drawBaseImage(context: inout GraphicsContext, size: CGSize) {
    let imageRect = fitRect(imageSize: doc.imageSize, in: size)
    let scale = imageRect.width / doc.imageSize.width
    
    // If background is set, draw it first with padding
    if doc.backgroundStyle != .none {
      let padding = doc.backgroundPadding * scale
      let backgroundRect = imageRect.insetBy(dx: -padding, dy: -padding)
      
      // Draw background
      switch doc.backgroundStyle {
      case .none:
        break
        
      case .solid:
        context.fill(Path(backgroundRect), with: .color(doc.backgroundColor))
        
      case .gradient:
        let gradient = Gradient(colors: [doc.backgroundGradientStart, doc.backgroundGradientEnd])
        let startPoint: CGPoint
        let endPoint: CGPoint
        
        switch doc.backgroundGradientDirection {
        case .topToBottom:
          startPoint = CGPoint(x: backgroundRect.midX, y: backgroundRect.minY)
          endPoint = CGPoint(x: backgroundRect.midX, y: backgroundRect.maxY)
        case .leftToRight:
          startPoint = CGPoint(x: backgroundRect.minX, y: backgroundRect.midY)
          endPoint = CGPoint(x: backgroundRect.maxX, y: backgroundRect.midY)
        case .topLeftToBottomRight:
          startPoint = CGPoint(x: backgroundRect.minX, y: backgroundRect.minY)
          endPoint = CGPoint(x: backgroundRect.maxX, y: backgroundRect.maxY)
        case .radial:
          startPoint = CGPoint(x: backgroundRect.midX, y: backgroundRect.midY)
          endPoint = CGPoint(x: backgroundRect.maxX, y: backgroundRect.midY)
        }
        
        context.fill(Path(backgroundRect), with: .linearGradient(gradient, startPoint: startPoint, endPoint: endPoint))
        
      case .mesh:
        let gradient = Gradient(colors: [doc.backgroundGradientStart, doc.backgroundGradientEnd])
        let startPoint = CGPoint(x: backgroundRect.minX, y: backgroundRect.minY)
        let endPoint = CGPoint(x: backgroundRect.maxX, y: backgroundRect.maxY)
        context.fill(Path(backgroundRect), with: .linearGradient(gradient, startPoint: startPoint, endPoint: endPoint))
        
      case .wallpaper:
        if let wallpaper = doc.getWallpaper(),
           let cgImage = wallpaper.cgImage(forProposedRect: nil, context: nil, hints: nil) {
          context.draw(Image(decorative: cgImage, scale: 1.0), in: backgroundRect)
        } else {
          context.fill(Path(backgroundRect), with: .color(.gray.opacity(0.2)))
        }
      }
      
      // Draw shadow if enabled
      if doc.backgroundShadowEnabled {
        let shadowCornerRadius = doc.backgroundCornerRadius > 0 ? doc.backgroundCornerRadius * scale : 0
        context.drawLayer { ctx in
          ctx.addFilter(.shadow(color: .black.opacity(doc.backgroundShadowOpacity), radius: doc.backgroundShadowRadius * scale))
          ctx.fill(Path(roundedRect: imageRect, cornerRadius: shadowCornerRadius), with: .color(.white))
        }
      }
    }
    
    // Draw the actual image (with optional corner radius clipping)
    let cornerRadius = doc.backgroundCornerRadius
    if cornerRadius > 0 {
      let scaledRadius = cornerRadius * scale
      let roundedPath = Path(roundedRect: imageRect, cornerRadius: scaledRadius)

      // Draw checkerboard behind corners when no background is set
      if doc.backgroundStyle == .none {
        let checkerSize: CGFloat = 6
        context.drawLayer { ctx in
          ctx.clip(to: roundedPath)
          let cols = Int(ceil(imageRect.width / checkerSize))
          let rows = Int(ceil(imageRect.height / checkerSize))
          for row in 0..<rows {
            for col in 0..<cols {
              let r = CGRect(
                x: imageRect.minX + CGFloat(col) * checkerSize,
                y: imageRect.minY + CGFloat(row) * checkerSize,
                width: checkerSize,
                height: checkerSize
              )
              let shade: Color = (row + col) % 2 == 0 ? .white : .gray.opacity(0.2)
              ctx.fill(Path(r), with: .color(shade))
            }
          }
        }
      }

      context.drawLayer { ctx in
        ctx.clip(to: roundedPath)
        ctx.draw(Image(decorative: doc.cgImage, scale: 1), in: imageRect)
      }
    } else {
      context.draw(Image(decorative: doc.cgImage, scale: 1), in: imageRect)
    }
  }

  private func drawAnnotations(context: inout GraphicsContext, size: CGSize) {
    let rect = fitRect(imageSize: doc.imageSize, in: size)
    let scale = rect.width / doc.imageSize.width

    // Blur/pixelate first (underlays)
    for a in doc.annotations {
      if case .blur = a {
        draw(annotation: a, context: &context, scale: scale, offset: rect.origin)
      }
    }

    // Collect all spotlights and draw them as a single combined dimming layer
    let spotlights = doc.annotations.compactMap { a -> SpotlightAnnotation? in
      if case .spotlight(let sp) = a { return sp }
      return nil
    }
    if !spotlights.isEmpty {
      drawCombinedSpotlights(spotlights, context: &context, scale: scale, offset: rect.origin)
    }

    // Then all other overlays (skip spotlights, already drawn)
    for a in doc.annotations {
      if case .blur = a { continue }
      if case .spotlight = a { continue }
      draw(annotation: a, context: &context, scale: scale, offset: rect.origin)
    }

    // Selection outline always on top
    for annotation in doc.annotations where doc.selectedIDs.contains(annotation.id) {
      drawSelection(
        for: annotation, context: &context, scale: scale, offset: rect.origin,
        showHandles: doc.selectedIDs.count == 1
      )
    }

    // Draw redaction suggestion indicators
    drawRedactionSuggestions(context: &context, scale: scale, offset: rect.origin)
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

      if suggestion.isSelected {
        // Selected suggestion: bold dashed orange border and soft fill
        context.stroke(
          Path(roundedRect: scaled, cornerRadius: 4),
          with: .color(.orange),
          style: StrokeStyle(lineWidth: 2, dash: [6, 4])
        )
        context.fill(
          Path(roundedRect: scaled, cornerRadius: 4),
          with: .color(.orange.opacity(0.12))
        )
      } else {
        // Unselected suggestion: subtle dotted orange border with light opacity
        context.stroke(
          Path(roundedRect: scaled, cornerRadius: 4),
          with: .color(.orange.opacity(0.45)),
          style: StrokeStyle(lineWidth: 1.5, dash: [3, 4])
        )
        context.fill(
          Path(roundedRect: scaled, cornerRadius: 4),
          with: .color(.orange.opacity(0.02))
        )
      }
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
    if case .marquee = activeSelectInteraction,
       let start = dragStartImagePoint, let current = dragCurrentImagePoint {
      let startView = imageToView(point: start, viewSize: size)
      let currentView = imageToView(point: current, viewSize: size)
      let rect = CGRect(
        x: min(startView.x, currentView.x), y: min(startView.y, currentView.y),
        width: abs(currentView.x - startView.x), height: abs(currentView.y - startView.y)
      )
      context.fill(Path(rect), with: .color(.accentColor.opacity(0.12)))
      context.stroke(
        Path(rect), with: .color(.accentColor),
        style: StrokeStyle(lineWidth: 1, dash: [4, 3])
      )
      return
    }
    // If we're moving/resizing an existing annotation, don't show tool previews.
    guard activeSelectInteraction == nil else { return }
    guard let start = dragStartImagePoint, let curr = dragCurrentImagePoint else { return }

    let rectFit = fitRect(imageSize: doc.imageSize, in: size)
    let scale = rectFit.width / doc.imageSize.width
    let offset = rectFit.origin

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
  
  private func magnificationGesture() -> some Gesture {
    MagnificationGesture()
      .onChanged { value in
        // Clamp zoom between 0.1x and 10x
        let newZoom = max(0.1, min(10.0, doc.zoomLevel * value))
        doc.zoomLevel = newZoom
      }
  }

  private func dragGesture(in size: CGSize) -> some Gesture {
    DragGesture(minimumDistance: 0)
      .onChanged { value in
        // If hand tool is active, pan the canvas instead of drawing
        if doc.tool == .hand && doc.pendingTextInput == nil {
          if !panGestureActive {
            panGestureActive = true
            panStartOffset = doc.panOffset
            NSCursor.closedHand.set()
          }
          doc.panOffset = CGSize(
            width: panStartOffset.width + value.translation.width,
            height: panStartOffset.height + value.translation.height
          )
          return
        }
        
        let imgPoint = viewToImage(point: value.location, viewSize: size)

        if dragStartImagePoint == nil {
          let clickCount = NSApp.currentEvent?.clickCount ?? 1

          // Interactive PII: Double-click to instantly redact/apply suggestion
          if clickCount == 2,
             let hitSuggestion = hitTestRedactionSuggestion(point: imgPoint) {
            doc.acceptRedaction(hitSuggestion)
            return
          }

          // Double-click on text/callout opens an inline editor.
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

          // Interactive PII: Single-click to toggle selection state
          if clickCount == 1,
             let hitSuggestion = hitTestRedactionSuggestion(point: imgPoint) {
            doc.toggleRedactionSelection(hitSuggestion.id)
            return
          }

          dragStartImagePoint = imgPoint
          dragCurrentImagePoint = imgPoint

          if doc.selectedIDs.count == 1,
             let selected = doc.selectedAnnotation,
             let handle = hitTestHandle(point: imgPoint, annotation: selected, viewSize: size) {
            movingStartPoint = imgPoint
            originalSelectedAtDragStart = selected
            activeSelectInteraction = .handle(handle)
            return
          }

          // Universal behavior: clicking an existing annotation selects it (and allows move/resize)
          // even if a drawing tool is currently active.
          if let hitID = hitTest(point: imgPoint), let a = doc.annotations.first(where: { $0.id == hitID }) {
            if isShiftDown {
              doc.toggleSelection(hitID)
              guard doc.selectedIDs.contains(hitID) else { return }
            } else if !doc.selectedIDs.contains(hitID) {
              doc.select(hitID)
            }
            movingStartPoint = imgPoint
            originalSelectedAtDragStart = a
            if doc.selectedIDs.count == 1,
               let hit = hitTestHandle(point: imgPoint, annotation: a, viewSize: size) {
              activeSelectInteraction = .handle(hit)
            } else {
              activeSelectInteraction = .move
            }
            return
          }

          if doc.tool == .select {
            marqueeIsAdditive = isShiftDown
            marqueeBaseSelection = marqueeIsAdditive ? doc.selectedIDs : []
            activeSelectInteraction = .marquee
            return
          }

          // Drawing on empty canvas deselects the previous annotation.
          doc.select(nil)

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
                // Keep dragStartImagePoint set so subsequent drag events
                // skip this init block and reach continuation handlers
                // (e.g. continueFreehandStroke for the freehand tool).
              }
            }
          }
          return
        }

        dragCurrentImagePoint = imgPoint

        if case .marquee = activeSelectInteraction {
          return
        }

        // Handle freehand drawing continuation
        if doc.tool == .freehand, doc.activeFreehandStroke != nil {
          doc.continueFreehandStroke(to: imgPoint)
          return
        }

        if let sel = doc.selectedID, let start = movingStartPoint {
          guard sel == doc.selectedID else { return }
          guard let interaction = activeSelectInteraction else { return }

          switch interaction {
          case .marquee:
            return
          case .move:
            let delta = CGPoint(x: imgPoint.x - start.x, y: imgPoint.y - start.y)
            movingStartPoint = imgPoint
            doc.beginEditSessionIfNeeded()
            doc.updateSelectionInSession { annotation in
              applyMove(delta: delta, annotation: &annotation)
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
        // Reset pan gesture state
         if panGestureActive {
           panGestureActive = false
           // Restore cursor based on current state
           if doc.tool == .hand && doc.pendingTextInput == nil {
             NSCursor.openHand.set()
           } else {
             NSCursor.arrow.set()
           }
          return
        }
        
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
          doc.continueFreehandStroke(to: imgEnd)
          doc.commitFreehandStroke()
          return
        }

        guard let start = dragStartImagePoint else { return }

        if case .marquee = activeSelectInteraction {
          let startView = imageToView(point: start, viewSize: size)
          let endView = value.location
          let distance = hypot(endView.x - startView.x, endView.y - startView.y)
          if distance >= 4 {
            let selectionRect = CGRect(
              x: min(start.x, imgEnd.x), y: min(start.y, imgEnd.y),
              width: abs(imgEnd.x - start.x), height: abs(imgEnd.y - start.y)
            )
            let hits = AnnotationSelectionGeometry.intersecting(
              selectionRect, annotations: doc.annotations
            )
            doc.select(marqueeBaseSelection.union(hits))
          } else if !marqueeIsAdditive {
            doc.select(nil)
          }
          return
        }

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
    case marquee
  }

  private enum HandleKind: Hashable {
    case rect(RectHandle)
    case arrowStart
    case arrowEnd
    case arrowBend
    case lineStart
    case lineEnd
    case measurementStart
    case measurementEnd
    case measurementLabel
    case loupeRadius
    case calloutTail
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
    // If background is set with padding, we want to show the padded area
    let padding = doc.backgroundStyle != .none ? doc.backgroundPadding : 0
    let totalWidth = imageSize.width + (padding * 2)
    let totalHeight = imageSize.height + (padding * 2)
    
    // Calculate base scale based on fit mode
    let baseScale: CGFloat
    switch doc.fitMode {
    case .fit:
      baseScale = min(viewSize.width / totalWidth, viewSize.height / totalHeight)
    case .fitWidth:
      baseScale = viewSize.width / totalWidth
    case .fitHeight:
      baseScale = viewSize.height / totalHeight
    case .actualSize:
      baseScale = 1.0
    }
    
    // Apply zoom level
    let scale = baseScale * doc.zoomLevel
    
    let w = imageSize.width * scale
    let h = imageSize.height * scale
    
    // Center by default, then apply pan offset
    let x = (viewSize.width - w) / 2 + doc.panOffset.width
    let y = (viewSize.height - h) / 2 + doc.panOffset.height
    
    return CGRect(x: x, y: y, width: w, height: h)
  }

  private func cropViewRect(_ r: CGRect, size: CGSize) -> CGRect {
    let rect = fitRect(imageSize: doc.imageSize, in: size)
    let scale = rect.width / doc.imageSize.width
    return CGRect(x: rect.minX + r.minX * scale, y: rect.minY + r.minY * scale, width: r.width * scale, height: r.height * scale)
  }

  private func viewToImage(point: CGPoint, viewSize: CGSize) -> CGPoint {
    let rect = fitRect(imageSize: doc.imageSize, in: viewSize)
    let scale = rect.width / doc.imageSize.width
    let p = CGPoint(x: (point.x - rect.minX) / scale, y: (point.y - rect.minY) / scale)
    return CGPoint(x: max(0, min(doc.imageSize.width, p.x)), y: max(0, min(doc.imageSize.height, p.y)))
  }

  private func imageToView(point: CGPoint, viewSize: CGSize) -> CGPoint {
    let rect = fitRect(imageSize: doc.imageSize, in: viewSize)
    let scale = rect.width / doc.imageSize.width
    return CGPoint(x: rect.minX + point.x * scale, y: rect.minY + point.y * scale)
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

    case .ellipse(let e):
      let vr = CGRect(
        x: offset.x + e.rect.minX * scale,
        y: offset.y + e.rect.minY * scale,
        width: e.rect.width * scale,
        height: e.rect.height * scale
      )
      if e.fill.enabled {
        context.fill(Path(ellipseIn: vr), with: .color(e.fill.color))
      }
      context.stroke(Path(ellipseIn: vr), with: .color(e.stroke.color), lineWidth: e.stroke.lineWidth * scale)

    case .arrow(let a):
      context.withCGContext { cgContext in
        cgContext.saveGState()
        defer { cgContext.restoreGState() }
        cgContext.translateBy(x: offset.x, y: offset.y)
        cgContext.scaleBy(x: scale, y: scale)
        ArrowGeometry(a).draw(in: cgContext)
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
      let geometry = CalloutGeometry(c)
      let transform = CGAffineTransform(a: scale, b: 0, c: 0, d: scale, tx: offset.x, ty: offset.y)
      if c.fill.enabled {
        context.fill(Path(geometry.outlinePath).applying(transform), with: .color(c.fill.color))
      }
      context.stroke(
        Path(geometry.outlinePath).applying(transform),
        with: .color(c.stroke.color), lineWidth: c.stroke.lineWidth * scale
      )
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
      context.withCGContext { cgContext in
        cgContext.saveGState()
        defer { cgContext.restoreGState() }
        cgContext.translateBy(x: offset.x, y: offset.y)
        cgContext.scaleBy(x: scale, y: scale)
        FreehandGeometry(f).draw(in: cgContext)
      }

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
      
    case .imageLayer(let img):
      guard let cgImage = CGImage.fromData(img.imageData) else { break }
      let vr = CGRect(
        x: offset.x + img.rect.minX * scale,
        y: offset.y + img.rect.minY * scale,
        width: img.rect.width * scale,
        height: img.rect.height * scale
      )
      context.draw(Image(decorative: cgImage, scale: 1), in: vr)

    case .loupe(let loupe):
      drawLoupe(loupe, context: &context, scale: scale, offset: offset)
    }
  }

  private func drawLoupe(
    _ loupe: LoupeAnnotation, context: inout GraphicsContext, scale: CGFloat, offset: CGPoint
  ) {
    let center = CGPoint(
      x: offset.x + loupe.center.x * scale, y: offset.y + loupe.center.y * scale
    )
    let radius = loupe.radius * scale
    let lensRect = CGRect(
      x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2
    )
    let imageRect = CGRect(
      origin: offset,
      size: CGSize(width: doc.imageSize.width * scale, height: doc.imageSize.height * scale)
    )

    var lensContext = context
    lensContext.clip(to: Path(ellipseIn: lensRect))
    let magnification = loupe.magnification
    lensContext.transform = LoupeGeometry.magnificationTransform(
      center: center, magnification: magnification
    ).concatenating(context.transform)
    lensContext.draw(Image(decorative: doc.cgImage, scale: 1), in: imageRect)

    context.drawLayer { layer in
      layer.addFilter(.shadow(color: .black.opacity(0.35), radius: max(2, radius * 0.06), y: 2))
      layer.stroke(Path(ellipseIn: lensRect), with: .color(.white.opacity(0.95)), lineWidth: max(3, radius * 0.09))
      layer.stroke(
        Path(ellipseIn: lensRect.insetBy(dx: radius * 0.055, dy: radius * 0.055)),
        with: .color(.black.opacity(0.55)), lineWidth: max(1, radius * 0.025)
      )
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
              Canvas { context, _ in
                context.withCGContext { cgContext in
                  cgContext.translateBy(x: rect.minX, y: rect.minY)
                  cgContext.scaleBy(x: scale, y: scale)
                  AnnotationTextLayout.draw(t, in: cgContext)
                }
              }
            }
          }

        case .callout(let c):
          Group {
            if pending?.kind == .callout, editingID == c.id {
              EmptyView()
            } else {
              Canvas { context, _ in
                context.withCGContext { cgContext in
                  cgContext.translateBy(x: rect.minX, y: rect.minY)
                  cgContext.scaleBy(x: scale, y: scale)
                  AnnotationTextLayout.drawText(in: c, context: cgContext)
                }
              }
            }
          }

        case .step(let s):
          let center = CGPoint(x: rect.origin.x + s.center.x * scale, y: rect.origin.y + s.center.y * scale)
          let r = s.radius * scale
          Text(s.displayValue)
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
        Canvas { ctx, _ in
          ctx.withCGContext { cgContext in
            cgContext.saveGState()
            defer { cgContext.restoreGState() }
            cgContext.translateBy(x: rect.minX, y: rect.minY)
            cgContext.scaleBy(x: scale, y: scale)
            FreehandGeometry(activeStroke).draw(in: cgContext)
          }
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

  private func drawSelection(
    for annotation: Annotation, context: inout GraphicsContext, scale: CGFloat,
    offset: CGPoint, showHandles: Bool
  ) {
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

    case .loupe(let loupe):
      let center = CGPoint(
        x: offset.x + loupe.center.x * scale, y: offset.y + loupe.center.y * scale
      )
      let radius = loupe.radius * scale
      let lensRect = CGRect(
        x: center.x - radius, y: center.y - radius,
        width: radius * 2, height: radius * 2
      )
      context.stroke(Path(ellipseIn: lensRect), with: .color(.blue.opacity(0.85)), style: stroke)
      if showHandles {
        drawHandle(at: CGPoint(x: center.x + radius, y: center.y), context: &context)
      }

    case .arrow(let a):
      let s = CGPoint(x: offset.x + a.start.x * scale, y: offset.y + a.start.y * scale)
      let e = CGPoint(x: offset.x + a.end.x * scale, y: offset.y + a.end.y * scale)
      let transform = CGAffineTransform(a: scale, b: 0, c: 0, d: scale, tx: offset.x, ty: offset.y)
      let p = Path(ArrowGeometry(a).path).applying(transform)
      context.stroke(p, with: .color(.blue.opacity(0.85)), style: stroke)
      if showHandles {
        drawHandle(at: s, context: &context)
        drawHandle(at: e, context: &context)
        let bend = CGPoint(x: offset.x + a.midpoint.x * scale, y: offset.y + a.midpoint.y * scale)
        let bendRect = CGRect(x: bend.x - 4, y: bend.y - 4, width: 8, height: 8)
        context.fill(Path(ellipseIn: bendRect), with: .color(.white))
        context.stroke(Path(ellipseIn: bendRect), with: .color(.green), lineWidth: 1.5)
      }

    case .rect(let r):
      let vr = CGRect(x: offset.x + r.rect.minX * scale, y: offset.y + r.rect.minY * scale, width: r.rect.width * scale, height: r.rect.height * scale)
      context.stroke(Path(vr), with: .color(.blue.opacity(0.85)), style: stroke)
      if showHandles { drawRectHandles(rect: vr, context: &context) }

    case .ellipse(let e):
      let vr = CGRect(x: offset.x + e.rect.minX * scale, y: offset.y + e.rect.minY * scale, width: e.rect.width * scale, height: e.rect.height * scale)
      context.stroke(Path(ellipseIn: vr), with: .color(.blue.opacity(0.85)), style: stroke)
      if showHandles { drawRectHandles(rect: vr, context: &context) }

    case .callout(let c):
      let vr = CGRect(x: offset.x + c.rect.minX * scale, y: offset.y + c.rect.minY * scale, width: c.rect.width * scale, height: c.rect.height * scale)
      let geometry = CalloutGeometry(c)
      let transform = CGAffineTransform(a: scale, b: 0, c: 0, d: scale, tx: offset.x, ty: offset.y)
      context.stroke(Path(geometry.outlinePath).applying(transform), with: .color(.blue.opacity(0.85)), style: stroke)
      if showHandles {
        drawRectHandles(rect: vr, context: &context)
        if let tailTip = c.tailTip {
          drawHandle(at: CGPoint(x: offset.x + tailTip.x * scale, y: offset.y + tailTip.y * scale), context: &context)
        }
      }

    case .blur(let b):
      let vr = CGRect(x: offset.x + b.rect.minX * scale, y: offset.y + b.rect.minY * scale, width: b.rect.width * scale, height: b.rect.height * scale)
      context.stroke(Path(vr), with: .color(.blue.opacity(0.85)), style: stroke)
      if showHandles { drawRectHandles(rect: vr, context: &context) }

    case .text(let t):
      let bounds = AnnotationTextLayout.textBounds(t)
      let r = CGRect(
        x: offset.x + bounds.minX * scale - 6,
        y: offset.y + bounds.minY * scale - 6,
        width: bounds.width * scale + 12,
        height: bounds.height * scale + 12
      )
      context.stroke(Path(roundedRect: r, cornerRadius: 10), with: .color(.blue.opacity(0.85)), style: stroke)

    case .line(let l):
      let s = CGPoint(x: offset.x + l.start.x * scale, y: offset.y + l.start.y * scale)
      let e = CGPoint(x: offset.x + l.end.x * scale, y: offset.y + l.end.y * scale)
      var p = Path(); p.move(to: s); p.addLine(to: e)
      context.stroke(p, with: .color(.blue.opacity(0.85)), style: stroke)
      if showHandles {
        drawHandle(at: s, context: &context)
        drawHandle(at: e, context: &context)
      }

    case .freehand(let f):
      let geometry = FreehandGeometry(f)
      guard !geometry.path.isEmpty else { break }
      let bounds = geometry.bounds
      let boundingRect = CGRect(
        x: bounds.minX * scale + offset.x - 4, y: bounds.minY * scale + offset.y - 4,
        width: bounds.width * scale + 8, height: bounds.height * scale + 8
      )
      context.stroke(Path(boundingRect), with: .color(.blue.opacity(0.85)), style: stroke)

    case .spotlight(let sp):
      let vr = CGRect(x: offset.x + sp.rect.minX * scale, y: offset.y + sp.rect.minY * scale, width: sp.rect.width * scale, height: sp.rect.height * scale)
      context.stroke(Path(vr), with: .color(.blue.opacity(0.85)), style: stroke)
      if showHandles { drawRectHandles(rect: vr, context: &context) }

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
      
    case .imageLayer(let img):
      let vr = CGRect(x: offset.x + img.rect.minX * scale, y: offset.y + img.rect.minY * scale, width: img.rect.width * scale, height: img.rect.height * scale)
      context.stroke(Path(vr), with: .color(.blue.opacity(0.85)), style: stroke)
      if showHandles { drawRectHandles(rect: vr, context: &context) }
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
      if near(a.midpoint) { return HandleHit(kind: .arrowBend) }
      return nil

    case .rect(let r):
      return hitRectHandle(point: point, rect: r.rect, hitRadiusImg: hitRadiusImg)
        .map { HandleHit(kind: .rect($0)) }

    case .ellipse(let e):
      return hitRectHandle(point: point, rect: e.rect, hitRadiusImg: hitRadiusImg)
        .map { HandleHit(kind: .rect($0)) }

    case .callout(let c):
      if let tailTip = c.tailTip, near(tailTip) { return HandleHit(kind: .calloutTail) }
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

    case .imageLayer(let img):
      return hitRectHandle(point: point, rect: img.rect, hitRadiusImg: hitRadiusImg)
        .map { HandleHit(kind: .rect($0)) }

    case .loupe(let loupe):
      let radiusHandle = CGPoint(x: loupe.center.x + loupe.radius, y: loupe.center.y)
      return near(radiusHandle) ? HandleHit(kind: .loupeRadius) : nil

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
      a = o
      a.moveEndpoint(start: newStart, end: o.end)
      annotation = .arrow(a)

    case (.arrowEnd, .arrow(let o), .arrow(var a)):
      var newEnd = current
      if isShiftDown {
        newEnd = snap45(from: o.start, to: current)
      }
      a = o
      a.moveEndpoint(start: o.start, end: newEnd)
      annotation = .arrow(a)

    case (.arrowBend, .arrow, .arrow(var a)):
      a.bendPoint = current
      annotation = .arrow(a)

    case (.loupeRadius, .loupe(let original), .loupe(var loupe)):
      loupe.radius = max(12, hypot(current.x - original.center.x, current.y - original.center.y))
      annotation = .loupe(loupe)

    case (.calloutTail, .callout, .callout(var callout)):
      callout.tailTip = current
      annotation = .callout(callout)

    case (.rect(let h), .rect(let o), .rect(var r)):
      r.rect = clampRect(resizedRect(from: o.rect, handle: h, to: current, constrainSquare: isShiftDown))
      annotation = .rect(r)

    case (.rect(let h), .ellipse(let o), .ellipse(var e)):
      e.rect = clampRect(resizedRect(from: o.rect, handle: h, to: current, constrainSquare: isShiftDown))
      annotation = .ellipse(e)

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

    case (.rect(let h), .imageLayer(let o), .imageLayer(var img)):
      img.rect = clampRect(resizedRect(from: o.rect, handle: h, to: current, constrainSquare: isShiftDown))
      annotation = .imageLayer(img)

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
      case .ellipse(let e):
        // Point-in-ellipse test using normalized coordinates
        let cx = e.rect.midX, cy = e.rect.midY
        let rx = (e.rect.width / 2) + 8, ry = (e.rect.height / 2) + 8
        let dx = point.x - cx, dy = point.y - cy
        if (dx * dx) / (rx * rx) + (dy * dy) / (ry * ry) <= 1 { return e.id }
      case .callout(let c):
        if CalloutGeometry(c).contains(point, tolerance: 8) { return c.id }
      case .arrow(let ar):
        if ArrowGeometry(ar).contains(point, tolerance: 10) { return ar.id }
      case .text(let t):
        if AnnotationTextLayout.textBounds(t).insetBy(dx: -8, dy: -8).contains(point) { return t.id }

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
        if FreehandGeometry(f).contains(point, tolerance: 10) { return f.id }

      case .spotlight(let sp):
        if sp.rect.insetBy(dx: -8, dy: -8).contains(point) { return sp.id }

      case .counter(let c):
        if hypot(point.x - c.center.x, point.y - c.center.y) <= (c.radius + 8) { return c.id }

      case .emoji(let e):
        let approx = CGRect(x: e.position.x - e.size / 2, y: e.position.y - e.size / 2, width: e.size, height: e.size)
        if approx.insetBy(dx: -10, dy: -10).contains(point) { return e.id }
        
      case .imageLayer(let img):
        if img.rect.insetBy(dx: -8, dy: -8).contains(point) { return img.id }
      case .loupe(let loupe):
        if LoupeGeometry.contains(point, loupe: loupe, tolerance: 8) {
          return loupe.id
        }
      }
    }
    return nil
  }

  private func hitTestRedactionSuggestion(point: CGPoint) -> RedactionSuggestion? {
    let matches = doc.suggestedRedactions.filter { $0.rect.contains(point) }
    return matches.sorted { $0.rect.width * $0.rect.height < $1.rect.width * $1.rect.height }.first
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
    case .ellipse(var e):
      e.rect = e.rect.offsetBy(dx: delta.x, dy: delta.y)
      annotation = .ellipse(e)
    case .callout(var c):
      c.rect = c.rect.offsetBy(dx: delta.x, dy: delta.y)
      if let tailTip = c.tailTip {
        c.tailTip = CGPoint(x: tailTip.x + delta.x, y: tailTip.y + delta.y)
      }
      annotation = .callout(c)
    case .arrow(var a):
      a.translate(by: delta)
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
      
    case .imageLayer(var img):
      img.rect = img.rect.offsetBy(dx: delta.x, dy: delta.y)
      annotation = .imageLayer(img)

    case .loupe(var loupe):
      loupe.center = CGPoint(x: loupe.center.x + delta.x, y: loupe.center.y + delta.y)
      annotation = .loupe(loupe)
    }
  }
}

private struct InlineTextEditorOverlay: View {
  @ObservedObject var doc: AnnotationDocument
  let pending: AnnotationDocument.PendingTextInput
  let targetID: UUID
  let rect: CGRect
  let scale: CGFloat

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
    }
    .onChange(of: pending.id) { _ in
      doc.beginEditSessionIfNeeded()
    }
  }

  private var inlineTextField: some View {
    let (fontSize, color, highlighted, highlightColor, highlightOpacity) = currentTextStyle

    let padding = highlighted ? AnnotationTextLayout.highlightPadding : .zero
    return AnnotationTextEditor(
      text: textBinding, fontSize: fontSize / scale, color: color,
      wraps: false, onCommit: doc.commitPendingTextInput, onCancel: doc.cancelPendingTextInput
    )
    .frame(width: textFieldWidth / scale, height: textFieldHeight / scale, alignment: .topLeading)
    .scaleEffect(scale, anchor: .topLeading)
    .frame(width: textFieldWidth, height: textFieldHeight, alignment: .topLeading)
    .padding(.horizontal, padding.width * scale)
    .padding(.vertical, padding.height * scale)
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
    .help("Return adds a line; Command-Return finishes editing; Escape cancels")
  }

  private var inlineCalloutField: some View {
    guard let callout = currentCallout else { return AnyView(EmptyView()) }

    let modelInset = AnnotationTextLayout.calloutTextRect(callout)
    let inset = CGRect(
      x: rect.minX + modelInset.minX * scale,
      y: rect.minY + modelInset.minY * scale,
      width: modelInset.width * scale, height: modelInset.height * scale
    )
    let field = AnnotationTextEditor(
      text: textBinding, fontSize: callout.fontSize, color: callout.textColor,
      wraps: true, onCommit: doc.commitPendingTextInput, onCancel: doc.cancelPendingTextInput
    )
    .frame(width: modelInset.width, height: modelInset.height, alignment: .topLeading)
    .scaleEffect(scale, anchor: .topLeading)
    .frame(width: inset.width, height: inset.height, alignment: .topLeading)
    .background(Color.black.opacity(0.18))
    .clipShape(RoundedRectangle(cornerRadius: 8))
    .overlay(
      RoundedRectangle(cornerRadius: 8)
        .strokeBorder(Color.white.opacity(0.28), lineWidth: 1)
    )
    .offset(x: inset.minX, y: inset.minY)
    .help("Return adds a line; Command-Return finishes editing; Escape cancels")

    return AnyView(field)
  }

  private var textFieldWidth: CGFloat {
    let (fontSize, color, _, _, _) = currentTextStyle
    let layout = AnnotationTextLayout(text: textBinding.wrappedValue, fontSize: fontSize / scale, color: color)
    return max(60, layout.size.width + 4) * scale
  }

  private var textFieldHeight: CGFloat {
    let (fontSize, color, _, _, _) = currentTextStyle
    let layout = AnnotationTextLayout(text: textBinding.wrappedValue, fontSize: fontSize / scale, color: color)
    return max(fontSize / scale * 1.2, layout.size.height) * scale
  }

  private var textFieldOrigin: CGPoint {
    textOrigin
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
