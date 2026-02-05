import SwiftUI

struct PreferencesView: View {
  @ObservedObject var prefs: OverlayPreferencesStore

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      Text("Preferences")
        .font(.system(size: 20, weight: .semibold))
        .padding(.bottom, 4)

      Group {
        if #available(macOS 13.0, *) {
          Form {
            Section("Overlays") {
              Toggle("Show click overlay", isOn: $prefs.showClickOverlay)
              Toggle("Show keystroke HUD", isOn: $prefs.showKeystrokeHUD)
            }

            Section("Clicks") {
              ColorPicker("Ripple color", selection: $prefs.clickColor, supportsOpacity: true)
            }

            Section("HUD") {
              Picker("Placement", selection: $prefs.hudPlacement) {
                ForEach(HUDPlacement.allCases) { p in
                  Text(p.label).tag(p)
                }
              }
            }

            Section {
              Text("Note: Click/keystroke overlays and global hotkeys require Accessibility + Input Monitoring permission.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            }
          }
          .formStyle(.grouped)
        } else {
          Form {
            Section("Overlays") {
              Toggle("Show click overlay", isOn: $prefs.showClickOverlay)
              Toggle("Show keystroke HUD", isOn: $prefs.showKeystrokeHUD)
            }

            Section("Clicks") {
              ColorPicker("Ripple color", selection: $prefs.clickColor, supportsOpacity: true)
            }

            Section("HUD") {
              Picker("Placement", selection: $prefs.hudPlacement) {
                ForEach(HUDPlacement.allCases) { p in
                  Text(p.label).tag(p)
                }
              }
            }

            Section {
              Text("Note: Click/keystroke overlays and global hotkeys require Accessibility + Input Monitoring permission.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            }
          }
        }
      }

      Spacer()
    }
    .padding(20)
    .frame(width: 520, height: 420)
  }
}
