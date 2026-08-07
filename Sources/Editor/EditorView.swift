import AppKit
import QuartzCore
import SwiftUI

struct EditorView: View {
  @ObservedObject var doc: AnnotationDocument

  let onClose: () -> Void

  @State private var hostWindow: NSWindow? = nil
  @State private var showInspector: Bool = true
  @State private var piiListExpanded: Bool = false
  
  // Helper to determine if pan hint should be shown
  private var needsPanHint: Bool {
    // Show hint if image is larger than viewport at current zoom
    let aspectRatio = doc.imageSize.height / doc.imageSize.width
    return aspectRatio > 2.5 || doc.zoomLevel > 1.0
  }

  var body: some View {
    applyChangeHandlers(to: editorLayout)
  }

  private var editorLayout: some View {
    VStack(spacing: 0) {
      // Minimal top bar
      topBar
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial)

      Divider()

      // Redaction suggestions banner (Pro feature)
      if !doc.suggestedRedactions.isEmpty || doc.hasRedactionMetadata {
        redactionSuggestionsBanner
      }

      // Main content: sidebar + canvas + inspector
      HStack(spacing: 0) {
        // Left tool sidebar
        toolSidebar
          .frame(width: 52)
          .background(Color(nsColor: .controlBackgroundColor))

        Divider()

        // Canvas area
        EditorCanvasView(doc: doc)
          .background(Color(nsColor: .windowBackgroundColor))

        // Right inspector panel
        if showInspector {
          Divider()
          inspectorPanel
            .frame(width: 220)
            .background(Color(nsColor: .controlBackgroundColor))
        }
      }
    }
    .frame(minWidth: 800, minHeight: 550)
    .background(WindowAccessor { w in
      hostWindow = w
    })
  }

  // MARK: - Top Bar (minimal)

  private var topBar: some View {
    HStack(spacing: 10) {
      // Undo / Redo Group
      HStack(spacing: 2) {
        ToolbarIconButton(
          icon: "arrow.uturn.backward",
          helpText: "Undo (⌘Z)"
        ) {
          doc.undo()
        }
        .keyboardShortcut("z", modifiers: .command)

        ToolbarIconButton(
          icon: "arrow.uturn.forward",
          helpText: "Redo (⇧⌘Z)"
        ) {
          doc.redo()
        }
        .keyboardShortcut("z", modifiers: [.command, .shift])
      }
      .padding(3)
      .background(
        RoundedRectangle(cornerRadius: 8, style: .continuous)
          .fill(Color.primary.opacity(0.03))
      )
      .overlay(
        RoundedRectangle(cornerRadius: 8, style: .continuous)
          .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
      )

      // Delete button
      ToolbarIconButton(
        icon: "trash",
        isDisabled: doc.selectedID == nil,
        helpText: "Delete selected (Delete)"
      ) {
        doc.deleteSelected()
      }

      Spacer()

      // Document title pill
      HStack(spacing: 6) {
        Image(systemName: "photo")
          .font(.system(size: 10, weight: .semibold))
          .foregroundColor(.secondary)
        Text(doc.sourceURL.lastPathComponent)
          .font(.system(size: 11, weight: .semibold))
          .foregroundColor(.primary.opacity(0.85))
          .lineLimit(1)
      }
      .padding(.horizontal, 10)
      .padding(.vertical, 4)
      .background(
        Capsule()
          .fill(Color.primary.opacity(0.04))
      )
      .overlay(
        Capsule()
          .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
      )

      Spacer()

      // Copy & Export
      HStack(spacing: 6) {
        ToolbarIconButton(
          icon: "doc.on.doc",
          helpText: "Copy to clipboard (⌘C)"
        ) {
          EditorRenderer.copyToClipboard(doc: doc)
        }
        .keyboardShortcut("c", modifiers: .command)

        // Export Menu
        Menu {
          Button("Quick Export (PNG)") {
            quickExport()
          }
          .keyboardShortcut("e", modifiers: .command)

          Divider()

          ForEach(EditorRenderer.ExportFormat.allCases) { format in
            Button("Save as \(format.label)...") {
              exportAs(format: format)
            }
          }

          Divider()

          Button("Share...") {
            shareImage()
          }
          .keyboardShortcut("s", modifiers: [.command, .shift])

          if let mailService = NSSharingService(named: .composeEmail) {
            Button("Email...") {
              shareTo(service: mailService)
            }
          }

          if let messagesService = NSSharingService(named: .composeMessage) {
            Button("Messages...") {
              shareTo(service: messagesService)
            }
          }

          if let airdropService = NSSharingService(named: .sendViaAirDrop) {
            Button("AirDrop...") {
              shareTo(service: airdropService)
            }
          }
        } label: {
          HStack(spacing: 4) {
            Image(systemName: "square.and.arrow.up")
              .font(.system(size: 12, weight: .semibold))
            Text("Export")
              .font(.system(size: 11, weight: .semibold))
            Image(systemName: "chevron.down")
              .font(.system(size: 8, weight: .bold))
              .opacity(0.7)
          }
          .foregroundColor(.white)
          .padding(.horizontal, 10)
          .padding(.vertical, 5)
          .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
              .fill(Color.accentColor)
          )
          .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .help("Export image options")
      }

      Divider().frame(height: 16)

      // Zoom Control Pill
      HStack(spacing: 2) {
        ToolbarIconButton(
          icon: "minus.magnifyingglass",
          helpText: "Zoom Out (⌘-)"
        ) {
          doc.zoomLevel = max(0.1, doc.zoomLevel / 1.2)
        }
        .keyboardShortcut("-", modifiers: .command)

        Menu {
          Button("Fit") {
            doc.fitMode = .fit
            doc.zoomLevel = 1.0
            doc.panOffset = .zero
          }

          Button("Fit Width") {
            doc.fitMode = .fitWidth
            doc.zoomLevel = 1.0
            doc.panOffset = .zero
          }

          Button("Fit Height") {
            doc.fitMode = .fitHeight
            doc.zoomLevel = 1.0
            doc.panOffset = .zero
          }

          Button("Actual Size") {
            doc.fitMode = .actualSize
            doc.zoomLevel = 1.0
            doc.panOffset = .zero
          }

          Divider()

          ForEach([0.25, 0.5, 0.75, 1.0, 1.5, 2.0, 3.0], id: \.self) { zoom in
            Button("\(Int(zoom * 100))%") {
              doc.zoomLevel = zoom
            }
          }
        } label: {
          Text("\(Int(doc.zoomLevel * 100))%")
            .font(.system(size: 11, weight: .medium, design: .monospaced))
            .foregroundColor(.primary.opacity(0.85))
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .background(
              RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(Color.primary.opacity(0.04))
            )
            .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .help("Zoom Level options")

        ToolbarIconButton(
          icon: "plus.magnifyingglass",
          helpText: "Zoom In (⌘+)"
        ) {
          doc.zoomLevel = min(10.0, doc.zoomLevel * 1.2)
        }
        .keyboardShortcut("+", modifiers: .command)
      }
      .padding(3)
      .background(
        RoundedRectangle(cornerRadius: 8, style: .continuous)
          .fill(Color.primary.opacity(0.03))
      )
      .overlay(
        RoundedRectangle(cornerRadius: 8, style: .continuous)
          .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
      )

      if needsPanHint {
        Text("Press H to Pan")
          .font(.system(size: 10, weight: .medium))
          .foregroundColor(.secondary)
          .padding(.horizontal, 6)
          .padding(.vertical, 2)
          .background(Capsule().fill(Color.secondary.opacity(0.1)))
      }

      Divider().frame(height: 16)

      // Toggle inspector
      ToolbarIconButton(
        icon: "sidebar.right",
        isSelected: showInspector,
        helpText: showInspector ? "Hide Inspector" : "Show Inspector"
      ) {
        withAnimation(.easeInOut(duration: 0.2)) {
          showInspector.toggle()
        }
      }
    }
  }

  // MARK: - Redaction Suggestions Banner

  // MARK: - Redaction Suggestions Banner
 
  private var redactionSuggestionsBanner: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack(spacing: 12) {
        Image(systemName: "eye.trianglebadge.exclamationmark")
          .foregroundColor(.orange)
          .font(.system(size: 14, weight: .medium))

        if doc.suggestedRedactions.isEmpty {
          Text("PII suggestions dismissed")
            .font(.system(size: 12))
            .foregroundColor(.secondary)
        } else {
          Button {
            withAnimation(.spring(response: 0.28, dampingFraction: 0.85)) {
              piiListExpanded.toggle()
            }
          } label: {
            HStack(spacing: 6) {
              Image(systemName: piiListExpanded ? "chevron.down" : "chevron.right")
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(.secondary)
              Text("**\(doc.suggestedRedactions.count)** sensitive item\(doc.suggestedRedactions.count == 1 ? "" : "s") detected")
                .font(.system(size: 12))
            }
          }
          .buttonStyle(.plain)
        }

        Spacer()
        
        // Redaction style picker (only when suggestions exist)
        if !doc.suggestedRedactions.isEmpty {
          HStack(spacing: 4) {
            Text("as")
              .font(.system(size: 11))
              .foregroundColor(.secondary)
            Picker("", selection: $doc.redactionStyle) {
              ForEach(BlurMode.allCases) { mode in
                Text(mode.label).tag(mode)
              }
            }
            .labelsHidden()
            .frame(width: 100)
            .font(.system(size: 11))
          }
        }

        // Actions
        Button {
          withAnimation(.spring()) {
            doc.loadRedactionSuggestions()
          }
        } label: {
          Image(systemName: "arrow.clockwise")
        }
        .buttonStyle(.borderless)
        .font(.system(size: 11))
        .foregroundColor(.secondary)
        .help("Reload PII suggestions")
        
        if !doc.suggestedRedactions.isEmpty {
          Button("Dismiss") {
            withAnimation(.spring()) {
              doc.dismissAllRedactions()
              piiListExpanded = false
            }
          }
          .buttonStyle(.borderless)
          .font(.system(size: 12))
          .foregroundColor(.secondary)

          Button {
            withAnimation(.spring()) {
              doc.acceptAllRedactions()
            }
          } label: {
            HStack(spacing: 4) {
              Image(systemName: "eye.slash.fill")
              Text("Apply")
            }
            .font(.system(size: 11, weight: .semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(
              LinearGradient(
                colors: [.orange, .orange.opacity(0.85)],
                startPoint: .top,
                endPoint: .bottom
              )
            )
            .foregroundColor(.white)
            .cornerRadius(6)
            .shadow(color: .orange.opacity(0.15), radius: 1.5, x: 0, y: 1)
          }
          .buttonStyle(.plain)
        }
      }
      
      // Expandable list of suggestions with checkboxes
      if piiListExpanded && !doc.suggestedRedactions.isEmpty {
        VStack(alignment: .leading, spacing: 6) {
          ForEach(doc.suggestedRedactions) { suggestion in
            Button {
              withAnimation(.easeInOut(duration: 0.15)) {
                doc.toggleRedactionSelection(suggestion.id)
              }
            } label: {
              HStack(spacing: 8) {
                Image(systemName: suggestion.isSelected ? "checkmark.circle.fill" : "circle")
                  .font(.system(size: 13, weight: .semibold))
                  .foregroundColor(suggestion.isSelected ? .orange : .secondary.opacity(0.6))

                HStack(spacing: 6) {
                  Image(systemName: suggestion.icon)
                    .font(.system(size: 10))
                    .foregroundColor(suggestion.isSelected ? .orange : .secondary)
                  Text(suggestion.kindLabel)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(suggestion.isSelected ? .primary : .secondary)
                  Text("•")
                    .foregroundColor(.secondary.opacity(0.3))
                  Text(truncatedMatch(suggestion.matchedText))
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(suggestion.isSelected ? .primary : .secondary)
                }

                Spacer()
              }
              .padding(.horizontal, 10)
              .padding(.vertical, 5)
              .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                  .fill(suggestion.isSelected ? Color.orange.opacity(0.08) : Color.primary.opacity(0.03))
              )
              .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                  .strokeBorder(suggestion.isSelected ? Color.orange.opacity(0.2) : Color.clear, lineWidth: 1)
              )
              .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
          }
          
          // Select/Deselect all controls
          HStack(spacing: 12) {
            Button("Select All") {
              withAnimation(.easeInOut(duration: 0.15)) {
                doc.selectAllRedactions()
              }
            }
            .buttonStyle(.link)
            .font(.system(size: 11))
            
            Button("Deselect All") {
              withAnimation(.easeInOut(duration: 0.15)) {
                doc.deselectAllRedactions()
              }
            }
            .buttonStyle(.link)
            .font(.system(size: 11))
          }
          .padding(.top, 2)
        }
      }
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 8)
    .background(Color.orange.opacity(0.05))
    .background(.ultraThinMaterial)
    .overlay(
      VStack {
        Spacer()
        Divider()
      }
    )
  }

  private func truncatedMatch(_ text: String) -> String {
    if text.count <= 16 {
      return text
    }
    let prefix = text.prefix(8)
    let suffix = text.suffix(4)
    return "\(prefix)...\(suffix)"
  }

  // MARK: - Tool Sidebar (left)

  private var toolSidebar: some View {
    ScrollView(.vertical, showsIndicators: false) {
      VStack(spacing: 2) {
        // Selection
        sidebarToolButton(.select)
        sidebarToolButton(.hand)

        Divider().padding(.vertical, 4).padding(.horizontal, 6)

        // Drawing tools
        ForEach([AnnotationTool.rect, .line, .arrow, .freehand], id: \.self) { tool in
          sidebarToolButton(tool)
        }

        Divider().padding(.vertical, 4).padding(.horizontal, 6)

        // Text tools
        ForEach([AnnotationTool.text, .callout, .emoji], id: \.self) { tool in
          sidebarToolButton(tool)
        }

        Divider().padding(.vertical, 4).padding(.horizontal, 6)

        // Pro tools
        ForEach([AnnotationTool.blur, .spotlight, .step], id: \.self) { tool in
          sidebarToolButton(tool)
        }

        Divider().padding(.vertical, 4).padding(.horizontal, 6)

        // Measurement
        sidebarToolButton(.measurement)

        Spacer()
      }
      .padding(.vertical, 8)
      .padding(.horizontal, 4)
    }
  }

  private func sidebarToolButton(_ tool: AnnotationTool) -> some View {
    let isSelected = doc.tool == tool
    let shortcut = tool.shortcutKey ?? ""

    return SidebarToolButton(
      tool: tool,
      isSelected: isSelected,
      shortcut: shortcut
    ) {
      selectTool(tool)
    }
  }

  private func selectTool(_ tool: AnnotationTool) {
    doc.tool = tool
  }

  // MARK: - Inspector Panel (right)

  private var inspectorPanel: some View {
    ScrollView(.vertical, showsIndicators: false) {
      VStack(alignment: .leading, spacing: 16) {
        // Style section - only for tools that use stroke/fill
        if doc.tool.usesStroke || doc.tool.usesFill {
          inspectorSection("Style") {
            styleInspector
          }
        }

        // Tool-specific section
        if hasToolSpecificOptions {
          inspectorSection(doc.tool.label + " Options") {
            toolOptionsInspector
          }
        }

        // Presentation section - always available
        inspectorSection("Presentation") {
          presentationInspector
        }
      }
      .padding(12)
    }
  }

  private func inspectorSection<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      Text(title)
        .font(.system(size: 10, weight: .bold))
        .foregroundColor(.secondary)
        .textCase(.uppercase)
        .padding(.leading, 2)

      VStack(alignment: .leading, spacing: 10) {
        content()
      }
      .padding(10)
      .background(
        RoundedRectangle(cornerRadius: 10, style: .continuous)
          .fill(Color(nsColor: .controlBackgroundColor).opacity(0.7))
      )
      .overlay(
        RoundedRectangle(cornerRadius: 10, style: .continuous)
          .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
      )
    }
  }

  // MARK: - Style Inspector

  private var styleInspector: some View {
    VStack(alignment: .leading, spacing: 10) {
      // Color - for stroke-based tools
      if doc.tool.usesStroke {
        HStack {
          Text("Color")
            .frame(width: 60, alignment: .leading)
          ColorPicker("", selection: Binding(get: {
            doc.stroke.color
          }, set: { new in
            doc.stroke.color = new
          }), supportsOpacity: true)
          .labelsHidden()
        }

        // Stroke width
        HStack {
          Text("Width")
            .frame(width: 60, alignment: .leading)
          Slider(value: Binding(get: {
            Double(doc.stroke.lineWidth)
          }, set: { v in
            doc.stroke.lineWidth = CGFloat(v)
          }), in: 1...18, onEditingChanged: { editing in
            if editing {
              doc.beginEditSessionIfNeeded()
            } else {
              doc.endEditSession()
            }
          })
          Text("\(Int(doc.stroke.lineWidth))")
            .font(.system(size: 11, design: .monospaced))
            .foregroundColor(.secondary)
            .frame(width: 20)
        }
      }

      // Fill - for tools that support fill
      if doc.tool.usesFill {
        HStack {
          Text("Fill")
            .frame(width: 60, alignment: .leading)
          Toggle("", isOn: $doc.fill.enabled)
            .toggleStyle(.switch)
            .controlSize(.small)
          Spacer()
          if doc.fill.enabled {
            ColorPicker("", selection: $doc.fill.color, supportsOpacity: true)
              .labelsHidden()
          }
        }
      }
    }
    .font(.system(size: 12))
  }

  // MARK: - Tool Options Inspector

  private var hasToolSpecificOptions: Bool {
    switch doc.tool {
    case .blur, .spotlight, .step, .arrow, .text, .callout, .freehand, .emoji, .measurement:
      return true
    default:
      return false
    }
  }

  @ViewBuilder
  private var toolOptionsInspector: some View {
    VStack(alignment: .leading, spacing: 10) {
      switch doc.tool {
      case .blur:
        blurOptions
      case .spotlight:
        spotlightOptions
      case .step:
        badgeOptions
      case .arrow:
        arrowOptions
      case .text, .callout:
        textOptions
      case .freehand:
        freehandOptions
      case .emoji:
        emojiOptions
      case .measurement:
        measurementOptions
      default:
        EmptyView()
      }
    }
    .font(.system(size: 12))
  }

  private var blurOptions: some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack {
        Text("Mode")
          .frame(width: 60, alignment: .leading)
        Picker("", selection: $doc.blurMode) {
          ForEach(BlurMode.allCases) { m in
            Text(m.label).tag(m)
          }
        }
        .labelsHidden()
      }

      HStack {
        Text("Amount")
          .frame(width: 60, alignment: .leading)
        Slider(value: Binding(get: {
          Double(doc.blurAmount)
        }, set: { v in
          doc.blurAmount = CGFloat(v)
        }), in: 2...40)
        Text("\(Int(doc.blurAmount))")
          .font(.system(size: 11, design: .monospaced))
          .foregroundColor(.secondary)
          .frame(width: 20)
      }
    }
  }

  private var spotlightOptions: some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack {
        Text("Shape")
          .frame(width: 60, alignment: .leading)
        Picker("", selection: $doc.spotlightShape) {
          ForEach(SpotlightShape.allCases) { s in
            Text(s.label).tag(s)
          }
        }
        .labelsHidden()
      }

      HStack {
        Text("Dim")
          .frame(width: 60, alignment: .leading)
        Slider(value: $doc.spotlightDimmingOpacity, in: 0.3...0.9)
        Text("\(Int(doc.spotlightDimmingOpacity * 100))%")
          .font(.system(size: 11, design: .monospaced))
          .foregroundColor(.secondary)
          .frame(width: 30)
      }

      HStack {
        Text("Border")
          .frame(width: 60, alignment: .leading)
        Toggle("", isOn: $doc.spotlightShowBorder)
          .toggleStyle(.switch)
          .controlSize(.small)
      }
    }
  }

  private var badgeOptions: some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack {
        Text("Fill")
          .frame(width: 60, alignment: .leading)
        ColorPicker("", selection: $doc.stepFillColor, supportsOpacity: true)
          .labelsHidden()
      }

      HStack {
        Text("Text")
          .frame(width: 60, alignment: .leading)
        ColorPicker("", selection: $doc.stepTextColor, supportsOpacity: true)
          .labelsHidden()
      }

      HStack {
        Text("Size")
          .frame(width: 60, alignment: .leading)
        Slider(value: Binding(get: {
          Double(doc.stepRadius)
        }, set: { v in
          doc.stepRadius = CGFloat(v)
        }), in: 10...44)
      }

      HStack {
        Text("Mode")
          .frame(width: 60, alignment: .leading)
        Picker("", selection: $doc.stepMode) {
          ForEach(CounterMode.allCases) { m in
            Text(m.label).tag(m)
          }
        }
        .labelsHidden()
      }
    }
  }

  private var arrowOptions: some View {
    HStack {
      Text("Head")
        .frame(width: 60, alignment: .leading)
      Picker("", selection: $doc.arrowHeadStyle) {
        ForEach(ArrowHeadStyle.allCases) { s in
          Text(s.label).tag(s)
        }
      }
      .labelsHidden()
    }
  }

  private var textOptions: some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack {
        Text("Size")
          .frame(width: 60, alignment: .leading)
        Slider(value: $doc.textFontSize, in: 12...72)
        Text("\(Int(doc.textFontSize))")
          .font(.system(size: 11, design: .monospaced))
          .foregroundColor(.secondary)
          .frame(width: 20)
      }

      HStack {
        Text("Color")
          .frame(width: 60, alignment: .leading)
        ColorPicker("", selection: $doc.textColor, supportsOpacity: true)
          .labelsHidden()
      }

      HStack {
        Text("Highlight")
          .frame(width: 60, alignment: .leading)
        Toggle("", isOn: $doc.textHighlighted)
          .toggleStyle(.switch)
          .controlSize(.small)
      }
    }
  }

  private var freehandOptions: some View {
    HStack {
      Text("Highlighter")
        .frame(width: 70, alignment: .leading)
      Toggle("", isOn: $doc.freehandIsHighlighter)
        .toggleStyle(.switch)
        .controlSize(.small)
    }
  }

  private var emojiOptions: some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack {
        Text("Emoji")
          .frame(width: 60, alignment: .leading)
        EmojiPicker(selected: $doc.selectedEmoji)
      }

      HStack {
        Text("Size")
          .frame(width: 60, alignment: .leading)
        Slider(value: $doc.emojiSize, in: 24...96)
        Text("\(Int(doc.emojiSize))")
          .font(.system(size: 11, design: .monospaced))
          .foregroundColor(.secondary)
          .frame(width: 20)
      }
    }
  }

  private var measurementOptions: some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack {
        Text("Unit")
          .frame(width: 60, alignment: .leading)
        Picker("", selection: $doc.measurementUnit) {
          ForEach(MeasurementUnit.allCases) { u in
            Text(u.fullName).tag(u)
          }
        }
        .labelsHidden()
      }

      HStack {
        Text("Snap")
          .frame(width: 60, alignment: .leading)
        Toggle("", isOn: $doc.measurementSnapEnabled)
          .toggleStyle(.switch)
          .controlSize(.small)
      }

      HStack {
        Text("End caps")
          .frame(width: 60, alignment: .leading)
        Toggle("", isOn: $doc.measurementShowExtensionLines)
          .toggleStyle(.switch)
          .controlSize(.small)
      }
    }
  }

  // MARK: - Presentation Inspector

  private var presentationInspector: some View {
    VStack(alignment: .leading, spacing: 12) {
      // Corners - always visible (works with or without background)
      HStack {
        Text("Corners")
          .frame(width: 70, alignment: .leading)
        Slider(value: $doc.backgroundCornerRadius, in: 0...48)
        Text("\(Int(doc.backgroundCornerRadius))")
          .font(.system(size: 11, design: .monospaced))
          .foregroundColor(.secondary)
          .frame(width: 24)
      }

      // Background
      VStack(alignment: .leading, spacing: 6) {
        HStack {
          Text("Background")
            .frame(width: 70, alignment: .leading)
          Picker("", selection: Binding(get: {
            doc.backgroundStyle
          }, set: { newStyle in
            doc.backgroundStyle = newStyle
            // Load wallpaper when wallpaper style is selected
            if newStyle == .wallpaper {
              doc.loadWallpaper()
            }
          })) {
            ForEach(BackgroundStyle.allCases) { style in
              Text(style.label).tag(style)
            }
          }
          .labelsHidden()
        }

        if doc.backgroundStyle != .none {
          if doc.backgroundStyle == .solid {
            HStack {
              Text("Color")
                .frame(width: 70, alignment: .leading)
              ColorPicker("", selection: $doc.backgroundColor)
                .labelsHidden()
            }
          } else if doc.backgroundStyle == .gradient || doc.backgroundStyle == .mesh {
            HStack {
              Text("Colors")
                .frame(width: 70, alignment: .leading)
              ColorPicker("", selection: $doc.backgroundGradientStart)
                .labelsHidden()
              ColorPicker("", selection: $doc.backgroundGradientEnd)
                .labelsHidden()
            }

            if doc.backgroundStyle == .gradient {
              HStack {
                Text("Direction")
                  .frame(width: 70, alignment: .leading)
                Picker("", selection: $doc.backgroundGradientDirection) {
                  ForEach(GradientDirection.allCases) { d in
                    Text(d.label).tag(d)
                  }
                }
                .labelsHidden()
              }
            }
          } else if doc.backgroundStyle == .wallpaper {
            HStack {
              Text("Source")
                .frame(width: 70, alignment: .leading)
              Text("Main Display")
                .foregroundColor(.secondary)
                .font(.system(size: 11))
            }
          }

          HStack {
            Text("Padding")
              .frame(width: 70, alignment: .leading)
            Slider(value: $doc.backgroundPadding, in: 0...120)
            Text("\(Int(doc.backgroundPadding))")
              .font(.system(size: 11, design: .monospaced))
              .foregroundColor(.secondary)
              .frame(width: 24)
          }

          HStack {
            Text("Shadow")
              .frame(width: 70, alignment: .leading)
            Toggle("", isOn: $doc.backgroundShadowEnabled)
              .toggleStyle(.switch)
              .controlSize(.small)
          }
        }
      }
    }
    .font(.system(size: 12))
  }

  // MARK: - Change Handlers

  private func applyChangeHandlers<V: View>(to view: V) -> some View {
    view
      .onChange(of: doc.hasUnsavedChanges) { _ in
        hostWindow?.isDocumentEdited = doc.hasUnsavedChanges
      }
      .onChange(of: doc.selectedID) { _ in
        doc.syncStyleFromSelectionIfNeeded()
      }
      .onChange(of: doc.stroke) { _ in
        applyStrokeToSelectionIfNeeded()
      }
      .onChange(of: doc.fill) { _ in
        applyFillToSelectionIfNeeded()
      }
      .onChange(of: doc.arrowHeadStyle) { _ in
        applyArrowHeadToSelectionIfNeeded()
      }
      .onChange(of: doc.textColor) { _ in
        applyTextStyleToSelectionIfNeeded()
      }
      .onChange(of: doc.textFontSize) { _ in
        applyTextStyleToSelectionIfNeeded()
      }
      .onChange(of: doc.textHighlighted) { _ in
        applyTextStyleToSelectionIfNeeded()
      }
      .onChange(of: doc.blurMode) { _ in
        applyBlurToSelectionIfNeeded()
      }
      .onChange(of: doc.blurAmount) { _ in
        applyBlurToSelectionIfNeeded()
      }
      .onChange(of: doc.stepRadius) { _ in
        applyStepToSelectionIfNeeded()
      }
      .onChange(of: doc.stepFillColor) { _ in
        applyStepToSelectionIfNeeded()
      }
      .onChange(of: doc.stepTextColor) { _ in
        applyStepToSelectionIfNeeded()
      }
      .onChange(of: doc.stepBorderColor) { _ in
        applyStepToSelectionIfNeeded()
      }
      .onChange(of: doc.stepBorderWidth) { _ in
        applyStepToSelectionIfNeeded()
      }
      .onChange(of: doc.stepMode) { _ in
        applyStepToSelectionIfNeeded()
      }
      .onChange(of: doc.measurementUnit) { _ in
        applyMeasurementToSelectionIfNeeded()
      }
      .onChange(of: doc.measurementShowExtensionLines) { _ in
        applyMeasurementToSelectionIfNeeded()
      }
      .onExitCommand {
        if doc.pendingTextInput != nil {
          doc.cancelPendingTextInput()
        } else {
          onClose()
        }
      }
  }

  // MARK: - Export Actions

  private func quickExport() {
    do {
      let url = try EditorRenderer.exportPNGNextToSource(doc: doc)
      NotificationCenter.default.post(name: .editorDidSave, object: doc.sourceURL)
      NSWorkspace.shared.activateFileViewerSelecting([url])
    } catch {
      let alert = NSAlert(error: error)
      alert.runModal()
    }
  }

  private func exportAs(format: EditorRenderer.ExportFormat) {
    do {
      if let url = try EditorRenderer.exportWithSavePanel(doc: doc, format: format) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
      }
    } catch {
      let alert = NSAlert(error: error)
      alert.runModal()
    }
  }

  private func shareImage() {
    guard let image = EditorRenderer.renderNSImage(doc: doc) else { return }
    guard let window = hostWindow, let contentView = window.contentView else { return }

    let picker = NSSharingServicePicker(items: [image])
    picker.show(relativeTo: .zero, of: contentView, preferredEdge: .minY)
  }

  private func shareTo(service: NSSharingService) {
    guard let image = EditorRenderer.renderNSImage(doc: doc) else { return }
    service.perform(withItems: [image])
  }
}

