import SwiftUI

/// A labeled region on the board. The body ignores clicks (so marquee selection still works
/// over it); only the header (move/rename) and the corner handle (resize) are interactive.
struct BoardZoneView: View {
  let zone: BoardZone
  let vm: BoardViewModel
  let style: BoardThemeStyle
  let size: CGSize
  let isEditing: Bool
  let cardCount: Int
  let doneCount: Int

  @State private var draftTitle = ""
  @FocusState private var titleFocused: Bool

  private var tint: Color { Color(boardHex: zone.colorHex) ?? .blue }

  var body: some View {
    ZStack(alignment: .topLeading) {
      RoundedRectangle(cornerRadius: 18, style: .continuous)
        .fill(tint.opacity(style.theme == .paper ? 0.08 : 0.13))
        .overlay {
          RoundedRectangle(cornerRadius: 18, style: .continuous)
            .strokeBorder(tint.opacity(0.55), style: StrokeStyle(lineWidth: 1.5, dash: [7, 5]))
        }
        .allowsHitTesting(false)

      header
        .padding(10)
    }
    .frame(width: size.width, height: size.height)
    .overlay(alignment: .bottomTrailing) {
      Image(systemName: "arrow.down.right")
        .font(.system(size: 10, weight: .bold))
        .foregroundStyle(tint)
        .frame(width: 22, height: 22)
        .background(tint.opacity(0.18), in: Circle())
        .padding(6)
        .contentShape(Rectangle())
        .gesture(
          DragGesture(minimumDistance: 1, coordinateSpace: .named(BoardCanvasView.space))
            .onChanged { v in
              let base = zone.frame.cgRect.size
              vm.zoneResize = (zone.id, CGSize(
                width: max(180, base.width + v.translation.width / vm.scale),
                height: max(140, base.height + v.translation.height / vm.scale)
              ))
            }
            .onEnded { _ in vm.endZoneResize() }
        )
        .help("Resize zone")
    }
  }

  private var header: some View {
    HStack(spacing: 8) {
      Circle().fill(tint).frame(width: 9, height: 9)
      if isEditing {
        TextField("Zone name", text: $draftTitle)
          .textFieldStyle(.plain)
          .font(.system(size: 14, weight: .bold, design: .rounded))
          .foregroundStyle(style.textColor)
          .frame(width: 160)
          .focused($titleFocused)
          .onAppear {
            draftTitle = zone.title
            DispatchQueue.main.async { titleFocused = true }
          }
          .onSubmit(commit)
          .onChange(of: titleFocused) { if !$0 { commit() } }
      } else {
        Text(zone.title)
          .font(.system(size: 14, weight: .bold, design: .rounded))
          .foregroundStyle(style.textColor)
          .lineLimit(1)
      }
      if cardCount > 0 {
        Text(doneCount > 0 ? "\(doneCount)/\(cardCount)" : "\(cardCount)")
          .font(.system(size: 11, weight: .semibold, design: .rounded))
          .foregroundStyle(style.secondaryTextColor)
          .padding(.horizontal, 6)
          .padding(.vertical, 1)
          .background(tint.opacity(0.18), in: Capsule())
      }
    }
    .padding(.horizontal, 10)
    .padding(.vertical, 6)
    .background(.ultraThinMaterial, in: Capsule())
    .environment(\.colorScheme, style.chromeIsDark ? .dark : .light)
    .contentShape(Capsule())
    .gesture(
      DragGesture(minimumDistance: 2, coordinateSpace: .named(BoardCanvasView.space))
        .onChanged { v in
          vm.zoneDrag = (zone.id, CGSize(width: v.translation.width / vm.scale, height: v.translation.height / vm.scale))
        }
        .onEnded { _ in vm.endZoneDrag() }
    )
    .simultaneousGesture(TapGesture(count: 2).onEnded { vm.editingZoneID = zone.id })
    .contextMenu {
      Button("Rename") { vm.editingZoneID = zone.id }
      Menu("Color") {
        ForEach(BoardPalette.zoneColors, id: \.self) { hex in
          Button {
            vm.store.updateZone(zone.id) { $0.colorHex = hex }
          } label: {
            Label(hex, systemImage: zone.colorHex == hex ? "checkmark.circle.fill" : "circle.fill")
          }
        }
      }
      Divider()
      Button("Delete Zone (keep cards)", role: .destructive) { vm.store.deleteZone(zone.id) }
    }
    .help("Drag to move · double-click to rename")
  }

  private func commit() {
    let title = draftTitle.trimmingCharacters(in: .whitespaces)
    if !title.isEmpty, title != zone.title {
      vm.store.updateZone(zone.id) { $0.title = title }
    }
    if vm.editingZoneID == zone.id { vm.editingZoneID = nil }
  }
}
