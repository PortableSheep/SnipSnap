import AppKit
import Combine
import SwiftUI
import os.log

private let boardControllerLog = OSLog(subsystem: "com.snipsnap.Snipsnap", category: "BoardController")

/// Coordinates the Board feature: data, overlay, pop-out pins, hot corner, and quick-add entry
/// points (Send to Board, clipboard hotkey). Owned by `AppDelegate`.
@MainActor
final class BoardController {
  let store: BoardStore
  let prefs: BoardPreferencesStore
  let factory: CardFactory
  let enrichment: BoardEnrichmentService
  let viewModel: BoardViewModel
  private let overlay: BoardOverlayController
  private let pins: BoardPinController
  private let hotCorner = HotCornerMonitor()
  private let hud = BoardHUD()
  private let metadataStore = CaptureMetadataStore()
  private weak var pinnedImages: PinnedImageWindowController?

  private var cancellables = Set<AnyCancellable>()
  private var lastPinnedSnapshot: [UUID: BoardCard] = [:]
  private var saveObserver: NSObjectProtocol?

  var openEditor: ((URL) -> Void)?
  var showPreferences: (() -> Void)?
  /// Called whenever something that affects the status menu changes (pins hidden, etc.).
  var onStateChange: (() -> Void)?

  init(
    pinnedImages: PinnedImageWindowController?,
    store: BoardStore? = nil,
    prefs: BoardPreferencesStore? = nil
  ) {
    let store = store ?? BoardStore()
    let prefs = prefs ?? .shared
    self.store = store
    self.prefs = prefs
    self.pinnedImages = pinnedImages
    factory = CardFactory(store: store, tilt: { prefs.tiltCards })
    enrichment = BoardEnrichmentService(store: store, prefs: prefs)
    viewModel = BoardViewModel(store: store, prefs: prefs, factory: factory, enrichment: enrichment)
    overlay = BoardOverlayController(vm: viewModel)
    pins = BoardPinController(store: store, prefs: prefs)

    viewModel.actions = BoardActions(
      close: { [weak self] in self?.hideBoard() },
      popOut: { [weak self] id in self?.popOut(id) },
      returnPin: { [weak self] id in self?.returnPin(id) },
      openInEditor: { [weak self] id in self?.openInEditor(id) },
      togglePinsHidden: { [weak self] in self?.togglePinsHidden() },
      showPreferences: { [weak self] in
        self?.hideBoard()
        self?.showPreferences?()
      }
    )

    pins.onReturnToBoard = { [weak self] id in
      self?.returnPin(id)
      self?.showBoard()
    }
    pins.onOpenInEditor = { [weak self] id in self?.openInEditor(id) }
    pins.onToggleTodo = { [weak self] id in self?.viewModel.toggleTodo(id) }

    hotCorner.onTrigger = { [weak self] in self?.toggleBoard() }

    pinnedImages?.onSendToBoard = { [weak self] url in self?.sendCaptureToBoard(url) }
    pinnedImages?.onPinWhileHidden = { [weak self] in self?.setPinsHidden(false) }
  }

  deinit {
    if let saveObserver { NotificationCenter.default.removeObserver(saveObserver) }
  }

