import AppKit
import Foundation
import SwiftUI

/// A redaction suggestion loaded from capture metadata.
struct RedactionSuggestion: Identifiable, Hashable {
  let id: UUID
  let kind: RedactionKind
  let matchedText: String
  /// Rect in image coordinates (origin top-left, in pixels).
  let rect: CGRect
  var isSelected: Bool = true

  var kindLabel: String {
    switch kind {
    case .email: return "Email"
    case .creditCard: return "Credit Card"
    case .phoneNumber: return "Phone Number"
    case .ssn: return "SSN"
    case .ipAddress: return "IP Address"
    case .token: return "API Key / Token"
    case .address: return "Street Address"
    case .dateOfBirth: return "Date of Birth"
    case .accountNumber: return "Account Number"
    case .privateKey: return "Private Key"
    }
  }

  var icon: String {
    switch kind {
    case .email: return "envelope.fill"
    case .creditCard: return "creditcard.fill"
    case .phoneNumber: return "phone.fill"
    case .ssn: return "number.square.fill"
    case .ipAddress: return "network"
    case .token: return "key.fill"
    case .address: return "house.fill"
    case .dateOfBirth: return "calendar"
    case .accountNumber: return "number.circle.fill"
    case .privateKey: return "lock.fill"
    }
  }
}

final class AnnotationDocument: ObservableObject {
  let sourceURL: URL
  let cgImage: CGImage
  let imageSize: CGSize

  /// Suggested redactions from OCR detection (Pro feature).
  @Published var suggestedRedactions: [RedactionSuggestion] = []
  
  /// Track if redaction metadata exists (even if suggestions are dismissed)
  @Published var hasRedactionMetadata: Bool = false
  
  /// Track annotation IDs that were created from PII redaction
  private var piiRedactionAnnotationIDs: Set<UUID> = []

  private var loupeSourceCache: (blurs: [BlurAnnotation], image: CGImage)?

  /// Source image for loupes: the screenshot with blur/redactions applied, so magnifying
  /// never reveals hidden pixels. Cached until the blur annotations change.
  var loupeSourceImage: CGImage {
    let blurs = annotations.compactMap { annotation -> BlurAnnotation? in
      if case .blur(let blur) = annotation { return blur }
      return nil
    }
    if blurs.isEmpty { return cgImage }
    if let cache = loupeSourceCache, cache.blurs == blurs { return cache.image }
    let image = EditorRenderer.renderRedactedSource(doc: self) ?? cgImage
    loupeSourceCache = (blurs, image)
    return image
  }

  @Published var tool: AnnotationTool = .select
  @Published var alignmentSnappingEnabled = true
  @Published var annotations: [Annotation] = [] {
    didSet { recomputeUnsavedChanges() }
  }

  /// Non-destructive crop in image coordinates (top-left origin). Applied at export.
  @Published var cropRect: CGRect? = nil {
    didSet { recomputeUnsavedChanges() }
  }
  /// True while the user is adjusting the crop box.
  @Published private(set) var isCropping = false
  /// Crop box being edited (image coordinates).
  @Published var pendingCrop: CGRect = .zero
  private var savedCropRect: CGRect? = nil
  @Published var selectedID: UUID? = nil {
    didSet {
      guard !isUpdatingSelection else { return }
      selectedIDs = selectedID.map { Set([$0]) } ?? []
      syncStyleFromSelectionIfNeeded()
    }
  }
  @Published private(set) var selectedIDs: Set<UUID> = []
  private var isUpdatingSelection = false

  var selectedAnnotation: Annotation? {
    guard let id = selectedID else { return nil }
    return annotations.first { $0.id == id }
  }

  func select(_ id: UUID?) {
    setSelection(id.map { [$0] } ?? [], primary: id)
  }

  func select(_ ids: Set<UUID>) {
    setSelection(ids, primary: annotations.last(where: { ids.contains($0.id) })?.id)
  }

  func toggleSelection(_ id: UUID) {
    var selection = selectedIDs
    if selection.contains(id) {
      selection.remove(id)
    } else {
      selection.insert(id)
    }
    let primary = selection.contains(id) ? id : annotations.last(where: { selection.contains($0.id) })?.id
    setSelection(selection, primary: primary)
  }

