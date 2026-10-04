import AppKit
import Combine
import SwiftUI

/// Window-level actions the board UI asks its coordinator to perform.
struct BoardActions {
  var close: () -> Void = {}
  var popOut: (UUID) -> Void = { _ in }
  var returnPin: (UUID) -> Void = { _ in }
  var openInEditor: (UUID) -> Void = { _ in }
  var togglePinsHidden: () -> Void = {}
  var showPreferences: () -> Void = {}
}

/// UI state for the corkboard overlay. Persistent data lives in `BoardStore`; this holds
/// transient state (viewport, selection, in-progress drags, search, editing).
@MainActor
final class BoardViewModel: ObservableObject {
  static let minScale: CGFloat = 0.25
  static let maxScale: CGFloat = 2.5

  let store: BoardStore
  let prefs: BoardPreferencesStore
  let factory: CardFactory
  let enrichment: BoardEnrichmentService
  var actions = BoardActions()

  @Published var scale: CGFloat
  @Published var offset: CGSize
  @Published var canvasSize: CGSize = .zero

  @Published var selection: Set<UUID> = []
  @Published var dragTranslation: CGSize = .zero
  @Published var draggingIDs: Set<UUID> = []
  @Published var resizing: (id: UUID, size: CGSize)?
  @Published var marquee: CGRect?

  @Published var zoneDrag: (id: UUID, translation: CGSize)?
  @Published var zoneResize: (id: UUID, size: CGSize)?

  @Published var searchQuery = "" { didSet { recomputeMatches() } }
  @Published private(set) var matches: Set<UUID>?
  @Published var searchFocusToken = 0

  @Published var editingCardID: UUID?
  @Published var editingZoneID: UUID?
  @Published var detailCardID: UUID?

  @Published var toast: BoardToast?
  private var toastWork: DispatchWorkItem?

  private var cancellables = Set<AnyCancellable>()

  init(store: BoardStore, prefs: BoardPreferencesStore, factory: CardFactory, enrichment: BoardEnrichmentService) {
    self.store = store
    self.prefs = prefs
    self.factory = factory
    self.enrichment = enrichment
    let vp = store.board.viewport
    scale = CGFloat(vp.scale)
    offset = CGSize(width: vp.offsetX, height: vp.offsetY)

    store.objectWillChange
      .sink { [weak self] in
        DispatchQueue.main.async { self?.recomputeMatches() }
      }
      .store(in: &cancellables)
  }

  // MARK: - Coordinates

  func toBoard(_ p: CGPoint) -> CGPoint {
    CGPoint(x: (p.x - offset.width) / scale, y: (p.y - offset.height) / scale)
  }

  func toView(_ p: CGPoint) -> CGPoint {
    CGPoint(x: p.x * scale + offset.width, y: p.y * scale + offset.height)
  }

  func toView(_ r: CGRect) -> CGRect {
    CGRect(origin: toView(r.origin), size: CGSize(width: r.width * scale, height: r.height * scale))
  }

  var visibleBoardRect: CGRect {
    let origin = toBoard(.zero)
    return CGRect(origin: origin, size: CGSize(width: canvasSize.width / scale, height: canvasSize.height / scale))
  }

  /// Where to put new cards: under the mouse if it's over the board, else a free slot in view.
  func insertionPoint(viewPoint: CGPoint? = nil) -> CGPoint {
    if let viewPoint, CGRect(origin: .zero, size: canvasSize).insetBy(dx: 20, dy: 60).contains(viewPoint) {
      return toBoard(viewPoint)
    }
    return store.insertionOrigin(in: visibleBoardRect)
  }

  // MARK: - Viewport

  func pan(by delta: CGSize) {
    offset = CGSize(width: offset.width + delta.width, height: offset.height + delta.height)
  }

  func zoom(by factor: CGFloat, around viewPoint: CGPoint) {
    let newScale = min(Self.maxScale, max(Self.minScale, scale * factor))
    guard newScale != scale else { return }
    let ratio = newScale / scale
    offset = CGSize(
      width: viewPoint.x - (viewPoint.x - offset.width) * ratio,
      height: viewPoint.y - (viewPoint.y - offset.height) * ratio
    )
    scale = newScale
  }

  func resetZoom() {
    let center = CGPoint(x: canvasSize.width / 2, y: canvasSize.height / 2)
    zoom(by: 1 / scale, around: center)
  }

