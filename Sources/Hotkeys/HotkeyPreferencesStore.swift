import AppKit
import Carbon
import Combine
import Foundation

/// Actions that can be bound to global hotkeys
enum HotkeyAction: String, CaseIterable, Identifiable {
  case toggleRecording
  case toggleStrip
  case captureRegion
  case captureWindow

  var id: String { rawValue }

  var label: String {
    switch self {
    case .toggleRecording: return "Start/Stop Recording"
    case .toggleStrip: return "Show/Hide Strip"
    case .captureRegion: return "Capture Region"
    case .captureWindow: return "Capture Window"
    }
  }

  var icon: String {
    switch self {
    case .toggleRecording: return "record.circle"
    case .toggleStrip: return "rectangle.split.3x1"
    case .captureRegion: return "rectangle.dashed"
    case .captureWindow: return "macwindow"
    }
  }
}

/// A hotkey binding (key + modifiers)
struct HotkeyBinding: Codable, Equatable {
  var keyCode: UInt32
  var modifiers: UInt32

  /// Human-readable representation like "⌘⇧6"
  var displayString: String {
    var parts: [String] = []

    // Order: Control, Option, Shift, Command
    if modifiers & UInt32(controlKey) != 0 { parts.append("⌃") }
    if modifiers & UInt32(optionKey) != 0 { parts.append("⌥") }
    if modifiers & UInt32(shiftKey) != 0 { parts.append("⇧") }
    if modifiers & UInt32(cmdKey) != 0 { parts.append("⌘") }

    // Key name
    if let keyName = Self.keyName(for: keyCode) {
      parts.append(keyName)
    }

    return parts.joined()
  }

  static func keyName(for keyCode: UInt32) -> String? {
    switch Int(keyCode) {
    case kVK_ANSI_A: return "A"
    case kVK_ANSI_B: return "B"
    case kVK_ANSI_C: return "C"
    case kVK_ANSI_D: return "D"
    case kVK_ANSI_E: return "E"
    case kVK_ANSI_F: return "F"
    case kVK_ANSI_G: return "G"
    case kVK_ANSI_H: return "H"
    case kVK_ANSI_I: return "I"
    case kVK_ANSI_J: return "J"
    case kVK_ANSI_K: return "K"
    case kVK_ANSI_L: return "L"
    case kVK_ANSI_M: return "M"
    case kVK_ANSI_N: return "N"
    case kVK_ANSI_O: return "O"
    case kVK_ANSI_P: return "P"
    case kVK_ANSI_Q: return "Q"
    case kVK_ANSI_R: return "R"
    case kVK_ANSI_S: return "S"
    case kVK_ANSI_T: return "T"
    case kVK_ANSI_U: return "U"
    case kVK_ANSI_V: return "V"
    case kVK_ANSI_W: return "W"
    case kVK_ANSI_X: return "X"
    case kVK_ANSI_Y: return "Y"
    case kVK_ANSI_Z: return "Z"
    case kVK_ANSI_0: return "0"
    case kVK_ANSI_1: return "1"
    case kVK_ANSI_2: return "2"
    case kVK_ANSI_3: return "3"
    case kVK_ANSI_4: return "4"
    case kVK_ANSI_5: return "5"
    case kVK_ANSI_6: return "6"
    case kVK_ANSI_7: return "7"
    case kVK_ANSI_8: return "8"
    case kVK_ANSI_9: return "9"
    case kVK_Space: return "Space"
    case kVK_Return: return "↩"
    case kVK_Tab: return "⇥"
    case kVK_Delete: return "⌫"
    case kVK_Escape: return "⎋"
    case kVK_LeftArrow: return "←"
    case kVK_RightArrow: return "→"
    case kVK_UpArrow: return "↑"
    case kVK_DownArrow: return "↓"
    case kVK_F1: return "F1"
    case kVK_F2: return "F2"
    case kVK_F3: return "F3"
    case kVK_F4: return "F4"
    case kVK_F5: return "F5"
    case kVK_F6: return "F6"
    case kVK_F7: return "F7"
    case kVK_F8: return "F8"
    case kVK_F9: return "F9"
    case kVK_F10: return "F10"
    case kVK_F11: return "F11"
    case kVK_F12: return "F12"
    default: return nil
    }
  }

  /// Default bindings
  static let defaults: [HotkeyAction: HotkeyBinding] = [
    .toggleRecording: HotkeyBinding(keyCode: UInt32(kVK_ANSI_6), modifiers: UInt32(cmdKey | shiftKey)),
    .toggleStrip: HotkeyBinding(keyCode: UInt32(kVK_ANSI_S), modifiers: UInt32(cmdKey | shiftKey)),
    .captureRegion: HotkeyBinding(keyCode: UInt32(kVK_ANSI_5), modifiers: UInt32(cmdKey | shiftKey)),
    .captureWindow: HotkeyBinding(keyCode: UInt32(kVK_ANSI_4), modifiers: UInt32(cmdKey | shiftKey)),
  ]
}

/// Stores and persists hotkey preferences
final class HotkeyPreferencesStore: ObservableObject {
  static let shared = HotkeyPreferencesStore()

  @Published var bindings: [HotkeyAction: HotkeyBinding] {
    didSet { save() }
  }

  private let key = "HotkeyBindings"

  private init() {
    if let data = UserDefaults.standard.data(forKey: key),
       let decoded = try? JSONDecoder().decode([String: HotkeyBinding].self, from: data) {
      var loaded: [HotkeyAction: HotkeyBinding] = [:]
      for (rawValue, binding) in decoded {
        if let action = HotkeyAction(rawValue: rawValue) {
          loaded[action] = binding
        }
      }
      // Merge with defaults for any missing actions
      self.bindings = HotkeyBinding.defaults.merging(loaded) { _, new in new }
    } else {
      self.bindings = HotkeyBinding.defaults
    }
  }

  private func save() {
    let toEncode = Dictionary(uniqueKeysWithValues: bindings.map { ($0.key.rawValue, $0.value) })
    if let data = try? JSONEncoder().encode(toEncode) {
      UserDefaults.standard.set(data, forKey: key)
    }
  }

  func binding(for action: HotkeyAction) -> HotkeyBinding {
    bindings[action] ?? HotkeyBinding.defaults[action]!
  }

  func setBinding(_ binding: HotkeyBinding, for action: HotkeyAction) {
    bindings[action] = binding
  }

  func resetToDefaults() {
    bindings = HotkeyBinding.defaults
  }
}
