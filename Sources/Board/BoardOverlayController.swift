import AppKit
import SwiftUI

/// Borderless non-activating panel that can still become key (so text fields and key
/// shortcuts work) without pulling the user's current app out of focus.
final class KeyablePanel: NSPanel {
  override var canBecomeKey: Bool { true }
  override var canBecomeMain: Bool { false }
}

/// Hosts the corkboard SwiftUI view and accepts drops from other apps.
private final class BoardContainerView: NSView {
  var onDrop: ((NSPasteboard, CGPoint) -> Bool)?
  private let highlight = CALayer()

  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    registerForDraggedTypes(CardFactory.acceptedTypes)
    wantsLayer = true
    highlight.borderColor = NSColor.controlAccentColor.cgColor
    highlight.borderWidth = 4
    highlight.cornerRadius = 0
    highlight.isHidden = true
    highlight.zPosition = 100
    layer?.addSublayer(highlight)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError() }

  override func layout() {
    super.layout()
    highlight.frame = bounds
  }

  override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
    highlight.isHidden = false
    return .copy
  }

  override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation { .copy }

  override func draggingExited(_ sender: NSDraggingInfo?) {
    highlight.isHidden = true
  }

  override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
    highlight.isHidden = true
    let local = convert(sender.draggingLocation, from: nil)
    // SwiftUI uses a top-left origin.
    let point = CGPoint(x: local.x, y: bounds.height - local.y)
    return onDrop?(sender.draggingPasteboard, point) ?? false
  }
}

/// Owns the full-screen board overlay window and its input handling.
@MainActor
final class BoardOverlayController {
  private let vm: BoardViewModel
  private var panel: KeyablePanel?
  private var monitors: [Any] = []
  private(set) var isVisible = false

  var onDidHide: (() -> Void)?

  init(vm: BoardViewModel) {
    self.vm = vm
  }

  func toggle() {
    isVisible ? hide() : show()
  }

  func show() {
    let screen = Self.screenUnderMouse()
    let panel = self.panel ?? makePanel()
    self.panel = panel
    panel.setFrame(screen.frame, display: false)
    vm.notch = BoardNotch(screen: screen)

    if !isVisible {
      // Recreate the root view so appear animations replay and state is fresh.
      installContent(in: panel)
      panel.alphaValue = 0
      panel.orderFrontRegardless()
      panel.makeKey()
      NSAnimationContext.runAnimationGroup { ctx in
        ctx.duration = 0.16
        panel.animator().alphaValue = 1
      }
      installMonitors()
      isVisible = true
    } else {
      panel.makeKey()
    }
  }

  func hide() {
    guard isVisible, let panel else { return }
    isVisible = false
    removeMonitors()
    vm.persistViewport()
    vm.editingCardID = nil
    vm.editingZoneID = nil
    vm.detailCardID = nil
    vm.store.saveNow()
    NSAnimationContext.runAnimationGroup({ ctx in
      ctx.duration = 0.14
      panel.animator().alphaValue = 0
    }, completionHandler: { [weak self] in
      Task { @MainActor in
        guard let self, !self.isVisible else { return }
        panel.orderOut(nil)
        self.onDidHide?()
      }
    })
  }

  /// Converts a board rect into global screen coordinates (AppKit, bottom-left origin).
  func screenRect(forBoardRect rect: CGRect) -> CGRect? {
    guard let panel, isVisible else { return nil }
    let view = vm.toView(rect)
    let frame = panel.frame
    return CGRect(x: frame.minX + view.minX, y: frame.maxY - view.maxY, width: view.width, height: view.height)
  }

  // MARK: - Setup

  private func makePanel() -> KeyablePanel {
    let panel = KeyablePanel(
      contentRect: .zero,
      styleMask: [.borderless, .nonactivatingPanel],
      backing: .buffered,
      defer: false
    )
    panel.level = .modalPanel
    panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
    panel.isOpaque = false
    panel.backgroundColor = .clear
    panel.hasShadow = false
    panel.hidesOnDeactivate = false
    panel.isReleasedWhenClosed = false
    panel.isMovable = false
    panel.acceptsMouseMovedEvents = true
    panel.animationBehavior = .none
    return panel
  }

  private func installContent(in panel: NSPanel) {
    let container = BoardContainerView(frame: NSRect(origin: .zero, size: panel.frame.size))
    container.autoresizingMask = [.width, .height]
    container.onDrop = { [weak self] pasteboard, point in
      guard let self else { return false }
      let added = self.vm.addFromPasteboard(pasteboard, atBoardPoint: self.vm.toBoard(point))
      return added > 0
    }
    let hosting = NSHostingView(rootView: BoardCanvasView(vm: vm))
    hosting.frame = container.bounds
    hosting.autoresizingMask = [.width, .height]
    container.addSubview(hosting)
    panel.contentView = container
  }