extension EditorView {
  private func applyStrokeToSelectionIfNeeded() {
    guard let id = doc.selectedID else { return }
    guard let a = doc.annotations.first(where: { $0.id == id }) else { return }
    switch a {
    case .rect:
      doc.updateSelectedMaybeInSession { ann in
        if case .rect(var r) = ann {
          r.stroke = doc.stroke
          ann = .rect(r)
        }
      }
    case .ellipse:
      doc.updateSelectedMaybeInSession { ann in
        if case .ellipse(var e) = ann {
          e.stroke = doc.stroke
          ann = .ellipse(e)
        }
      }
    case .line:
      doc.updateSelectedMaybeInSession { ann in
        if case .line(var l) = ann {
          l.stroke = doc.stroke
          ann = .line(l)
        }
      }
    case .arrow:
      doc.updateSelectedMaybeInSession { ann in
        if case .arrow(var ar) = ann {
          ar.stroke = doc.stroke
          ann = .arrow(ar)
        }
      }
    case .freehand:
      doc.updateSelectedMaybeInSession { ann in
        if case .freehand(var f) = ann {
          f.stroke = doc.stroke
          ann = .freehand(f)
        }
      }
    case .callout:
      doc.updateSelectedMaybeInSession { ann in
        if case .callout(var c) = ann {
          c.stroke = doc.stroke
          ann = .callout(c)
        }
      }
    case .text:
      break
    case .blur:
      break
    case .spotlight:
      doc.updateSelectedMaybeInSession { ann in
        if case .spotlight(var sp) = ann, doc.spotlightShowBorder {
          sp.borderStroke = doc.stroke
          ann = .spotlight(sp)
        }
      }
    case .step:
      break
    case .counter:
      break
    case .emoji:
      break
    case .measurement:
      doc.updateSelectedMaybeInSession { ann in
        if case .measurement(var m) = ann {
          m.stroke = doc.stroke
          ann = .measurement(m)
        }
      }
    case .imageLayer:
      break
    }
  }