  func zoomToFit() {
    let rects = store.cards.map(\.frame.cgRect) + store.zones.map(\.frame.cgRect)
    guard let first = rects.first, canvasSize.width > 0 else {
      withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
        scale = 1
        offset = .zero
      }
      return
    }
    let bounds = rects.dropFirst().reduce(first) { $0.union($1) }.insetBy(dx: -40, dy: -40)
    let available = CGSize(width: canvasSize.width - 80, height: canvasSize.height - 160)
    let s = min(1.25, max(Self.minScale, min(available.width / bounds.width, available.height / bounds.height)))
    withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
      scale = s
      offset = CGSize(
        width: (canvasSize.width - bounds.width * s) / 2 - bounds.minX * s,
        height: 60 + (canvasSize.height - 60 - bounds.height * s) / 2 - bounds.minY * s
      )
    }
  }

  func persistViewport() {
    store.setViewport(BoardViewport(offsetX: offset.width, offsetY: offset.height, scale: scale))
  }

  // MARK: - Search

  var isSearching: Bool { !searchQuery.trimmingCharacters(in: .whitespaces).isEmpty }

  private func recomputeMatches() {
    let q = searchQuery.trimmingCharacters(in: .whitespaces)
    let newValue: Set<UUID>? = q.isEmpty ? nil : store.matchingCardIDs(q)
    if newValue != matches { matches = newValue }
  }

  func isDimmed(_ id: UUID) -> Bool {
    guard let matches else { return false }
    return !matches.contains(id)
  }

  // MARK: - Selection & dragging

  func select(_ id: UUID, extend: Bool) {
    if extend {
      if selection.contains(id) { selection.remove(id) } else { selection.insert(id) }
    } else if !selection.contains(id) {
      selection = [id]
    }
    store.bringToFront(selection.contains(id) ? selection : [id])
  }

  func clearSelection() {
    selection = []
    editingCardID = nil
    editingZoneID = nil
  }

  func beginCardDrag(_ id: UUID, extend: Bool) {
    if draggingIDs.isEmpty {
      if !selection.contains(id) { select(id, extend: extend) } else { store.bringToFront(selection) }
      draggingIDs = selection.contains(id) ? selection : [id]
    }
  }

  func updateCardDrag(viewTranslation: CGSize) {
    dragTranslation = CGSize(width: viewTranslation.width / scale, height: viewTranslation.height / scale)
  }

  func endCardDrag() {
    store.move(draggingIDs, by: dragTranslation)
    draggingIDs = []
    dragTranslation = .zero
  }

  func offsetFor(_ id: UUID) -> CGSize {
    draggingIDs.contains(id) ? dragTranslation : .zero
  }

  func updateMarquee(from start: CGPoint, to end: CGPoint, extend: Bool, baseSelection: Set<UUID>) {
    let rect = CGRect(
      x: min(start.x, end.x), y: min(start.y, end.y),
      width: abs(end.x - start.x), height: abs(end.y - start.y)
    )
    marquee = rect
    let boardRect = CGRect(origin: toBoard(rect.origin), size: CGSize(width: rect.width / scale, height: rect.height / scale))
    let hit = Set(store.cards.filter { $0.frame.cgRect.intersects(boardRect) }.map(\.id))
    selection = extend ? baseSelection.union(hit) : hit
  }

  func endMarquee() {
    marquee = nil
  }

  func selectAll() {
    selection = Set(store.cards.map(\.id))
  }

  // MARK: - Resizing

  func updateResize(_ card: BoardCard, viewTranslation: CGSize) {
    let base = card.frame.cgRect.size
    var w = max(120, base.width + viewTranslation.width / scale)
    var h = max(70, base.height + viewTranslation.height / scale)
    if card.kind == .capture, base.width > 0 {
      // Keep the image aspect ratio.
      let aspect = base.height / base.width
      w = max(120, base.width + (viewTranslation.width + viewTranslation.height / aspect) / 2 / scale)
      h = w * aspect
    }
    resizing = (card.id, CGSize(width: min(w, 2400), height: min(h, 2400)))
  }

  func endResize() {
    guard let resizing, let card = store.card(resizing.id) else { self.resizing = nil; return }
    store.setFrame(card.id, CGRect(origin: card.frame.cgRect.origin, size: resizing.size))
    self.resizing = nil
  }

  func liveSize(_ card: BoardCard) -> CGSize {
    if let resizing, resizing.id == card.id { return resizing.size }
    return card.frame.cgRect.size
  }

  // MARK: - Card actions

  func addNote(at boardPoint: CGPoint? = nil) {
    let origin = boardPoint.map { CGPoint(x: $0.x - CardFactory.Size.note.width / 2, y: $0.y - 24) }
      ?? store.insertionOrigin(in: visibleBoardRect)
    let card = store.add(factory.noteCard(at: origin))
    selection = [card.id]
    editingCardID = card.id
  }

  @discardableResult
  func addFromPasteboard(_ pasteboard: NSPasteboard, atBoardPoint point: CGPoint, source: SourceContext? = nil) -> Int {
    let cards = factory.cards(from: pasteboard, at: point, source: source)
    guard !cards.isEmpty else { return 0 }
    var added: Set<UUID> = []
    for card in cards {
      let saved = store.add(card)
      added.insert(saved.id)
      enrichment.enrich(saved.id)
    }
    withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) { selection = added }
    return cards.count
  }

  func paste(viewPoint: CGPoint?) {
    let count = addFromPasteboard(.general, atBoardPoint: insertionPoint(viewPoint: viewPoint))
    if count == 0 { showToast("Nothing to paste", systemImage: "clipboard") }
  }

  func delete(_ ids: Set<UUID>) {
    guard !ids.isEmpty else { return }
    for id in ids where store.card(id)?.pin != nil { actions.returnPin(id) }
    store.archive(ids)
    selection.subtract(ids)
    if let detailCardID, ids.contains(detailCardID) { self.detailCardID = nil }
    let noun = ids.count == 1 ? "Card" : "\(ids.count) cards"
    showToast("\(noun) deleted", systemImage: "trash", actionTitle: "Undo") { [weak self] in
      self?.store.restore(ids)
      self?.selection = ids
    }
  }

  func toggleTodo(_ id: UUID) {
    guard let card = store.card(id) else { return }
    let next: TodoState = card.todo == .done ? .open : .done
    withAnimation(.spring(response: 0.25, dampingFraction: 0.7)) {
      store.setTodo([id], next)
    }
  }

  func setTodo(_ ids: Set<UUID>, enabled: Bool) {
    store.setTodo(ids, enabled ? .open : nil)
  }

  func setColor(_ ids: Set<UUID>, hex: String?) {
    for id in ids { store.update(id) { $0.colorHex = hex } }
  }

  func copy(_ id: UUID) {
    guard let card = store.card(id) else { return }
    let pb = NSPasteboard.general
    pb.clearContents()
    switch card.kind {
    case .capture:
      if let url = store.imageURL(for: card), let image = NSImage(contentsOf: url) {
        pb.writeObjects([image])
      }
    case .link:
      if let url = card.url {
        pb.writeObjects([url as NSURL])
        pb.setString(url.absoluteString, forType: .string)
      }
    case .text, .note:
      pb.setString(card.text ?? "", forType: .string)
    }
    showToast("Copied", systemImage: "doc.on.doc")
  }

  func copyText(_ id: UUID) {
    guard let text = store.card(id)?.copyableText, !text.isEmpty else {
      showToast("No text found", systemImage: "text.magnifyingglass")
      return
    }
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(text, forType: .string)
    showToast("Text copied", systemImage: "doc.on.doc")
  }

  func open(_ id: UUID) {
    guard let card = store.card(id) else { return }
    switch card.kind {
    case .link:
      if let url = card.url { NSWorkspace.shared.open(url) }
    case .capture:
      detailCardID = id
    case .text, .note:
      editingCardID = id
    }
  }

  // MARK: - Zones

  func addZone() {
    let visible = visibleBoardRect
    let size = CGSize(width: 340, height: 420)
    let frame = CGRect(
      x: visible.midX - size.width / 2 + CGFloat(store.zones.count % 4) * 24,
      y: visible.minY + 90 + CGFloat(store.zones.count % 4) * 24,
      width: size.width, height: size.height
    )
    let zone = store.addZone(title: "New Zone", frame: frame)
    editingZoneID = zone.id
  }

  func addTodoTemplate() {
    let visible = visibleBoardRect
    let width: CGFloat = 3 * 320 + 2 * 24
    store.applyTodoTemplate(origin: CGPoint(x: visible.midX - width / 2, y: visible.minY + 90))
  }

  func endZoneDrag() {
    if let zoneDrag { store.moveZone(zoneDrag.id, by: zoneDrag.translation) }
    zoneDrag = nil
  }

  func endZoneResize() {
    if let zoneResize, let zone = store.zones.first(where: { $0.id == zoneResize.id }) {
      store.setZoneFrame(zone.id, CGRect(origin: zone.frame.cgRect.origin, size: zoneResize.size))
    }
    zoneResize = nil
  }

  /// Visual offset for a card while its zone is being dragged.
  func zoneOffsetFor(_ card: BoardCard) -> CGSize {
    guard let zoneDrag, card.zoneID == zoneDrag.id else { return .zero }
    return zoneDrag.translation
  }

  func tidyUp() {
    withAnimation(.spring(response: 0.45, dampingFraction: 0.82)) {
      store.tidyUp()
    }
  }

  // MARK: - Toast

  func showToast(_ message: String, systemImage: String, actionTitle: String? = nil, action: (() -> Void)? = nil) {
    toastWork?.cancel()
    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
      toast = BoardToast(message: message, systemImage: systemImage, actionTitle: actionTitle, action: action)
    }
    let work = DispatchWorkItem { [weak self] in
      withAnimation(.easeOut(duration: 0.2)) { self?.toast = nil }
    }
    toastWork = work
    DispatchQueue.main.asyncAfter(deadline: .now() + (action == nil ? 1.6 : 5), execute: work)
  }
}

struct BoardToast: Identifiable {
  let id = UUID()
  var message: String
  var systemImage: String
  var actionTitle: String?
  var action: (() -> Void)?
}
