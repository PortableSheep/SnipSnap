import AppKit
import Combine
import SwiftUI

@MainActor
final class StripWindowController: NSObject {
  private let autoHideDelay: TimeInterval = 3.0

  private var isHovered: Bool = false
  private var isUserDragging = false
  private var isApplyingFrame = false
  private var dockedScreenID: NSNumber?
  private var dockedFrame: NSRect = .zero
  private var hideAnimationGeneration = 0
  private var cancellables = Set<AnyCancellable>()
  private var autoHideWorkItem: DispatchWorkItem?
  private var screenChangeWorkItem: DispatchWorkItem?
  private var screenObserver: NSObjectProtocol?

  let state: StripState
  let library: CaptureLibrary
  private let editor: EditorWindowController
  private let presentation: PresentationWindowController
  private let pinnedImages: PinnedImageWindowController

  private let panel: NSPanel
  private let tabPanel: NSPanel

  init(state: StripState, library: CaptureLibrary, editor: EditorWindowController, presentation: PresentationWindowController, pinnedImages: PinnedImageWindowController) {
    self.state = state
    self.library = library
    self.editor = editor
    self.presentation = presentation
    self.pinnedImages = pinnedImages

    // Session is scoped to this app run.
    self.state.startNewSession()

    let style: NSWindow.StyleMask = [.borderless, .nonactivatingPanel]
    let initialThickness = StripLayout.thickness
    panel = NSPanel(
      contentRect: .init(x: 0, y: 0, width: initialThickness, height: initialThickness),
      styleMask: style,
      backing: .buffered,
      defer: false
    )

    // Auto-hide tab: small panel that peeks from the edge when strip is hidden.
    tabPanel = NSPanel(
      contentRect: .init(x: 0, y: 0, width: 44, height: 44),
      styleMask: [.borderless, .nonactivatingPanel],
      backing: .buffered,
      defer: false
    )

    super.init()

    // --- Main panel setup ---
    panel.isFloatingPanel = true
    panel.level = .floating
    panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
    panel.isMovableByWindowBackground = true
    panel.titleVisibility = .hidden
    panel.titlebarAppearsTransparent = true
    panel.hasShadow = true
    panel.backgroundColor = .clear
    panel.isOpaque = false
    panel.acceptsMouseMovedEvents = true

    panel.delegate = self

    let root = StripView(library: library, state: state, onOpen: { [weak self] item in
      guard let self else { return }
      switch item.kind {
      case .image:
        self.editor.openEditor(for: item.url)
      case .video:
        self.library.open(item)
      }
    }, onPin: { [weak self] item in
      self?.pinnedImages.pin(url: item.url)
    }, onPresent: { [weak self] item in
      guard let self else { return }
      // Present from this item onwards (items from this point to the end)
      if let index = self.library.items.firstIndex(where: { $0.id == item.id }) {
        let itemsFromHere = Array(self.library.items[index...])
        let title = "From '\(item.url.deletingPathExtension().lastPathComponent)'"
        self.presentation.show(items: itemsFromHere, library: self.library, title: title)
      }
    }, onHoverChanged: { [weak self] hovering in
      self?.setHovered(hovering)
    })
    let stripHostingView = NSHostingView(rootView: root)
    stripHostingView.sizingOptions = []
    panel.contentView = stripHostingView

    // --- Tab panel setup ---
    tabPanel.isFloatingPanel = true
    tabPanel.level = .floating
    tabPanel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
    tabPanel.isMovableByWindowBackground = false
    tabPanel.titleVisibility = .hidden
    tabPanel.titlebarAppearsTransparent = true
    tabPanel.hasShadow = false
    tabPanel.backgroundColor = .clear
    tabPanel.isOpaque = false
    tabPanel.acceptsMouseMovedEvents = true
    tabPanel.ignoresMouseEvents = false

    let tabView = AutoHideTabView(state: state) { [weak self] in
      self?.revealFromTab()
    }
    let tabHostingView = NSHostingView(rootView: tabView)
    tabHostingView.sizingOptions = []
    tabPanel.contentView = tabHostingView

    // --- Initial layout ---
    applyDock(position: state.dockPosition, animate: false)

    state.$dockPosition
      .removeDuplicates()
      .receive(on: DispatchQueue.main)
      .sink { [weak self] pos in
        guard let self else { return }
        self.applyDock(position: pos, animate: true)
        if self.state.isAutoHidden {
          self.updateTabFrame()
        }
      }
      .store(in: &cancellables)
    
    // Observe visibility changes (dropFirst to skip initial value - we handle that below)
    state.$isVisible
      .dropFirst()
      .removeDuplicates()
      .receive(on: DispatchQueue.main)
      .sink { [weak self] visible in
        if visible {
          self?.show()
        } else {
          self?.hide()
        }
      }
      .store(in: &cancellables)

    // When auto-hide is toggled off, reveal immediately.
    state.$autoHideEnabled
      .dropFirst()
      .removeDuplicates()
      .receive(on: DispatchQueue.main)
      .sink { [weak self] enabled in
        guard let self else { return }
        if !enabled {
          self.cancelAutoHide()
          if self.state.isAutoHidden {
            self.revealFromAutoHide(animate: true)
          }
        } else if !self.isHovered {
          self.scheduleAutoHide()
        }
      }
      .store(in: &cancellables)

    // Re-dock the strip when the display configuration changes (e.g. external monitor disconnect).
    screenObserver = NotificationCenter.default.addObserver(
      forName: NSApplication.didChangeScreenParametersNotification,
      object: NSApplication.shared,
      queue: .main
    ) { [weak self] _ in
      self?.handleScreenParametersChanged()
    }

    // Only show on init if state says visible (after AppDelegate may have set it to false)
    if state.isVisible {
      show()
    }
  }