  private func applyFillToSelectionIfNeeded() {
    guard let id = doc.selectedID else { return }
    guard let a = doc.annotations.first(where: { $0.id == id }) else { return }
    switch a {
    case .rect:
      doc.updateSelectedMaybeInSession { ann in
        if case .rect(var r) = ann {
          r.fill = doc.fill
          ann = .rect(r)
        }
      }
    case .ellipse:
      doc.updateSelectedMaybeInSession { ann in
        if case .ellipse(var e) = ann {
          e.fill = doc.fill
          ann = .ellipse(e)
        }
      }
    case .callout:
      doc.updateSelectedMaybeInSession { ann in
        if case .callout(var c) = ann {
          c.fill = doc.fill
          ann = .callout(c)
        }
      }
    default:
      break
    }
  }

  private func applyArrowHeadToSelectionIfNeeded() {
    guard let id = doc.selectedID else { return }
    guard let a = doc.annotations.first(where: { $0.id == id }) else { return }
    guard case .arrow = a else { return }

    doc.updateSelectedMaybeInSession { ann in
      if case .arrow(var ar) = ann {
        ar.headStyle = doc.arrowHeadStyle
        ann = .arrow(ar)
      }
    }
  }

  private func applyTextStyleToSelectionIfNeeded() {
    guard let id = doc.selectedID else { return }
    guard let a = doc.annotations.first(where: { $0.id == id }) else { return }

    switch a {
    case .text:
      doc.updateSelectedMaybeInSession { ann in
        if case .text(var t) = ann {
          t.color = doc.textColor
          t.fontSize = doc.textFontSize
          t.highlighted = doc.textHighlighted
          ann = .text(t)
        }
      }
    case .callout:
      doc.updateSelectedMaybeInSession { ann in
        if case .callout(var c) = ann {
          c.textColor = doc.textColor
          c.fontSize = doc.textFontSize
          ann = .callout(c)
        }
      }
    default:
      break
    }
  }

