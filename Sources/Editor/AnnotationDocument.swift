import AppKit
import Foundation
import SwiftUI

final class AnnotationDocument: ObservableObject {
  let sourceURL: URL
  let cgImage: CGImage
  let imageSize: CGSize

  @Published var tool: AnnotationTool = .select
  @Published var annotations: [Annotation] = [] {
    didSet {
      hasUnsavedChanges = annotationsHash(annotations) != savedAnnotationsHash
    }
  }
  @Published var selectedID: UUID? = nil

  @Published private(set) var hasUnsavedChanges: Bool = false
  private var savedAnnotationsHash: Int = 0

  // Tool settings
  @Published var stroke = StrokeStyleModel(color: .white, lineWidth: 4)
  @Published var fill = FillStyleModel(color: .black.opacity(0.25), enabled: false)
  @Published var arrowHeadStyle: ArrowHeadStyle = .filled
  @Published var textColor: Color = .white
  @Published var textFontSize: CGFloat = 28
  @Published var textHighlighted: Bool = false

  // Blur tool settings
  @Published var blurMode: BlurMode = .pixelate
  @Published var blurAmount: CGFloat = 16

  // Step tool settings
  @Published var stepRadius: CGFloat = 22
  @Published var stepFillColor: Color = .red
  @Published var stepTextColor: Color = .white
  @Published var stepBorderColor: Color = .white
  @Published var stepBorderWidth: CGFloat = 3

  // Measurement tool settings
  @Published var measurementUnit: MeasurementUnit = .pixels
  @Published var measurementPPI: CGFloat = 72
  @Published var measurementBaseFontSize: CGFloat = 16
  @Published var measurementShowExtensionLines: Bool = true
  @Published var measurementSnapEnabled: Bool = true

  // Spotlight tool settings
  @Published var spotlightShape: SpotlightShape = .roundedRect
  @Published var spotlightDimmingOpacity: CGFloat = 0.65
  @Published var spotlightShowBorder: Bool = false

  // Counter tool settings
  @Published var counterRadius: CGFloat = 18
  @Published var counterFillColor: Color = .blue
  @Published var counterTextColor: Color = .white
  @Published var counterBorderColor: Color = .white
  @Published var counterBorderWidth: CGFloat = 2
  @Published var counterMode: CounterMode = .numbers  // numbers, letters, custom

  // Emoji tool settings
  @Published var selectedEmoji: String = "👍"
  @Published var emojiSize: CGFloat = 48

  // Freehand tool settings
  @Published var freehandIsHighlighter: Bool = false

  // Active freehand stroke (while drawing)
  @Published var activeFreehandStroke: FreehandAnnotation? = nil

  // Device frame settings (Pro feature)
  @Published var deviceFrame: DeviceFrame = .none
  @Published var deviceFrameColor: DeviceFrameColor = .black
  @Published var deviceFrameCustomColor: Color = Color(white: 0.15)

  // Background settings (Pro feature)
  @Published var backgroundStyle: BackgroundStyle = .none
  @Published var backgroundColor: Color = .gray
  @Published var backgroundGradientStart: Color = Color(hue: 0.6, saturation: 0.8, brightness: 0.9)
  @Published var backgroundGradientEnd: Color = Color(hue: 0.8, saturation: 0.8, brightness: 0.9)
  @Published var backgroundGradientDirection: GradientDirection = .topLeftToBottomRight
  @Published var backgroundPadding: CGFloat = 48
  @Published var backgroundCornerRadius: CGFloat = 16
  @Published var backgroundShadowEnabled: Bool = true
  @Published var backgroundShadowRadius: CGFloat = 24
  @Published var backgroundShadowOpacity: CGFloat = 0.3

  // Edge detection for measurement snapping
  let snapGuideManager = SnapGuideManager()

  // Transient input overlay
  @Published var pendingTextInput: PendingTextInput? = nil

  // Undo/redo
  private var undoStack: [[Annotation]] = []
  private var redoStack: [[Annotation]] = []

  private var isEditSessionActive: Bool = false