  deinit {
    autoHideWorkItem?.cancel()
    screenChangeWorkItem?.cancel()
    snapWorkItem?.cancel()
    if let screenObserver {
      NotificationCenter.default.removeObserver(screenObserver)
    }
  }

  private func handleScreenParametersChanged() {
    isUserDragging = false
    snapWorkItem?.cancel()
    cancelAutoHide()
    // Debounce: macOS may fire the notification before screen geometry is fully settled.
    screenChangeWorkItem?.cancel()
    let work = DispatchWorkItem { [weak self] in
      guard let self, self.panel.isVisible || self.state.isAutoHidden else { return }
      self.applyDock(position: self.state.dockPosition, animate: false)
      if self.state.isAutoHidden {
        self.updateTabFrame()
      } else if !self.isHovered {
        self.scheduleAutoHide()
      }
    }
    screenChangeWorkItem = work
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: work)
  }

  var isVisible: Bool {
    state.isVisible
  }

  func show() {
    if !state.isVisible {
      state.isVisible = true
    }
    cancelAutoHide()
    snapWorkItem?.cancel()
    isUserDragging = false
    hideTab()
    hideAnimationGeneration += 1
    state.isAutoHidden = false
    panel.ignoresMouseEvents = false
    panel.alphaValue = 1
    panel.orderFrontRegardless()
    applyDock(position: state.dockPosition, animate: false)

    if state.autoHideEnabled && !isHovered {
      scheduleAutoHide()
    }
  }

  func hide() {
    if state.isVisible {
      state.isVisible = false
    }
    cancelAutoHide()
    snapWorkItem?.cancel()
    isUserDragging = false
    hideAnimationGeneration += 1
    hideTab()
    isHovered = false
    state.isAutoHidden = false
    panel.orderOut(nil)
  }

  func toggle() {
    if state.isVisible {
      hide()
    } else {
      show()
    }
  }

  func refresh() {
    library.refresh()
  }

  /// Briefly reveals the strip (e.g. after a new capture) then re-arms auto-hide.
  func revealForCapture() {
    guard state.isVisible else { return }
    if state.isAutoHidden {
      revealFromAutoHide(animate: true)
    }
    // Re-arm so it slides away after the timeout.
    if state.autoHideEnabled {
      scheduleAutoHide()
    }
  }

  private func applyDock(position: StripDockPosition, animate: Bool) {
    guard let screen = dockedScreen else { return }
    dockedScreenID = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber
    dockedFrame = StripLayout.dockedFrame(position: position, visible: screen.visibleFrame)
    setPanelFrame(state.isAutoHidden ? computeHiddenFrame() : dockedFrame,
                  animate: animate && !state.isAutoHidden)
  }

  private var dockedScreen: NSScreen? {
    // A hidden panel can report a neighboring or disconnected display.
    NSScreen.screens.first {
      ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber) == dockedScreenID
    } ?? NSScreen.main ?? NSScreen.screens.first
  }

  private func setPanelFrame(_ frame: NSRect, animate: Bool) {
    isApplyingFrame = true
    defer { isApplyingFrame = false }
    if animate {
      panel.animator().setFrame(frame, display: true)
    } else {
      panel.setFrame(frame, display: true)
    }
  }

  private func setHovered(_ hovering: Bool) {
    guard !state.isAutoHidden, state.isVisible else { return }
    guard hovering != isHovered else { return }
    isHovered = hovering

    guard state.autoHideEnabled else { return }
    if hovering {
      cancelAutoHide()
    } else {
      scheduleAutoHide()
    }
  }

  // MARK: - Auto-Hide

  private func scheduleAutoHide() {
    cancelAutoHide()
    guard state.isVisible, state.autoHideEnabled, !state.isAutoHidden, !isUserDragging else { return }
    let work = DispatchWorkItem { [weak self] in
      self?.performAutoHide()
    }
    autoHideWorkItem = work
    DispatchQueue.main.asyncAfter(deadline: .now() + autoHideDelay, execute: work)
  }

  private func cancelAutoHide() {
    autoHideWorkItem?.cancel()
    autoHideWorkItem = nil
  }

  private func performAutoHide() {
    guard state.isVisible, !state.isAutoHidden, state.autoHideEnabled, !isHovered, !isUserDragging else { return }
    state.isAutoHidden = true
    panel.ignoresMouseEvents = true
    hideAnimationGeneration += 1
    let generation = hideAnimationGeneration

    let hiddenFrame = computeHiddenFrame()
    NSAnimationContext.runAnimationGroup { ctx in
      ctx.duration = 0.3
      ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
      setPanelFrame(hiddenFrame, animate: true)
      panel.animator().alphaValue = 0
    } completionHandler: { [weak self] in
      guard let self, self.hideAnimationGeneration == generation,
            self.state.isVisible, self.state.isAutoHidden else { return }
      self.panel.orderOut(nil)
      self.showTab()
    }
  }

  private func revealFromAutoHide(animate: Bool) {
    guard state.isAutoHidden else { return }
    hideAnimationGeneration += 1
    state.isAutoHidden = false
    hideTab()
    panel.ignoresMouseEvents = false
    panel.alphaValue = 1
    applyDock(position: state.dockPosition, animate: animate)
    panel.orderFrontRegardless()
  }

  private func revealFromTab() {
    revealFromAutoHide(animate: true)
    // Re-arm timer in case mouse doesn't enter the strip content.
    scheduleAutoHide()
  }

  private func computeHiddenFrame() -> NSRect {
    var frame = dockedFrame
    switch state.dockPosition {
    case .left:   frame.origin.x -= frame.width + StripLayout.margin
    case .right:  frame.origin.x += frame.width + StripLayout.margin
    case .top:    frame.origin.y += frame.height + StripLayout.margin
    case .bottom: frame.origin.y -= frame.height + StripLayout.margin
    }
    return frame
  }

  // MARK: - Tab

  private func showTab() {
    guard state.isVisible, state.isAutoHidden else { return }
    updateTabFrame()
    tabPanel.orderFrontRegardless()
  }

  private func hideTab() {
    tabPanel.orderOut(nil)
  }

  private func updateTabFrame() {
    guard let screen = dockedScreen else { return }
    let frame = StripLayout.tabFrame(position: state.dockPosition, screen: screen.frame, visible: screen.visibleFrame)
    tabPanel.setFrame(frame, display: true)
  }

  private func snapToEdgeIfNeeded() {
    guard isUserDragging else { return }
    isUserDragging = false
    defer {
      if !isHovered { scheduleAutoHide() }
    }
    guard let screen = panel.screen ?? NSScreen.main else { return }
    dockedScreenID = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber
    dockedFrame = panel.frame
    guard let position = StripLayout.nearestEdge(frame: panel.frame, screen: screen.frame,
                                                 visible: screen.visibleFrame) else { return }

    state.dockPosition = position
    applyDock(position: position, animate: true)
  }

  private var snapWorkItem: DispatchWorkItem?
  private func scheduleSnap() {
    snapWorkItem?.cancel()
    let item = DispatchWorkItem { [weak self] in
      guard let self, self.isUserDragging else { return }
      if NSEvent.pressedMouseButtons & 1 != 0 {
        self.scheduleSnap()
      } else {
        self.snapToEdgeIfNeeded()
      }
    }
    snapWorkItem = item
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: item)
  }

}