  /// Call once at launch.
  func start() {
    store.purgeArchived()
    pins.restorePins()
    pinnedImages?.setAllHidden(prefs.pinsHidden)
    lastPinnedSnapshot = Dictionary(uniqueKeysWithValues: store.cards.filter { $0.pin != nil }.map { ($0.id, $0) })

    Publishers.CombineLatest(prefs.$hotCorner, prefs.$hotCornerDelay)
      .removeDuplicates { $0.0 == $1.0 && $0.1 == $1.1 }
      .sink { [weak self] corner, delay in self?.hotCorner.configure(corner: corner, delay: delay) }
      .store(in: &cancellables)

    store.$board
      .dropFirst()
      .receive(on: RunLoop.main)
      .sink { [weak self] _ in self?.syncPins() }
      .store(in: &cancellables)

    prefs.$theme.dropFirst()
      .receive(on: RunLoop.main)
      .sink { [weak self] _ in self?.pins.refreshAll() }
      .store(in: &cancellables)

    saveObserver = NotificationCenter.default.addObserver(forName: .editorDidSave, object: nil, queue: .main) { [weak self] note in
      guard let url = note.object as? URL else { return }
      Task { @MainActor in self?.handleEditorSave(url) }
    }

    // Defer enrichment so launch isn't slowed down.
    DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
      self?.enrichment.enrichAll()
    }
  }

  // MARK: - Board visibility

  var isBoardVisible: Bool { overlay.isVisible }

  func toggleBoard() { overlay.toggle() }

  func showBoard() { overlay.show() }

  func hideBoard() { overlay.hide() }

  // MARK: - Pins

  var pinsHidden: Bool { prefs.pinsHidden }

  var hasAnyPins: Bool { !pins.pinnedIDs.isEmpty || pinnedImages?.hasPins == true }

  func togglePinsHidden() {
    setPinsHidden(!prefs.pinsHidden)
  }

  func setPinsHidden(_ hidden: Bool) {
    prefs.pinsHidden = hidden
    pins.setAllHidden(hidden)
    pinnedImages?.setAllHidden(hidden)
    if overlay.isVisible {
      viewModel.showToast(hidden ? "Pins hidden" : "Pins shown", systemImage: hidden ? "pin.slash" : "pin")
    } else {
      hud.show(message: hidden ? "Pins hidden" : "Pins shown", systemImage: hidden ? "pin.slash" : "pin", image: nil)
    }
    onStateChange?()
  }

  func popOut(_ id: UUID) {
    guard let card = store.card(id) else { return }
    if prefs.pinsHidden { setPinsHidden(false) }
    var rect = overlay.screenRect(forBoardRect: card.frame.cgRect)
    // Pins open at least at 100% scale, and images a bit larger for readability.
    if var r = rect {
      let minScale: CGFloat = card.kind == .capture ? 1.4 : 1
      let target = CGSize(width: card.frame.width * minScale, height: card.frame.height * minScale)
      if r.width < target.width {
        r = CGRect(x: r.midX - target.width / 2, y: r.midY - target.height / 2, width: target.width, height: target.height)
      }
      rect = r
    }
    hideBoard()
    pins.pin(id, from: rect)
    onStateChange?()
  }

  func returnPin(_ id: UUID) {
    pins.unpin(id)
    onStateChange?()
  }

  /// Keeps pin windows in sync with board changes (content edits, deletes, returns).
  private func syncPins() {
    let pinned = Dictionary(uniqueKeysWithValues: store.cards.filter { $0.pin != nil }.map { ($0.id, $0) })
    for id in pins.pinnedIDs {
      guard let card = pinned[id] else {
        pins.refresh(id) // removes the window when the card was unpinned/deleted
        continue
      }
      if let old = lastPinnedSnapshot[id], Self.contentEqual(old, card) { continue }
      pins.refresh(id)
    }
    lastPinnedSnapshot = pinned
  }

  private static func contentEqual(_ a: BoardCard, _ b: BoardCard) -> Bool {
    var a = a, b = b
    a.pin = nil; b.pin = nil
    a.frame = b.frame; a.zIndex = b.zIndex; a.zoneID = b.zoneID; a.rotation = b.rotation
    a.updatedAt = b.updatedAt
    return a == b
  }

  // MARK: - Editor round-trip

  func openInEditor(_ id: UUID) {
    guard let card = store.card(id), let name = card.imageAsset else { return }
    hideBoard()
    openEditor?(store.assetURL(name))
  }

  private func handleEditorSave(_ url: URL) {
    guard url.deletingLastPathComponent().standardizedFileURL == store.assetsURL.standardizedFileURL,
          let id = store.cardID(forAssetURL: url) else { return }
    store.refreshThumbnail(for: id)
    store.update(id) { $0.ocrText = nil; $0.detectedItems = nil }
    enrichment.reindex(id)
    pins.refresh(id)
  }

  // MARK: - Quick add

  /// "Send to Board" for an existing SnipSnap capture (strip, editor, pinned image).
  func sendCaptureToBoard(_ captureURL: URL, renderedImage: Data? = nil) {
    let metadata = metadataStore.load(for: captureURL)
    let origin = overlay.isVisible
      ? viewModel.insertionPoint()
      : store.insertionOrigin(in: viewModel.visibleBoardRect.isEmpty ? CGRect(x: 0, y: 0, width: 1400, height: 900) : viewModel.visibleBoardRect)
    do {
      let card = try factory.captureCard(captureURL: captureURL, metadata: metadata, at: origin, renderedImage: renderedImage)
      let saved = store.add(card)
      enrichment.enrich(saved.id)
      announce("Added to Board", systemImage: "rectangle.stack.badge.plus", image: store.thumbnail(for: saved))
    } catch {
      os_log(.error, log: boardControllerLog, "Send to Board failed: %{public}@", error.localizedDescription)
      announce("Couldn’t add to Board", systemImage: "exclamationmark.triangle", image: nil)
    }
  }

  /// Turns whatever is on the clipboard into card(s), tagged with the frontmost app/tab.
  func clipboardToBoard() {
    Task { @MainActor in
      let source = await SourceContextProvider.snapshot(includeBrowserTab: prefs.captureBrowserContext)
      let origin = overlay.isVisible
        ? viewModel.insertionPoint()
        : store.insertionOrigin(in: viewModel.visibleBoardRect.isEmpty ? CGRect(x: 0, y: 0, width: 1400, height: 900) : viewModel.visibleBoardRect)
      let count = viewModel.addFromPasteboard(.general, atBoardPoint: origin, source: source)
      if count == 0 {
        announce("Clipboard is empty", systemImage: "clipboard", image: nil)
      } else {
        let first = viewModel.selection.first.flatMap { store.card($0) }
        let image = first.flatMap { store.thumbnail(for: $0) }
        announce(count == 1 ? "Clipboard added to Board" : "\(count) cards added to Board", systemImage: "doc.on.clipboard", image: image)
      }
    }
  }

  private func announce(_ message: String, systemImage: String, image: NSImage?) {
    if overlay.isVisible {
      viewModel.showToast(message, systemImage: systemImage)
    } else {
      hud.onClick = { [weak self] in self?.showBoard() }
      hud.show(message: message, systemImage: systemImage, image: image)
    }
  }

  // MARK: - Capture context

  /// Writes source app / browser tab into a capture's metadata sidecar (merging with existing data).
  func recordCaptureContext(_ context: SourceContext, for captureURL: URL) {
    guard context.appName != nil || context.pageURL != nil else { return }
    try? metadataStore.update(
      for: captureURL,
      default: { CaptureMetadata(createdAt: (try? captureURL.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? Date()) }
    ) { meta in
      meta.sourceAppName = context.appName
      meta.sourceBundleID = context.bundleID
      meta.sourceURL = context.pageURL
      meta.sourcePageTitle = context.pageTitle
    }
  }
}