  struct PendingTextInput: Identifiable {
    let id = UUID()
    var kind: AnnotationTool // .text or .callout
    var positionOrRect: EitherPositionOrRect
    var initialText: String
    var targetAnnotationID: UUID? = nil
    var removeTargetOnCancel: Bool = false
  }

  enum EitherPositionOrRect {
    case position(CGPoint)
    case rect(CGRect)
  }

  init(sourceURL: URL) throws {
    self.sourceURL = sourceURL

    guard let nsImage = NSImage(contentsOf: sourceURL) else {
      throw NSError(domain: "SnipSnap", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to load image"])
    }

    guard let cg = nsImage.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
      throw NSError(domain: "SnipSnap", code: 2, userInfo: [NSLocalizedDescriptionKey: "Failed to decode image"])
    }

    self.cgImage = cg
    self.imageSize = CGSize(width: cg.width, height: cg.height)

    // Initial state is "saved" (no edits yet).
    savedAnnotationsHash = annotationsHash(annotations)
    hasUnsavedChanges = false
  }

  func markSaved() {
    savedAnnotationsHash = annotationsHash(annotations)
    hasUnsavedChanges = false
  }

  func cancelPendingTextInput() {
    guard let pending = pendingTextInput else { return }
    if pending.removeTargetOnCancel, let targetID = pending.targetAnnotationID {
      annotations.removeAll(where: { $0.id == targetID })
      if selectedID == targetID {
        selectedID = nil
      }
    } else if let targetID = pending.targetAnnotationID {
      // Revert edits to the original value.
      if let idx = annotations.firstIndex(where: { $0.id == targetID }) {
        var a = annotations[idx]
        switch (pending.kind, a) {
        case (.text, .text(var t)):
          t.text = pending.initialText
          a = .text(t)
        case (.callout, .callout(var c)):
          c.text = pending.initialText
          a = .callout(c)
        default:
          break
        }
        annotations[idx] = a
      }
    }
    pendingTextInput = nil
    endEditSession()
  }

  func commitPendingTextInput() {
    guard let pending = pendingTextInput else { return }
    guard let targetID = pending.targetAnnotationID else {
      pendingTextInput = nil
      endEditSession()
      return
    }

    guard let idx = annotations.firstIndex(where: { $0.id == targetID }) else {
      pendingTextInput = nil
      endEditSession()
      return
    }

    let trimmed: String
    switch annotations[idx] {
    case .text(let t):
      trimmed = t.text.trimmingCharacters(in: .whitespacesAndNewlines)
    case .callout(let c):
      trimmed = c.text.trimmingCharacters(in: .whitespacesAndNewlines)
    default:
      trimmed = ""
    }

    guard !trimmed.isEmpty else {
      cancelPendingTextInput()
      return
    }

    // Normalize to trimmed value.
    var a = annotations[idx]
    switch a {
    case .text(var t):
      t.text = trimmed
      a = .text(t)
    case .callout(var c):
      c.text = trimmed
      a = .callout(c)
    default:
      break
    }
    annotations[idx] = a

    pendingTextInput = nil
    endEditSession()
  }

  private func annotationsHash(_ anns: [Annotation]) -> Int {
    var hasher = Hasher()
    for a in anns {
      hasher.combine(a)
    }
    return hasher.finalize()
  }

  func syncStyleFromSelectionIfNeeded() {
    guard let id = selectedID, let a = annotations.first(where: { $0.id == id }) else { return }
    switch a {
    case .rect(let r):
      stroke = r.stroke
      fill = r.fill
    case .arrow(let ar):
      stroke = ar.stroke
      arrowHeadStyle = ar.headStyle
    case .text(let t):
      textColor = t.color
      textFontSize = t.fontSize
      textHighlighted = t.highlighted
    case .callout(let c):
      stroke = c.stroke
      fill = c.fill
      textColor = c.textColor
      textFontSize = c.fontSize
    case .blur(let b):
      blurMode = b.mode
      blurAmount = b.amount
    case .step(let s):
      stepRadius = s.radius
      stepFillColor = s.fillColor
      stepTextColor = s.textColor
      stepBorderColor = s.borderColor
      stepBorderWidth = s.borderWidth
    case .spotlight(let sp):
      spotlightShape = sp.shape
      spotlightDimmingOpacity = sp.dimmingOpacity
      spotlightShowBorder = sp.borderStroke != nil
      if let bs = sp.borderStroke {
        stroke = bs
      }
    case .counter(let c):
      counterRadius = c.radius
      counterFillColor = c.fillColor
      counterTextColor = c.textColor
      counterBorderColor = c.borderColor
      counterBorderWidth = c.borderWidth
    case .emoji(let e):
      selectedEmoji = e.emoji
      emojiSize = e.size
    case .freehand(let f):
      stroke = f.stroke
      freehandIsHighlighter = f.isHighlighter
    case .line(let l):
      stroke = l.stroke
    case .measurement(let m):
      stroke = m.stroke
      measurementUnit = m.unit
      measurementPPI = m.ppi
      measurementBaseFontSize = m.baseFontSize
      measurementShowExtensionLines = m.showExtensionLines
    }
  }