  private func setSelection(_ ids: Set<UUID>, primary: UUID?) {
    let validIDs = ids.filter { id in annotations.contains(where: { $0.id == id }) }
    isUpdatingSelection = true
    selectedIDs = Set(validIDs)
    selectedID = primary.flatMap { selectedIDs.contains($0) ? $0 : nil }
      ?? annotations.last(where: { selectedIDs.contains($0.id) })?.id
    isUpdatingSelection = false
    syncStyleFromSelectionIfNeeded()
  }

  var inspectorTool: AnnotationTool? {
    guard selectedIDs.count <= 1 else { return nil }
    if let annotation = selectedAnnotation {
      return annotation.inspectorTool
    }
    return tool
  }

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
  @Published var stepMode: CounterMode = .numbers

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

  // Emoji tool settings
  @Published var selectedEmoji: String = "👍"
  @Published var emojiSize: CGFloat = 48

  // Loupe tool settings
  @Published var loupeMagnification: CGFloat = 2.5

  // Freehand tool settings
  @Published var freehandIsHighlighter: Bool = false

  // Redaction settings
  @Published var redactionStyle: BlurMode = .pixelate
  
  // Active freehand stroke (while drawing)
  @Published var activeFreehandStroke: FreehandAnnotation? = nil

  // Zoom and pan state
  @Published var zoomLevel: CGFloat = 1.0
  @Published var panOffset: CGSize = .zero
  
  /// Fit mode for initial zoom
  enum FitMode: String, CaseIterable {
    case fit
    case fitWidth
    case fitHeight
    case actualSize
    
    var label: String {
      switch self {
      case .fit: return "Fit"
      case .fitWidth: return "Fit Width"
      case .fitHeight: return "Fit Height"
      case .actualSize: return "Actual Size"
      }
    }
  }
  @Published var fitMode: FitMode = .fit

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
  
  // Wallpaper background (cached)
  private var cachedWallpaper: NSImage?
  
  @MainActor
  func loadWallpaper() {
    if cachedWallpaper == nil {
      cachedWallpaper = WallpaperHelper.getDesktopWallpaper()
    }
  }
  
  func getWallpaper() -> NSImage? {
    return cachedWallpaper
  }

  // Edge detection for measurement snapping
  let snapGuideManager = SnapGuideManager()

  @Published var isShowingShortcuts = false

  // Transient input overlay
  @Published var pendingTextInput: PendingTextInput? = nil

  // Undo/redo
  private struct Snapshot {
    var annotations: [Annotation]
    var cropRect: CGRect?
  }
  private var undoStack: [Snapshot] = []
  private var redoStack: [Snapshot] = []
  private var currentSnapshot: Snapshot { Snapshot(annotations: annotations, cropRect: cropRect) }

  private var isEditSessionActive: Bool = false
  private var lastNudge: (ids: Set<UUID>, time: Date)?
  private var lastPaste: (changeCount: Int, count: Int)?

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
    let project = try EditorProjectStore.load(sourceURL: sourceURL, imageSize: self.imageSize)
    self.annotations = try project?.annotations.map { try $0.annotation() } ?? []
    self.cropRect = project?.cropRect
    self.savedAnnotationsHash = annotationsHash(self.annotations)
    self.savedCropRect = self.cropRect

    // Start with fit for all images - user can zoom as needed
    self.fitMode = .fit

    // A loaded sidecar is already the saved document state.
    hasUnsavedChanges = false