extension Notification.Name {
  /// Post with `object` = capture file URL to add it to the Board (strip, editor, etc.).
  static let sendToBoard = Notification.Name("SnipSnap.sendToBoard")
  /// Optional `userInfo` key with PNG `Data` to use instead of reading the capture file.
  static let sendToBoardImageDataKey = "imageData"
}

// MARK: - HUD

/// Small transient confirmation shown near the bottom of the screen when the board is closed.
@MainActor
final class BoardHUD {
  private var panel: NSPanel?
  private var hideWork: DispatchWorkItem?
  var onClick: (() -> Void)?

  func show(message: String, systemImage: String, image: NSImage?) {
    hideWork?.cancel()
    let screen = BoardOverlayController.screenUnderMouse()
    let view = BoardHUDView(message: message, systemImage: systemImage, image: image) { [weak self] in
      self?.dismiss()
      self?.onClick?()
    }
    let hosting = NSHostingView(rootView: view)
    let size = hosting.fittingSize
    let frame = NSRect(
      x: screen.visibleFrame.midX - size.width / 2,
      y: screen.visibleFrame.minY + 80,
      width: size.width,
      height: size.height
    )
    let panel = self.panel ?? {
      let p = NSPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
      p.level = .statusBar
      p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
      p.isOpaque = false
      p.backgroundColor = .clear
      p.hasShadow = false
      p.hidesOnDeactivate = false
      p.isReleasedWhenClosed = false
      return p
    }()
    self.panel = panel
    panel.contentView = hosting
    panel.setFrame(frame, display: true)
    panel.alphaValue = 0
    panel.orderFrontRegardless()
    NSAnimationContext.runAnimationGroup { ctx in
      ctx.duration = 0.15
      panel.animator().alphaValue = 1
    }
    let work = DispatchWorkItem { [weak self] in self?.dismiss() }
    hideWork = work
    DispatchQueue.main.asyncAfter(deadline: .now() + 1.8, execute: work)
  }

  private func dismiss() {
    guard let panel else { return }
    NSAnimationContext.runAnimationGroup({ ctx in
      ctx.duration = 0.2
      panel.animator().alphaValue = 0
    }, completionHandler: {
      panel.orderOut(nil)
    })
  }
}

private struct BoardHUDView: View {
  let message: String
  let systemImage: String
  let image: NSImage?
  let onClick: () -> Void

  var body: some View {
    HStack(spacing: 12) {
      if let image {
        Image(nsImage: image)
          .resizable()
          .aspectRatio(contentMode: .fill)
          .frame(width: 44, height: 32)
          .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
      } else {
        Image(systemName: systemImage).font(.system(size: 16, weight: .semibold))
      }
      VStack(alignment: .leading, spacing: 1) {
        Text(message).font(.system(size: 13, weight: .semibold))
        Text("Click to open Board").font(.system(size: 11)).foregroundStyle(.secondary)
      }
    }
    .padding(.horizontal, 16)
    .padding(.vertical, 10)
    .background(.regularMaterial, in: Capsule())
    .overlay(Capsule().strokeBorder(.white.opacity(0.12)))
    .environment(\.colorScheme, .dark)
    .padding(16)
    .contentShape(Rectangle())
    .onTapGesture(perform: onClick)
  }
}
