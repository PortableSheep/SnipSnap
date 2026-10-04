import AppKit
import SwiftUI
import VisionKit

/// Large in-board inspector for a card: full image with Live Text, title, notes, and source context.
struct CardDetailView: View {
  let card: BoardCard
  let vm: BoardViewModel
  let style: BoardThemeStyle

  @State private var title = ""
  @State private var note = ""
  @State private var showOCR = false

  var body: some View {
    ZStack {
      Color.black.opacity(0.55)
        .ignoresSafeArea()
        .contentShape(Rectangle())
        .onTapGesture { close() }

      HStack(spacing: 0) {
        preview
          .frame(maxWidth: .infinity, maxHeight: .infinity)
          .background(Color.black.opacity(0.35))
        sidebar
          .frame(width: 320)
      }
      .frame(
        width: min(1200, vm.canvasSize.width * 0.86),
        height: min(820, vm.canvasSize.height * 0.82)
      )
      .background(.regularMaterial)
      .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
      .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(.white.opacity(0.12)))
      .shadow(color: .black.opacity(0.5), radius: 40, y: 20)
      .environment(\.colorScheme, .dark)
    }
    .onAppear {
      title = card.title ?? ""
      note = card.note ?? ""
    }
    .onDisappear(perform: commit)
  }

  @ViewBuilder
  private var preview: some View {
    switch card.kind {
    case .capture:
      if let url = vm.store.imageURL(for: card), let image = NSImage(contentsOf: url) {
        LiveTextImageView(image: image)
          .padding(16)
      }
    case .link:
      VStack(spacing: 16) {
        if let preview = vm.store.image(named: card.previewAsset) {
          Image(nsImage: preview).resizable().aspectRatio(contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        if let url = card.url {
          Button(url.absoluteString) { NSWorkspace.shared.open(url) }
            .buttonStyle(.link)
        }
      }
      .padding(24)
    case .text, .note:
      ScrollView {
        Text(card.text ?? "")
          .font(.system(size: 15))
          .textSelection(.enabled)
          .frame(maxWidth: .infinity, alignment: .leading)
          .padding(24)
      }
    }
  }

  private var sidebar: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 16) {
        HStack {
          Spacer()
          Button(action: close) {
            Image(systemName: "xmark").font(.system(size: 12, weight: .bold))
              .frame(width: 26, height: 26)
              .background(.white.opacity(0.1), in: Circle())
          }
          .buttonStyle(.plain)
          .help("Close (Esc)")
        }

        TextField("Title", text: $title)
          .textFieldStyle(.plain)
          .font(.system(size: 18, weight: .bold, design: .rounded))
          .onSubmit(commit)

        if let todo = card.todo {
          HStack(spacing: 8) {
            TodoCheckbox(state: todo) { vm.toggleTodo(card.id) }
            Text(todo == .done ? "Done" : "To do").font(.system(size: 13, weight: .medium))
          }
        }

        VStack(alignment: .leading, spacing: 6) {
          sectionLabel("Notes")
          TextEditor(text: $note)
            .font(.system(size: 13))
            .scrollContentBackground(.hidden)
            .padding(6)
            .frame(minHeight: 90)
            .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
        }

        if let source = card.source {
          VStack(alignment: .leading, spacing: 6) {
            sectionLabel("Context")
            if let app = source.appName {
              Label(app, systemImage: "app")
            }
            if let page = source.pageURL {
              Button {
                NSWorkspace.shared.open(page)
              } label: {
                Label(source.pageTitle ?? page.absoluteString, systemImage: "safari")
                  .lineLimit(2)
              }
              .buttonStyle(.link)
            }
            Label(source.capturedAt.formatted(date: .abbreviated, time: .shortened), systemImage: "clock")
          }
          .font(.system(size: 12))
          .foregroundStyle(.secondary)
        }

        if let items = card.detectedItems, !items.isEmpty {
          VStack(alignment: .leading, spacing: 6) {
            sectionLabel("Found in this card")
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
              Button {
                if let url = item.actionURL { NSWorkspace.shared.open(url) }
              } label: {
                Label(item.value, systemImage: item.kind == .link ? "link" : item.kind == .email ? "envelope" : "phone")
                  .lineLimit(1)
                  .truncationMode(.middle)
              }
              .buttonStyle(.link)
              .font(.system(size: 12))
            }
          }
        }

        if let ocr = card.ocrText, !ocr.isEmpty {
          DisclosureGroup("Recognized text", isExpanded: $showOCR) {
            Text(ocr)
              .font(.system(size: 11))
              .textSelection(.enabled)
              .frame(maxWidth: .infinity, alignment: .leading)
          }
          .font(.system(size: 12, weight: .semibold))
        }

        Divider()

        VStack(alignment: .leading, spacing: 8) {
          actionButton("Pop Out (Always on Top)", "pin") { commit(); vm.actions.popOut(card.id) }
          if card.kind == .capture {
            actionButton("Edit in Editor", "pencil.tip.crop.circle") { commit(); vm.actions.openInEditor(card.id) }
          }
          actionButton("Copy", "doc.on.doc") { vm.copy(card.id) }
          if card.copyableText != nil {
            actionButton("Copy Text", "text.viewfinder") { vm.copyText(card.id) }
          }
          if card.todo == nil {
            actionButton("Make Todo", "checkmark.circle") { vm.setTodo([card.id], enabled: true) }
          }
          actionButton("Delete", "trash", role: .destructive) { vm.delete([card.id]) }
        }
      }
      .padding(18)
    }
  }

  private func sectionLabel(_ text: String) -> some View {
    Text(text.uppercased())
      .font(.system(size: 10, weight: .bold))
      .foregroundStyle(.secondary)
  }

  private func actionButton(_ title: String, _ icon: String, role: ButtonRole? = nil, action: @escaping () -> Void) -> some View {
    Button(role: role, action: action) {
      Label(title, systemImage: icon)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .foregroundStyle(role == .destructive ? Color.red : Color.primary)
    .font(.system(size: 13))
  }

  private func commit() {
    let t = title.trimmingCharacters(in: .whitespacesAndNewlines)
    let n = note.trimmingCharacters(in: .whitespacesAndNewlines)
    guard vm.store.card(card.id) != nil else { return }
    if (card.title ?? "") != t || (card.note ?? "") != n {
      vm.store.update(card.id) { c in
        c.title = t.isEmpty ? nil : t
        c.note = n.isEmpty ? nil : n
      }
    }
  }

  private func close() {
    commit()
    vm.detailCardID = nil
  }
}

