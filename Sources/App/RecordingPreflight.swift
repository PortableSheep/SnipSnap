import SwiftUI
import AppKit

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
  @State var mode: RecordingMode
  @State var showClicks: Bool
  @State var showKeys: Bool
  @State var showCursor: Bool
  @State var hudPlacement: HUDPlacement
  @State var ringColor: Color

  let onDone: (RecordingPreflightResult?) -> Void

  var body: some View {
    VStack(spacing: 0) {
      // Mode selection
      VStack(alignment: .leading, spacing: 12) {
        Text("Recording Mode")
          .font(.system(size: 12, weight: .medium))
        
        Picker("Capture", selection: $mode) {
          ForEach(RecordingMode.allCases) { m in
            Text(m.label).tag(m)
          }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(.horizontal, 24)
      .padding(.top, 20)
      .padding(.bottom, 18)
      
      Divider()
      
      // Display options
      VStack(alignment: .leading, spacing: 14) {
        Text("Display Options")
          .font(.system(size: 12, weight: .medium))
        
        VStack(alignment: .leading, spacing: 10) {
          Toggle("Show mouse clicks", isOn: $showClicks)
          Toggle("Show keystrokes", isOn: $showKeys)
          Toggle("Show cursor", isOn: $showCursor)
        }
        .toggleStyle(.switch)
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(.horizontal, 24)
      .padding(.vertical, 18)
      
      Divider()
      
      // Advanced settings
      VStack(spacing: 14) {
        HStack(spacing: 16) {
          Text("HUD Position")
            .font(.system(size: 12, weight: .medium))
            .frame(width: 110, alignment: .leading)
          
          Picker("HUD placement", selection: $hudPlacement) {
            ForEach(HUDPlacement.allCases, id: \.self) { p in
              Text(p.label).tag(p)
            }
          }
          .pickerStyle(.menu)
          .labelsHidden()
          .frame(maxWidth: .infinity, alignment: .leading)
        }
        
        HStack(spacing: 16) {
          Text("Click Color")
            .font(.system(size: 12, weight: .medium))
            .frame(width: 110, alignment: .leading)
          
          ColorPicker("", selection: $ringColor, supportsOpacity: false)
            .labelsHidden()
            .frame(width: 60, alignment: .leading)
          
          Spacer()
        }
      }
      .padding(.horizontal, 24)
      .padding(.vertical, 18)
      
      Divider()
      
      // Action buttons
      HStack(spacing: 12) {
        Spacer()
        
        Button("Cancel") { 
          onDone(nil) 
        }
        .keyboardShortcut(.cancelAction)
        .buttonStyle(.borderless)
        
        Button("Start Recording") {
          let res = RecordingPreflightResult(
            mode: mode,
            showClicks: showClicks,
            showKeys: showKeys,
            showCursor: showCursor,
            hudPlacement: hudPlacement,
            ringColor: ringColor
          )
          onDone(res)
        }
        .keyboardShortcut(.defaultAction)
        .buttonStyle(.borderedProminent)
      }
      .padding(.horizontal, 24)
      .padding(.top, 18)
      .padding(.bottom, 22)
    }
    .frame(width: 450)
    .background(Color(nsColor: .windowBackgroundColor))
  }
}

@MainActor
final class RecordingPreflightController {
  static func presentAsMenu(prefDefaults: OverlayPreferencesStore, completion: @escaping (RecordingPreflightResult?) -> Void) -> NSMenu {
    let menu = NSMenu()
    menu.autoenablesItems = false
    
    let view = RecordingPreflightView(
      mode: lastMode(),
      showClicks: prefDefaults.showClickOverlay,
      showKeys: prefDefaults.showKeystrokeHUD,
      showCursor: prefDefaults.showCursor,
      hudPlacement: prefDefaults.hudPlacement,
      ringColor: prefDefaults.clickColor,
      onDone: { res in
        if let res { store(res) }
        completion(res)
        // Close the menu
        menu.cancelTracking()
      }
    )
    
    let hostingView = NSHostingView(rootView: view)
    hostingView.frame = NSRect(x: 0, y: 0, width: 450, height: 380)
    
    let menuItem = NSMenuItem()
    menuItem.view = hostingView
    menu.addItem(menuItem)
    
    return menu
  }

  private static func lastMode() -> RecordingMode {
    let raw = UserDefaults.standard.string(forKey: "prefs.recording.mode")
    return RecordingMode(rawValue: raw ?? "fullscreen") ?? .fullscreen
  }

  private static func store(_ res: RecordingPreflightResult) {
    UserDefaults.standard.set(res.mode.rawValue, forKey: "prefs.recording.mode")
  }
}
