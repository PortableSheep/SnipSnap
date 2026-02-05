import AppKit
import SwiftUI

@MainActor
final class LicenseWindowController {
  static let shared = LicenseWindowController()

  private var window: NSWindow?

  func show(license: LicenseManager) {
    if let window {
      AppActivation.bringToFront(window)
      return
    }

    var createdWindow: NSWindow?
    let view = LicenseActivationView(
      license: license,
      onClose: {
        createdWindow?.close()
      }
    )
    let hosting = NSHostingView(rootView: view)

    let w = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 520, height: 280),
      styleMask: [.titled, .closable],
      backing: .buffered,
      defer: false
    )
    w.title = "Activate Pro"
    w.isReleasedWhenClosed = false
    w.center()
    w.contentView = hosting

    createdWindow = w

    NotificationCenter.default.addObserver(
      forName: NSWindow.willCloseNotification,
      object: w,
      queue: .main
    ) { [weak self] _ in
      Task { @MainActor in
        self?.window = nil
      }
    }

    window = w
    AppActivation.bringToFront(w)
  }
}

private struct LicenseActivationView: View {
  @ObservedObject var license: LicenseManager

  var onClose: () -> Void

  @State private var key: String = ""

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      VStack(alignment: .leading, spacing: 6) {
        Text("SnipSnap Pro")
          .font(.system(size: 18, weight: .semibold))

        if license.isProUnlocked {
          Text("Thank you for being a Pro member!")
            .font(.system(size: 13))
            .foregroundStyle(.secondary)
        } else {
          Text("Paste your license key to unlock Pro features on this Mac.")
            .font(.system(size: 13))
            .foregroundStyle(.secondary)
        }
      }

      if license.isProUnlocked {
        // Pro active state
        GroupBox {
          HStack(spacing: 12) {
            Image(systemName: "checkmark.seal.fill")
              .font(.system(size: 32))
              .foregroundStyle(.green)

            VStack(alignment: .leading, spacing: 4) {
              Text("Pro is active")
                .font(.system(size: 14, weight: .semibold))
              Text("All Pro features are unlocked on this Mac.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            }

            Spacer()
          }
          .padding(.vertical, 8)
        }
      } else {
        // License key entry
        GroupBox {
          VStack(alignment: .leading, spacing: 10) {
            Group {
              if #available(macOS 13.0, *) {
                TextField("License key", text: $key, axis: .vertical)
                  .lineLimit(2...6)
              } else {
                TextField("License key", text: $key)
              }
            }
            .textFieldStyle(.roundedBorder)
            .font(.system(size: 12, design: .monospaced))

            if let err = license.lastValidationError {
              Text(err)
                .font(.system(size: 13))
                .foregroundStyle(.red)
            }
          }
          .padding(.vertical, 4)
        }
      }

      HStack {
        if license.isProUnlocked {
          Button("Deactivate") {
            license.deactivate()
          }
          .foregroundStyle(.red)
        }

        Spacer()

        Button("Close") {
          onClose()
        }
        .keyboardShortcut(license.isProUnlocked ? .defaultAction : .cancelAction)

        if !license.isProUnlocked {
          Button("Activate") {
            let ok = license.activate(tokenString: key)
            if ok {
              // Don't close - show the success state
            }
          }
          .disabled(key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
          .keyboardShortcut(.defaultAction)
        }
      }
    }
    .padding(20)
    .frame(minWidth: 520)
  }
}
