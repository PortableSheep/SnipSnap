import AppKit
import SwiftUI

/// Root SwiftUI view of the full-screen corkboard overlay.
struct BoardCanvasView: View {
  static let space = "boardSurface"

  @ObservedObject var vm: BoardViewModel
  @ObservedObject var store: BoardStore
  @ObservedObject var prefs: BoardPreferencesStore

  @State private var marqueeBase: Set<UUID> = []
  @State private var marqueeExtend = false
  @State private var appeared = false

  init(vm: BoardViewModel) {
    self.vm = vm
    self.store = vm.store
    self.prefs = vm.prefs
  }

  private var style: BoardThemeStyle { BoardThemeStyle(theme: prefs.theme) }

  var body: some View {
    ZStack {
      backdrop
      content
      if let marquee = vm.marquee {
        Rectangle()
          .fill(Color.accentColor.opacity(0.12))
          .overlay(Rectangle().strokeBorder(Color.accentColor.opacity(0.8), lineWidth: 1))
          .frame(width: marquee.width, height: marquee.height)
          .position(x: marquee.midX, y: marquee.midY)
          .allowsHitTesting(false)
      }
      if store.cards.isEmpty && store.zones.isEmpty {
        BoardEmptyState(style: style)
          .allowsHitTesting(false)
          .transition(.opacity)
      }
      VStack {
        BoardToolbar(vm: vm, store: store, prefs: prefs, style: style)
          .padding(.top, 18)
        Spacer()
        if let toast = vm.toast {
          BoardToastView(toast: toast)
            .padding(.bottom, 36)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
      }
      if let id = vm.detailCardID, let card = store.card(id) {
        CardDetailView(card: card, vm: vm, style: style)
          .transition(.opacity.combined(with: .scale(scale: 0.97)))
          .zIndex(10)
      }
    }
    .coordinateSpace(name: Self.space)
    .background(
      GeometryReader { geo in
        Color.clear
          .onAppear { vm.canvasSize = geo.size }
          .onChange(of: geo.size) { vm.canvasSize = $0 }
      }
    )
    .opacity(appeared ? 1 : 0)
    .scaleEffect(appeared ? 1 : 1.015)
    .onAppear { withAnimation(.easeOut(duration: 0.18)) { appeared = true } }
    .animation(.spring(response: 0.3, dampingFraction: 0.85), value: vm.detailCardID)
  }

  // MARK: - Backdrop & background gestures

  private var backdrop: some View {
    BoardBackdrop(theme: prefs.theme)
      .ignoresSafeArea()
      .contentShape(Rectangle())
      .gesture(
        DragGesture(minimumDistance: 3, coordinateSpace: .named(Self.space))
          .onChanged { v in
            if vm.marquee == nil {
              marqueeExtend = NSEvent.modifierFlags.contains(.shift) || NSEvent.modifierFlags.contains(.command)
              marqueeBase = marqueeExtend ? vm.selection : []
              vm.editingCardID = nil
            }
            vm.updateMarquee(from: v.startLocation, to: v.location, extend: marqueeExtend, baseSelection: marqueeBase)
          }
          .onEnded { _ in vm.endMarquee() }
      )
      .gesture(
        SpatialTapGesture(count: 2, coordinateSpace: .named(Self.space))
          .onEnded { v in vm.addNote(at: vm.toBoard(v.location)) }
      )
      .simultaneousGesture(
        TapGesture().onEnded {
          vm.clearSelection()
          if prefs.clickBackgroundToClose { vm.actions.close() }
        }
      )
  }

  // MARK: - Content (zones + cards), transformed by the viewport

  private var content: some View {
    let cards = store.cardsInPaintOrder
    return ZStack(alignment: .topLeading) {
      ForEach(store.zones) { zone in
        zoneView(zone, cards: cards)
      }
      ForEach(cards) { card in
        cardView(card)
      }
    }
    .frame(width: max(1, vm.canvasSize.width), height: max(1, vm.canvasSize.height), alignment: .topLeading)
    .scaleEffect(vm.scale, anchor: .topLeading)
    .offset(vm.offset)
  }

  private func zoneView(_ zone: BoardZone, cards: [BoardCard]) -> some View {
    let members = cards.filter { $0.zoneID == zone.id }
    var frame = zone.frame.cgRect
    if let resize = vm.zoneResize, resize.id == zone.id { frame.size = resize.size }
    if let drag = vm.zoneDrag, drag.id == zone.id {
      frame.origin.x += drag.translation.width
      frame.origin.y += drag.translation.height
    }
    return BoardZoneView(
      zone: zone,
      vm: vm,
      style: style,
      size: frame.size,
      isEditing: vm.editingZoneID == zone.id,
      cardCount: members.count,
      doneCount: members.filter { $0.todo == .done }.count
    )
    .position(x: frame.midX, y: frame.midY)
  }

  private func cardView(_ card: BoardCard) -> some View {
    let size = vm.liveSize(card)
    let drag = vm.offsetFor(card.id)
    let zoneDrag = vm.zoneOffsetFor(card)
    let isEditing = vm.editingCardID == card.id
    let isDragging = vm.draggingIDs.contains(card.id) && vm.dragTranslation != .zero
    return BoardCardView(
      card: card,
      vm: vm,
      style: style,
      isSelected: vm.selection.contains(card.id),
      isDragging: isDragging,
      isEditing: isEditing,
      isDimmed: vm.isDimmed(card.id),
      size: size,
      tilt: prefs.tiltCards
    )
    .position(
      x: card.frame.x + size.width / 2 + drag.width + zoneDrag.width,
      y: card.frame.y + size.height / 2 + drag.height + zoneDrag.height
    )
    .gesture(
      DragGesture(minimumDistance: 0, coordinateSpace: .named(Self.space))
        .onChanged { v in
          let extend = NSEvent.modifierFlags.contains(.shift) || NSEvent.modifierFlags.contains(.command)
          vm.beginCardDrag(card.id, extend: extend)
          if abs(v.translation.width) + abs(v.translation.height) > 2 {
            vm.updateCardDrag(viewTranslation: v.translation)
          }
        }
        .onEnded { _ in vm.endCardDrag() },
      including: isEditing ? .subviews : .all
    )
    .simultaneousGesture(TapGesture(count: 2).onEnded { vm.open(card.id) })
    .transition(.scale(scale: 0.6).combined(with: .opacity))
  }
}

// MARK: - Toolbar

private struct BoardToolbar: View {
  @ObservedObject var vm: BoardViewModel
  @ObservedObject var store: BoardStore
  @ObservedObject var prefs: BoardPreferencesStore
  let style: BoardThemeStyle
  @FocusState private var searchFocused: Bool

