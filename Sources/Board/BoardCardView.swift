import AppKit
import SwiftUI

/// Renders a single card on the corkboard (also reused inside pop-out pin windows).
struct CardContentView: View {
  let card: BoardCard
  let store: BoardStore
  let style: BoardThemeStyle
  var isEditing: Bool = false
  var onTextChange: ((String) -> Void)?
  var onEndEditing: (() -> Void)?

  var body: some View {
    switch card.kind {
    case .capture: captureBody
    case .link: linkBody
    case .text: textBody
    case .note: noteBody
    }
  }

  // MARK: Capture

  private var framed: Bool { style.theme != .glass }

  private var captureBody: some View {
    VStack(spacing: 0) {
      ZStack {
        if let image = store.thumbnail(for: card) {
          Image(nsImage: image)
            .resizable()
            .interpolation(.high)
            .aspectRatio(contentMode: .fill)
        } else {
          Rectangle().fill(Color.gray.opacity(0.25))
            .overlay(Image(systemName: "photo").font(.title2).foregroundStyle(.secondary))
        }
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      .clipped()
      .clipShape(RoundedRectangle(cornerRadius: framed ? 2 : 10, style: .continuous))
      .padding(framed ? 7 : 0)

      if framed, let caption = captionText {
        Text(caption)
          .font(.system(size: 11, weight: .medium, design: .rounded))
          .foregroundStyle(Color(white: 0.25))
          .lineLimit(1)
          .truncationMode(.middle)
          .padding(.horizontal, 10)
          .padding(.bottom, 7)
          .padding(.top, -2)
          .frame(maxWidth: .infinity, alignment: .leading)
      }
    }
    .background(framed ? Color(white: 0.985) : .clear)
    .overlay(alignment: .bottomLeading) {
      if !framed, let caption = captionText {
        Text(caption)
          .font(.system(size: 11, weight: .semibold, design: .rounded))
          .foregroundStyle(.white)
          .lineLimit(1)
          .truncationMode(.middle)
          .padding(.horizontal, 8)
          .padding(.vertical, 4)
          .background(.ultraThinMaterial.opacity(0.9), in: Capsule())
          .environment(\.colorScheme, .dark)
          .padding(8)
      }
    }
  }

  private var captionText: String? {
    if let title = card.title, !title.isEmpty { return title }
    if let app = card.source?.appName { return app }
    return nil
  }

  // MARK: Link

  private var linkBody: some View {
    VStack(alignment: .leading, spacing: 0) {
      if let preview = store.image(named: card.previewAsset) {
        Image(nsImage: preview)
          .resizable()
          .aspectRatio(contentMode: .fill)
          .frame(maxWidth: .infinity)
          .frame(height: max(0, (card.frame.height - CardFactory.Size.link.height)))
          .clipped()
      }
      HStack(alignment: .top, spacing: 10) {
        Group {
          if let icon = store.image(named: card.faviconAsset) {
            Image(nsImage: icon).resizable().aspectRatio(contentMode: .fit)
          } else {
            Image(systemName: card.url?.isFileURL == true ? "doc" : "globe")
              .font(.system(size: 15, weight: .medium))
              .foregroundStyle(style.cardText.opacity(0.6))
          }
        }
        .frame(width: 22, height: 22)
        .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))

        VStack(alignment: .leading, spacing: 3) {
          Text(card.title ?? card.url?.host ?? "Link")
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(style.cardText)
            .lineLimit(2)
          Text(card.url?.host?.replacingOccurrences(of: "www.", with: "") ?? card.url?.absoluteString ?? "")
            .font(.system(size: 11))
            .foregroundStyle(style.cardText.opacity(0.55))
            .lineLimit(1)
        }
        Spacer(minLength: 0)
      }
      .padding(12)
      Spacer(minLength: 0)
    }
    .background(style.cardFace)
  }

  // MARK: Text

  private var textBody: some View {
    VStack(alignment: .leading, spacing: 8) {
      Image(systemName: "text.quote")
        .font(.system(size: 11, weight: .bold))
        .foregroundStyle(style.cardText.opacity(0.35))
      if isEditing {
        editor(font: .system(size: 12.5), color: style.cardText)
      } else {
        Text(card.text ?? "")
          .font(.system(size: 12.5))
          .foregroundStyle(style.cardText)
          .frame(maxWidth: .infinity, alignment: .leading)
      }
      Spacer(minLength: 0)
      if let app = card.source?.appName {
        Text("from \(app)")
          .font(.system(size: 10, weight: .medium))
          .foregroundStyle(style.cardText.opacity(0.45))
      }
    }
    .padding(12)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    .background(style.cardFace)
  }

  // MARK: Note

  private var noteColor: Color {
    Color(boardHex: card.colorHex ?? BoardPalette.noteColors[0]) ?? .yellow
  }

  private var noteBody: some View {
    ZStack(alignment: .topLeading) {
      LinearGradient(colors: [noteColor, noteColor.opacity(0.88)], startPoint: .top, endPoint: .bottom)
      if isEditing {
        editor(font: .system(size: 15, weight: .medium, design: .rounded), color: Color(white: 0.12))
          .padding(12)
      } else if (card.text ?? "").isEmpty {
        Text("Double-click to write…")
          .font(.system(size: 14, weight: .medium, design: .rounded))
          .foregroundStyle(Color(white: 0.12).opacity(0.35))
          .padding(16)
      } else {
        Text(card.text ?? "")
          .font(.system(size: 15, weight: .medium, design: .rounded))
          .foregroundStyle(Color(white: 0.12))
          .frame(maxWidth: .infinity, alignment: .leading)
          .padding(16)
      }
    }
  }

  private func editor(font: Font, color: Color) -> some View {
    NoteEditor(
      text: card.text ?? "",
      font: font,
      color: color,
      onChange: { onTextChange?($0) },
      onEnd: { onEndEditing?() }
    )
  }
}

