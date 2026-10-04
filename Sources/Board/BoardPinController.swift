import AppKit
import SwiftUI

/// Floating always-on-top windows for cards that have been "popped out" of the board.
/// Mirrors `PinnedImageWindowController` (same panel style + resize corner) but is keyed by
/// card ID and persists each pin's frame in the board so pins survive relaunch.
@MainActor
final class BoardPinController {
  private let store: BoardStore
  private let prefs: BoardPreferencesStore
  private var panels: [UUID: NSPanel] = [:]
  private var delegates: [UUID: CardPinDelegate] = [:]
  private var resizeStart: [UUID: NSRect] = [:]

  var onReturnToBoard: ((UUID) -> Void)?
  var onOpenInEditor: ((UUID) -> Void)?
  var onToggleTodo: ((UUID) -> Void)?

  static let minSize = NSSize(width: 110, height: 70)

  init(store: BoardStore, prefs: BoardPreferencesStore) {
    self.store = store
    self.prefs = prefs
  }

  var pinnedIDs: Set<UUID> { Set(panels.keys) }

  func isPinned(_ id: UUID) -> Bool { panels[id] != nil }

  /// Recreates pin windows for cards that were popped out when the app last quit.
  func restorePins() {
    for card in store.cards where card.pin != nil {
      show(card, at: card.pin?.screenFrame.cgRect, animated: false)
    }
  }

  /// Pops a card out at `screenRect` (global coords) — or where it was last pinned / centered.
  func pin(_ id: UUID, from screenRect: CGRect?) {
    guard let card = store.card(id) else { return }
    if let existing = panels[id] {
      existing.orderFrontRegardless()
      return
    }
    let rect = screenRect ?? card.pin?.screenFrame.cgRect
    show(card, at: rect, animated: true)
    if let panel = panels[id] {
      store.setPin(id, PinState(screenFrame: CodableRect(panel.frame)))
    }
  }

  func unpin(_ id: UUID) {
    guard let panel = panels[id] else {
      store.setPin(id, nil)
      return
    }
    cleanup(id)
    store.setPin(id, nil)
    NSAnimationContext.runAnimationGroup({ ctx in
      ctx.duration = 0.12
      panel.animator().alphaValue = 0
    }, completionHandler: {
      panel.orderOut(nil)
    })
  }

  func setAllHidden(_ hidden: Bool) {
    for panel in panels.values {
      if hidden { panel.orderOut(nil) } else { panel.orderFrontRegardless() }
    }
  }

  /// Rebuilds pin content (e.g. after the card changed on the board).
  func refresh(_ id: UUID) {
    guard let panel = panels[id], let card = store.card(id) else { return }
    if card.isArchived || card.pin == nil {
      cleanup(id)
      panel.orderOut(nil)
      return
    }
    panel.contentView = makeContent(card: card, panel: panel)
  }

  func refreshAll() {
    for id in panels.keys { refresh(id) }
  }

  // MARK: - Private

  private func show(_ card: BoardCard, at rect: CGRect?, animated: Bool) {
    let frame = Self.validatedFrame(rect, card: card)
    let panel = NSPanel(
      contentRect: frame,
      styleMask: [.borderless, .nonactivatingPanel],
      backing: .buffered,
      defer: false
    )
    panel.isFloatingPanel = true
    panel.hidesOnDeactivate = false
    panel.level = .floating
    panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
    panel.isMovableByWindowBackground = true
    panel.hasShadow = true
    panel.isOpaque = false
    panel.backgroundColor = .clear
    panel.isReleasedWhenClosed = false
    panel.minSize = Self.minSize
    panel.setFrame(frame, display: false)
    panel.contentView = makeContent(card: card, panel: panel)

    let id = card.id
    let delegate = CardPinDelegate(
      onFrameChange: { [weak self, weak panel] in
        guard let self, let panel, self.panels[id] != nil else { return }
        self.store.setPin(id, PinState(screenFrame: CodableRect(panel.frame)))
      }
    )
    panel.delegate = delegate
    delegates[id] = delegate
    panels[id] = panel

    guard !prefs.pinsHidden else { return }
    if animated {
      panel.alphaValue = 0
      panel.orderFrontRegardless()
      NSAnimationContext.runAnimationGroup { ctx in
        ctx.duration = 0.18
        panel.animator().alphaValue = 1
      }
    } else {
      panel.orderFrontRegardless()
    }
  }

  private func cleanup(_ id: UUID) {
    panels[id]?.delegate = nil
    panels[id] = nil
    delegates[id] = nil
    resizeStart[id] = nil
  }

  private func makeContent(card: BoardCard, panel: NSPanel) -> NSView {
    let id = card.id
    let hosting = NSHostingView(rootView: CardPinView(
      card: card,
      store: store,
      onResize: { [weak self, weak panel] translation in
        guard let self, let panel else { return }
        self.resize(panel: panel, id: id, translation: translation)
      },
      onResizeEnded: { [weak self, weak panel] in
        guard let self else { return }
        self.resizeStart[id] = nil
        if let panel { self.store.setPin(id, PinState(screenFrame: CodableRect(panel.frame))) }
      },
      onReturn: { [weak self] in self?.onReturnToBoard?(id) },
      onEdit: { [weak self] in self?.onOpenInEditor?(id) },
      onToggleTodo: { [weak self] in self?.onToggleTodo?(id) },
      onCopy: { [weak self] in self?.copy(id) }
    ))
    hosting.wantsLayer = true
    hosting.layer?.cornerRadius = 12
    hosting.layer?.cornerCurve = .continuous
    hosting.layer?.masksToBounds = true
    return hosting
  }