  private var openTodos: Int { store.cards.filter { $0.todo == .open }.count }

  var body: some View {
    HStack(spacing: 6) {
      HStack(spacing: 6) {
        Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
        TextField("Search board", text: $vm.searchQuery)
          .textFieldStyle(.plain)
          .frame(width: 180)
          .focused($searchFocused)
          .onExitCommand {
            vm.searchQuery = ""
            searchFocused = false
          }
        if vm.isSearching {
          Text("\(vm.matches?.count ?? 0)")
            .font(.caption.monospacedDigit())
            .foregroundStyle(.secondary)
          Button { vm.searchQuery = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }
            .buttonStyle(.plain)
        }
      }
      .padding(.horizontal, 10)
      .padding(.vertical, 6)
      .background(Color.primary.opacity(0.07), in: Capsule())

      divider

      ToolbarButton(systemName: "note.text.badge.plus", help: "New note (double-click the board)") { vm.addNote() }
      ToolbarButton(systemName: "doc.on.clipboard", help: "Paste clipboard as card (⌘V)") { vm.paste(viewPoint: nil) }
      Menu {
        Button("Add Zone") { vm.addZone() }
        Button("Add Todo · Doing · Done") { vm.addTodoTemplate() }
      } label: {
        Image(systemName: "rectangle.dashed.badge.record")
      }
      .menuStyle(.borderlessButton)
      .menuIndicator(.hidden)
      .fixedSize()
      .frame(width: 30, height: 28)
      .help("Zones")
      ToolbarButton(systemName: "wand.and.stars", help: "Tidy up") { vm.tidyUp() }

      divider

      ToolbarButton(systemName: "minus.magnifyingglass", help: "Zoom out") {
        withAnimation(.easeOut(duration: 0.15)) { vm.zoom(by: 0.8, around: center) }
      }
      Button { withAnimation(.easeOut(duration: 0.2)) { vm.resetZoom() } } label: {
        Text("\(Int((vm.scale * 100).rounded()))%")
          .font(.system(size: 11, weight: .semibold).monospacedDigit())
          .frame(width: 40)
      }
      .buttonStyle(.plain)
      .help("Reset zoom")
      ToolbarButton(systemName: "plus.magnifyingglass", help: "Zoom in") {
        withAnimation(.easeOut(duration: 0.15)) { vm.zoom(by: 1.25, around: center) }
      }
      ToolbarButton(systemName: "arrow.up.left.and.down.right.magnifyingglass", help: "Zoom to fit") { vm.zoomToFit() }

      divider

      ToolbarButton(
        systemName: prefs.pinsHidden ? "pin.slash" : "pin",
        help: prefs.pinsHidden ? "Show popped-out pins" : "Hide popped-out pins"
      ) { vm.actions.togglePinsHidden() }
      Menu {
        Picker("Theme", selection: $prefs.theme) {
          ForEach(BoardTheme.allCases) { Text($0.label).tag($0) }
        }
        .pickerStyle(.inline)
        Toggle("Tilt Cards", isOn: $prefs.tiltCards)
        Divider()
        Button("Board Settings…") { vm.actions.showPreferences() }
      } label: {
        Image(systemName: "paintpalette")
      }
      .menuStyle(.borderlessButton)
      .menuIndicator(.hidden)
      .fixedSize()
      .frame(width: 30, height: 28)
      .help("Appearance")

      if openTodos > 0 {
        Text("\(openTodos) open")
          .font(.system(size: 11, weight: .semibold, design: .rounded))
          .padding(.horizontal, 8)
          .padding(.vertical, 3)
          .background(Color.accentColor.opacity(0.25), in: Capsule())
          .help("Open todos")
      }

      ToolbarButton(systemName: "xmark", help: "Close board (Esc)") { vm.actions.close() }
    }
    .padding(.horizontal, 10)
    .padding(.vertical, 7)
    .background(.regularMaterial, in: Capsule())
    .overlay(Capsule().strokeBorder(Color.white.opacity(0.12), lineWidth: 1))
    .shadow(color: .black.opacity(0.3), radius: 16, y: 6)
    .environment(\.colorScheme, style.chromeIsDark ? .dark : .light)
    .onChange(of: vm.searchFocusToken) { _ in searchFocused = true }
  }

