import Foundation

enum ToolRegistry {
  static let allTools: [AnnotationTool: any EditorTool] = [
    .rect: RectTool(),
    .line: LineTool(),
    .arrow: ArrowTool(),
    .freehand: FreehandTool(),
    .text: TextTool(),
    .callout: CalloutTool(),
    .blur: BlurTool(),
    .spotlight: SpotlightTool(),
    .step: StepTool(),
    .counter: CounterTool(),
    .emoji: EmojiTool(),
    .measurement: MeasurementTool(),
  ]

  static func tool(for id: AnnotationTool) -> (any EditorTool)? {
    allTools[id]
  }

  static func requiredFeature(for id: AnnotationTool) -> ProFeature? {
    tool(for: id)?.requiredFeature
  }
}

private struct RectTool: EditorTool {
  let id: AnnotationTool = .rect
  let requiredFeature: ProFeature? = nil
  let capabilities: ToolCapabilities = [.usesDrag]

  func begin(doc: AnnotationDocument, at point: CGPoint, isShiftDown: Bool) -> ToolBeginResult {
    .startDrag
  }

  func preview(doc: AnnotationDocument, start: CGPoint, current: CGPoint, isShiftDown: Bool) -> Annotation? {
    let r = rectFrom(start: start, end: current, constrainSquare: isShiftDown)
    return .rect(RectAnnotation(rect: r, stroke: doc.stroke, fill: doc.fill))
  }

  func commit(doc: AnnotationDocument, start: CGPoint, end: CGPoint, isShiftDown: Bool) {
    let r = rectFrom(start: start, end: end, constrainSquare: isShiftDown)
    if r.width >= 2 && r.height >= 2 {
      doc.pushUndoCheckpoint()
      doc.annotations.append(.rect(RectAnnotation(rect: r, stroke: doc.stroke, fill: doc.fill)))
      doc.selectedID = doc.annotations.last?.id
    }
  }
}

private struct LineTool: EditorTool {
  let id: AnnotationTool = .line
  let requiredFeature: ProFeature? = nil
  let capabilities: ToolCapabilities = [.usesDrag]

  func begin(doc: AnnotationDocument, at point: CGPoint, isShiftDown: Bool) -> ToolBeginResult {
    .startDrag
  }

  func preview(doc: AnnotationDocument, start: CGPoint, current: CGPoint, isShiftDown: Bool) -> Annotation? {
    let end = isShiftDown ? snap45(from: start, to: current) : current
    return .line(LineAnnotation(start: start, end: end, stroke: doc.stroke))
  }

  func commit(doc: AnnotationDocument, start: CGPoint, end: CGPoint, isShiftDown: Bool) {
    let e = isShiftDown ? snap45(from: start, to: end) : end
    if hypot(e.x - start.x, e.y - start.y) >= 2 {
      doc.pushUndoCheckpoint()
      doc.annotations.append(.line(LineAnnotation(start: start, end: e, stroke: doc.stroke)))
      doc.selectedID = doc.annotations.last?.id
    }
  }
}

private struct ArrowTool: EditorTool {
  let id: AnnotationTool = .arrow
  let requiredFeature: ProFeature? = nil
  let capabilities: ToolCapabilities = [.usesDrag]

  func begin(doc: AnnotationDocument, at point: CGPoint, isShiftDown: Bool) -> ToolBeginResult {
    .startDrag
  }

  func preview(doc: AnnotationDocument, start: CGPoint, current: CGPoint, isShiftDown: Bool) -> Annotation? {
    let end = isShiftDown ? snap45(from: start, to: current) : current
    return .arrow(ArrowAnnotation(start: start, end: end, stroke: doc.stroke, headStyle: doc.arrowHeadStyle))
  }

  func commit(doc: AnnotationDocument, start: CGPoint, end: CGPoint, isShiftDown: Bool) {
    let e = isShiftDown ? snap45(from: start, to: end) : end
    if hypot(e.x - start.x, e.y - start.y) >= 2 {
      doc.pushUndoCheckpoint()
      doc.annotations.append(.arrow(ArrowAnnotation(start: start, end: e, stroke: doc.stroke, headStyle: doc.arrowHeadStyle)))
      doc.selectedID = doc.annotations.last?.id
    }
  }
}

private struct TextTool: EditorTool {
  let id: AnnotationTool = .text
  let requiredFeature: ProFeature? = nil
  let capabilities: ToolCapabilities = [.clickOnly]