  private func applyBlurToSelectionIfNeeded() {
    guard let id = doc.selectedID else { return }
    guard let a = doc.annotations.first(where: { $0.id == id }) else { return }
    guard case .blur = a else { return }

    doc.updateSelectedMaybeInSession { ann in
      if case .blur(var b) = ann {
        b.mode = doc.blurMode
        b.amount = doc.blurAmount
        ann = .blur(b)
      }
    }
  }

  private func applyStepToSelectionIfNeeded() {
    guard let id = doc.selectedID else { return }
    guard let a = doc.annotations.first(where: { $0.id == id }) else { return }
    guard case .step = a else { return }

    doc.updateSelectedMaybeInSession { ann in
      if case .step(var s) = ann {
        s.radius = doc.stepRadius
        s.fillColor = doc.stepFillColor
        s.textColor = doc.stepTextColor
        s.borderColor = doc.stepBorderColor
        s.borderWidth = doc.stepBorderWidth
        s.mode = doc.stepMode
        ann = .step(s)
      }
    }
  }

  private func applyMeasurementToSelectionIfNeeded() {
    guard let id = doc.selectedID else { return }
    guard let a = doc.annotations.first(where: { $0.id == id }) else { return }
    guard case .measurement = a else { return }

    doc.updateSelectedMaybeInSession { ann in
      if case .measurement(var m) = ann {
        m.unit = doc.measurementUnit
        m.ppi = doc.measurementPPI
        m.baseFontSize = doc.measurementBaseFontSize
        m.showExtensionLines = doc.measurementShowExtensionLines
        m.stroke = doc.stroke
        ann = .measurement(m)
      }
    }
  }
}
// MARK: - Reusable Toolbar Controls

