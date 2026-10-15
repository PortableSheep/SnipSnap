import Carbon
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
        contentRect: NSRect(origin: .zero, size: Self.initialContentSize(for: doc.imageSize)),
        styleMask: [.titled, .closable, .miniaturizable, .resizable],
        backing: .buffered,
        defer: false
      )
      win.title = url.lastPathComponent
      win.isReleasedWhenClosed = false
      win.contentView = hosting
      win.center()
      // Remember the user's preferred editor size/position across sessions.
      win.setFrameAutosaveName(Self.frameAutosaveName)

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
          // Hide from app switcher when last editor window closes
          if self?.windows.isEmpty == true {
            AppActivation.hideFromAppSwitcher()
          }
        }
      }

      // Local key handling: Cmd+Z, Shift+Cmd+Z, Delete, Escape, Tool shortcuts.
      let monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
        guard let self, let w = self.windows[url], NSApp.keyWindow === w else { return event }

        let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if mods == .command, event.charactersIgnoringModifiers?.lowercased() == "k" {
          doc.isCropping ? doc.applyCrop() : doc.beginCrop()
          return nil
        }
        if doc.isCropping {
          switch event.keyCode {
          case 36, 76: doc.applyCrop(); return nil
          case 53: doc.cancelCrop(); return nil
          default:
            // Leave ⌘-shortcuts (undo, zoom, close…) working; swallow tool keys and Delete.
            if !mods.contains(.command) { return nil }
          }
        }

        if event.modifierFlags.contains(.command) {
          if mods == .command, event.charactersIgnoringModifiers?.lowercased() == "s",
             doc.pendingTextInput == nil {
            do {
              try doc.saveProject()
            } catch {
              NSAlert(error: error).runModal()
            }
            return nil
          }

          if mods == .command, event.charactersIgnoringModifiers?.lowercased() == "d",
             doc.pendingTextInput == nil {
            doc.duplicateSelected()
            return nil
          }

          // Cmd+Z / Shift+Cmd+Z
          if event.charactersIgnoringModifiers == "z" {
            if doc.pendingTextInput != nil { return event }
            if event.modifierFlags.contains(.shift) {
              doc.redo()
            } else {
              doc.undo()
            }
            return nil
          }
          
          // Cmd+V - Paste copied annotations, otherwise an image layer
          if event.charactersIgnoringModifiers == "v" {
            if doc.pendingTextInput != nil { return event }
            if let pasted = AnnotationClipboard.annotations() {
              doc.pasteAnnotations(pasted, pasteboardChangeCount: NSPasteboard.general.changeCount)
            } else {
              self.pasteImageFromClipboard(doc: doc)
            }
            return nil
          }

          if mods == .command, event.charactersIgnoringModifiers == "/" {
            doc.isShowingShortcuts.toggle()
            return nil
          }

          // Cmd+W - Close window
          if event.charactersIgnoringModifiers == "w" {
            w.performClose(nil)
            return nil
          }
        }

        // Delete / Backspace (skip when editing inline text so the TextField receives the event)
        if event.keyCode == 51 || event.keyCode == 117 {
          if doc.pendingTextInput == nil {
            doc.deleteSelected()
            return nil
          }
        }

        // Escape closes pending text input
        if event.keyCode == 53 {
          if doc.pendingTextInput != nil {
            doc.cancelPendingTextInput()
            return nil
          }
        }

        // Arrow keys nudge the selection (Shift = 10 px)
        if let direction = Self.nudgeDirection(keyCode: event.keyCode),
           doc.pendingTextInput == nil,
           !doc.selectedIDs.isEmpty,
           !Self.controlHasKeyFocus(in: event.window),
           mods.subtracting([.shift, .numericPad, .function]).isEmpty {
          let step: CGFloat = mods.contains(.shift) ? 10 : 1
          doc.nudgeSelected(by: CGPoint(x: direction.x * step, y: direction.y * step))
          return nil
        }

        // Tool shortcuts (only when not editing text)
        if doc.pendingTextInput == nil,
           !event.modifierFlags.contains(.command) {
          if event.charactersIgnoringModifiers == "?" || (event.charactersIgnoringModifiers == "/" && mods == .shift) {
            doc.isShowingShortcuts.toggle()
            return nil
          }
          if let char = event.charactersIgnoringModifiers?.lowercased() {
              let toolShortcuts: [String: AnnotationTool] = [
                "v": .select,
                "h": .hand,
                "r": .rect,
                "o": .ellipse,
                "l": .line,
                "a": .arrow,
              "m": .freehand,  // marker
              "t": .text,
              "c": .callout,
              "b": .blur,
              "s": .spotlight,
              "n": .step,     // numbered steps
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
      AppActivation.showInAppSwitcher()
      AppActivation.bringToFront(win)

    } catch {
      let alert = NSAlert(error: error)
      alert.runModal()
    }
  }

  /// Unit direction in image coordinates (y grows downward) for an arrow key.
  /// True when an inspector control (slider, picker, field) owns the keyboard, so arrow
  /// keys should adjust that control rather than nudge annotations on the canvas.
  static func controlHasKeyFocus(in window: NSWindow?) -> Bool {
    guard let responder = window?.firstResponder else { return false }
    return responder is NSControl || responder is NSText
  }

  static func nudgeDirection(keyCode: UInt16) -> CGPoint? {
    switch Int(keyCode) {
    case kVK_LeftArrow: return CGPoint(x: -1, y: 0)
    case kVK_RightArrow: return CGPoint(x: 1, y: 0)
    case kVK_UpArrow: return CGPoint(x: 0, y: -1)
    case kVK_DownArrow: return CGPoint(x: 0, y: 1)
    default: return nil
    }
  }

  private static let frameAutosaveName = "SnipSnapEditorWindow"

  /// Default size when no saved frame exists: fit the image plus editor chrome on screen.
  static func initialContentSize(for imageSize: CGSize, visible: CGSize? = nil) -> CGSize {
    let screen = visible ?? NSScreen.main?.visibleFrame.size ?? CGSize(width: 1440, height: 900)
    let chrome = CGSize(width: 52 + 220 + 48, height: 48 + 48)
    let maxSize = CGSize(width: screen.width * 0.9, height: screen.height * 0.9)
    let width = min(max(imageSize.width + chrome.width, 800), maxSize.width)
    let height = min(max(imageSize.height + chrome.height, 550), maxSize.height)
    return CGSize(width: width.rounded(), height: height.rounded())
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
  
  private func pasteImageFromClipboard(doc: AnnotationDocument) {
    let pasteboard = NSPasteboard.general
    
    // Try to get image data from clipboard
    guard let imageData = pasteboard.data(forType: .tiff) ?? pasteboard.data(forType: .png) else {
      return
    }
    
    // Create NSImage to get dimensions
    guard let nsImage = NSImage(data: imageData),
          let cgImage = nsImage.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
      return
    }
    
    // Get PNG representation
    let bitmap = NSBitmapImageRep(cgImage: cgImage)
    guard let finalData = bitmap.representation(using: .png, properties: [:]) else {
      return
    }
    
    // Place image in center of canvas at reasonable size
    let imageWidth = CGFloat(cgImage.width)
    let imageHeight = CGFloat(cgImage.height)
    let canvasWidth = doc.imageSize.width
    let canvasHeight = doc.imageSize.height
    
    // Scale to fit within 50% of canvas while maintaining aspect ratio
    let maxSize = min(canvasWidth, canvasHeight) * 0.5
    let scale = min(maxSize / imageWidth, maxSize / imageHeight, 1.0)
    let finalWidth = imageWidth * scale
    let finalHeight = imageHeight * scale
    
    // Center position
    let x = (canvasWidth - finalWidth) / 2
    let y = (canvasHeight - finalHeight) / 2
    
    let rect = CGRect(x: x, y: y, width: finalWidth, height: finalHeight)
    let imageLayer = ImageLayerAnnotation(rect: rect, imageData: finalData)
    
    doc.pushUndoCheckpoint()
    doc.annotations.append(.imageLayer(imageLayer))
    doc.selectedID = imageLayer.id
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
    alert.informativeText = "Save the editable annotations and crop alongside the original image?"
    alert.addButton(withTitle: "Save Project")
    alert.addButton(withTitle: "Don’t Save")
    alert.addButton(withTitle: "Cancel")
    alert.alertStyle = .warning

    let resp = alert.runModal()
    switch resp {
    case .alertFirstButtonReturn:
      do {
        try doc.saveProject()
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
