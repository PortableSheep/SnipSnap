import AppKit
import SwiftUI
import Testing
@testable import SnipSnap

@Suite("Strip window controller", .serialized)
struct StripWindowControllerTests {
  @Test @MainActor
  func displayChangesAndAutoHideDoNotRedockOrLeaveInvisibleHoverTargets() async throws {
    let defaults = UserDefaults.standard
    let keys = ["strip.dockPosition", "strip.isVisible", "strip.autoHideEnabled", "strip.showOnStartup",
                "strip.verticalDockFraction", "strip.horizontalDockFraction"]
    let saved = keys.map { defaults.object(forKey: $0) }
    defer {
      for (key, value) in zip(keys, saved) {
        if let value { defaults.set(value, forKey: key) }
        else { defaults.removeObject(forKey: key) }
      }
    }
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    let state = StripState()
    state.isVisible = false
    state.autoHideEnabled = false
    state.dockPosition = .right
    state.verticalDockFraction = 0.5
    state.horizontalDockFraction = 0.5
    let previousWindows = Set(NSApplication.shared.windows.map(\.windowNumber))
    let controller = StripWindowController(
      state: state, library: CaptureLibrary(capturesDirURL: directory),
      editor: EditorWindowController(), presentation: PresentationWindowController(),
      pinnedImages: PinnedImageWindowController()
    )
    let panel = try #require(NSApp.windows.first { $0.delegate === controller })
    let tab = try #require(NSApp.windows.first { !previousWindows.contains($0.windowNumber) && $0 !== panel })
    defer {
      controller.hide()
      panel.close()
      tab.close()
    }
    let content = try #require(panel.contentView as? NSHostingView<StripView>)
    controller.show()
    try await Task.sleep(for: .milliseconds(400))
    let screen = try #require(panel.screen)

    // Simulate macOS relocating a window to the upper-right after a display disappears.
    panel.setFrameOrigin(CGPoint(x: screen.frame.maxX - panel.frame.width - StripLayout.margin,
                                 y: screen.visibleFrame.maxY - panel.frame.height - StripLayout.margin))
    controller.windowDidMove(Notification(name: NSWindow.didMoveNotification, object: panel))
    try await Task.sleep(for: .milliseconds(400))
    #expect(state.dockPosition == .right)
    #expect(state.suppressOpensUntil == nil)
    NotificationCenter.default.post(name: NSApplication.didChangeScreenParametersNotification, object: NSApp)
    try await Task.sleep(for: .milliseconds(500))
    #expect(panel.frame == StripLayout.dockedFrame(position: .right, visible: screen.visibleFrame))
    #expect(state.dockPosition == .right)

    // Exercise orientation changes so hosting constraints cannot leave a huge tab.
    for position: StripDockPosition in [.top, .left, .bottom, .right] {
      state.dockPosition = position
      try await Task.sleep(for: .milliseconds(500))
      #expect(panel.frame == StripLayout.dockedFrame(position: position, visible: screen.visibleFrame))
    }
    state.autoHideEnabled = true
    content.rootView.onHoverChanged(false)
    try await Task.sleep(for: .seconds(3.6))
    #expect(state.isAutoHidden)
    #expect(state.dockPosition == .right)
    #expect(panel.ignoresMouseEvents)
    #expect(!panel.isVisible)
    #expect(controller.isVisible)
    #expect(tab.isVisible)
    #expect(tab.frame == StripLayout.tabFrame(position: .right, screen: screen.frame, visible: screen.visibleFrame))
    content.rootView.onHoverChanged(true)
    #expect(state.isAutoHidden)

    for position: StripDockPosition in [.top, .left, .bottom, .right] {
      state.dockPosition = position
      try await Task.sleep(for: .milliseconds(300))
      #expect(state.isAutoHidden)
      #expect(!panel.isVisible)
      #expect(tab.frame == StripLayout.tabFrame(position: position, screen: screen.frame, visible: screen.visibleFrame))
    }

    NotificationCenter.default.post(name: NSApplication.didChangeScreenParametersNotification, object: NSApp)
    try await Task.sleep(for: .milliseconds(500))
    #expect(state.isAutoHidden)
    #expect(!panel.isVisible)
    #expect(state.dockPosition == .right)
    #expect(tab.frame.size == CGSize(width: 14, height: 44))

    controller.revealForCapture()
    try await Task.sleep(for: .milliseconds(500))
    #expect(!state.isAutoHidden)
    #expect(panel.isVisible)
    #expect(!panel.ignoresMouseEvents)
    #expect(!tab.isVisible)
    #expect(panel.frame == StripLayout.dockedFrame(position: .right, visible: screen.visibleFrame))

    // Revealing during the hide animation must invalidate its late completion.
    try await Task.sleep(for: .seconds(2.6))
    #expect(state.isAutoHidden)
    controller.revealForCapture()
    try await Task.sleep(for: .milliseconds(500))
    #expect(!state.isAutoHidden)
    #expect(panel.isVisible)
    #expect(panel.alphaValue == 1)
    #expect(!tab.isVisible)

    try await Task.sleep(for: .seconds(3.1))
    #expect(state.isAutoHidden)
    #expect(tab.isVisible)
    controller.toggle()
    #expect(!state.isVisible)
    #expect(!state.isAutoHidden)
    #expect(!panel.isVisible)
    #expect(!tab.isVisible)
    state.autoHideEnabled = false

    controller.toggle()
    #expect(state.isVisible)
    #expect(panel.isVisible)
    controller.toggle()
    #expect(!state.isVisible)
    #expect(!panel.isVisible)
  }
}
