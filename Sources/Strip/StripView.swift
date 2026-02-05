import AppKit
import SwiftUI

typealias ThumbAction = (CaptureItem) -> Void

struct StripView: View {
  @ObservedObject var library: CaptureLibrary
  @ObservedObject var state: StripState
  @ObservedObject var license: LicenseManager
  let onOpen: ThumbAction
  let onPresent: (CaptureItem) -> Void
  let onHoverChanged: (Bool) -> Void

  @State private var isHovered: Bool = false
  @State private var hoverDebounceTask: Task<Void, Never>? = nil
  @State private var deleteTask: Task<Void, Never>? = nil

  var body: some View {
    let isVertical = state.dockPosition.isVertical
    let thumbSize: CGFloat = isHovered ? 88 : 62
    let spacing: CGFloat = isHovered ? 8 : 6
    let padding: CGFloat = isHovered ? 10 : 6

    GeometryReader { geo in
      let availableLength = isVertical ? geo.size.height : geo.size.width

      // Most recent items (session scoped) in compact mode; full list on expand.
      let sessionItems = library.items.filter { $0.createdAt >= state.sessionStartDate }

      let maxCompactCount = max(1, compactMaxCount(
        availableLength: availableLength,
        thumbSize: thumbSize,
        spacing: spacing,
        padding: padding
      ))

      let displayItems: [CaptureItem] = isHovered
        ? library.items
        : Array(sessionItems.prefix(maxCompactCount))

      StripSurface(isHovered: isHovered) {
        Group {
          if library.items.isEmpty {
            emptyState(title: "No captures yet")
          } else if displayItems.isEmpty {
            // In compact mode we only show "this session" items.
            // If user has older captures but none in-session yet, keep it quiet.
            emptyState(title: "No session captures")
          } else {
            ScrollView(isVertical ? .vertical : .horizontal, showsIndicators: false) {
              if isVertical {
                LazyVStack(spacing: spacing) {
                  thumbs(items: displayItems, size: thumbSize)
                }
                .padding(padding)
              } else {
                LazyHStack(spacing: spacing) {
                  thumbs(items: displayItems, size: thumbSize)
                }
                .padding(padding)
              }
            }
          }
        }
      }
      .contentShape(Rectangle())
      .contextMenu {
        Button("Dock Left") { state.dockPosition = .left }
        Button("Dock Right") { state.dockPosition = .right }
        Button("Dock Top") { state.dockPosition = .top }
        Button("Dock Bottom") { state.dockPosition = .bottom }

        Divider()

        Button("Delete Previous Session Captures…") {
          deleteTask?.cancel()
          deleteTask = Task { @MainActor in
            deletePreviousSessionCaptures()
          }
        }
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      .onHover { hovering in
        // Debounce hover changes to prevent flickering when window resizes
        hoverDebounceTask?.cancel()
        hoverDebounceTask = Task { @MainActor in
          // Small delay on hover-off to prevent flicker during resize
          if !hovering {
            try? await Task.sleep(nanoseconds: 80_000_000) // 80ms
          }
          guard !Task.isCancelled else { return }
          if isHovered != hovering {
            isHovered = hovering
            onHoverChanged(hovering)
          }
        }
      }
      .animation(.spring(response: 0.22, dampingFraction: 0.9), value: isHovered)
    }
  }

  @MainActor
  private func deletePreviousSessionCaptures() {
    let cutoff = state.sessionStartDate
    let oldItems = library.items.filter { $0.createdAt < cutoff }
    guard !oldItems.isEmpty else {
      NSSound.beep()
      return
    }

    let alert = NSAlert()
    alert.alertStyle = .warning
    alert.messageText = "Delete previous session captures?"
    alert.informativeText = "This will permanently delete \(oldItems.count) capture file(s) created before this SnipSnap session (and their .snipsnap.json sidecars). This can’t be undone."
    alert.addButton(withTitle: "Delete")
    alert.addButton(withTitle: "Cancel")

    let resp = alert.runModal()
    guard resp == .alertFirstButtonReturn else { return }

    _ = library.deleteCaptures(olderThan: cutoff)
  }

  private func emptyState(title: String) -> some View {
    let verticalCompact = state.dockPosition.isVertical && !isHovered

    return VStack(spacing: isHovered ? 8 : 6) {
      Image(systemName: "photo.on.rectangle")
        .font(.system(size: isHovered ? 18 : 16, weight: .semibold))
        .foregroundStyle(.secondary)

      if !verticalCompact {
        Text(title)
          .font(.system(size: 12, weight: .semibold))
          .foregroundStyle(.secondary)
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .help(title)
  }

  private func thumbs(items: [CaptureItem], size: CGFloat) -> some View {
    ForEach(items) { item in
      Button {
        guard state.canOpenItemsNow else { return }
        if !FileManager.default.fileExists(atPath: item.url.path) {
          library.refresh()
          NSSound.beep()
          return
        }
        onOpen(item)
      } label: {
        ThumbView(
          image: library.thumbnail(for: item, targetPixelSize: 256),
          isVideo: item.kind == .video,
          size: size
        )
      }
      .buttonStyle(StripThumbButtonStyle())
      .help(item.url.lastPathComponent)
      .contextMenu {
        Button("Open") {
          onOpen(item)
        }

        Button("Reveal in Finder") {
          FinderReveal.reveal(item.url)
        }

        Button("Share…") {
          SharePresenter.share(url: item.url)
        }
        
        Divider()
        
        if license.has(.presentationMode) {
          Button("Present from Here…") {
            onPresent(item)
          }
        } else {
          Button("Present from Here… (Pro)") {
            LicenseWindowController.shared.show(license: license)
          }
        }

        if license.has(.ocrIndexing) {
          let text = library.metadata(for: item)?.ocrText ?? ""
          Button("Copy Text (OCR)") {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
          }
          .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        } else {
          Button("Copy Text (OCR) (Pro)") {
            LicenseWindowController.shared.show(license: license)
          }
        }

        let isVideo = item.kind == .video

        if license.has(.recordingUpgrades) {
          Button("Trim Video…") {
            guard isVideo else { return }
            VideoTrimPresenter.trimVideo(at: item.url)
          }
          .disabled(!isVideo)
        } else {
          Button(isVideo ? "Trim Video… (Pro)" : "Trim Video…") {
            guard isVideo else { return }
            LicenseWindowController.shared.show(license: license)
          }
          .disabled(!isVideo)
        }

        if license.has(.recordingUpgrades) {
          Button("Export GIF…") {
            guard isVideo else { return }
            GIFExportPresenter.exportGIF(fromVideoURL: item.url)
          }
          .disabled(!isVideo)
        } else {
          Button(isVideo ? "Export GIF… (Pro)" : "Export GIF…") {
            guard isVideo else { return }
            LicenseWindowController.shared.show(license: license)
          }
          .disabled(!isVideo)
        }
      }
    }
  }

  private func compactMaxCount(availableLength: CGFloat, thumbSize: CGFloat, spacing: CGFloat, padding: CGFloat) -> Int {
    // Surface has an outer padding of 4 on each side.
    let surfacePadding: CGFloat = 4
    let usable = max(0, availableLength - (surfacePadding * 2) - (padding * 2))
    // Total length for n items is: n*thumb + (n-1)*spacing.
    // Solve for n: n <= (usable + spacing) / (thumb + spacing)
    let denom = max(1, thumbSize + spacing)
    return Int(floor((usable + spacing) / denom))
  }
}

private struct StripSurface<Content: View>: View {
  let isHovered: Bool
  @ViewBuilder let content: () -> Content

  var body: some View {
    content()
      .background(.regularMaterial)
      .clipShape(RoundedRectangle(cornerRadius: isHovered ? 18 : 16, style: .continuous))
      .overlay(
        RoundedRectangle(cornerRadius: isHovered ? 18 : 16, style: .continuous)
          .strokeBorder(Color.primary.opacity(0.10), lineWidth: 1)
      )
      .padding(4)
  }
}

private struct StripThumbButtonStyle: ButtonStyle {
  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
      .background(
        RoundedRectangle(cornerRadius: 12, style: .continuous)
          .fill(Color.primary.opacity(configuration.isPressed ? 0.10 : 0.0))
      )
  }
}

private struct ThumbView: View {
  let image: NSImage?
  let isVideo: Bool
  let size: CGFloat

  var body: some View {
    ZStack(alignment: .bottomTrailing) {
      if let image {
        Image(nsImage: image)
          .resizable()
          .scaledToFill()
          .frame(width: size, height: size)
          .clipped()
          .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
      } else {
        Rectangle()
          .fill(Color.secondary.opacity(0.15))
          .frame(width: size, height: size)
          .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
      }

      if isVideo {
        Image(systemName: "video.fill")
          .font(.system(size: 10, weight: .semibold))
          .padding(6)
          .background(.thinMaterial)
          .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
          .padding(6)
      }
    }
  }
}
