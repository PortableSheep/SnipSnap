import Carbon
import SwiftUI

struct PreferencesRootView: View {
  @ObservedObject var prefs: OverlayPreferencesStore
  @ObservedObject var proPrefs: ProPreferencesStore
  @ObservedObject var license: LicenseManager
  @ObservedObject var hotkeyPrefs = HotkeyPreferencesStore.shared

  @State private var page: PreferencesPage = .general

  var body: some View {
    HStack(spacing: 0) {
      // Sidebar
      sidebar
        .frame(width: 180)

      Divider()

      // Content
      content
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    .frame(width: 750, height: 520)
    .background(Color(NSColor.windowBackgroundColor))
  }

  private var sidebar: some View {
    VStack(alignment: .leading, spacing: 4) {
      ForEach(PreferencesPage.allCases) { p in
        sidebarButton(for: p)
      }

      Spacer()

      // Pro badge at bottom
      if license.isProUnlocked {
        HStack(spacing: 6) {
          Image(systemName: "star.fill")
            .foregroundColor(.yellow)
          Text("Pro Active")
            .font(.system(size: 11, weight: .medium))
            .foregroundColor(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
      }
    }
    .padding(.vertical, 12)
    .padding(.horizontal, 8)
    .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
  }

  private func sidebarButton(for p: PreferencesPage) -> some View {
    Button {
      withAnimation(.easeInOut(duration: 0.15)) {
        page = p
      }
    } label: {
      HStack(spacing: 10) {
        Image(systemName: p.icon)
          .font(.system(size: 14))
          .frame(width: 20)
          .foregroundColor(page == p ? .accentColor : .secondary)

        Text(p.title)
          .font(.system(size: 13, weight: page == p ? .medium : .regular))

        Spacer()
      }
      .padding(.horizontal, 10)
      .padding(.vertical, 8)
      .background(
        RoundedRectangle(cornerRadius: 6)
          .fill(page == p ? Color.accentColor.opacity(0.15) : Color.clear)
      )
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
  }

  @ViewBuilder
  private var content: some View {
    ScrollView {
      switch page {
      case .general:
        GeneralPreferencesView(proPrefs: proPrefs, license: license)
      case .overlays:
        OverlaysPreferencesView(prefs: prefs)
      case .shortcuts:
        ShortcutsPreferencesView(hotkeyPrefs: hotkeyPrefs)
      case .about:
        AboutPreferencesView(license: license)
      }
    }
    .padding(24)
  }
}

// MARK: - General Preferences

private struct GeneralPreferencesView: View {
  @ObservedObject var proPrefs: ProPreferencesStore
  @ObservedObject var license: LicenseManager
  @AppStorage("LaunchAtLogin") private var launchAtLogin = false

  var body: some View {
    VStack(alignment: .leading, spacing: 24) {
      // Header
      PreferenceHeader(title: "General", subtitle: "Basic app settings and behaviors")

      // Startup
      PreferenceSection("Startup") {
        PreferenceRow(icon: "power", title: "Launch at login", subtitle: "Start SnipSnap when you log in") {
          Toggle("", isOn: $launchAtLogin)
            .toggleStyle(.switch)
            .controlSize(.small)
        }
      }

      // Pro Features
      PreferenceSection("Pro Features") {
        PreferenceRow(icon: "text.viewfinder", title: "OCR + Indexing", subtitle: "Extract text from captures for search") {
          Toggle("", isOn: $proPrefs.enableOCRIndexing)
            .toggleStyle(.switch)
            .controlSize(.small)
            .disabled(!license.has(.ocrIndexing))
        }

        PreferenceRow(icon: "eye.trianglebadge.exclamationmark", title: "Smart Redaction", subtitle: "Detect sensitive info (emails, keys)") {
          Toggle("", isOn: $proPrefs.enableSmartRedaction)
            .toggleStyle(.switch)
            .controlSize(.small)
            .disabled(!license.has(.smartRedaction))
        }

        PreferenceRow(icon: "icloud", title: "Cloud Sync", subtitle: "Mirror captures to iCloud Drive") {
          Toggle("", isOn: $proPrefs.enableCloudSync)
            .toggleStyle(.switch)
            .controlSize(.small)
            .disabled(!license.has(.cloudSync))
        }

        if !license.isProUnlocked {
          Button {
            LicenseWindowController.shared.show(license: license)
          } label: {
            HStack {
              Image(systemName: "star.fill")
                .foregroundColor(.yellow)
              Text("Unlock Pro Features")
                .font(.system(size: 12, weight: .medium))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: 6).fill(Color.accentColor.opacity(0.15)))
          }
          .buttonStyle(.plain)
          .padding(.top, 4)
        }
      }

      Spacer()
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }
}

// MARK: - Overlays Preferences

private struct OverlaysPreferencesView: View {
  @ObservedObject var prefs: OverlayPreferencesStore

  var body: some View {
    VStack(alignment: .leading, spacing: 20) {
      PreferenceHeader(title: "Overlays", subtitle: "Click and keystroke visualization during recording")

      // Settings
      PreferenceSection("Display") {
        PreferenceRow(icon: "cursorarrow.click", title: "Click Overlay", subtitle: "Show ripple effect on mouse clicks") {
          Toggle("", isOn: $prefs.showClickOverlay)
            .toggleStyle(.switch)
            .controlSize(.small)
        }

        PreferenceRow(icon: "keyboard", title: "Keystroke HUD", subtitle: "Display pressed keys on screen") {
          Toggle("", isOn: $prefs.showKeystrokeHUD)
            .toggleStyle(.switch)
            .controlSize(.small)
        }
      }

      PreferenceSection("Appearance") {
        PreferenceRow(icon: "paintpalette", title: "Click Color", subtitle: "Color of the ripple effect") {
          ColorPicker("", selection: $prefs.clickColor, supportsOpacity: true)
            .labelsHidden()
        }

        PreferenceRow(icon: "rectangle.bottomhalf.filled", title: "HUD Position", subtitle: "Where to show the keystroke HUD") {
          Picker("", selection: $prefs.hudPlacement) {
            ForEach(HUDPlacement.allCases) { p in
              Text(p.label).tag(p)
            }
          }
          .labelsHidden()
          .frame(width: 140)
        }
      }

      // Preview
      PreferenceSection("Preview") {
        OverlayPreviewView(prefs: prefs)
          .frame(height: 100)
          .frame(maxWidth: .infinity)
      }

      Text("Overlays require Accessibility permission.")
        .font(.system(size: 11))
        .foregroundColor(.secondary)

      Spacer()
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }
}

// MARK: - Shortcuts Preferences

private struct ShortcutsPreferencesView: View {
  @ObservedObject var hotkeyPrefs: HotkeyPreferencesStore
  @State private var recordingAction: HotkeyAction?
  @State private var showConflictAlert = false
  @State private var conflictMessage = ""

  var body: some View {
    VStack(alignment: .leading, spacing: 24) {
      PreferenceHeader(title: "Shortcuts", subtitle: "Customize global keyboard shortcuts")

      PreferenceSection("Global Hotkeys") {
        ForEach(HotkeyAction.allCases) { action in
          ShortcutRow(
            action: action,
            binding: hotkeyPrefs.binding(for: action),
            isRecording: recordingAction == action,
            onStartRecording: {
              recordingAction = action
            },
            onStopRecording: { newBinding in
              if let newBinding {
                // Check for conflicts
                for otherAction in HotkeyAction.allCases where otherAction != action {
                  if hotkeyPrefs.binding(for: otherAction) == newBinding {
                    conflictMessage = "This shortcut is already used by \"\(otherAction.label)\""
                    showConflictAlert = true
                    recordingAction = nil
                    return
                  }
                }
                hotkeyPrefs.setBinding(newBinding, for: action)
              }
              recordingAction = nil
            }
          )
        }
      }

      HStack {
        Button("Reset to Defaults") {
          hotkeyPrefs.resetToDefaults()
        }
        .buttonStyle(.plain)
        .foregroundColor(.accentColor)

        Spacer()

        Text("Click a shortcut, then press new keys")
          .font(.system(size: 11))
          .foregroundColor(.secondary)
      }

      Spacer()
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .alert("Shortcut Conflict", isPresented: $showConflictAlert) {
      Button("OK", role: .cancel) {}
    } message: {
      Text(conflictMessage)
    }
  }
}

private struct ShortcutRow: View {
  let action: HotkeyAction
  let binding: HotkeyBinding
  let isRecording: Bool
  let onStartRecording: () -> Void
  let onStopRecording: (HotkeyBinding?) -> Void

  var body: some View {
    HStack(spacing: 12) {
      Image(systemName: action.icon)
        .font(.system(size: 14))
        .foregroundColor(.secondary)
        .frame(width: 24)

      VStack(alignment: .leading, spacing: 2) {
        Text(action.label)
          .font(.system(size: 13))
        Text("Global hotkey")
          .font(.system(size: 11))
          .foregroundColor(.secondary)
      }

      Spacer()

      ShortcutRecorderButton(
        binding: binding,
        isRecording: isRecording,
        onStartRecording: onStartRecording,
        onStopRecording: onStopRecording
      )
    }
    .padding(.vertical, 6)
  }
}

private struct ShortcutRecorderButton: View {
  let binding: HotkeyBinding
  let isRecording: Bool
  let onStartRecording: () -> Void
  let onStopRecording: (HotkeyBinding?) -> Void

  var body: some View {
    Button {
      if isRecording {
        onStopRecording(nil)
      } else {
        onStartRecording()
      }
    } label: {
      HStack(spacing: 4) {
        if isRecording {
          Text("Press keys…")
            .font(.system(size: 12))
            .foregroundColor(.accentColor)
        } else {
          Text(binding.displayString)
            .font(.system(size: 12, weight: .medium, design: .monospaced))
        }
      }
      .padding(.horizontal, 12)
      .padding(.vertical, 6)
      .background(
        RoundedRectangle(cornerRadius: 6)
          .fill(isRecording ? Color.accentColor.opacity(0.2) : Color(NSColor.controlBackgroundColor))
      )
      .overlay(
        RoundedRectangle(cornerRadius: 6)
          .stroke(isRecording ? Color.accentColor : Color.gray.opacity(0.3), lineWidth: 1)
      )
    }
    .buttonStyle(.plain)
    .background(
      ShortcutRecorderKeyHandler(isRecording: isRecording, onKeyPress: onStopRecording)
    )
  }
}

private struct ShortcutRecorderKeyHandler: NSViewRepresentable {
  let isRecording: Bool
  let onKeyPress: (HotkeyBinding?) -> Void

  func makeNSView(context: Context) -> KeyRecorderView {
    KeyRecorderView(onKeyPress: onKeyPress)
  }

  func updateNSView(_ nsView: KeyRecorderView, context: Context) {
    nsView.isRecording = isRecording
    nsView.onKeyPress = onKeyPress
    if isRecording {
      nsView.window?.makeFirstResponder(nsView)
    }
  }

  class KeyRecorderView: NSView {
    var isRecording = false
    var onKeyPress: (HotkeyBinding?) -> Void

    init(onKeyPress: @escaping (HotkeyBinding?) -> Void) {
      self.onKeyPress = onKeyPress
      super.init(frame: .zero)
    }

    required init?(coder: NSCoder) { fatalError() }

    override var acceptsFirstResponder: Bool { isRecording }

    override func keyDown(with event: NSEvent) {
      guard isRecording else {
        super.keyDown(with: event)
        return
      }

      // Escape cancels
      if event.keyCode == UInt16(kVK_Escape) {
        onKeyPress(nil)
        return
      }

      // Build modifiers
      var mods: UInt32 = 0
      if event.modifierFlags.contains(.command) { mods |= UInt32(cmdKey) }
      if event.modifierFlags.contains(.shift) { mods |= UInt32(shiftKey) }
      if event.modifierFlags.contains(.option) { mods |= UInt32(optionKey) }
      if event.modifierFlags.contains(.control) { mods |= UInt32(controlKey) }

      // Require at least Cmd or Ctrl for global hotkeys
      if mods & UInt32(cmdKey) == 0 && mods & UInt32(controlKey) == 0 {
        NSSound.beep()
        return
      }

      let binding = HotkeyBinding(keyCode: UInt32(event.keyCode), modifiers: mods)
      onKeyPress(binding)
    }
  }
}

// MARK: - About Preferences

private struct AboutPreferencesView: View {
  @ObservedObject var license: LicenseManager

  var body: some View {
    VStack(alignment: .leading, spacing: 24) {
      // App Icon & Name
      HStack(spacing: 16) {
        Image(nsImage: NSApp.applicationIconImage)
          .resizable()
          .frame(width: 64, height: 64)

        VStack(alignment: .leading, spacing: 4) {
          Text("SnipSnap")
            .font(.system(size: 24, weight: .bold))
          Text("Version 1.0.0")
            .font(.system(size: 13))
            .foregroundColor(.secondary)
          if license.isProUnlocked {
            HStack(spacing: 4) {
              Image(systemName: "star.fill")
                .foregroundColor(.yellow)
              Text("Pro")
                .font(.system(size: 12, weight: .semibold))
            }
          }
        }
      }

      Divider()

      Text("A fast, professional-grade screen capture and annotation tool for macOS.")
        .font(.system(size: 13))
        .foregroundColor(.secondary)
        .fixedSize(horizontal: false, vertical: true)

      VStack(alignment: .leading, spacing: 8) {
        Text("Features")
          .font(.system(size: 13, weight: .semibold))

        FeatureRow(icon: "camera.viewfinder", text: "Region & Window Screenshots")
        FeatureRow(icon: "record.circle", text: "Screen Recording with Audio")
        FeatureRow(icon: "pencil.and.outline", text: "Powerful Annotation Editor")
        FeatureRow(icon: "cursorarrow.click.2", text: "Click & Keystroke Visualization")
        FeatureRow(icon: "star.fill", text: "Pro: GIF Export, Presentation Mode, OCR", isPro: true)
      }

      Spacer()

      HStack {
        Text("© 2026 SnipSnap")
          .font(.system(size: 11))
          .foregroundColor(.secondary)

        Spacer()

        Button("Visit Website") {
          if let url = URL(string: "https://snipsnap.app") {
            NSWorkspace.shared.open(url)
          }
        }
        .buttonStyle(.plain)
        .foregroundColor(.accentColor)
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }
}

private struct FeatureRow: View {
  let icon: String
  let text: String
  var isPro: Bool = false

  var body: some View {
    HStack(spacing: 8) {
      Image(systemName: icon)
        .font(.system(size: 12))
        .foregroundColor(isPro ? .yellow : .accentColor)
        .frame(width: 20)
      Text(text)
        .font(.system(size: 12))
        .foregroundColor(.secondary)
    }
  }
}

// MARK: - Reusable Components

private struct PreferenceHeader: View {
  let title: String
  let subtitle: String

  var body: some View {
    VStack(alignment: .leading, spacing: 4) {
      Text(title)
        .font(.system(size: 20, weight: .semibold))
      Text(subtitle)
        .font(.system(size: 13))
        .foregroundColor(.secondary)
    }
    .padding(.bottom, 8)
  }
}

private struct PreferenceSection<Content: View>: View {
  let title: String
  let content: Content

  init(_ title: String, @ViewBuilder content: () -> Content) {
    self.title = title
    self.content = content()
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text(title)
        .font(.system(size: 11, weight: .semibold))
        .foregroundColor(.secondary)
        .textCase(.uppercase)

      VStack(alignment: .leading, spacing: 10) {
        content
      }
      .padding(12)
      .background(
        RoundedRectangle(cornerRadius: 8)
          .fill(Color(NSColor.controlBackgroundColor))
      )
    }
  }
}

private struct PreferenceRow<Content: View>: View {
  let icon: String
  let title: String
  let subtitle: String
  let control: Content

  init(icon: String, title: String, subtitle: String, @ViewBuilder control: () -> Content) {
    self.icon = icon
    self.title = title
    self.subtitle = subtitle
    self.control = control()
  }

  var body: some View {
    HStack(spacing: 12) {
      Image(systemName: icon)
        .font(.system(size: 14))
        .foregroundColor(.accentColor)
        .frame(width: 24)

      VStack(alignment: .leading, spacing: 2) {
        Text(title)
          .font(.system(size: 13))
        Text(subtitle)
          .font(.system(size: 11))
          .foregroundColor(.secondary)
      }

      Spacer()

      control
    }
  }
}
