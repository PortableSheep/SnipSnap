import Foundation

struct ClickEvent: Sendable {
  let time: CFTimeInterval
  let x: CGFloat
  let y: CGFloat
}

struct KeyEvent: Sendable {
  let time: CFTimeInterval
  let text: String
  
  /// Returns a display-friendly version of the key
  var displayText: String {
    KeyEvent.displayName(for: text)
  }
  
  /// Map special characters to readable key names
  static func displayName(for text: String) -> String {
    // Check for special Unicode characters that represent keys
    switch text {
    // Backspace, Delete
    case "\u{7F}", "\u{08}":
      return "⌫"
    case "\u{7F7F}": // Forward delete
      return "⌦"
    // Return/Enter
    case "\r", "\n", "\u{03}":
      return "↵"
    // Tab
    case "\t":
      return "⇥"
    // Escape
    case "\u{1B}":
      return "⎋"
    // Space
    case " ":
      return "␣"
    // Arrow keys
    case "\u{F700}": // Up
      return "↑"
    case "\u{F701}": // Down
      return "↓"
    case "\u{F702}": // Left
      return "←"
    case "\u{F703}": // Right
      return "→"
    // Function keys
    case "\u{F704}":
      return "F1"
    case "\u{F705}":
      return "F2"
    case "\u{F706}":
      return "F3"
    case "\u{F707}":
      return "F4"
    case "\u{F708}":
      return "F5"
    case "\u{F709}":
      return "F6"
    case "\u{F70A}":
      return "F7"
    case "\u{F70B}":
      return "F8"
    case "\u{F70C}":
      return "F9"
    case "\u{F70D}":
      return "F10"
    case "\u{F70E}":
      return "F11"
    case "\u{F70F}":
      return "F12"
    // Home/End/Page
    case "\u{F729}":
      return "↖"
    case "\u{F72B}":
      return "↘"
    case "\u{F72C}":
      return "⇞"
    case "\u{F72D}":
      return "⇟"
    default:
      // For other control characters, show as symbols
      if let scalar = text.unicodeScalars.first, scalar.value < 32 {
        return "⌃\(Character(UnicodeScalar(scalar.value + 64)!))"
      }
      // Return uppercase for single letters
      if text.count == 1, text.first?.isLetter == true {
        return text.uppercased()
      }
      return text
    }
  }
}