  private func resize(panel: NSPanel, id: UUID, translation: CGSize) {
    let start = resizeStart[id] ?? panel.frame
    resizeStart[id] = start
    let isImage = store.card(id)?.kind == .capture
    let maxSize = (panel.screen ?? NSScreen.main)?.visibleFrame.size ?? NSSize(width: 3000, height: 3000)
    var width = max(Self.minSize.width, min(maxSize.width, start.width + translation.width))
    var height = max(Self.minSize.height, min(maxSize.height, start.height + translation.height))
    if isImage, start.width > 0 {
      let aspect = start.height / start.width
      width = max(Self.minSize.width, min(maxSize.width, start.width + (translation.width + translation.height / aspect) / 2))
      height = width * aspect
    }
    panel.setFrame(NSRect(x: start.minX, y: start.maxY - height, width: width, height: height), display: true)
  }

  private func copy(_ id: UUID) {
    guard let card = store.card(id) else { return }
    let pb = NSPasteboard.general
    pb.clearContents()
    switch card.kind {
    case .capture:
      if let url = store.imageURL(for: card), let image = NSImage(contentsOf: url) { pb.writeObjects([image]) }
    case .link:
      if let url = card.url { pb.setString(url.absoluteString, forType: .string) }
    case .text, .note:
      pb.setString(card.text ?? "", forType: .string)
    }
  }

  /// Keeps pins on a visible screen and at a sensible size.
  static func validatedFrame(_ rect: CGRect?, card: BoardCard) -> CGRect {
    let screen = NSScreen.main ?? NSScreen.screens.first
    let visible = screen?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1440, height: 900)
    var size = rect?.size ?? card.frame.cgRect.size
    // Images are pinned a bit larger than their board thumbnail by default.
    if rect == nil, card.kind == .capture { size = CGSize(width: size.width * 1.5, height: size.height * 1.5) }
    size.width = min(max(size.width, minSize.width), visible.width * 0.8)
    size.height = min(max(size.height, minSize.height), visible.height * 0.8)

    if let rect {
      let target = CGRect(origin: rect.origin, size: size)
      if let hit = NSScreen.screens.max(by: { $0.visibleFrame.intersection(target).area < $1.visibleFrame.intersection(target).area }),
         !hit.visibleFrame.intersection(target).isNull {
        let vf = hit.visibleFrame
        let w = min(size.width, vf.width), h = min(size.height, vf.height)
        let x = min(max(target.minX, vf.minX), vf.maxX - w)
        let y = min(max(target.minY, vf.minY), vf.maxY - h)
        return CGRect(x: x, y: y, width: w, height: h)
      }
    }
    return CGRect(x: visible.midX - size.width / 2, y: visible.midY - size.height / 2, width: size.width, height: size.height)
  }
}

@MainActor
private final class CardPinDelegate: NSObject, NSWindowDelegate {
  let onFrameChange: () -> Void

  init(onFrameChange: @escaping () -> Void) {
    self.onFrameChange = onFrameChange
  }

  func windowDidMove(_ notification: Notification) { onFrameChange() }
}

private struct CardPinView: View {
  let card: BoardCard
  let store: BoardStore
  let onResize: (CGSize) -> Void
  let onResizeEnded: () -> Void
  let onReturn: () -> Void
  let onEdit: () -> Void
  let onToggleTodo: () -> Void
  let onCopy: () -> Void

  @State private var hovering = false
  @State private var resizing = false

  var body: some View {
    let controls = hovering || resizing
    ZStack {
      CardContentView(card: card, store: store, style: BoardThemeStyle(theme: .glass))

      if card.todo == .done {
        Color.black.opacity(0.35).allowsHitTesting(false)
      }

      VStack {
        HStack(alignment: .top) {
          if let todo = card.todo {
            TodoCheckbox(state: todo, action: onToggleTodo)
          }
          Spacer()
          HStack(spacing: 4) {
            CardIconButton(systemName: "doc.on.doc", help: "Copy", action: onCopy)
            CardIconButton(systemName: "rectangle.on.rectangle.angled", help: "Return to Board", action: onReturn)
          }
          .opacity(controls ? 1 : 0)
        }
        Spacer()
        HStack(alignment: .bottom) {
          if let items = card.detectedItems, !items.isEmpty, card.kind != .link {
            DetectedChips(items: items, limit: 2)
          }
          Spacer()
          ZStack {
            ResizeCorner()
            ResizeDragSurface(onResize: onResize, onResizeEnded: onResizeEnded, onDraggingChanged: { resizing = $0 })
          }
          .frame(width: 24, height: 24)
          .opacity(controls ? 1 : 0)
          .help("Resize")
        }
      }
      .padding(6)
    }
    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(.white.opacity(0.14)))
    .contentShape(Rectangle())
    .onHover { h in withAnimation(.easeOut(duration: 0.12)) { hovering = h } }
    .onTapGesture(count: 2) {
      if card.kind == .link, let url = card.url { NSWorkspace.shared.open(url) }
    }
    .contextMenu {
      if card.kind == .link, let url = card.url {
        Button("Open Link") { NSWorkspace.shared.open(url) }
      }
      if card.kind == .capture {
        Button("Edit in Editor", action: onEdit)
      }
      if let page = card.source?.pageURL {
        Button("Open Source Page") { NSWorkspace.shared.open(page) }
      }
      Button("Copy", action: onCopy)
      if card.todo != nil {
        Button(card.todo == .done ? "Mark Not Done" : "Mark Done", action: onToggleTodo)
      }
      Divider()
      Button("Return to Board", action: onReturn)
    }
  }
}

private extension CGRect {
  var area: CGFloat { isNull ? 0 : width * height }
}
