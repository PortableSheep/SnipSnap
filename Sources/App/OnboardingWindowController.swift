import AppKit
import SwiftUI

@MainActor
final class OnboardingWindowController {
  static let shared = OnboardingWindowController()

  private var window: NSWindow?

  private init() {}

  /// Show the onboarding window. If `markComplete` is true, sets the
  /// `hasCompletedOnboarding` flag when the user dismisses the window.
  func show(markComplete: Bool = true) {
    if let existing = window {
      existing.makeKeyAndOrderFront(nil)
      NSApp.activate(ignoringOtherApps: true)
      return
    }

    let view = OnboardingView(onClose: { [weak self] in
      if markComplete {
        UserDefaults.standard.set(true, forKey: "hasCompletedOnboarding")
      }
      self?.window?.close()
    })
    let hosting = NSHostingView(rootView: view)

    let win = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 520, height: 520),
      styleMask: [.titled, .closable],
      backing: .buffered,
      defer: false
    )
    win.title = "Welcome to SnipSnap"
    win.center()
    win.contentView = hosting
    win.isReleasedWhenClosed = false

    window = win
    win.makeKeyAndOrderFront(nil)
    NSApp.activate(ignoringOtherApps: true)
  }

  static var hasCompletedOnboarding: Bool {
    UserDefaults.standard.bool(forKey: "hasCompletedOnboarding")
  }
}

// MARK: - SwiftUI View

struct OnboardingView: View {
  let onClose: () -> Void

  @State private var screenRecordingGranted = false
  @State private var accessibilityGranted = false
  @State private var inputMonitoringGranted = false
  @State private var refreshID = UUID()
  @State private var pollTimer: Timer?

  var body: some View {
    VStack(spacing: 20) {
      // Header
      VStack(spacing: 8) {
        Image(systemName: "scissors")
          .font(.system(size: 48))
          .foregroundColor(.accentColor)

        Text("Welcome to SnipSnap")
          .font(.title)
          .fontWeight(.bold)

        Text("Grant permissions so SnipSnap can capture your screen and respond to hotkeys.")
          .font(.subheadline)
          .foregroundColor(.secondary)
          .multilineTextAlignment(.center)
          .padding(.horizontal)
      }
      .padding(.top, 20)

      // Permission rows
      VStack(spacing: 0) {
        PermissionRow(
          icon: "record.circle",
          title: "Screen Recording",
          description: "Required to capture screenshots and record video.",
          isGranted: screenRecordingGranted,
          onGrant: {
            _ = ScreenRecordingPermission.hasAccess(prompt: true)
            refreshPermissions()
          }
        )

        Divider().padding(.horizontal)
          
          PermissionRow(
            icon: "hand.raised",
            title: "Accessibility",
            description: "Required for global hotkeys and click/keystroke overlays.",
            isGranted: accessibilityGranted,
            onGrant: {
                _ = AccessibilityPermission.isTrusted(prompt: true)
                refreshPermissions()
            }
          )
          
          if (!isUnifiedPermissionOS()) {
              Divider().padding(.horizontal)

              PermissionRow(
                icon: "keyboard",
                title: "Input Monitoring",
                description: "Required to show keystroke and click overlays in recordings.",
                isGranted: inputMonitoringGranted,
                onGrant: {
                  _ = InputMonitoringPermission.hasAccess(prompt: true)
                  refreshPermissions()
                }
              )
          }
      }
      .background(Color(nsColor: .controlBackgroundColor))
      .cornerRadius(10)
      .padding(.horizontal, 24)
      .id(refreshID)

      Spacer()

      HStack(spacing: 12) {
        Button("Open System Settings") {
          if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy") {
            NSWorkspace.shared.open(url)
          }
        }
        .buttonStyle(.bordered)
        .controlSize(.large)

        Button(action: onClose) {
          Text(allGranted ? "Get Started" : "Continue Anyway")
            .fontWeight(.semibold)
            .frame(minWidth: 120)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
      }
      .padding(.bottom, 20)
    }
    .frame(width: 520, height: 520)
    .onAppear {
      refreshPermissions()
      startPolling()
    }
    .onDisappear {
      stopPolling()
    }
    .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
      refreshPermissions()
    }
  }

    private func startPolling() {
        stopPolling()
        pollTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { _ in
            Task { @MainActor in refreshPermissions() }
        }
    }

    private func stopPolling() {
        pollTimer?.invalidate()
        pollTimer = nil
    }

    private var allGranted: Bool {
        screenRecordingGranted && accessibilityGranted && inputMonitoringGranted
    }

    private func refreshPermissions() {
        screenRecordingGranted = ScreenRecordingPermission.hasAccess(prompt: false)
        
        if (isUnifiedPermissionOS()) {
            accessibilityGranted = AccessibilityPermission.isTrusted(prompt: false)
            inputMonitoringGranted = accessibilityGranted
        } else {
            accessibilityGranted = AccessibilityPermission.isTrusted(prompt: false)
            inputMonitoringGranted = InputMonitoringPermission.hasAccess(prompt: false)
        }
        
        refreshID = UUID()
    }

    private func isUnifiedPermissionOS() -> Bool {
        let v = ProcessInfo.processInfo.operatingSystemVersion
        // macOS 15+ or 14.4+
        return (v.majorVersion > 14) || (v.majorVersion == 14 && v.minorVersion >= 4)
    }
}

// MARK: - Permission Row

private struct PermissionRow: View {
  let icon: String
  let title: String
  let description: String
  let isGranted: Bool
  let onGrant: () -> Void

  var body: some View {
    HStack(spacing: 14) {
      Image(systemName: icon)
        .font(.title2)
        .foregroundColor(.accentColor)
        .frame(width: 32)

      VStack(alignment: .leading, spacing: 2) {
        Text(title)
          .fontWeight(.medium)
        Text(description)
          .font(.caption)
          .foregroundColor(.secondary)
      }

      Spacer()

      if isGranted {
        Image(systemName: "checkmark.circle.fill")
          .font(.title2)
          .foregroundColor(.green)
      } else {
        Button("Grant") {
          onGrant()
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
      }
    }
    .padding(.horizontal, 16)
    .padding(.vertical, 12)
  }
}
