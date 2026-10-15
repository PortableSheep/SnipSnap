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