  func begin(doc: AnnotationDocument, at point: CGPoint, isShiftDown: Bool) -> ToolBeginResult {
    // Create the annotation immediately so editing can happen inline/live.
    doc.beginEditSessionIfNeeded()
    let t = TextAnnotation(
      position: point,
      text: "",
      color: doc.textColor,
      fontSize: doc.textFontSize,
      highlighted: doc.textHighlighted
    )
    doc.annotations.append(.text(t))
    doc.selectedID = t.id
    doc.pendingTextInput = .init(
      kind: .text,
      positionOrRect: .position(point),
      initialText: "",
      targetAnnotationID: t.id,
      removeTargetOnCancel: true
    )
    return .handled
  }

  func preview(doc: AnnotationDocument, start: CGPoint, current: CGPoint, isShiftDown: Bool) -> Annotation? { nil }
  func commit(doc: AnnotationDocument, start: CGPoint, end: CGPoint, isShiftDown: Bool) {}
}

private struct CalloutTool: EditorTool {
  let id: AnnotationTool = .callout
  let requiredFeature: ProFeature? = nil
  let capabilities: ToolCapabilities = [.usesDrag]

  func begin(doc: AnnotationDocument, at point: CGPoint, isShiftDown: Bool) -> ToolBeginResult {
    .startDrag
  }

  func preview(doc: AnnotationDocument, start: CGPoint, current: CGPoint, isShiftDown: Bool) -> Annotation? {
    let r = rectFrom(start: start, end: current, constrainSquare: false)
    return .callout(CalloutAnnotation(rect: r, text: "", stroke: doc.stroke, fill: doc.fill, textColor: doc.textColor, fontSize: doc.textFontSize))
  }

  func commit(doc: AnnotationDocument, start: CGPoint, end: CGPoint, isShiftDown: Bool) {
    let r = rectFrom(start: start, end: end, constrainSquare: false)
    if r.width >= 10 && r.height >= 10 {
      doc.pushUndoCheckpoint()
      let callout = CalloutAnnotation(rect: r, text: "", stroke: doc.stroke, fill: doc.fill, textColor: doc.textColor, fontSize: doc.textFontSize)
      doc.annotations.append(.callout(callout))
      doc.selectedID = callout.id
      doc.pendingTextInput = .init(
        kind: .callout,
        positionOrRect: .rect(r),
        initialText: "",
        targetAnnotationID: callout.id,
        removeTargetOnCancel: true
      )
    }
  }
}

private struct BlurTool: EditorTool {
  let id: AnnotationTool = .blur
  let requiredFeature: ProFeature? = .advancedAnnotations
  let capabilities: ToolCapabilities = [.usesDrag]

  func begin(doc: AnnotationDocument, at point: CGPoint, isShiftDown: Bool) -> ToolBeginResult {
    .startDrag
  }

  func preview(doc: AnnotationDocument, start: CGPoint, current: CGPoint, isShiftDown: Bool) -> Annotation? {
    let r = rectFrom(start: start, end: current, constrainSquare: false)
    return .blur(BlurAnnotation(rect: r, mode: doc.blurMode, amount: doc.blurAmount))
  }

  func commit(doc: AnnotationDocument, start: CGPoint, end: CGPoint, isShiftDown: Bool) {
    let r = rectFrom(start: start, end: end, constrainSquare: false)
    if r.width >= 10 && r.height >= 10 {
      doc.pushUndoCheckpoint()
      doc.annotations.append(.blur(BlurAnnotation(rect: r, mode: doc.blurMode, amount: doc.blurAmount)))
      doc.selectedID = doc.annotations.last?.id
    }
  }
}

private struct StepTool: EditorTool {
  let id: AnnotationTool = .step
  let requiredFeature: ProFeature? = .advancedAnnotations
  let capabilities: ToolCapabilities = [.clickOnly]

  func begin(doc: AnnotationDocument, at point: CGPoint, isShiftDown: Bool) -> ToolBeginResult {
    doc.pushUndoCheckpoint()
    let n = doc.nextStepNumber()
    doc.annotations.append(
      .step(
        StepAnnotation(
          center: point,
          number: n,
          radius: doc.stepRadius,
          fillColor: doc.stepFillColor,
          textColor: doc.stepTextColor,
          borderColor: doc.stepBorderColor,
          borderWidth: doc.stepBorderWidth
        )
      )
    )
    doc.selectedID = doc.annotations.last?.id
    return .handled
  }

  func preview(doc: AnnotationDocument, start: CGPoint, current: CGPoint, isShiftDown: Bool) -> Annotation? { nil }
  func commit(doc: AnnotationDocument, start: CGPoint, end: CGPoint, isShiftDown: Bool) {}
}

private struct FreehandTool: EditorTool {
  let id: AnnotationTool = .freehand
  let requiredFeature: ProFeature? = nil
  let capabilities: ToolCapabilities = [.usesDrag, .continuousDraw]

