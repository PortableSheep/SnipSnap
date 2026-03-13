import AppKit
import Combine
import SwiftUI

@MainActor
final class StripWindowController: NSObject {
  private let expandedThickness: CGFloat = 112
  private let collapsedThickness: CGFloat = 76
  private let maxLength: CGFloat = 560
  private let margin: CGFloat = 18
  private let autoHideDelay: TimeInterval = 3.0

  private var isHovered: Bool = false
  private var cancellables = Set<AnyCancellable>()
  private var autoHideWorkItem: DispatchWorkItem?
  private var screenChangeWorkItem: DispatchWorkItem?

  let state: StripState
  let library: CaptureLibrary
  private let editor: EditorWindowController
  private let presentation: PresentationWindowController

  private let panel: NSPanel
  private let tabPanel: NSPanel

  init(state: StripState, library: CaptureLibrary, editor: EditorWindowController, presentation: PresentationWindowController) {
    self.state = state
    self.library = library
    self.editor = editor
    self.presentation = presentation

    // Session is scoped to this app run.
    self.state.startNewSession()

    let style: NSWindow.StyleMask = [.borderless, .nonactivatingPanel]
    let initialThickness = expandedThickness
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
    panel.contentView = NSHostingView(rootView: root)

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
    tabPanel.contentView = NSHostingView(rootView: tabView)

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
    NotificationCenter.default.addObserver(
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

  private func handleScreenParametersChanged() {
    // Debounce: macOS may fire the notification before screen geometry is fully settled.
    screenChangeWorkItem?.cancel()
    let work = DispatchWorkItem { [weak self] in
      guard let self, self.panel.isVisible || self.state.isAutoHidden else { return }
      self.applyDock(position: self.state.dockPosition, animate: false)
      if self.state.isAutoHidden {
        self.updateTabFrame()
      }
    }
    screenChangeWorkItem = work
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: work)
  }

  var isVisible: Bool {
    panel.isVisible
  }

  func show() {
    if !state.isVisible {
      state.isVisible = true
    }
    cancelAutoHide()
    hideTab()
    state.isAutoHidden = false
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
    hideTab()
    state.isAutoHidden = false
    panel.orderOut(nil)
  }

  func toggle() {
    if panel.isVisible {
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
    guard let screen = panel.screen ?? NSScreen.main else { return }
    let visible = screen.visibleFrame
    let full = screen.frame

    let thickness = expandedThickness

    // If the Dock occupies an edge, visibleFrame will be inset from full frame.
    // This lets us “avoid Dock” without relying on private APIs.
    let leftInset = max(0, visible.minX - full.minX)
    let rightInset = max(0, full.maxX - visible.maxX)

    let horizontalLength = max(260, min(maxLength, visible.width - margin * 2))
    let verticalLength = max(260, min(maxLength, visible.height - margin * 2))

    let target: NSRect
    switch position {
    case .left:
      let xBase = leftInset > 0.5 ? visible.minX : full.minX
      target = NSRect(
        x: xBase + margin,
        y: visible.midY - verticalLength / 2,
        width: thickness,
        height: verticalLength
      )
    case .right:
      let xBase = rightInset > 0.5 ? visible.maxX : full.maxX
      target = NSRect(
        x: xBase - thickness - margin,
        y: visible.midY - verticalLength / 2,
        width: thickness,
        height: verticalLength
      )
    case .top:
      target = NSRect(
        x: visible.midX - horizontalLength / 2,
        y: visible.maxY - thickness - margin,
        width: horizontalLength,
        height: thickness
      )
    case .bottom:
      target = NSRect(
        x: visible.midX - horizontalLength / 2,
        y: visible.minY + margin,
        width: horizontalLength,
        height: thickness
      )
    }

    if animate {
      panel.animator().setFrame(target, display: true)
    } else {
      panel.setFrame(target, display: true)
    }
  }

  private func setHovered(_ hovering: Bool) {
    guard hovering != isHovered else { return }
    isHovered = hovering

    guard state.autoHideEnabled else { return }
    if hovering {
      cancelAutoHide()
      if state.isAutoHidden {
        revealFromAutoHide(animate: true)
      }
    } else {
      scheduleAutoHide()
    }
  }

  // MARK: - Auto-Hide

  private func scheduleAutoHide() {
    cancelAutoHide()
    guard state.autoHideEnabled, !state.isAutoHidden else { return }
    let work = DispatchWorkItem { [weak self] in
      DispatchQueue.main.async { self?.performAutoHide() }
    }
    autoHideWorkItem = work
    DispatchQueue.main.asyncAfter(deadline: .now() + autoHideDelay, execute: work)
  }

  private func cancelAutoHide() {
    autoHideWorkItem?.cancel()
    autoHideWorkItem = nil
  }

  private func performAutoHide() {
    guard !state.isAutoHidden, state.autoHideEnabled, !isHovered else { return }
    state.isAutoHidden = true

    let hiddenFrame = computeHiddenFrame()
    NSAnimationContext.runAnimationGroup { ctx in
      ctx.duration = 0.3
      ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
      panel.animator().setFrame(hiddenFrame, display: true)
      panel.animator().alphaValue = 0
    } completionHandler: { [weak self] in
      self?.showTab()
    }
  }

  private func revealFromAutoHide(animate: Bool) {
    guard state.isAutoHidden else { return }
    state.isAutoHidden = false
    hideTab()
    panel.alphaValue = 1
    applyDock(position: state.dockPosition, animate: animate)
  }

  private func revealFromTab() {
    revealFromAutoHide(animate: true)
    // Re-arm timer in case mouse doesn't enter the strip content.
    scheduleAutoHide()
  }

  private func computeHiddenFrame() -> NSRect {
    var frame = panel.frame
    switch state.dockPosition {
    case .left:   frame.origin.x -= frame.width + margin
    case .right:  frame.origin.x += frame.width + margin
    case .top:    frame.origin.y += frame.height + margin
    case .bottom: frame.origin.y -= frame.height + margin
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
    guard let screen = panel.screen ?? NSScreen.main else { return }
    let visible = screen.visibleFrame
    let full = screen.frame
    let isVertical = state.dockPosition.isVertical
    let tabW: CGFloat = isVertical ? 14 : 44
    let tabH: CGFloat = isVertical ? 44 : 14

    let frame: NSRect
    switch state.dockPosition {
    case .left:
      frame = NSRect(x: full.minX, y: visible.midY - tabH / 2, width: tabW, height: tabH)
    case .right:
      frame = NSRect(x: full.maxX - tabW, y: visible.midY - tabH / 2, width: tabW, height: tabH)
    case .top:
      frame = NSRect(x: visible.midX - tabW / 2, y: visible.maxY - tabH, width: tabW, height: tabH)
    case .bottom:
      frame = NSRect(x: visible.midX - tabW / 2, y: visible.minY, width: tabW, height: tabH)
    }
    tabPanel.setFrame(frame, display: true)
  }

  private func snapToEdgeIfNeeded() {
    guard let screen = panel.screen ?? NSScreen.main else { return }
    let visible = screen.visibleFrame
    let full = screen.frame
    let f = panel.frame

    let threshold: CGFloat = 44

    // For left/right, prefer true screen edges so we can dock even if the macOS Dock is on that side.
    // For top/bottom, use visibleFrame to avoid fighting the menu bar area.
    let leftTargetX = full.minX + margin
    let rightTargetX = full.maxX - margin
    let bottomTargetY = visible.minY + margin
    let topTargetY = visible.maxY - margin

    let leftDist = abs(f.minX - leftTargetX)
    let rightDist = abs(f.maxX - rightTargetX)
    let bottomDist = abs(f.minY - bottomTargetY)
    let topDist = abs(f.maxY - topTargetY)

    let minDist = min(leftDist, rightDist, bottomDist, topDist)
    guard minDist <= threshold else { return }

    let position: StripDockPosition
    if minDist == leftDist {
      position = .left
    } else if minDist == rightDist {
      position = .right
    } else if minDist == topDist {
      position = .top
    } else {
      position = .bottom
    }

    state.dockPosition = position
    applyDock(position: position, animate: true)
  }

  private var snapWorkItem: DispatchWorkItem?
  private func scheduleSnap() {
    snapWorkItem?.cancel()
    let item = DispatchWorkItem { [weak self] in
      DispatchQueue.main.async {
        self?.snapToEdgeIfNeeded()
      }
    }
    snapWorkItem = item
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: item)
  }

}

extension StripWindowController: NSWindowDelegate {
  func windowDidEndLiveResize(_ notification: Notification) {
    snapToEdgeIfNeeded()
  }

  func windowDidMove(_ notification: Notification) {
    // If the strip is moving, treat mouse-up as a drag gesture, not a click.
    state.suppressItemOpens(for: 0.45)
    cancelAutoHide()
    scheduleSnap()
  }

  func windowDidEndSheet(_ notification: Notification) {
    snapToEdgeIfNeeded()
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
