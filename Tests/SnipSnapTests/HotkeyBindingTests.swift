import Carbon
import Testing
@testable import SnipSnap

@Suite("Hotkey bindings")
struct HotkeyBindingTests {
  @Test("Remapped binding resolves from the emitted bindings, not the default")
  func resolvesRemappedBinding() {
    let remapped = HotkeyBinding(keyCode: UInt32(kVK_ANSI_K), modifiers: UInt32(cmdKey | optionKey))
    var bindings = HotkeyBinding.defaults
    bindings[.toggleBoard] = remapped

    #expect(HotkeyBinding.resolved(for: .toggleBoard, in: bindings) == remapped)
    #expect(HotkeyBinding.resolved(for: .toggleBoard, in: bindings) != HotkeyBinding.defaults[.toggleBoard])
  }

  @Test("Missing bindings fall back to defaults")
  func fallsBackToDefault() {
    #expect(HotkeyBinding.resolved(for: .toggleBoard, in: [:]) == HotkeyBinding.defaults[.toggleBoard])
  }
}

@Suite("Hotkey conflicts")
struct HotkeyConflictTests {
  @Test("macOS screenshot and Spotlight shortcuts are flagged")
  func reservedSystemShortcuts() {
    let screenshot = HotkeyBinding(keyCode: UInt32(kVK_ANSI_4), modifiers: UInt32(cmdKey | shiftKey))
    let spotlight = HotkeyBinding(keyCode: UInt32(kVK_Space), modifiers: UInt32(cmdKey))
    #expect(screenshot.reservedShortcutName != nil)
    #expect(spotlight.reservedShortcutName == "Spotlight")
  }

  @Test("Command plus a single key is flagged as a standard app command")
  func commandOnlyIsReserved() {
    let copy = HotkeyBinding(keyCode: UInt32(kVK_ANSI_C), modifiers: UInt32(cmdKey))
    #expect(copy.reservedShortcutName?.contains("⌘C") == true)
  }

  @Test("SnipSnap defaults do not collide with reserved shortcuts or each other")
  func defaultsAreClean() {
    for (action, binding) in HotkeyBinding.defaults {
      #expect(binding.reservedShortcutName == nil, "\(action) uses a reserved shortcut")
      #expect(binding.isDisplayable)
    }
    #expect(Set(HotkeyBinding.defaults.values).count == HotkeyBinding.defaults.count)
  }

  @Test("Keys without a display name are not accepted")
  func undisplayableKey() {
    #expect(!HotkeyBinding(keyCode: UInt32(kVK_CapsLock), modifiers: UInt32(cmdKey)).isDisplayable)
  }
}
