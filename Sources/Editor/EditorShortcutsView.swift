import SwiftUI

struct EditorShortcut: Hashable {
  let keys: String
  let action: String
}

struct EditorShortcutSection: Hashable {
  let title: String
  let shortcuts: [EditorShortcut]

  static let all: [EditorShortcutSection] = [
    EditorShortcutSection(title: "Tools", shortcuts: [
      .init(keys: "V", action: "Select"), .init(keys: "H", action: "Pan"),
      .init(keys: "R", action: "Rectangle"), .init(keys: "O", action: "Ellipse"),
      .init(keys: "L", action: "Line"), .init(keys: "A", action: "Arrow"),
      .init(keys: "M", action: "Marker"), .init(keys: "T", action: "Text"),
      .init(keys: "C", action: "Callout"), .init(keys: "B", action: "Blur"),
      .init(keys: "S", action: "Spotlight"), .init(keys: "N", action: "Numbered step"),
      .init(keys: "E", action: "Emoji"), .init(keys: "D", action: "Measure"),
    ]),
    EditorShortcutSection(title: "Selection", shortcuts: [
      .init(keys: "⇧ Click", action: "Add or remove from selection"),
      .init(keys: "Drag empty area", action: "Marquee select"),
      .init(keys: "← ↑ → ↓", action: "Nudge 1 px"),
      .init(keys: "⇧ Arrow", action: "Nudge 10 px"),
      .init(keys: "⌥ Drag", action: "Move without snapping"),
      .init(keys: "⌘D", action: "Duplicate"),
      .init(keys: "⌫", action: "Delete"),
    ]),
    EditorShortcutSection(title: "Edit", shortcuts: [
      .init(keys: "⌘C", action: "Copy image (and selected annotations)"),
      .init(keys: "⌘V", action: "Paste annotations or image"),
      .init(keys: "⌘Z / ⇧⌘Z", action: "Undo / Redo"),
      .init(keys: "⌘K", action: "Crop (↩ apply, ⎋ cancel)"),
      .init(keys: "⌘S", action: "Save editable project"),
    ]),
    EditorShortcutSection(title: "Output", shortcuts: [
      .init(keys: "⌘E", action: "Quick export PNG"),
      .init(keys: "⇧⌘P", action: "Pin to screen"),
      .init(keys: "⇧⌘S", action: "Share"),
      .init(keys: "⌘+ / ⌘-", action: "Zoom"),
      .init(keys: "? or ⌘/", action: "Show this list"),
    ]),
  ]
}

struct EditorShortcutsView: View {
  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text("Keyboard Shortcuts").font(.headline)
      HStack(alignment: .top, spacing: 24) {
        ForEach(EditorShortcutSection.all, id: \.self) { section in
          VStack(alignment: .leading, spacing: 6) {
            Text(section.title.uppercased())
              .font(.system(size: 10, weight: .semibold))
              .foregroundColor(.secondary)
            ForEach(section.shortcuts, id: \.self) { shortcut in
              HStack(spacing: 8) {
                Text(shortcut.keys)
                  .font(.system(size: 11, weight: .semibold, design: .rounded))
                  .padding(.horizontal, 5)
                  .padding(.vertical, 1)
                  .background(RoundedRectangle(cornerRadius: 4).fill(Color.primary.opacity(0.08)))
                Text(shortcut.action).font(.system(size: 11))
              }
            }
          }
        }
      }
    }
    .padding(16)
  }
}