/// Inline text editor that grabs focus when it appears.
private struct NoteEditor: View {
  @State var text: String
  let font: Font
  let color: Color
  let onChange: (String) -> Void
  let onEnd: () -> Void
  @FocusState private var focused: Bool

  var body: some View {
    TextEditor(text: $text)
      .font(font)
      .foregroundStyle(color)
      .scrollContentBackground(.hidden)
      .background(.clear)
      .focused($focused)
      .onAppear { DispatchQueue.main.async { focused = true } }
      .onChange(of: text) { onChange($0) }
      .onChange(of: focused) { if !$0 { onEnd() } }
  }
}

/// Small rounded chips for links/emails/phones detected in a card.
struct DetectedChips: View {
  let items: [DetectedItem]
  var limit = 3

  var body: some View {
    HStack(spacing: 4) {
      ForEach(Array(items.prefix(limit).enumerated()), id: \.offset) { _, item in
        Button {
          if let url = item.actionURL { NSWorkspace.shared.open(url) }
        } label: {
          HStack(spacing: 3) {
            Image(systemName: icon(item.kind)).font(.system(size: 8, weight: .bold))
            Text(item.displayText).lineLimit(1)
          }
          .font(.system(size: 10, weight: .semibold))
          .foregroundStyle(.white)
          .padding(.horizontal, 7)
          .padding(.vertical, 3.5)
          .background(Color.accentColor.opacity(0.92), in: Capsule())
          .shadow(color: .black.opacity(0.25), radius: 2, y: 1)
        }
        .buttonStyle(.plain)
        .help(item.value)
      }
      if items.count > limit {
        Text("+\(items.count - limit)")
          .font(.system(size: 10, weight: .bold))
          .foregroundStyle(.white)
          .padding(.horizontal, 6)
          .padding(.vertical, 3.5)
          .background(.black.opacity(0.5), in: Capsule())
      }
    }
  }

  private func icon(_ kind: DetectedItem.Kind) -> String {
    switch kind {
    case .link: return "link"
    case .email: return "envelope.fill"
    case .phone: return "phone.fill"
    }
  }
}

/// Round todo checkbox.
struct TodoCheckbox: View {
  let state: TodoState
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      ZStack {
        Circle()
          .fill(state == .done ? Color.green : Color.white)
          .frame(width: 22, height: 22)
          .shadow(color: .black.opacity(0.3), radius: 2, y: 1)
        Circle()
          .stroke(state == .done ? Color.green : Color(white: 0.55), lineWidth: 1.5)
          .frame(width: 22, height: 22)
        if state == .done {
          Image(systemName: "checkmark")
            .font(.system(size: 11, weight: .heavy))
            .foregroundStyle(.white)
            .transition(.scale.combined(with: .opacity))
        }
      }
    }
    .buttonStyle(.plain)
    .help(state == .done ? "Mark as not done" : "Mark as done")
  }
}