private struct ToolbarIconButton: View {
  let icon: String
  var title: String? = nil
  var isSelected: Bool = false
  var isDisabled: Bool = false
  var isAccent: Bool = false
  let helpText: String
  let action: () -> Void

  @State private var isHovered: Bool = false

  var body: some View {
    Button(action: action) {
      HStack(spacing: 5) {
        Image(systemName: icon)
          .font(.system(size: 12, weight: .medium))
        if let title {
          Text(title)
            .font(.system(size: 11, weight: .medium))
        }
      }
      .foregroundColor(foregroundColor)
      .padding(.horizontal, title != nil ? 9 : 7)
      .padding(.vertical, 5)
      .frame(minWidth: 28, minHeight: 28)
      .background(
        RoundedRectangle(cornerRadius: 6, style: .continuous)
          .fill(backgroundColor)
      )
      .overlay(
        RoundedRectangle(cornerRadius: 6, style: .continuous)
          .strokeBorder(borderColor, lineWidth: 1)
      )
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .disabled(isDisabled)
    .help(helpText)
    .onHover { hover in
      withAnimation(.easeInOut(duration: 0.12)) {
        isHovered = hover
      }
    }
  }

  private var foregroundColor: Color {
    if isDisabled { return .secondary.opacity(0.35) }
    if isAccent { return .white }
    if isSelected { return .accentColor }
    return .primary.opacity(isHovered ? 0.95 : 0.75)
  }

  private var backgroundColor: Color {
    if isDisabled { return .clear }
    if isAccent {
      return isHovered ? Color.accentColor.opacity(0.88) : Color.accentColor
    }
    if isSelected {
      return Color.accentColor.opacity(0.14)
    }
    return isHovered ? Color.primary.opacity(0.09) : Color.primary.opacity(0.03)
  }

  private var borderColor: Color {
    if isAccent { return .clear }
    if isSelected { return Color.accentColor.opacity(0.3) }
    return isHovered ? Color.primary.opacity(0.12) : Color.clear
  }
}

private struct SidebarToolButton: View {
  let tool: AnnotationTool
  let isSelected: Bool
  let shortcut: String
  let action: () -> Void