  private var center: CGPoint { CGPoint(x: vm.canvasSize.width / 2, y: vm.canvasSize.height / 2) }

  private var divider: some View {
    Rectangle().fill(Color.primary.opacity(0.15)).frame(width: 1, height: 18).padding(.horizontal, 2)
  }
}

private struct ToolbarButton: View {
  let systemName: String
  let help: String
  let action: () -> Void
  @State private var hovering = false

  var body: some View {
    Button(action: action) {
      Image(systemName: systemName)
        .font(.system(size: 13, weight: .medium))
        .frame(width: 30, height: 28)
        .background(Color.primary.opacity(hovering ? 0.1 : 0), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
        .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .onHover { hovering = $0 }
    .help(help)
  }
}

// MARK: - Empty state & toast

private struct BoardEmptyState: View {
  let style: BoardThemeStyle

  var body: some View {
    VStack(spacing: 14) {
      Image(systemName: "square.on.square.dashed")
        .font(.system(size: 54, weight: .light))
      Text("Your board is empty")
        .font(.system(size: 22, weight: .bold, design: .rounded))
      VStack(alignment: .leading, spacing: 6) {
        hint("arrow.down.doc", "Drop screenshots, files, links, or text here")
        hint("command", "Press ⌘V to paste your clipboard as a card")
        hint("cursorarrow.click.2", "Double-click anywhere to write a note")
        hint("camera.viewfinder", "Use “Send to Board” on any SnipSnap capture")
      }
      .font(.system(size: 13))
    }
    .foregroundStyle(style.textColor.opacity(0.75))
    .padding(32)
  }

  private func hint(_ icon: String, _ text: String) -> some View {
    HStack(spacing: 10) {
      Image(systemName: icon).frame(width: 20)
      Text(text)
    }
  }
}

private struct BoardToastView: View {
  let toast: BoardToast

  var body: some View {
    HStack(spacing: 10) {
      Image(systemName: toast.systemImage)
      Text(toast.message).font(.system(size: 13, weight: .semibold))
      if let title = toast.actionTitle, let action = toast.action {
        Button(title, action: action)
          .buttonStyle(.borderedProminent)
          .controlSize(.small)
      }
    }
    .padding(.horizontal, 16)
    .padding(.vertical, 10)
    .background(.regularMaterial, in: Capsule())
    .environment(\.colorScheme, .dark)
    .shadow(color: .black.opacity(0.3), radius: 12, y: 4)
  }
}
