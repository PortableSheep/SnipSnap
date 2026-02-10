import SwiftUI
import AppKit

enum CaptureMode: String, CaseIterable, Identifiable, Codable {
  case region
  case window
  case fullscreen
  case scrollingWindow

  var id: String { rawValue }
  var label: String {
    switch self {
    case .region: return "Region"
    case .window: return "Window"
    case .fullscreen: return "Full Screen"
    case .scrollingWindow: return "Scrolling Window"
    }
  }
}

enum CaptureDelay: Double, CaseIterable, Identifiable, Codable {
  case none = 0
  case three = 3
  case five = 5
  case ten = 10

  var id: Double { rawValue }
  var label: String {
    switch self {
    case .none: return "None"
    case .three: return "3 seconds"
    case .five: return "5 seconds"
    case .ten: return "10 seconds"
    }
  }
}

struct CapturePreflightResult {
  var mode: CaptureMode
  var delay: CaptureDelay
}

private struct CapturePreflightView: View {
  @State var mode: CaptureMode
  @State var delay: CaptureDelay

  let onDone: (CapturePreflightResult?) -> Void

  var body: some View {
    VStack(spacing: 0) {
      // Mode selection
      VStack(alignment: .leading, spacing: 12) {
        Text("Capture Mode")
          .font(.system(size: 12, weight: .medium))
          .foregroundColor(.primary)
        
        Picker("Capture Mode", selection: $mode) {
          ForEach(CaptureMode.allCases) { m in
            Text(m.label).tag(m)
          }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
      }
      .padding(.horizontal, 24)
      .padding(.top, 20)
      .padding(.bottom, 18)
      
      Divider()
      
      // Delay setting
      HStack(spacing: 16) {
        Text("Delay")
          .font(.system(size: 12, weight: .medium))
          .foregroundColor(.primary)
        
        Spacer()
        
        Picker("Delay", selection: $delay) {
          ForEach(CaptureDelay.allCases) { d in
            Text(d.label).tag(d)
          }
        }
        .pickerStyle(.menu)
        .labelsHidden()
        .frame(width: 130)
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
        
        Button("Capture") {
          let res = CapturePreflightResult(
            mode: mode,
            delay: delay
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
    .frame(width: 400)
    .background(Color(nsColor: .windowBackgroundColor))
  }
}

@MainActor
final class CapturePreflightController {
  static func presentAsMenu(completion: @escaping (CapturePreflightResult?) -> Void) -> NSMenu {
    let menu = NSMenu()
    menu.autoenablesItems = false
    
    let view = CapturePreflightView(
      mode: lastMode(),
      delay: lastDelay(),
      onDone: { res in
        if let res { store(res) }
        completion(res)
        // Close the menu
        menu.cancelTracking()
      }
    )
    
    let hostingView = NSHostingView(rootView: view)
    hostingView.frame = NSRect(x: 0, y: 0, width: 400, height: 200)
    
    let menuItem = NSMenuItem()
    menuItem.view = hostingView
    menu.addItem(menuItem)
    
    return menu
  }

  private static func lastMode() -> CaptureMode {
    let raw = UserDefaults.standard.string(forKey: "prefs.capture.mode")
    return CaptureMode(rawValue: raw ?? "region") ?? .region
  }

  private static func lastDelay() -> CaptureDelay {
    let value = UserDefaults.standard.double(forKey: "prefs.capture.delay")
    return CaptureDelay(rawValue: value) ?? .none
  }

  private static func store(_ res: CapturePreflightResult) {
    UserDefaults.standard.set(res.mode.rawValue, forKey: "prefs.capture.mode")
    UserDefaults.standard.set(res.delay.rawValue, forKey: "prefs.capture.delay")
  }
}

