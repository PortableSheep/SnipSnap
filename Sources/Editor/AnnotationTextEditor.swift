import AppKit
import SwiftUI

struct AnnotationTextEditor: NSViewRepresentable {
  @Binding var text: String
  let fontSize: CGFloat
  let color: Color
  let wraps: Bool
  let onCommit: () -> Void
  let onCancel: () -> Void

  func makeCoordinator() -> Coordinator { Coordinator(self) }

  func makeNSView(context: Context) -> NSScrollView {
    let scroll = NSScrollView()
    scroll.drawsBackground = false
    let editor = EditingTextView(frame: .zero)
    editor.isRichText = false
    editor.importsGraphics = false
    editor.allowsUndo = true
    editor.drawsBackground = false
    editor.textContainerInset = .zero
    editor.textContainer?.lineFragmentPadding = 0
    editor.layoutManager?.usesFontLeading = true
    editor.isVerticallyResizable = true
    editor.isHorizontallyResizable = !wraps
    editor.autoresizingMask = wraps ? [.width] : []
    editor.textContainer?.widthTracksTextView = wraps
    editor.textContainer?.heightTracksTextView = false
    editor.textContainer?.containerSize = CGSize(
      width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude
    )
    editor.delegate = context.coordinator
    scroll.documentView = editor
    updateNSView(scroll, context: context)
    return scroll
  }

  func updateNSView(_ scroll: NSScrollView, context: Context) {
    context.coordinator.parent = self
    guard let editor = scroll.documentView as? EditingTextView else { return }
    if editor.string != text { editor.string = text }
    let font = NSFont.systemFont(ofSize: fontSize, weight: .semibold)
    let textColor = NSColor(color)
    if editor.font != font { editor.font = font }
    if editor.textColor != textColor { editor.textColor = textColor }
    editor.onCommit = onCommit
    editor.onCancel = onCancel
    editor.sizeToFit()
    if !context.coordinator.didFocus {
      DispatchQueue.main.async { [weak editor, weak coordinator = context.coordinator] in
        guard let editor, let coordinator, !coordinator.didFocus,
              let window = editor.window else { return }
        coordinator.didFocus = window.makeFirstResponder(editor)
        editor.setSelectedRange(NSRange(location: editor.string.utf16.count, length: 0))
      }
    }
  }

  final class Coordinator: NSObject, NSTextViewDelegate {
    var parent: AnnotationTextEditor
    var didFocus = false

    init(_ parent: AnnotationTextEditor) { self.parent = parent }

    func textDidChange(_ notification: Notification) {
      guard let editor = notification.object as? NSTextView else { return }
      parent.text = editor.string
    }
  }

  final class EditingTextView: NSTextView {
    var onCommit: (() -> Void)?
    var onCancel: (() -> Void)?

    override func keyDown(with event: NSEvent) {
      if event.keyCode == 53 {
        onCancel?()
      } else if (event.keyCode == 36 || event.keyCode == 76),
                event.modifierFlags.contains(.command) {
        onCommit?()
      } else {
        super.keyDown(with: event)
      }
    }
  }
}