    // Load redaction suggestions from metadata if available.
    loadRedactionSuggestions()
  }

  func loadRedactionSuggestions() {
    let metadataStore = CaptureMetadataStore()
    guard let metadata = metadataStore.load(for: sourceURL),
          let candidates = metadata.redactionCandidates, !candidates.isEmpty else {
      hasRedactionMetadata = false
      return
    }

    hasRedactionMetadata = true
    
    // Convert Vision coordinates (bottom-left origin, normalized 0-1)
    // to image coordinates (top-left origin, pixels).
    suggestedRedactions = candidates.map { candidate in
      let box = candidate.boundingBox
      // Vision: origin at bottom-left, y increases upward
      // Image: origin at top-left, y increases downward
      let x = box.x * imageSize.width
      let y = (1.0 - box.y - box.height) * imageSize.height
      let w = box.width * imageSize.width
      let h = box.height * imageSize.height

      return RedactionSuggestion(
        id: UUID(),
        kind: candidate.kind,
        matchedText: candidate.matchedText,
        rect: CGRect(x: x, y: y, width: w, height: h)
      )
    }
  }

  /// Accept a redaction suggestion - adds blur/pixelate annotation or removes the area.
  func acceptRedaction(_ suggestion: RedactionSuggestion) {
    pushUndoCheckpoint()
    
    if redactionStyle == .redact {
      // For "redact" mode, add a rectangle annotation with black fill to cover the text
      let rect = RectAnnotation(
        rect: suggestion.rect,
        stroke: StrokeStyleModel(color: .black, lineWidth: 0),
        fill: FillStyleModel(color: .black, enabled: true)
      )
      let annotation = Annotation.rect(rect)
      annotations.append(annotation)
      piiRedactionAnnotationIDs.insert(annotation.id)
    } else {
      // For pixelate mode
      let blur = BlurAnnotation(
        rect: suggestion.rect,
        mode: redactionStyle,
        amount: 12
      )
      let annotation = Annotation.blur(blur)
      annotations.append(annotation)
      piiRedactionAnnotationIDs.insert(annotation.id)
    }

    // Don't remove from suggestions - keep them visible for redo
    // User can dismiss them explicitly if they don't want to see them anymore
  }

  /// Dismiss a redaction suggestion without adding a blur.
  func dismissRedaction(_ suggestion: RedactionSuggestion) {
    suggestedRedactions.removeAll { $0.id == suggestion.id }
  }

  /// Dismiss all remaining suggestions.
  func dismissAllRedactions() {
    suggestedRedactions.removeAll()
  }
  
  func toggleRedactionSelection(_ suggestionID: UUID) {
    if let index = suggestedRedactions.firstIndex(where: { $0.id == suggestionID }) {
      suggestedRedactions[index].isSelected.toggle()
    }
  }
  
  func selectAllRedactions() {
    for index in suggestedRedactions.indices {
      suggestedRedactions[index].isSelected = true
    }
  }
  
  func deselectAllRedactions() {
    for index in suggestedRedactions.indices {
      suggestedRedactions[index].isSelected = false
    }
  }

  /// Accept all remaining suggestions.
  func acceptAllRedactions() {
    guard !suggestedRedactions.isEmpty else { return }
    pushUndoCheckpoint()
    
    // Remove any previous PII redaction annotations
    annotations.removeAll { annotation in
      piiRedactionAnnotationIDs.contains(annotation.id)
    }
    piiRedactionAnnotationIDs.removeAll()
    
    // Apply redactions only for selected suggestions
    for suggestion in suggestedRedactions where suggestion.isSelected {
      if redactionStyle == .redact {
        let rect = RectAnnotation(
          rect: suggestion.rect,
          stroke: StrokeStyleModel(color: .black, lineWidth: 0),
          fill: FillStyleModel(color: .black, enabled: true)
        )
        let annotation = Annotation.rect(rect)
        annotations.append(annotation)
        piiRedactionAnnotationIDs.insert(annotation.id)
      } else {
        let blur = BlurAnnotation(
          rect: suggestion.rect,
          mode: redactionStyle,
          amount: 12
        )
        let annotation = Annotation.blur(blur)
        annotations.append(annotation)
        piiRedactionAnnotationIDs.insert(annotation.id)
      }
    }
    
    // Don't remove suggestions - let user dismiss them explicitly if desired
  }

  func markSaved() {
    savedAnnotationsHash = annotationsHash(annotations)
    savedCropRect = cropRect
    hasUnsavedChanges = false
  }

  func saveProject() throws {
    try EditorProjectStore.save(
      sourceURL: sourceURL, imageSize: imageSize, cropRect: cropRect, annotations: annotations
    )
    markSaved()
  }

  private func recomputeUnsavedChanges() {
    hasUnsavedChanges = annotationsHash(annotations) != savedAnnotationsHash || cropRect != savedCropRect
  }

  // MARK: - Crop

  var fullImageRect: CGRect { CGRect(origin: .zero, size: imageSize) }

  func beginCrop() {
    if pendingTextInput != nil { commitPendingTextInput() }
    selectedID = nil
    pendingCrop = cropRect ?? fullImageRect
    isCropping = true
  }

  func cancelCrop() {
    isCropping = false
  }

  func applyCrop() {
    guard isCropping else { return }
    isCropping = false
    let r = Self.normalizedCrop(pendingCrop, in: imageSize)
    guard r != cropRect else { return }
    pushUndoCheckpoint()
    cropRect = r
  }

  func clearCrop() {
    isCropping = false
    guard cropRect != nil else { return }
    pushUndoCheckpoint()
    cropRect = nil
  }

  /// Snaps a crop box to whole pixels inside the image. Returns nil for "no crop"
  /// (the full image) or a box too small to be useful.
  static func normalizedCrop(_ rect: CGRect, in imageSize: CGSize) -> CGRect? {
    let bounds = CGRect(origin: .zero, size: imageSize)
    let r = rect.standardized.intersection(bounds).integral.intersection(bounds)
    guard !r.isNull, r.width >= 4, r.height >= 4 else { return nil }
    if r.size == imageSize { return nil }
    return r
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
    case .ellipse(let e):
      stroke = e.stroke
      fill = e.fill
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
      stepMode = s.mode
    case .spotlight(let sp):
      spotlightShape = sp.shape
      spotlightDimmingOpacity = sp.dimmingOpacity
      spotlightShowBorder = sp.borderStroke != nil
      if let bs = sp.borderStroke {
        stroke = bs
      }
    case .counter(let c):
      stepRadius = c.radius
      stepFillColor = c.fillColor
      stepTextColor = c.textColor
      stepBorderColor = c.borderColor
      stepBorderWidth = c.borderWidth
    case .emoji(let e):
      selectedEmoji = e.emoji
      emojiSize = e.size
    case .freehand(let f):
      stroke.color = f.stroke.color
      // Highlighter annotations store the expanded width, not the base setting.
      stroke.lineWidth = f.isHighlighter ? f.stroke.lineWidth / 3 : f.stroke.lineWidth
      freehandIsHighlighter = f.isHighlighter
    case .line(let l):
      stroke = l.stroke
    case .measurement(let m):
      stroke = m.stroke
      measurementUnit = m.unit
      measurementPPI = m.ppi
      measurementBaseFontSize = m.baseFontSize
      measurementShowExtensionLines = m.showExtensionLines
    case .imageLayer:
      // Image layers don't have style properties to sync
      break
    case .loupe(let l):
      loupeMagnification = l.magnification
    }
  }

  func nextStepNumber() -> Int {
    let nums = annotations.compactMap { a -> Int? in
      if case .step(let s) = a { return s.number }
      return nil
    }
    return (nums.max() ?? 0) + 1
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
    guard var stroke = activeFreehandStroke, stroke.points.last != point else { return }
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

  func recognizeSelectedFreehandShape() {
    guard let annotation = selectedAnnotation, case .freehand(let stroke) = annotation,
          let shape = FreehandShapeRecognition.recognize(stroke),
          shape != stroke.recognizedShape else { return }
    updateSelected { annotation in
      guard case .freehand(var stroke) = annotation else { return }
      stroke.recognizedShape = shape
      annotation = .freehand(stroke)
    }
  }

  func restoreSelectedFreehandStroke() {
    guard let annotation = selectedAnnotation,
          case .freehand(let stroke) = annotation,
          stroke.recognizedShape != nil else { return }
    updateSelected { annotation in
      guard case .freehand(var stroke) = annotation else { return }
      stroke.recognizedShape = nil
      annotation = .freehand(stroke)
    }
  }

  func pushUndoCheckpoint() {
    lastNudge = nil
    undoStack.append(currentSnapshot)
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
    lastNudge = nil
    redoStack.append(currentSnapshot)
    annotations = prev.annotations
    cropRect = prev.cropRect
    selectedIDs = selectedIDs.filter { id in annotations.contains(where: { $0.id == id }) }
    if let sel = selectedID, !annotations.contains(where: { $0.id == sel }) {
      select(nil)
    }
    syncStyleFromSelectionIfNeeded()
  }

  func redo() {
    guard let next = redoStack.popLast() else { return }
    lastNudge = nil
    undoStack.append(currentSnapshot)
    annotations = next.annotations
    cropRect = next.cropRect
    selectedIDs = selectedIDs.filter { id in annotations.contains(where: { $0.id == id }) }
    if let sel = selectedID, !annotations.contains(where: { $0.id == sel }) {
      select(nil)
    }
    syncStyleFromSelectionIfNeeded()
  }

  func deleteSelected() {
    guard !selectedIDs.isEmpty else { return }
    pushUndoCheckpoint()
    annotations.removeAll(where: { selectedIDs.contains($0.id) })
    select(nil)
  }

  func duplicateSelected() {
    let duplicates = annotations.filter { selectedIDs.contains($0.id) }.map { $0.duplicate() }
    guard !duplicates.isEmpty else { return }
    pushUndoCheckpoint()
    annotations.append(contentsOf: duplicates)
    setSelection(Set(duplicates.map(\.id)), primary: duplicates.last?.id)
  }

  /// Moves the selection by `delta` image pixels. Rapid repeats (holding an arrow key)
  /// coalesce into one undo step.
  func nudgeSelected(by delta: CGPoint, now: Date = Date()) {
    guard !selectedIDs.isEmpty, delta != .zero else { return }
    let coalesce = lastNudge.map { $0.ids == selectedIDs && now.timeIntervalSince($0.time) < 1 } ?? false
    if !coalesce { pushUndoCheckpoint() }
    for index in annotations.indices where selectedIDs.contains(annotations[index].id) {
      annotations[index].translate(by: delta)
    }
    lastNudge = (selectedIDs, now)
  }

  /// Inserts copies of `pasted` (with new IDs) and selects them. Repeated pastes of the
  /// same clipboard cascade so copies don't stack exactly on top of each other.
  func pasteAnnotations(_ pasted: [Annotation], pasteboardChangeCount: Int) {
    guard !pasted.isEmpty else { return }
    if lastPaste?.changeCount == pasteboardChangeCount {
      lastPaste?.count += 1
    } else {
      let overlapsOriginals = pasted.contains { item in annotations.contains { $0.id == item.id } }
      lastPaste = (pasteboardChangeCount, overlapsOriginals ? 1 : 0)
    }
    let step = CGFloat(lastPaste?.count ?? 0) * 12
    let copies = pasted.map { $0.duplicate(offset: CGPoint(x: step, y: step)) }
    pushUndoCheckpoint()
    annotations.append(contentsOf: copies)
    setSelection(Set(copies.map(\.id)), primary: copies.last?.id)
  }

  func bringSelectedToFront() {
    let selected = annotations.filter { selectedIDs.contains($0.id) }
    guard !selected.isEmpty, annotations.suffix(selected.count) != selected[...] else {
      return
    }
    pushUndoCheckpoint()
    annotations.removeAll { selectedIDs.contains($0.id) }
    annotations.append(contentsOf: selected)
  }

  func sendSelectedToBack() {
    let selected = annotations.filter { selectedIDs.contains($0.id) }
    guard !selected.isEmpty, annotations.prefix(selected.count) != selected[...] else {
      return
    }
    pushUndoCheckpoint()
    annotations.removeAll { selectedIDs.contains($0.id) }
    annotations.insert(contentsOf: selected, at: 0)
  }

  func moveSelectedForward() {
    var reordered = annotations
    guard reordered.count > 1 else { return }
    for index in (0..<(reordered.count - 1)).reversed()
    where selectedIDs.contains(reordered[index].id) && !selectedIDs.contains(reordered[index + 1].id) {
      reordered.swapAt(index, index + 1)
    }
    guard reordered != annotations else { return }
    pushUndoCheckpoint()
    annotations = reordered
  }

  func moveSelectedBackward() {
    var reordered = annotations
    guard reordered.count > 1 else { return }
    for index in 1..<reordered.count
    where selectedIDs.contains(reordered[index].id) && !selectedIDs.contains(reordered[index - 1].id) {
      reordered.swapAt(index, index - 1)
    }
    guard reordered != annotations else { return }
    pushUndoCheckpoint()
    annotations = reordered
  }

  func updateSelectionInSession(_ update: (inout Annotation) -> Void) {
    for index in annotations.indices where selectedIDs.contains(annotations[index].id) {
      var annotation = annotations[index]
      update(&annotation)
      annotations[index] = annotation
    }
  }

  func updateSelected(_ update: (inout Annotation) -> Void) {
    guard let id = selectedID, let idx = annotations.firstIndex(where: { $0.id == id }) else { return }
    var a = annotations[idx]
    update(&a)
    guard a != annotations[idx] else { return }
    pushUndoCheckpoint()
    annotations[idx] = a
  }

  func updateSelectedInSession(_ update: (inout Annotation) -> Void) {
    guard let id = selectedID, let idx = annotations.firstIndex(where: { $0.id == id }) else { return }
    var a = annotations[idx]
    update(&a)
    guard a != annotations[idx] else { return }
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