  @State private var isHovered: Bool = false

  var body: some View {
    Button(action: action) {
      VStack(spacing: 2) {
        Image(systemName: tool.icon)
          .font(.system(size: 14, weight: isSelected ? .bold : .medium))
        if !shortcut.isEmpty {
          Text(shortcut)
            .font(.system(size: 8, weight: .semibold, design: .rounded))
            .foregroundColor(isSelected ? .white.opacity(0.85) : .secondary.opacity(0.75))
        }
      }
      .frame(width: 38, height: 38)
      .background(
        RoundedRectangle(cornerRadius: 8, style: .continuous)
          .fill(isSelected ? Color.accentColor : (isHovered ? Color.primary.opacity(0.08) : Color.clear))
      )
      .overlay(
        RoundedRectangle(cornerRadius: 8, style: .continuous)
          .strokeBorder(isSelected ? Color.accentColor.opacity(0.4) : (isHovered ? Color.primary.opacity(0.12) : Color.clear), lineWidth: 1)
      )
      .foregroundColor(isSelected ? .white : (isHovered ? .primary : .primary.opacity(0.8)))
      .shadow(color: isSelected ? Color.accentColor.opacity(0.25) : .clear, radius: 3, x: 0, y: 1)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .frame(maxWidth: .infinity, minHeight: 42)
    .contentShape(Rectangle())
    .onHover { hovering in
      withAnimation(.easeInOut(duration: 0.12)) {
        isHovered = hovering
      }
    }
    .help(shortcut.isEmpty ? tool.label : "\(tool.label) – Press \(shortcut)")
  }
}

// MARK: - Emoji Picker Component

private struct EmojiPicker: View {
  @Binding var selected: String