  func nextStepNumber() -> Int {
    let nums = annotations.compactMap { a -> Int? in
      if case .step(let s) = a { return s.number }
      return nil
    }
    return (nums.max() ?? 0) + 1
  }

  func nextCounterValue() -> String {
    let existingCount = annotations.filter { a in
      if case .counter = a { return true }
      return false
    }.count
    return counterMode.value(for: existingCount + 1)
  }

  // MARK: - Freehand Drawing

  func beginFreehandStroke(at point: CGPoint, isHighlighter: Bool) {
    beginEditSessionIfNeeded()
    var strokeStyle = stroke
    if isHighlighter || freehandIsHighlighter {
      // Highlighter: wider, more transparent
      strokeStyle.lineWidth = max(stroke.lineWidth * 3, 16)
    }
    activeFreehandStroke = FreehandAnnotation(
      points: [point],
      stroke: strokeStyle,
      isHighlighter: isHighlighter || freehandIsHighlighter
    )
  }

  func continueFreehandStroke(to point: CGPoint) {
    guard var stroke = activeFreehandStroke else { return }
    stroke.points.append(point)
    activeFreehandStroke = stroke
  }

  func commitFreehandStroke() {
    guard let stroke = activeFreehandStroke else { return }
    if stroke.points.count >= 2 {
      annotations.append(.freehand(stroke))
      selectedID = stroke.id
    }
    activeFreehandStroke = nil
    endEditSession()
  }

  func pushUndoCheckpoint() {
    undoStack.append(annotations)
    if undoStack.count > 100 { undoStack.removeFirst(undoStack.count - 100) }
    redoStack.removeAll(keepingCapacity: false)
  }

  func beginEditSessionIfNeeded() {
    guard !isEditSessionActive else { return }
    isEditSessionActive = true
    pushUndoCheckpoint()
  }

  func endEditSession() {
    isEditSessionActive = false
  }

  func undo() {
    guard let prev = undoStack.popLast() else { return }
    redoStack.append(annotations)
    annotations = prev
    if let sel = selectedID, !annotations.contains(where: { $0.id == sel }) {
      selectedID = nil
    }
  }

  func redo() {
    guard let next = redoStack.popLast() else { return }
    undoStack.append(annotations)
    annotations = next
  }

  func deleteSelected() {
    guard let id = selectedID else { return }
    pushUndoCheckpoint()
    annotations.removeAll(where: { $0.id == id })
    selectedID = nil
  }

  func updateSelected(_ update: (inout Annotation) -> Void) {
    guard let id = selectedID, let idx = annotations.firstIndex(where: { $0.id == id }) else { return }
    pushUndoCheckpoint()
    var a = annotations[idx]
    update(&a)
    annotations[idx] = a
  }

  func updateSelectedInSession(_ update: (inout Annotation) -> Void) {
    guard let id = selectedID, let idx = annotations.firstIndex(where: { $0.id == id }) else { return }
    var a = annotations[idx]
    update(&a)
    annotations[idx] = a
  }

  func updateSelectedMaybeInSession(_ update: (inout Annotation) -> Void) {
    if isEditSessionActive {
      updateSelectedInSession(update)
    } else {
      updateSelected(update)
    }
  }
}
