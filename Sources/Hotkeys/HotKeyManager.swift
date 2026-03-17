import AppKit
import Carbon
import Combine
import os.log

private let hotkeyLog = OSLog(subsystem: "com.snipsnap.Snipsnap", category: "Hotkeys")

final class HotKeyManager {
  private var eventHandler: EventHandlerRef?
  private var hotKeyRefs: [EventHotKeyRef?] = []
  var onAction: ((HotkeyAction) -> Void)?

  private var cancellables = Set<AnyCancellable>()

  func start() {
    stop()

    var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))

    let status = InstallEventHandler(
      GetApplicationEventTarget(),
      { (_, eventRef, userData) -> OSStatus in
        guard let eventRef else { return noErr }
        guard let userData else { return noErr }

        let manager = Unmanaged<HotKeyManager>.fromOpaque(userData).takeUnretainedValue()

        var hotKeyID = EventHotKeyID()
        let err = GetEventParameter(
          eventRef,
          EventParamName(kEventParamDirectObject),
          EventParamType(typeEventHotKeyID),
          nil,
          MemoryLayout<EventHotKeyID>.size,
          nil,
          &hotKeyID
        )
        if err != noErr { return noErr }

        // Map hotkey ID to action
        if let action = HotkeyAction.allCases.first(where: { $0.hotkeyID == hotKeyID.id }) {
          manager.onAction?(action)
        }

        return noErr
      },
      1,
      &spec,
      UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque()),
      &eventHandler
    )

    if status != noErr {
      os_log(.error, log: hotkeyLog, "Failed to install Carbon event handler (status %d)", status)
      return
    }
    os_log(.info, log: hotkeyLog, "Carbon event handler installed")

    // Register hotkeys from preferences
    registerAllHotkeys()

    // Listen for preference changes
    HotkeyPreferencesStore.shared.$bindings
      .dropFirst()
      .sink { [weak self] _ in
        self?.registerAllHotkeys()
      }
      .store(in: &cancellables)
  }

  private func registerAllHotkeys() {
    // Unregister existing
    for ref in hotKeyRefs {
      if let ref { UnregisterEventHotKey(ref) }
    }
    hotKeyRefs.removeAll()

    // Register from preferences
    var failed = Set<HotkeyAction>()
    let prefs = HotkeyPreferencesStore.shared
    for action in HotkeyAction.allCases {
      let binding = prefs.binding(for: action)
      if !registerHotKey(id: action.hotkeyID, keyCode: binding.keyCode, modifiers: binding.modifiers) {
        failed.insert(action)
      }
    }
    prefs.failedRegistrations = failed
  }

  func stop() {
    for ref in hotKeyRefs {
      if let ref { UnregisterEventHotKey(ref) }
    }
    hotKeyRefs.removeAll()
    cancellables.removeAll()

    if let handler = eventHandler {
      RemoveEventHandler(handler)
      eventHandler = nil
    }
  }

  /// Returns `true` if the hotkey was registered successfully.
  @discardableResult
  private func registerHotKey(id: UInt32, keyCode: UInt32, modifiers: UInt32) -> Bool {
    let hotKeyID = EventHotKeyID(signature: OSType(0x534E5053), id: id) // 'SNPS'
    var ref: EventHotKeyRef?
    let status = RegisterEventHotKey(keyCode, modifiers, hotKeyID, GetApplicationEventTarget(), 0, &ref)
    if status == noErr {
      hotKeyRefs.append(ref)
      os_log(.info, log: hotkeyLog, "Registered hotkey id=%d keyCode=%d modifiers=0x%x", id, keyCode, modifiers)
      return true
    } else {
      os_log(.error, log: hotkeyLog, "Failed to register hotkey id=%d keyCode=%d modifiers=0x%x (status %d)", id, keyCode, modifiers, status)
      return false
    }
  }

  deinit {
    stop()
  }
}

// MARK: - HotkeyAction extension for ID mapping

extension HotkeyAction {
  var hotkeyID: UInt32 {
    switch self {
    case .toggleRecording: return 1
    case .toggleStrip: return 2
    case .captureRegion: return 3
    case .captureWindow: return 4
    case .quickCapture: return 5
    }
  }
}