  private let popularEmojis = ["👍", "👎", "👆", "👇", "👈", "👉", "✅", "❌", "⭐", "❗", "❓", "💡", "🔥", "❤️", "😊", "🎉"]

  var body: some View {
    Menu {
      ForEach(popularEmojis, id: \.self) { emoji in
        Button(emoji) {
          selected = emoji
        }
      }

      Divider()

      Button("Character Viewer...") {
        NSApp.orderFrontCharacterPalette(nil)
      }
    } label: {
      Text(selected)
        .font(.system(size: 18))
        .frame(width: 28, height: 28)
    }
    .menuStyle(.borderlessButton)
    .frame(width: 36)
  }
}

// MARK: - Toolbar Width Tracking

private struct ToolbarIntrinsicWidthPreferenceKey: PreferenceKey {
  static var defaultValue: CGFloat = 0
  static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
    value = max(value, nextValue())
  }
}

private struct ToolbarIntrinsicWidthReader: View {
  var body: some View {
    GeometryReader { proxy in
      Color.clear
        .preference(key: ToolbarIntrinsicWidthPreferenceKey.self, value: proxy.size.width)
    }
  }
}

private struct WindowAccessor: NSViewRepresentable {
  let callback: (NSWindow?) -> Void

  func makeNSView(context: Context) -> NSView {
    let v = NSView()
    DispatchQueue.main.async { [weak v] in
      self.callback(v?.window)
    }
    return v
  }

  func updateNSView(_ nsView: NSView, context: Context) {
    DispatchQueue.main.async { [weak nsView] in
      self.callback(nsView?.window)
    }
  }
}