  func begin(doc: AnnotationDocument, at point: CGPoint, isShiftDown: Bool) -> ToolBeginResult {
    doc.beginFreehandStroke(at: point, isHighlighter: isShiftDown)
    return .handled
  }

  func preview(doc: AnnotationDocument, start: CGPoint, current: CGPoint, isShiftDown: Bool) -> Annotation? {
    // Freehand preview is handled differently via continueFreehandStroke
    nil
  }

  func commit(doc: AnnotationDocument, start: CGPoint, end: CGPoint, isShiftDown: Bool) {
    doc.commitFreehandStroke()
  }
}

private struct SpotlightTool: EditorTool {
  let id: AnnotationTool = .spotlight
  let requiredFeature: ProFeature? = .advancedAnnotations
  let capabilities: ToolCapabilities = [.usesDrag]

  func begin(doc: AnnotationDocument, at point: CGPoint, isShiftDown: Bool) -> ToolBeginResult {
    .startDrag
  }

  func preview(doc: AnnotationDocument, start: CGPoint, current: CGPoint, isShiftDown: Bool) -> Annotation? {
    let r = rectFrom(start: start, end: current, constrainSquare: isShiftDown)
    return .spotlight(SpotlightAnnotation(
      rect: r,
      shape: doc.spotlightShape,
      dimmingOpacity: doc.spotlightDimmingOpacity,
      borderStroke: doc.spotlightShowBorder ? doc.stroke : nil
    ))
  }

  func commit(doc: AnnotationDocument, start: CGPoint, end: CGPoint, isShiftDown: Bool) {
    let r = rectFrom(start: start, end: end, constrainSquare: isShiftDown)
    if r.width >= 10 && r.height >= 10 {
      doc.pushUndoCheckpoint()
      doc.annotations.append(.spotlight(SpotlightAnnotation(
        rect: r,
        shape: doc.spotlightShape,
        dimmingOpacity: doc.spotlightDimmingOpacity,
        borderStroke: doc.spotlightShowBorder ? doc.stroke : nil
      )))
      doc.selectedID = doc.annotations.last?.id
    }
  }
}

private struct CounterTool: EditorTool {
  let id: AnnotationTool = .counter
  let requiredFeature: ProFeature? = .advancedAnnotations
  let capabilities: ToolCapabilities = [.clickOnly]

  func begin(doc: AnnotationDocument, at point: CGPoint, isShiftDown: Bool) -> ToolBeginResult {
    doc.pushUndoCheckpoint()
    let value = doc.nextCounterValue()
    doc.annotations.append(
      .counter(
        CounterAnnotation(
          center: point,
          value: value,
          radius: doc.counterRadius,
          fillColor: doc.counterFillColor,
          textColor: doc.counterTextColor,
          borderColor: doc.counterBorderColor,
          borderWidth: doc.counterBorderWidth
        )
      )
    )
    doc.selectedID = doc.annotations.last?.id
    return .handled
  }

  func preview(doc: AnnotationDocument, start: CGPoint, current: CGPoint, isShiftDown: Bool) -> Annotation? { nil }
  func commit(doc: AnnotationDocument, start: CGPoint, end: CGPoint, isShiftDown: Bool) {}
}

private struct EmojiTool: EditorTool {
  let id: AnnotationTool = .emoji
  let requiredFeature: ProFeature? = nil
  let capabilities: ToolCapabilities = [.clickOnly]

  func begin(doc: AnnotationDocument, at point: CGPoint, isShiftDown: Bool) -> ToolBeginResult {
    doc.pushUndoCheckpoint()
    doc.annotations.append(
      .emoji(
        EmojiAnnotation(
          position: point,
          emoji: doc.selectedEmoji,
          size: doc.emojiSize
        )
      )
    )
    doc.selectedID = doc.annotations.last?.id
    return .handled
  }

  func preview(doc: AnnotationDocument, start: CGPoint, current: CGPoint, isShiftDown: Bool) -> Annotation? { nil }
  func commit(doc: AnnotationDocument, start: CGPoint, end: CGPoint, isShiftDown: Bool) {}
}

private func rectFrom(start: CGPoint, end: CGPoint, constrainSquare: Bool) -> CGRect {
  var dx = end.x - start.x
  var dy = end.y - start.y
  if constrainSquare {
    let s = max(abs(dx), abs(dy))
    dx = dx < 0 ? -s : s
    dy = dy < 0 ? -s : s
  }
  let x1 = start.x
  let y1 = start.y
  let x2 = start.x + dx
  let y2 = start.y + dy
  return CGRect(x: min(x1, x2), y: min(y1, y2), width: abs(x2 - x1), height: abs(y2 - y1))
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