/// NSImageView with VisionKit's Live Text overlay (select text, data detectors, QR codes).
struct LiveTextImageView: NSViewRepresentable {
  let image: NSImage

  func makeNSView(context: Context) -> LiveTextContainer {
    LiveTextContainer()
  }

  func updateNSView(_ nsView: LiveTextContainer, context: Context) {
    nsView.setImage(image)
  }
}

final class LiveTextContainer: NSView {
  private let imageView = NSImageView()
  private let overlay = ImageAnalysisOverlayView()
  private var analysisTask: Task<Void, Never>?
  private weak var currentImage: NSImage?

  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    imageView.imageScaling = .scaleProportionallyUpOrDown
    imageView.translatesAutoresizingMaskIntoConstraints = false
    addSubview(imageView)
    NSLayoutConstraint.activate([
      imageView.leadingAnchor.constraint(equalTo: leadingAnchor),
      imageView.trailingAnchor.constraint(equalTo: trailingAnchor),
      imageView.topAnchor.constraint(equalTo: topAnchor),
      imageView.bottomAnchor.constraint(equalTo: bottomAnchor),
    ])
    overlay.autoresizingMask = [.width, .height]
    overlay.frame = imageView.bounds
    overlay.trackingImageView = imageView
    overlay.preferredInteractionTypes = .automatic
    imageView.addSubview(overlay)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError() }

  deinit { analysisTask?.cancel() }

  func setImage(_ image: NSImage) {
    guard image !== currentImage else { return }
    currentImage = image
    imageView.image = image
    overlay.analysis = nil
    analysisTask?.cancel()
    guard ImageAnalyzer.isSupported else { return }
    analysisTask = Task { @MainActor [weak self] in
      let analyzer = ImageAnalyzer()
      let config = ImageAnalyzer.Configuration([.text, .machineReadableCode])
      guard let analysis = try? await analyzer.analyze(image, orientation: .up, configuration: config),
            !Task.isCancelled else { return }
      self?.overlay.analysis = analysis
    }
  }
}
