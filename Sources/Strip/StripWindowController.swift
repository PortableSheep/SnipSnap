import AppKit
import Combine
import SwiftUI

@MainActor
final class StripWindowController: NSObject {
  private let expandedThickness: CGFloat = 112
  private let collapsedThickness: CGFloat = 76
  private let maxLength: CGFloat = 560
  private let margin: CGFloat = 18

  private var isHovered: Bool = false
  private var cancellables = Set<AnyCancellable>()

  let state: StripState
  let library: CaptureLibrary
  private let editor: EditorWindowController
  private let presentation: PresentationWindowController

  private let panel: NSPanel

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

    super.init()

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

    let root = StripView(library: library, state: state, license: LicenseManager.shared, onOpen: { [weak self] item in
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

    applyDock(position: state.dockPosition, animate: false)

    state.$dockPosition
      .removeDuplicates()
      .receive(on: DispatchQueue.main)
      .sink { [weak self] pos in
        self?.applyDock(position: pos, animate: true)
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

    // Only show on init if state says visible (after AppDelegate may have set it to false)
    if state.isVisible {
      show()
    }
  }

  var isVisible: Bool {
    panel.isVisible
  }

  func show() {
    if !state.isVisible {
      state.isVisible = true
    }
    panel.orderFrontRegardless()
  }

  func hide() {
    if state.isVisible {
      state.isVisible = false
    }
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

  private func applyDock(position: StripDockPosition, animate: Bool) {
    guard let screen = panel.screen ?? NSScreen.main else { return }
    let visible = screen.visibleFrame
    let full = screen.frame

    let thickness = isHovered ? expandedThickness : collapsedThickness

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

    // Keep the dock position but expand/collapse thickness smoothly.
    NSAnimationContext.runAnimationGroup { ctx in
      ctx.duration = 0.22
      applyDock(position: state.dockPosition, animate: true)
    }
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
    scheduleSnap()
  }

  func windowDidEndSheet(_ notification: Notification) {
    snapToEdgeIfNeeded()
  }

  func windowDidResignKey(_ notification: Notification) {
    // keep non-activating behavior
  }

}