extension StripWindowController: NSWindowDelegate {
  func windowWillMove(_ notification: Notification) {
    guard !isApplyingFrame, !state.isAutoHidden, state.isVisible,
          NSEvent.pressedMouseButtons & 1 != 0,
          let event = NSApp.currentEvent,
          event.window === panel,
          event.type == .leftMouseDown || event.type == .leftMouseDragged else { return }
    isUserDragging = true
    cancelAutoHide()
    scheduleSnap()
  }

  func windowDidMove(_ notification: Notification) {
    guard isUserDragging, !isApplyingFrame else { return }
    // If the strip is moving, treat mouse-up as a drag gesture, not a click.
    state.suppressItemOpens(for: 0.45)
    cancelAutoHide()
    scheduleSnap()
  }

  func windowDidResignKey(_ notification: Notification) {
    // keep non-activating behavior
  }

}

// MARK: - Auto-Hide Tab View

private struct AutoHideTabView: View {
  @ObservedObject var state: StripState
  let onHoverIn: () -> Void
  @State private var isHovered = false

  var body: some View {
    let isVertical = state.dockPosition.isVertical

    Capsule()
      .fill(Color.primary.opacity(isHovered ? 0.35 : 0.18))
      .frame(
        width: isVertical ? 5 : 32,
        height: isVertical ? 32 : 5
      )
      .frame(
        width: isVertical ? 14 : 44,
        height: isVertical ? 44 : 14
      )
      .contentShape(Rectangle())
      .onHover { hovering in
        withAnimation(.easeInOut(duration: 0.15)) {
          isHovered = hovering
        }
        if hovering {
          onHoverIn()
        }
      }
  }
}
