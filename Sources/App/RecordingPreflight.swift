import SwiftUI
import AppKit
import ObjectiveC

enum RecordingMode: String, CaseIterable, Identifiable, Codable {
  case fullscreen
  case window
  case region

  var id: String { rawValue }
  var label: String {
    switch self {
    case .fullscreen: return "Fullscreen"
    case .window: return "Window"
    case .region: return "Region"
    }
  }
}

struct RecordingPreflightResult {
  var mode: RecordingMode
  var showClicks: Bool
  var showKeys: Bool
  var showCursor: Bool
  var hudPlacement: HUDPlacement
  var ringColor: Color
}

private struct RecordingPreflightView: View {
  @Environment(\.dismiss) var dismiss

  @State var mode: RecordingMode
  @State var showClicks: Bool
  @State var showKeys: Bool
  @State var showCursor: Bool
  @State var hudPlacement: HUDPlacement
  @State var ringColor: Color

  let onDone: (RecordingPreflightResult?) -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      Picker("Capture", selection: $mode) {
        ForEach(RecordingMode.allCases) { m in
          Text(m.label).tag(m)
        }
      }
      .pickerStyle(.segmented)

      Toggle("Show clicks", isOn: $showClicks)
      Toggle("Show keystrokes", isOn: $showKeys)
      Toggle("Show cursor", isOn: $showCursor)

      HStack {
        Text("HUD placement")
        Spacer()
        Picker("HUD placement", selection: $hudPlacement) {
          ForEach(HUDPlacement.allCases, id: \.self) { p in
            Text(p.label).tag(p)
          }
        }
        .pickerStyle(.menu)
      }

      HStack {
        Text("Click color")
        Spacer()
        ColorPicker("", selection: $ringColor)
          .labelsHidden()
      }

      HStack {
        Spacer()
        Button("Cancel") { onDone(nil); dismiss() }
        Button("Start") {
          let res = RecordingPreflightResult(
            mode: mode,
            showClicks: showClicks,
            showKeys: showKeys,
            showCursor: showCursor,
            hudPlacement: hudPlacement,
            ringColor: ringColor
          )
          onDone(res)
          dismiss()
        }
        .keyboardShortcut(.defaultAction)
      }
    }
    .padding(16)
    .frame(width: 420)
  }
}

@MainActor
final class RecordingPreflightController {
  static func present(anchor: NSStatusBarButton?, prefDefaults: OverlayPreferencesStore) async -> RecordingPreflightResult? {
    await withCheckedContinuation { cont in
      var didResume = false
      let finish: (RecordingPreflightResult?) -> Void = { res in
        guard didResume == false else { return }
        didResume = true
        if let res { store(res) }
        cont.resume(returning: res)
      }

      var popoverRef: NSPopover?
      var windowRef: NSWindow?

      let view = RecordingPreflightView(
        mode: lastMode(),
        showClicks: prefDefaults.showClickOverlay,
        showKeys: prefDefaults.showKeystrokeHUD,
        showCursor: prefDefaults.showCursor,
        hudPlacement: prefDefaults.hudPlacement,
        ringColor: prefDefaults.clickColor,
        onDone: { res in
          popoverRef?.performClose(nil)
          windowRef?.close()
          finish(res)
        }
      )

      if let anchor {
        let popover = NSPopover()
        popover.behavior = .semitransient
        popover.contentSize = NSSize(width: 420, height: 360)
        let host = NSHostingController(rootView: view)
        popover.contentViewController = host
        popoverRef = popover

        // Resume continuation if the popover is dismissed by clicking elsewhere.
        final class PopDelegate: NSObject, NSPopoverDelegate {
          let onClose: () -> Void
          init(onClose: @escaping () -> Void) { self.onClose = onClose }
          func popoverDidClose(_ notification: Notification) { onClose() }
        }
        let delegate = PopDelegate { finish(nil) }
        popover.delegate = delegate
        objc_setAssociatedObject(popover, "delegate", delegate, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)

        popover.show(relativeTo: anchor.bounds, of: anchor, preferredEdge: .maxY)
        anchor.window?.makeKey()
        NSApp.activate(ignoringOtherApps: true)
      } else {
        let window = NSPanel(
          contentRect: NSRect(x: 0, y: 0, width: 420, height: 360),
          styleMask: [.titled, .closable, .utilityWindow],
          backing: .buffered,
          defer: false
        )
        windowRef = window
        window.title = "Recording Options"
        window.isFloatingPanel = true
        window.level = .floating
        window.center()

        let host = NSHostingController(rootView: view)
        window.contentViewController = host

        final class WindowDelegate: NSObject, NSWindowDelegate {
          let onClose: () -> Void
          init(onClose: @escaping () -> Void) { self.onClose = onClose }
          func windowWillClose(_ notification: Notification) { onClose() }
        }

        let delegate = WindowDelegate { finish(nil) }
        window.delegate = delegate
        objc_setAssociatedObject(window, "delegate", delegate, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)

        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
      }
    }
  }

  private static func lastMode() -> RecordingMode {
    let raw = UserDefaults.standard.string(forKey: "prefs.recording.mode")
    return RecordingMode(rawValue: raw ?? "fullscreen") ?? .fullscreen
  }

  private static func store(_ res: RecordingPreflightResult) {
    UserDefaults.standard.set(res.mode.rawValue, forKey: "prefs.recording.mode")
  }
}