  // MARK: - Input

  private func installMonitors() {
    removeMonitors()
    if let key = NSEvent.addLocalMonitorForEvents(matching: .keyDown, handler: { [weak self] event in
      guard let self else { return event }
      return self.handleKey(event) ? nil : event
    }) { monitors.append(key) }

    if let scroll = NSEvent.addLocalMonitorForEvents(matching: [.scrollWheel, .magnify], handler: { [weak self] event in
      guard let self, event.window === self.panel, self.vm.detailCardID == nil else { return event }
      self.handleScroll(event)
      return nil
    }) { monitors.append(scroll) }
  }

  private func removeMonitors() {
    for monitor in monitors { NSEvent.removeMonitor(monitor) }
    monitors.removeAll()
  }

  private var isTextEditing: Bool {
    panel?.firstResponder is NSText
  }

  private var mouseViewPoint: CGPoint? {
    guard let panel else { return nil }
    let p = panel.mouseLocationOutsideOfEventStream
    return CGPoint(x: p.x, y: panel.frame.height - p.y)
  }

  private func handleKey(_ event: NSEvent) -> Bool {
    guard isVisible, event.window === panel else { return false }
    let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
    let chars = event.charactersIgnoringModifiers?.lowercased() ?? ""

    if event.keyCode == 53 { // Esc
      if vm.editingCardID != nil || vm.editingZoneID != nil {
        vm.editingCardID = nil
        vm.editingZoneID = nil
        panel?.makeFirstResponder(nil)
      } else if vm.detailCardID != nil {
        vm.detailCardID = nil
      } else if vm.isSearching {
        vm.searchQuery = ""
        panel?.makeFirstResponder(nil)
      } else if !vm.selection.isEmpty {
        vm.clearSelection()
      } else {
        hide()
      }
      return true
    }

    if isTextEditing { return false }

    if mods == .command {
      switch chars {
      case "v": vm.paste(viewPoint: mouseViewPoint); return true
      case "f": vm.searchFocusToken += 1; return true
      case "a": vm.selectAll(); return true
      case "c":
        if let id = vm.selection.first, vm.selection.count == 1 { vm.copy(id); return true }
        return false
      case "n": vm.addNote(at: mouseViewPoint.map(vm.toBoard)); return true
      case "0": withAnimationSafe { self.vm.resetZoom() }; return true
      case "=", "+": vm.zoom(by: 1.25, around: center); return true
      case "-": vm.zoom(by: 0.8, around: center); return true
      case "w": hide(); return true
      default: return false
      }
    }
    if mods == [.command, .shift], chars == "1" || chars == "!" {
      vm.zoomToFit(); return true
    }

    if mods.isEmpty || mods == .function {
      switch event.keyCode {
      case 51, 117: // Delete, Forward Delete
        vm.delete(vm.selection); return true
      case 36, 76: // Return
        if vm.selection.count == 1, let id = vm.selection.first { vm.open(id); return true }
      case 49: // Space → quick look style details
        if vm.selection.count == 1, let id = vm.selection.first {
          vm.detailCardID = vm.detailCardID == nil ? id : nil
          return true
        }
      default:
        break
      }
      if chars == "t", !vm.selection.isEmpty {
        let allTodo = vm.selection.allSatisfy { vm.store.card($0)?.todo != nil }
        vm.setTodo(vm.selection, enabled: !allTodo)
        return true
      }
      if chars == "p", vm.selection.count == 1, let id = vm.selection.first {
        vm.actions.popOut(id); return true
      }
    }
    return false
  }

  private var center: CGPoint { CGPoint(x: vm.canvasSize.width / 2, y: vm.canvasSize.height / 2) }

  private func withAnimationSafe(_ body: @escaping () -> Void) {
    withAnimation(.easeOut(duration: 0.2), body)
  }

  private func handleScroll(_ event: NSEvent) {
    guard let point = mouseViewPoint else { return }
    if event.type == .magnify {
      vm.zoom(by: 1 + event.magnification, around: point)
      return
    }
    if event.modifierFlags.contains(.command) {
      let delta = event.hasPreciseScrollingDeltas ? event.scrollingDeltaY : event.scrollingDeltaY * 8
      vm.zoom(by: 1 + delta / 300, around: point)
      return
    }
    let multiplier: CGFloat = event.hasPreciseScrollingDeltas ? 1 : 12
    vm.pan(by: CGSize(width: event.scrollingDeltaX * multiplier, height: event.scrollingDeltaY * multiplier))
  }

  static func screenUnderMouse() -> NSScreen {
    let mouse = NSEvent.mouseLocation
    return NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main ?? NSScreen.screens[0]
  }
}