/// A card as it appears on the board: content + chrome (shadow, selection, todo, chips, menus, gestures).
struct BoardCardView: View {
  let card: BoardCard
  let vm: BoardViewModel
  let style: BoardThemeStyle
  let isSelected: Bool
  let isDragging: Bool
  let isEditing: Bool
  let isDimmed: Bool
  let size: CGSize
  let tilt: Bool

  @State private var hovering = false

  private var isDone: Bool { card.todo == .done }
  private var isPinnedOut: Bool { card.pin != nil }

  var body: some View {
    CardContentView(
      card: card,
      store: vm.store,
      style: style,
      isEditing: isEditing,
      onTextChange: { text in vm.store.update(card.id) { $0.text = text } },
      onEndEditing: {
        if vm.editingCardID == card.id { vm.editingCardID = nil }
      }
    )
    .frame(width: size.width, height: size.height)
    .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    .overlay {
      RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        .strokeBorder(isSelected ? Color.accentColor : Color.white.opacity(style.theme == .glass ? 0.12 : 0), lineWidth: isSelected ? 2.5 : 1)
    }
    .overlay { if isDone { doneOverlay } }
    .overlay { if isPinnedOut { pinnedOverlay } }
    .overlay(alignment: .topLeading) {
      if let todo = card.todo {
        TodoCheckbox(state: todo) { vm.toggleTodo(card.id) }
          .offset(x: -8, y: -8)
      }
    }
    .overlay(alignment: .top) {
      if style.usesPushPins, card.kind != .note || style.theme == .cork {
        PushPin(color: pinColor).offset(y: -5)
      }
    }
    .overlay(alignment: .bottomLeading) {
      if let items = card.detectedItems, !items.isEmpty, card.kind != .link {
        DetectedChips(items: items).padding(8).offset(y: framedOffset)
      }
    }
    .overlay(alignment: .topTrailing) {
      if hovering && !isEditing && !isPinnedOut && !isDragging {
        hoverControls.padding(6).transition(.opacity)
      }
    }
    .overlay(alignment: .bottomTrailing) {
      if (isSelected || hovering) && !isEditing && !isPinnedOut {
        CardResizeHandle()
          .gesture(
            DragGesture(minimumDistance: 1, coordinateSpace: .named(BoardCanvasView.space))
              .onChanged { vm.updateResize(card, viewTranslation: $0.translation) }
              .onEnded { _ in vm.endResize() }
          )
      }
    }
    .shadow(color: .black.opacity(isDragging ? 0.45 : 0.28), radius: isDragging ? 18 : 6, x: 0, y: isDragging ? 14 : 4)
    .scaleEffect(isDragging ? 1.035 : 1)
    .rotationEffect(.degrees(tilt && !isDragging && !isEditing ? card.rotation : 0))
    .opacity(isDimmed ? 0.18 : 1)
    .saturation(isDimmed ? 0.2 : 1)
    .onHover { h in withAnimation(.easeOut(duration: 0.12)) { hovering = h } }
    .contextMenu { BoardCardMenu(card: card, vm: vm) }
    .help(helpText)
  }

  private var cornerRadius: CGFloat {
    switch card.kind {
    case .note: return 3
    case .capture: return style.theme == .glass ? 10 : 3
    case .link, .text: return style.theme == .glass ? 12 : 6
    }
  }

  private var framedOffset: CGFloat { 0 }

  private var pinColor: Color {
    let colors: [Color] = [.red, .blue, .green, .orange, .purple]
    return colors[Int(card.id.uuid.0) % colors.count]
  }

  private var helpText: String {
    var parts: [String] = []
    if let app = card.source?.appName { parts.append(app) }
    if let page = card.source?.pageTitle { parts.append(page) }
    let date = (card.source?.capturedAt ?? card.createdAt).formatted(date: .abbreviated, time: .shortened)
    parts.append(date)
    return parts.joined(separator: " · ")
  }

  private var doneOverlay: some View {
    ZStack {
      RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        .fill(Color.black.opacity(0.35))
      Image(systemName: "checkmark.circle.fill")
        .font(.system(size: min(size.width, size.height) * 0.28))
        .foregroundStyle(.white, .green)
        .shadow(radius: 4)
    }
    .allowsHitTesting(false)
  }

