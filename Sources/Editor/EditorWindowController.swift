import AppKit
import SwiftUI

@MainActor
final class EditorWindowController {
  private var windows: [URL: NSWindow] = [:]
  private var monitors: [URL: Any] = [:]
  private var delegates: [URL: NSWindowDelegate] = [:]

  func openEditor(for url: URL) {
    if let existing = windows[url] {
      AppActivation.bringToFront(existing)
      return
    }

    do {
      let doc = try AnnotationDocument(sourceURL: url)

      let view = EditorView(doc: doc) { [weak self] in
        self?.close(url: url)
      }

      let hosting = NSHostingView(rootView: view)

      let win = NSWindow(
        contentRect: NSRect(x: 0, y: 0, width: 1100, height: 760),
        styleMask: [.titled, .closable, .miniaturizable, .resizable],
        backing: .buffered,
        defer: false
      )
      win.title = url.lastPathComponent
      win.isReleasedWhenClosed = false
      win.contentView = hosting
      win.center()

      let delegate = EditorWindowDelegate(doc: doc) { [weak self] in
        self?.removeMonitor(for: url)
        self?.delegates[url] = nil
      }
      win.delegate = delegate
      delegates[url] = delegate

      NotificationCenter.default.addObserver(
        forName: NSWindow.willCloseNotification,
        object: win,
        queue: .main
      ) { [weak self] _ in
        Task { @MainActor in
          self?.windows[url] = nil
          self?.removeMonitor(for: url)
          self?.delegates[url] = nil
        }
      }

      // Local key handling: Cmd+Z, Shift+Cmd+Z, Delete, Escape, Tool shortcuts.
      let monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
        guard let self, let w = self.windows[url], NSApp.keyWindow === w else { return event }

        if event.modifierFlags.contains(.command) {
          // Cmd+Z / Shift+Cmd+Z
          if event.charactersIgnoringModifiers == "z" {
            if event.modifierFlags.contains(.shift) {
              doc.redo()
            } else {
              doc.undo()
            }
            return nil
          }
        }

        // Delete / Backspace
        if event.keyCode == 51 || event.keyCode == 117 {
          doc.deleteSelected()
          return nil
        }

        // Escape closes pending text input
        if event.keyCode == 53 {
          if doc.pendingTextInput != nil {
            doc.cancelPendingTextInput()
            return nil
          }
        }

        // Tool shortcuts (only when not editing text)
        if doc.pendingTextInput == nil, !event.modifierFlags.contains(.command) {
          if let char = event.charactersIgnoringModifiers?.lowercased() {
            let toolShortcuts: [String: AnnotationTool] = [
              "v": .select,
              "r": .rect,
              "l": .line,
              "a": .arrow,
              "m": .freehand,  // marker
              "t": .text,
              "c": .callout,
              "b": .blur,
              "s": .spotlight,
              "n": .step,     // numbered steps
              "#": .counter,  // manual number badge (shift+3)
              "e": .emoji,
              "d": .measurement  // dimension
            ]

            if let tool = toolShortcuts[char] {
              doc.tool = tool
              return nil
            }
          }
        }

        return event
      }
      monitors[url] = monitor

      windows[url] = win
      AppActivation.bringToFront(win)

    } catch {
      let alert = NSAlert(error: error)
      alert.runModal()
    }
  }

  private func close(url: URL) {
    if let w = windows[url] {
      w.performClose(nil)
    }
    windows[url] = nil
    removeMonitor(for: url)
    delegates[url] = nil
  }

  private func removeMonitor(for url: URL) {
    if let m = monitors[url] {
      NSEvent.removeMonitor(m)
    }
    monitors[url] = nil
  }
}

@MainActor
private final class EditorWindowDelegate: NSObject, NSWindowDelegate {
  private let doc: AnnotationDocument
  private let onWillClose: () -> Void

  init(doc: AnnotationDocument, onWillClose: @escaping () -> Void) {
    self.doc = doc
    self.onWillClose = onWillClose
  }

  func windowShouldClose(_ sender: NSWindow) -> Bool {
    guard doc.hasUnsavedChanges else { return true }

    let alert = NSAlert()
    alert.messageText = "Save changes?"
    alert.informativeText = "You have unsaved annotations. Export before closing?"
    alert.addButton(withTitle: "Save")
    alert.addButton(withTitle: "Don’t Save")
    alert.addButton(withTitle: "Cancel")
    alert.alertStyle = .warning

    let resp = alert.runModal()
    switch resp {
    case .alertFirstButtonReturn:
      do {
        _ = try EditorRenderer.exportPNGNextToSource(doc: doc)
        doc.markSaved()
        return true
      } catch {
        let err = NSAlert(error: error)
        err.runModal()
        return false
      }
    case .alertSecondButtonReturn:
      return true
    default:
      return false
    }
  }

  func windowWillClose(_ notification: Notification) {
    onWillClose()
  }
}
