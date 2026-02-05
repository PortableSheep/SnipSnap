import AppKit
import CoreGraphics
import Foundation

private func debugLog(_ message: String) {
  let logFile = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("snipsnap-debug.log")
  let timestamp = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
  let line = "[\(timestamp)] \(message)\n"
  if let data = line.data(using: .utf8) {
    if FileManager.default.fileExists(atPath: logFile.path) {
      if let fileHandle = try? FileHandle(forWritingTo: logFile) {
        fileHandle.seekToEndOfFile()
        fileHandle.write(data)
        fileHandle.closeFile()
      }
    } else {
      try? data.write(to: logFile)
    }
  }
}

// Accessed from background queues; mark as @unchecked Sendable so Swift concurrency
// warnings are suppressed (internal locking prevents races for the small state here).
final class OverlayEventTap: @unchecked Sendable {
  private let lock = NSLock()
  private var clickEvents: [ClickEvent] = []
  private var keyEvents: [KeyEvent] = []

  private var mouseTap: CFMachPort?
  private var keyTap: CFMachPort?

  private var mouseRunLoopSource: CFRunLoopSource?
  private var keyRunLoopSource: CFRunLoopSource?

  var isRunning: Bool {
    mouseTap != nil || keyTap != nil
  }

  func start(promptForAccessibility: Bool) {
    debugLog("OverlayEventTap.start called, promptForAccessibility=\(promptForAccessibility)")
    
    // Event taps require Accessibility permissions in practice for global events.
    let hasAX = AccessibilityPermission.isTrusted(prompt: promptForAccessibility)
    debugLog("OverlayEventTap: AccessibilityPermission.isTrusted = \(hasAX)")
    if !hasAX {
      debugLog("OverlayEventTap: No accessibility permission, cannot start")
      return
    }

    // On newer macOS versions, global event monitoring is additionally gated by Input Monitoring.
    let hasInput = InputMonitoringPermission.hasAccess(prompt: promptForAccessibility)
    debugLog("OverlayEventTap: InputMonitoringPermission.hasAccess = \(hasInput)")
    if !hasInput {
      debugLog("OverlayEventTap: No input monitoring permission, cannot start")
      return
    }

    startMouseTap()
    startKeyTap()
    debugLog("OverlayEventTap: Started mouse and key taps, isRunning=\(isRunning)")
  }

  func stop() {
    stopMouseTap()
    stopKeyTap()
    lock.lock()
    clickEvents.removeAll(keepingCapacity: false)
    keyEvents.removeAll(keepingCapacity: false)
    lock.unlock()
  }

  func recordClick(x: CGFloat, y: CGFloat, time: CFTimeInterval) {
    lock.lock()
    clickEvents.append(ClickEvent(time: time, x: x, y: y))
    if clickEvents.count > 200 { clickEvents.removeFirst(clickEvents.count - 200) }
    lock.unlock()
  }

  func recordKey(text: String, time: CFTimeInterval) {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return }
    lock.lock()
    keyEvents.append(KeyEvent(time: time, text: trimmed))
    if keyEvents.count > 200 { keyEvents.removeFirst(keyEvents.count - 200) }
    lock.unlock()
  }

  func recentClicks(since time: CFTimeInterval) -> [ClickEvent] {
    lock.lock()
    let res = clickEvents.filter { $0.time >= time }
    lock.unlock()
    return res
  }

  func recentKeys(since time: CFTimeInterval) -> [KeyEvent] {
    lock.lock()
    let res = keyEvents.filter { $0.time >= time }
    lock.unlock()
    return res
  }

  // MARK: - Mouse tap

  private func startMouseTap() {
    stopMouseTap()

    let mask = (1 << CGEventType.leftMouseDown.rawValue)
      | (1 << CGEventType.rightMouseDown.rawValue)
      | (1 << CGEventType.otherMouseDown.rawValue)

    let callback: CGEventTapCallBack = { proxy, type, event, userInfo in
      guard let userInfo else { return Unmanaged.passUnretained(event) }
      let me = Unmanaged<OverlayEventTap>.fromOpaque(userInfo).takeUnretainedValue()

      if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
        if let tap = me.mouseTap {
          CGEvent.tapEnable(tap: tap, enable: true)
        }
        return Unmanaged.passUnretained(event)
      }

      let loc = event.location
      me.recordClick(x: loc.x, y: loc.y, time: CACurrentMediaTime())
      return Unmanaged.passUnretained(event)
    }

    guard let tap = CGEvent.tapCreate(
      tap: .cgSessionEventTap,
      place: .headInsertEventTap,
      options: .defaultTap,
      eventsOfInterest: CGEventMask(mask),
      callback: callback,
      userInfo: UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
    ) else {
      debugLog("OverlayEventTap: FAILED to create mouse tap - CGEvent.tapCreate returned nil")
      return
    }

    debugLog("OverlayEventTap: Successfully created mouse tap")
    mouseTap = tap
    let src = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
    mouseRunLoopSource = src
    CFRunLoopAddSource(CFRunLoopGetMain(), src, .commonModes)
    CGEvent.tapEnable(tap: tap, enable: true)
  }

  private func stopMouseTap() {
    if let src = mouseRunLoopSource {
      CFRunLoopRemoveSource(CFRunLoopGetMain(), src, .commonModes)
    }
    mouseRunLoopSource = nil
    mouseTap = nil
  }

  // MARK: - Key tap

  private func startKeyTap() {
    stopKeyTap()

    let mask = (1 << CGEventType.keyDown.rawValue)

    let callback: CGEventTapCallBack = { proxy, type, event, userInfo in
      guard let userInfo else { return Unmanaged.passUnretained(event) }
      let me = Unmanaged<OverlayEventTap>.fromOpaque(userInfo).takeUnretainedValue()

      if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
        if let tap = me.keyTap {
          CGEvent.tapEnable(tap: tap, enable: true)
        }
        return Unmanaged.passUnretained(event)
      }

      var length: Int = 0
      event.keyboardGetUnicodeString(maxStringLength: 8, actualStringLength: &length, unicodeString: nil)
      var buffer = [UniChar](repeating: 0, count: max(1, length))
      event.keyboardGetUnicodeString(maxStringLength: 8, actualStringLength: &length, unicodeString: &buffer)

      let s = String(utf16CodeUnits: buffer, count: length)
      me.recordKey(text: s, time: CACurrentMediaTime())

      return Unmanaged.passUnretained(event)
    }

    guard let tap = CGEvent.tapCreate(
      tap: .cgSessionEventTap,
      place: .headInsertEventTap,
      options: .defaultTap,
      eventsOfInterest: CGEventMask(mask),
      callback: callback,
      userInfo: UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
    ) else {
      debugLog("OverlayEventTap: FAILED to create key tap - CGEvent.tapCreate returned nil")
      return
    }

    debugLog("OverlayEventTap: Successfully created key tap")
    keyTap = tap
    let src = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
    keyRunLoopSource = src
    CFRunLoopAddSource(CFRunLoopGetMain(), src, .commonModes)
    CGEvent.tapEnable(tap: tap, enable: true)
  }

  private func stopKeyTap() {
    if let src = keyRunLoopSource {
      CFRunLoopRemoveSource(CFRunLoopGetMain(), src, .commonModes)
    }
    keyRunLoopSource = nil
    keyTap = nil
  }
}