  private var pinnedOverlay: some View {
    ZStack {
      RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        .fill(.ultraThinMaterial)
        .environment(\.colorScheme, .dark)
      VStack(spacing: 8) {
        Image(systemName: "pin.fill").font(.system(size: 18, weight: .semibold))
        Text("Popped out").font(.system(size: 12, weight: .semibold))
        Button("Return to Board") { vm.actions.returnPin(card.id) }
          .buttonStyle(.borderedProminent)
          .controlSize(.small)
      }
      .foregroundStyle(.white)
    }
  }

  private var hoverControls: some View {
    HStack(spacing: 4) {
      CardIconButton(systemName: "pin", help: "Pop out (always on top)") { vm.actions.popOut(card.id) }
      if card.kind == .capture {
        CardIconButton(systemName: "arrow.up.left.and.arrow.down.right", help: "Open details") { vm.detailCardID = card.id }
      }
      Menu {
        BoardCardMenu(card: card, vm: vm)
      } label: {
        Image(systemName: "ellipsis")
          .font(.system(size: 11, weight: .bold))
          .foregroundStyle(.white)
          .frame(width: 24, height: 24)
          .background(.black.opacity(0.55), in: Circle())
      }
      .menuStyle(.borderlessButton)
      .menuIndicator(.hidden)
      .fixedSize()
    }
  }
}

struct CardIconButton: View {
  let systemName: String
  let help: String
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      Image(systemName: systemName)
        .font(.system(size: 11, weight: .bold))
        .foregroundStyle(.white)
        .frame(width: 24, height: 24)
        .background(.black.opacity(0.55), in: Circle())
    }
    .buttonStyle(.plain)
    .help(help)
  }
}

private struct CardResizeHandle: View {
  var body: some View {
    Image(systemName: "arrow.up.left.and.arrow.down.right")
      .font(.system(size: 9, weight: .bold))
      .rotationEffect(.degrees(90))
      .foregroundStyle(.white)
      .frame(width: 20, height: 20)
      .background(Color.accentColor, in: Circle())
      .shadow(radius: 2)
      .offset(x: 7, y: 7)
      .contentShape(Rectangle())
  }
}

/// Context menu shared by board cards (and the "…" hover button).
struct BoardCardMenu: View {
  let card: BoardCard
  let vm: BoardViewModel

  private var targets: Set<UUID> {
    vm.selection.contains(card.id) ? vm.selection : [card.id]
  }

  var body: some View {
    if card.pin == nil {
      Button("Pop Out (Always on Top)") { vm.actions.popOut(card.id) }
    } else {
      Button("Return to Board") { vm.actions.returnPin(card.id) }
    }

    switch card.kind {
    case .link:
      Button("Open Link") { vm.open(card.id) }
    case .capture:
      Button("Show Details") { vm.detailCardID = card.id }
      Button("Edit in Editor") { vm.actions.openInEditor(card.id) }
    case .text, .note:
      Button("Edit Text") { vm.editingCardID = card.id }
    }
    if let pageURL = card.source?.pageURL {
      Button("Open Source Page") { NSWorkspace.shared.open(pageURL) }
    }

    Divider()

    Button("Copy") { vm.copy(card.id) }
    if card.kind == .capture {
      Button("Copy Text (OCR)") { vm.copyText(card.id) }
    }

    Divider()

    if card.todo == nil {
      Button("Make Todo") { vm.setTodo(targets, enabled: true) }
    } else {
      Button(card.todo == .done ? "Mark Not Done" : "Mark Done") { vm.toggleTodo(card.id) }
      Button("Remove Todo") { vm.setTodo(targets, enabled: false) }
    }

    if card.kind == .note {
      Menu("Color") {
        ForEach(BoardPalette.noteColors, id: \.self) { hex in
          Button(colorName(hex)) { vm.setColor(targets, hex: hex) }
        }
      }
    }

    Divider()

    Button("Delete", role: .destructive) { vm.delete(targets) }
  }

  private func colorName(_ hex: String) -> String {
    switch hex {
    case "#FFE27A": return "Yellow"
    case "#FFB3C1": return "Pink"
    case "#A8E6CF": return "Mint"
    case "#A0C4FF": return "Blue"
    case "#E0BBFF": return "Lavender"
    case "#FFFFFF": return "White"
    default: return hex
    }
  }
}
