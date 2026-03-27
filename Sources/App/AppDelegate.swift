import Cocoa
import Combine
import os.log
import Sparkle
import UniformTypeIdentifiers

private let appLog = OSLog(subsystem: "com.snipsnap.Snipsnap", category: "AppDelegate")

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
  private var statusItem: NSStatusItem?
  private let captureService = CaptureServiceClient()
  private var isServiceRecording: Bool = false
  private var lastCaptureURL: URL?

  private let stripState = StripState()
  private lazy var captureLibrary = CaptureLibrary(capturesDirURL: Self.capturesDirURL())
  private var stripController: StripWindowController?

  private lazy var editor = EditorWindowController()

  private let pinnedImages = PinnedImageWindowController()

  private let hotkeys = HotKeyManager()
  private var recordingStartedAt: Date?
  private var ticker: Timer?

  private let overlayPrefs = OverlayPreferencesStore()
  private let proPrefs = ProPreferencesStore()
  private let prefsWindow = PreferencesWindowController()

  private let presentation = PresentationWindowController()
  private let updaterController = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
  
  /// Floating stop button shown during recording (excluded from capture)
  private let floatingStopButton = FloatingStopButtonController()
  
  // Scroll capture UI - kept as instance vars to ensure they stay alive
  private var scrollCaptureOverlay: ScrollCaptureOverlay?
  private var scrollCaptureDecorator: ScrollCaptureRegionDecorator?
  private var scrollCaptureSession: ScrollCaptureSession?

  /// Event tap running in main app (which has Accessibility/Input Monitoring permissions)
  /// and forwarding events to the XPC service for baking into video.
  private let overlayEventTap = OverlayEventTap()
  private var eventForwardingTimer: Timer?

  private lazy var proServices = CaptureBackgroundServices(
    proPrefs: proPrefs,
    metadataStore: captureLibrary.metadataStore
  )

  func applicationDidFinishLaunching(_ notification: Notification) {
    statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    statusItem?.isVisible = true

    if let button = statusItem?.button {
      // Use SF Symbol for menu bar icon
      let image = NSImage(systemSymbolName: "scissors", accessibilityDescription: "SnipSnap")
        ?? NSImage(systemSymbolName: "circle.fill", accessibilityDescription: "SnipSnap")
      image?.isTemplate = true
      button.image = image
      button.imagePosition = .imageOnly
    }

    // Show strip on startup if user preference says so; otherwise start hidden.
    stripState.isVisible = stripState.showOnStartup
    stripController = StripWindowController(state: stripState, library: captureLibrary, editor: editor, presentation: presentation, pinnedImages: pinnedImages)

    pinnedImages.onEdit = { [weak self] url in
      self?.editor.openEditor(for: url)
    }

    // Global hotkeys via Carbon RegisterEventHotKey (no Accessibility permission needed).
    startHotkeys()

    refreshMenu()

    // Track item count to detect new captures
    var previousItemCount = captureLibrary.items.count
    
    captureLibrary.$items
      .receive(on: RunLoop.main)
      .sink { [weak self] items in
        guard let self else { return }
        self.proServices.handleLibraryItems(items)
        
        // Auto-show strip only when a NEW capture is added (count increases)
        // Don't show on launch just because old captures exist
        // Don't show during recording (strip is hidden while recording)
        let countIncreased = items.count > previousItemCount
        previousItemCount = items.count
        
        if countIncreased && !self.isRecording {
          self.stripState.isVisible = true
          self.stripController?.revealForCapture()
        }
      }
      .store(in: &cancellables)

    // Ensure automatic checks are enabled and check now on every launch
    updaterController.updater.automaticallyChecksForUpdates = true
    updaterController.updater.checkForUpdatesInBackground()

    // Show onboarding on first launch to guide users through permissions
    if !OnboardingWindowController.hasCompletedOnboarding {
      OnboardingWindowController.shared.show()
    } else {
      // On subsequent launches, check if permissions are still granted.
      // Delay slightly so the app finishes launching before showing any alerts.
      Task { @MainActor in
        try? await Task.sleep(nanoseconds: 2_000_000_000)
        await self.checkPermissionsOnStartup()
      }
    }
  }

  private var cancellables: Set<AnyCancellable> = []

  private var isRecording: Bool {
    isServiceRecording
  }

  private func stopActiveRecording() async throws {
    guard isServiceRecording else { throw ScreenRecorderError.notRecording }
    
    // Stop forwarding events to XPC
    stopOverlayEventForwarding()
    
    do {
      let url = try await captureService.stopRecording()
      lastCaptureURL = url
      isServiceRecording = false
      
      // Dismiss region indicator if showing
      RegionIndicatorWindow.dismiss()
      
      // Restore UI elements
      restoreUIAfterRecording()
    } catch let CaptureServiceError.remoteError(msg) where msg.lowercased().contains("not recording") {
      // Region recording can be cancelled during the interactive selection UI, or the recorder
      // can terminate early. Treat this as already-stopped and sync state.
      isServiceRecording = false
      RegionIndicatorWindow.dismiss()
      restoreUIAfterRecording()
    }
  }
  
  /// Hide SnipSnap UI elements that shouldn't appear in recording
  private func hideUIForRecording() {
    stripController?.hide()
    
    // Show floating stop button (excluded from capture)
    floatingStopButton.show { [weak self] in
      Task { @MainActor [weak self] in
        guard let self else { return }
        try? await self.stopActiveRecording()
        self.stripController?.refresh()
        self.recordingStartedAt = nil
        self.stopTicker()
        self.refreshMenu()
      }
    }
  }
  
  /// Restore UI elements after recording stops
  private func restoreUIAfterRecording() {
    floatingStopButton.hide()
    stripController?.show()
  }

  /// Check Screen Recording permission from the main app process so macOS
  /// shows the correct app icon and creates a single TCC entry.
  /// Returns true if permission is granted; shows instructions if denied.
  private func ensureScreenRecordingPermission() async -> Bool {
    // Fast path: CGPreflight returns true immediately after granting permission
    // (even before the app is restarted), avoiding a false-negative from SCShareableContent.
    if ScreenRecordingPermission.hasAccess(prompt: false) { return true }
    // Slower but more reliable check via ScreenCaptureKit
    if await ScreenRecordingPermission.checkAccess() { return true }
    // Trigger the system prompt from the main app (correct icon in dialog)
    _ = ScreenRecordingPermission.hasAccess(prompt: true)
    // Re-check both ways
    if ScreenRecordingPermission.hasAccess(prompt: false) { return true }
    if await ScreenRecordingPermission.checkAccess() { return true }
    // Still not granted — user denied or needs to restart
    ScreenRecordingPermission.showInstructionsAlert()
    return false
  }

  // MARK: - Startup Permission Check

  /// One-time startup check — shows a simple alert if permissions are missing.
  /// Does NOT use the onboarding window (which has a poll timer that can
  /// re-trigger system prompts). The user can always open onboarding manually
  /// via the menu, or permissions are checked at point-of-use before capture.
  private func checkPermissionsOnStartup() async {
    let hasScreenRecording = ScreenRecordingPermission.hasAccess(prompt: false)
    let hasAccessibility = AccessibilityPermission.isTrusted(prompt: false)

    guard !hasScreenRecording || !hasAccessibility else { return }

    var missing: [String] = []
    if !hasScreenRecording { missing.append("Screen Recording") }
    if !hasAccessibility { missing.append("Accessibility") }

    let alert = NSAlert()
    alert.alertStyle = .informational
    alert.messageText = "Missing Permissions"
    alert.informativeText = "SnipSnap needs \(missing.joined(separator: " and ")) permission\(missing.count > 1 ? "s" : "") to work properly. You can grant them in System Settings → Privacy & Security."
    alert.addButton(withTitle: "Open Settings")
    alert.addButton(withTitle: "Later")

    let resp = alert.runModal()
    if resp == .alertFirstButtonReturn {
      if !hasScreenRecording {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
          NSWorkspace.shared.open(url)
        }
      } else if !hasAccessibility {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
          NSWorkspace.shared.open(url)
        }
      }
    }
  }

  private func startFullScreenRecording() async throws {
    os_log(.info, log: appLog, "startFullScreenRecording called")
    guard await ensureScreenRecordingPermission() else { return }
    hideUIForRecording()
    let settings = makeOverlaySettingsForService()
    try await captureService.startFullScreenRecording(settings: settings)
    os_log(.info, log: appLog, "startFullScreenRecording succeeded")
    isServiceRecording = true
    
    // Start event forwarding if overlays enabled
    if overlayPrefs.showClickOverlay || overlayPrefs.showKeystrokeHUD {
      startOverlayEventForwarding()
    }
  }

  private func startWindowRecording(windowID: CGWindowID) async throws {
    debugLog("startWindowRecording called with windowID: \(windowID)")
    guard await ensureScreenRecordingPermission() else { return }
    hideUIForRecording()
    let settings = makeOverlaySettingsForService()
    try await captureService.startWindowRecording(settings: settings, windowID: windowID)
    isServiceRecording = true
    
    // Start event forwarding if overlays enabled
    if overlayPrefs.showClickOverlay || overlayPrefs.showKeystrokeHUD {
      startOverlayEventForwarding()
    }
  }

  private func makeOverlaySettingsForService() -> CaptureServiceSettings {
    return CaptureServiceSettings.from(
      showClickOverlay: overlayPrefs.showClickOverlay,
      showKeystrokeHUD: overlayPrefs.showKeystrokeHUD,
      showCursor: overlayPrefs.showCursor,
      hudPlacement: overlayPrefs.hudPlacement,
      clickColor: NSColor(overlayPrefs.clickColor)
    )
  }

  private func startRegionRecording(region: CGRect) async throws {
    guard await ensureScreenRecordingPermission() else { return }
    hideUIForRecording()
    let settings = makeOverlaySettingsForService()
    try await captureService.startRegionRecording(settings: settings, region: region)
    isServiceRecording = true
    
    // Show persistent border around the recording region
    RegionIndicatorWindow.show(region: region)
    
    // Start event forwarding if overlays enabled
    if overlayPrefs.showClickOverlay || overlayPrefs.showKeystrokeHUD {
      startOverlayEventForwarding()
    }

    Task { @MainActor [weak self] in
      guard let self else { return }
      try? await Task.sleep(nanoseconds: 650_000_000)
      if let status = try? await self.captureService.status(), status.isRecording == false {
        if let msg = status.lastRecordingError, !msg.isEmpty, msg.lowercased() != "cancelled" {
          self.showError(NSError(domain: "SnipSnap", code: 1, userInfo: [NSLocalizedDescriptionKey: msg]))
        }
      }
    }
  }

  private func applyPreflight(_ res: RecordingPreflightResult) {
    overlayPrefs.showClickOverlay = res.showClicks
    overlayPrefs.showKeystrokeHUD = res.showKeys
    overlayPrefs.showCursor = res.showCursor
    overlayPrefs.hudPlacement = res.hudPlacement
    overlayPrefs.clickColor = res.ringColor
  }

  private func startWithPreflight(forceMode: RecordingMode? = nil) async throws {
    debugLog("startWithPreflight called")
    guard !isRecording else { 
      debugLog("Already recording, returning")
      return 
    }

    guard let button = statusItem?.button else { return }
    
    debugLog("Presenting preflight controller...")
    
    return await withCheckedContinuation { continuation in
      let preflightMenu = RecordingPreflightController.presentAsMenu(prefDefaults: overlayPrefs) { [weak self] result in
        guard let self, let result else {
          debugLog("Preflight cancelled")
          continuation.resume()
          return
        }
        
        debugLog("Preflight result: mode=\(result.mode)")
        let mode = forceMode ?? result.mode
        self.applyPreflight(result)

        Task { @MainActor in
          if result.showClicks || result.showKeys {
            let hasAX = AccessibilityPermission.isTrusted(prompt: true)
            let hasInput = InputMonitoringPermission.hasAccess(prompt: true)
            if !hasAX { AccessibilityPermission.showInstructionsAlert() }
            if !hasInput { InputMonitoringPermission.showInstructionsAlert() }
          }

          debugLog("Starting recording with mode: \(mode)")
          do {
            switch mode {
            case .fullscreen:
              try await self.startFullScreenRecording()
              self.recordingStartedAt = Date()
              self.startTicker()
            case .window:
              debugLog("Showing window picker...")
              if let selection = await InteractiveWindowPicker.pick(mode: .window) {
                debugLog("Window selected: \(selection.windowID) - starting recording")
                try await self.startWindowRecording(windowID: selection.windowID)
                self.recordingStartedAt = Date()
                self.startTicker()
              } else {
                debugLog("Window selection cancelled")
              }
            case .region:
              debugLog("Showing region selection overlay...")
              if let rect = await RegionSelectionOverlay.select() {
                debugLog("Region selected: \(rect) - starting recording")
                try await self.startRegionRecording(region: rect)
                self.recordingStartedAt = Date()
                self.startTicker()
              } else {
                debugLog("Region selection cancelled or failed")
              }
            }

            self.refreshMenu()
          } catch {
            self.showError(error)
          }
          
          continuation.resume()
        }
      }
      
      // Position and show the menu - center it under the button with a small gap
      let menuWidth: CGFloat = 420
      let buttonWidth = button.bounds.width
      let xOffset = (buttonWidth - menuWidth) / 2
      preflightMenu.popUp(positioning: nil, at: NSPoint(x: xOffset, y: button.bounds.height + 4), in: button)
    }
  }

  private func captureRegionScreenshot() async throws {
    guard await ensureScreenRecordingPermission() else { return }
    let wasVisible = stripController?.isVisible == true
    if wasVisible { stripController?.hide() }
    defer { if wasVisible { stripController?.show() } }
    let url = try await captureService.captureRegionScreenshot()
    lastCaptureURL = url
  }

  private func captureWindowScreenshot() async throws {
    guard await ensureScreenRecordingPermission() else { return }
    let wasVisible = stripController?.isVisible == true
    if wasVisible { stripController?.hide() }
    defer { if wasVisible { stripController?.show() } }
    let url = try await captureService.captureWindowScreenshot()
    lastCaptureURL = url
  }

  private func captureFullScreenScreenshot() async throws {
    guard await ensureScreenRecordingPermission() else { return }
    let wasVisible = stripController?.isVisible == true
    if wasVisible { stripController?.hide() }
    defer { if wasVisible { stripController?.show() } }
    let url = try await captureService.captureFullScreenScreenshot()
    lastCaptureURL = url
  }

  private func captureScrollingWindow() async throws {
    guard await ensureScreenRecordingPermission() else { return }
    let wasVisible = stripController?.isVisible == true
    if wasVisible { stripController?.hide() }
    defer { if wasVisible { stripController?.show() } }
    // Use interactive region picker - scroll capture is ALWAYS region-based
    guard let selection = await InteractiveWindowPicker.pick(mode: .subRegion) else {
      debugLog("AppDelegate: Scroll capture cancelled - no region selected")
      return
    }
    
    // Scroll capture REQUIRES a sub-region
    guard let subRegion = selection.subRegion else {
      debugLog("AppDelegate: Scroll capture requires a region to be selected")
      showError(ScrollCaptureSession.Error.noRegionSelected)
      return
    }
    
    debugLog("AppDelegate: Starting scroll capture for region: \(subRegion)")
    
    // Create UI objects as instance variables to keep them alive
    let overlay = scrollCaptureOverlay ?? ScrollCaptureOverlay()
    let regionDecorator = scrollCaptureDecorator ?? ScrollCaptureRegionDecorator()
    let session = ScrollCaptureSession()
    
    // Store them
    self.scrollCaptureOverlay = overlay
    self.scrollCaptureDecorator = regionDecorator
    self.scrollCaptureSession = session
    
    // Show the region decorator
    regionDecorator.show(region: subRegion)
    
    // Default to auto-scroll mode
    let scrollMode: ScrollCaptureSession.Mode = .auto
    
    // Show the overlay UI first
    overlay.show(
      isAutoMode: scrollMode == .auto,
      onDone: { [weak self] in
        debugLog("AppDelegate: User clicked Done/Stop")
        Task { @MainActor in
          self?.scrollCaptureSession?.finish()
        }
      },
      onCancel: { [weak self] in
        debugLog("AppDelegate: User cancelled scroll capture")
        Task { @MainActor in
          self?.scrollCaptureSession?.cancel()
        }
      }
    )
    
    // Use a separate continuation approach
    do {
      let stitchedCGImage = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<CGImage, Error>) in
        // Start the capture session with region and mode
        session.start(
          region: subRegion,
          mode: scrollMode,
          onProgress: { [weak self] frameCount in
            Task { @MainActor in
              self?.scrollCaptureOverlay?.updateFrameCount(frameCount)
            }
          },
          onStatus: { [weak self] status in
            Task { @MainActor in
              self?.scrollCaptureOverlay?.updateStatus(status)
            }
          },
          completion: { [weak self] result in
            Task { @MainActor in
              debugLog("AppDelegate: Completion handler called")
              
              switch result {
              case .success(let stitchedImage):
                continuation.resume(returning: stitchedImage)
                
              case .failure(let error):
                debugLog("AppDelegate: Scroll capture failed: \(error.localizedDescription)")
                continuation.resume(throwing: error)
              }
            }
          }
        )
      }
      
      // NOW dismiss UI after we have the image
      debugLog("AppDelegate: Stitching completed, dismissing UI")
      
      // Wait a moment to ensure the completion callback has fully executed
      try? await Task.sleep(nanoseconds: 200_000_000)  // 0.2s
      
      scrollCaptureOverlay?.dismiss()
      scrollCaptureDecorator?.dismiss()
      
      // Wait for UI to fully tear down
      try? await Task.sleep(nanoseconds: 300_000_000)  // 0.3s
      
      self.scrollCaptureSession = nil
      
      // Save the stitched image (it's already a CGImage)
      debugLog("AppDelegate: Saving scroll capture...")
      let url = try saveScrollCapture(stitchedCGImage)
      lastCaptureURL = url
      debugLog("AppDelegate: Scroll capture saved to \(url.path)")
      
    } catch is CancellationError {
      // User cancelled - dismiss UI
      debugLog("AppDelegate: User cancelled, dismissing UI")
      scrollCaptureOverlay?.dismiss()
      scrollCaptureDecorator?.dismiss()
      self.scrollCaptureSession = nil
      throw CancellationError()
      
    } catch {
      // Error occurred - dismiss UI and show error
      debugLog("AppDelegate: Error occurred, dismissing UI")
      scrollCaptureOverlay?.dismiss()
      scrollCaptureDecorator?.dismiss()
      self.scrollCaptureSession = nil
      showError(error)
      throw error
    }
  }
  
  private func saveScrollCapture(_ image: CGImage) throws -> URL {
    // Create a unique filename
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
    let dateStr = formatter.string(from: Date())
    let filename = "Scroll Capture \(dateStr).png"
    
    // Get captures directory
    let capturesDir = FileManager.default.homeDirectoryForCurrentUser
      .appendingPathComponent("Library/Application Support/SnipSnap/captures")
    
    // Create directory if needed
    try FileManager.default.createDirectory(at: capturesDir, withIntermediateDirectories: true)
    
    let fileURL = capturesDir.appendingPathComponent(filename)
    
    // Save as PNG
    guard let destination = CGImageDestinationCreateWithURL(fileURL as CFURL, UTType.png.identifier as CFString, 1, nil) else {
      throw NSError(domain: "com.snipsnap.Snipsnap", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to create image destination"])
    }
    
    CGImageDestinationAddImage(destination, image, nil)
    
    guard CGImageDestinationFinalize(destination) else {
      throw NSError(domain: "com.snipsnap.Snipsnap", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to save image"])
    }
    
    return fileURL
  }


  private func performCapture(mode: CaptureMode, delay: CaptureDelay) async throws {
    let delayValue = delay.rawValue
    
    if delayValue > 0 {
      try await Task.sleep(nanoseconds: UInt64(delayValue * 1_000_000_000))
    }
    
    switch mode {
    case .region:
      try await captureRegionScreenshot()
    case .window:
      try await captureWindowScreenshot()
    case .fullscreen:
      try await captureFullScreenScreenshot()
    case .scrollingWindow:
      try await captureScrollingWindow()
    }
  }

  private func startHotkeys() {
    hotkeys.onAction = { [weak self] action in
      guard let self else { return }
      switch action {
      case .toggleRecording:
        self.onToggleRecording()
      case .toggleStrip:
        self.onToggleStrip()
      case .captureRegion:
        self.onCaptureRegionScreenshot()
      case .captureWindow:
        self.onCaptureWindowScreenshot()
      case .quickCapture:
        self.onQuickCapture()
      }
    }
    hotkeys.start()
  }

  private func refreshMenu() {
    let menu = NSMenu()

    let prefs = NSMenuItem(title: "Preferences…", action: #selector(onPreferences), keyEquivalent: "")
    prefs.target = self
    menu.addItem(prefs)

    let setupPerms = NSMenuItem(title: "Setup Permissions…", action: #selector(onSetupPermissions), keyEquivalent: "")
    setupPerms.target = self
    menu.addItem(setupPerms)

    let donate = NSMenuItem(title: "Support Development", action: #selector(onDonate), keyEquivalent: "")
    donate.target = self
    donate.image = NSImage(systemSymbolName: "gift.fill", accessibilityDescription: "Donate")
    menu.addItem(donate)

    let checkUpdates = NSMenuItem(title: "Check for Updates…", action: #selector(SPUStandardUpdaterController.checkForUpdates(_:)), keyEquivalent: "")
    checkUpdates.target = updaterController
    menu.addItem(checkUpdates)

    // Presentation Mode submenu
    let presMenu = NSMenu()
    
    let presSession = NSMenuItem(title: "Present Session", action: #selector(onPresentSession), keyEquivalent: "p")
    presSession.keyEquivalentModifierMask = [.command, .shift]
    presSession.target = self
    presMenu.addItem(presSession)
    
    let presAll = NSMenuItem(title: "Present All Captures", action: #selector(onPresentAll), keyEquivalent: "")
    presAll.target = self
    presMenu.addItem(presAll)
    
    let presItem = NSMenuItem(title: "Presentation Mode", action: nil, keyEquivalent: "")
    presItem.submenu = presMenu
    menu.addItem(presItem)

    menu.addItem(.separator())

    let toggleStrip = NSMenuItem(title: stripState.isVisible ? "Hide Strip" : "Show Strip", action: #selector(onToggleStrip), keyEquivalent: "s")
    toggleStrip.keyEquivalentModifierMask = [.command, .shift]
    toggleStrip.target = self
    menu.addItem(toggleStrip)

    menu.addItem(.separator())

    if isRecording {
      let dur = formattedElapsed()
      let stop = NSMenuItem(title: dur.isEmpty ? "Stop Recording" : "Stop Recording (\(dur))", action: #selector(onToggleRecording), keyEquivalent: "6")
      stop.keyEquivalentModifierMask = [.command, .shift]
      stop.target = self
      menu.addItem(stop)
    } else {
      let start = NSMenuItem(title: "Start Recording…", action: #selector(onToggleRecording), keyEquivalent: "6")
      start.keyEquivalentModifierMask = [.command, .shift]
      start.target = self
      menu.addItem(start)

      menu.addItem(.separator())

      let capture = NSMenuItem(title: "Capture…", action: #selector(onCapture), keyEquivalent: "2")
      capture.keyEquivalentModifierMask = [.command, .shift]
      capture.target = self
      menu.addItem(capture)
      
      menu.addItem(.separator())
      
      let openImage = NSMenuItem(title: "Open Image…", action: #selector(onOpenImage), keyEquivalent: "o")
      openImage.keyEquivalentModifierMask = [.command]
      openImage.target = self
      menu.addItem(openImage)
    }

    menu.addItem(.separator())

    let quit = NSMenuItem(title: "Quit SnipSnap", action: #selector(onQuit), keyEquivalent: "q")
    quit.keyEquivalentModifierMask = [.command]
    quit.target = self
    menu.addItem(quit)

    statusItem?.menu = menu

    // Status icon - show recording indicator when active
    if let button = statusItem?.button {
      if isRecording {
        let dur = formattedElapsed()
        // Red circle icon during recording
        let image = NSImage(systemSymbolName: "record.circle.fill", accessibilityDescription: "Recording")
        image?.isTemplate = false
        let config = NSImage.SymbolConfiguration(paletteColors: [.systemRed])
        button.image = image?.withSymbolConfiguration(config)
        button.title = dur
      } else {
        // Scissors icon when idle
        let image = NSImage(systemSymbolName: "scissors", accessibilityDescription: "SnipSnap")
        image?.isTemplate = true
        button.image = image
        button.title = ""
      }
    }
  }

  @objc private func onDonate() {
    DonationWindowController.shared.show()
  }

  @objc private func onPresentSession() {
    let sessionItems = captureLibrary.items.filter { $0.createdAt >= stripState.sessionStartDate }
    presentation.show(items: sessionItems, library: captureLibrary, title: "Session")
  }
  
  @objc private func onPresentAll() {
    presentation.show(items: captureLibrary.items, library: captureLibrary, title: "All Captures")
  }

  @objc private func onPreferences() {
    prefsWindow.show(prefs: overlayPrefs, proPrefs: proPrefs, stripState: stripState)
  }

  @objc private func onSetupPermissions() {
    OnboardingWindowController.shared.show(markComplete: false)
  }

  @objc private func onToggleStrip() {
    stripController?.toggle()
    refreshMenu()
  }

  @objc private func onToggleRecording() {
    debugLog("onToggleRecording called")
    Task { @MainActor in
      do {
        if isRecording {
          debugLog("Stopping recording...")
          try await stopActiveRecording()
          stripController?.refresh()
          recordingStartedAt = nil
          stopTicker()
          refreshMenu()
          return
        }

        debugLog("Starting with preflight...")
        try await startWithPreflight()
        debugLog("startWithPreflight completed")
      } catch {
        debugLog("Error: \(error)")
        showError(error)
      }
    }
  }

  @objc private func onStartRegionRecording() {
    Task { @MainActor in
      do {
        try await startWithPreflight(forceMode: .region)
      } catch {
        showError(error)
      }
    }
  }

  @objc private func onCaptureRegionScreenshot() {
    Task { @MainActor in
      do {
        let delay = CaptureDelay(rawValue: UserDefaults.standard.double(forKey: "prefs.capture.delay")) ?? .none
        if delay == .none {
          try await captureRegionScreenshot()
          stripController?.refresh()
          refreshMenu()
        } else {
          let seconds = Int(delay.rawValue)
          DelayedCaptureCountdown.show(seconds: seconds) { [weak self] in
            Task { @MainActor in
              guard let self else { return }
              do {
                try await self.captureRegionScreenshot()
                self.stripController?.refresh()
                self.refreshMenu()
              } catch {
                self.showError(error)
              }
            }
          }
        }
      } catch {
        showError(error)
      }
    }
  }

  @objc private func onCaptureWindowScreenshot() {
    Task { @MainActor in
      do {
        let delay = CaptureDelay(rawValue: UserDefaults.standard.double(forKey: "prefs.capture.delay")) ?? .none
        if delay == .none {
          try await captureWindowScreenshot()
          stripController?.refresh()
          refreshMenu()
        } else {
          let seconds = Int(delay.rawValue)
          DelayedCaptureCountdown.show(seconds: seconds) { [weak self] in
            Task { @MainActor in
              guard let self else { return }
              do {
                try await self.captureWindowScreenshot()
                self.stripController?.refresh()
                self.refreshMenu()
              } catch {
                self.showError(error)
              }
            }
          }
        }
      } catch {
        showError(error)
      }
    }
  }

  @objc private func onCapture() {
    guard let button = statusItem?.button else { return }
    
    let preflightMenu = CapturePreflightController.presentAsMenu { [weak self] result in
      guard let self, let result else { return }
      
      Task { @MainActor in
        do {
          if result.delay == .none {
            try await self.performCapture(mode: result.mode, delay: result.delay)
            self.stripController?.refresh()
            self.refreshMenu()
          } else {
            let seconds = Int(result.delay.rawValue)
            DelayedCaptureCountdown.show(seconds: seconds) {
              Task { @MainActor in
                do {
                  try await self.performCapture(mode: result.mode, delay: .none)
                  self.stripController?.refresh()
                  self.refreshMenu()
                } catch {
                  self.showError(error)
                }
              }
            }
          }
        } catch {
          self.showError(error)
        }
      }
    }
    
    // Position and show the menu - center it under the button with a small gap
    let menuWidth: CGFloat = 400
    let buttonWidth = button.bounds.width
    let xOffset = (buttonWidth - menuWidth) / 2
    preflightMenu.popUp(positioning: nil, at: NSPoint(x: xOffset, y: button.bounds.height + 4), in: button)
  }

  /// Quick capture using last-chosen mode and delay (no preflight dialog).
  private func onQuickCapture() {
    Task { @MainActor in
      do {
        let modeRaw = UserDefaults.standard.string(forKey: "prefs.capture.mode")
        let mode = CaptureMode(rawValue: modeRaw ?? "region") ?? .region
        let delayValue = UserDefaults.standard.double(forKey: "prefs.capture.delay")
        let delay = CaptureDelay(rawValue: delayValue) ?? .none

        if delay == .none {
          try await performCapture(mode: mode, delay: delay)
          stripController?.refresh()
          refreshMenu()
        } else {
          let seconds = Int(delay.rawValue)
          DelayedCaptureCountdown.show(seconds: seconds) { [weak self] in
            Task { @MainActor in
              guard let self else { return }
              do {
                try await self.performCapture(mode: mode, delay: .none)
                self.stripController?.refresh()
                self.refreshMenu()
              } catch {
                self.showError(error)
              }
            }
          }
        }
      } catch {
        showError(error)
      }
    }
  }
  
  private func startTicker() {
    stopTicker()
    ticker = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
      Task { @MainActor in
        guard let self else { return }

        // Keep UI state synced with the capture service (region selection can be cancelled,
        // or the recorder can terminate early).
        if self.isServiceRecording {
          if let status = try? await self.captureService.status() {
            self.isServiceRecording = status.isRecording
            if let url = status.lastCaptureURL {
              self.lastCaptureURL = url
            }
            if !status.isRecording {
              self.recordingStartedAt = nil
              self.stopTicker()

              if let msg = status.lastRecordingError, !msg.isEmpty, msg.lowercased() != "cancelled" {
                self.showError(NSError(domain: "SnipSnap", code: 1, userInfo: [NSLocalizedDescriptionKey: msg]))
              }
            }
          }
        }

        self.refreshMenu()
      }
    }
  }

  private func stopTicker() {
    ticker?.invalidate()
    ticker = nil
  }

  private func formattedElapsed() -> String {
    guard let started = recordingStartedAt else { return "" }
    let elapsed = Int(Date().timeIntervalSince(started))
    let m = elapsed / 60
    let s = elapsed % 60
    return String(format: "%02d:%02d", m, s)
  }

  @objc private func onRevealLastRecording() {
    guard let url = lastCaptureURL else { return }
    FinderReveal.reveal(url)
  }

  @objc private func onOpenLastRecording() {
    guard let url = lastCaptureURL else { return }
    NSWorkspace.shared.open(url)
  }

  @objc private func onCopyLastRecordingPath() {
    guard let url = lastCaptureURL else { return }
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(url.path, forType: .string)
  }

  @objc private func onQuit() {
    NSApplication.shared.terminate(nil)
  }

  @objc private func onExportLastCaptureAsGIF() {
    guard let url = lastCaptureURL else { return }
    GIFExportPresenter.exportGIF(fromVideoURL: url)
  }

  @objc private func onTrimLastCapture() {
    guard let url = lastCaptureURL else { return }
    VideoTrimPresenter.trimVideo(at: url)
  }

  private func showError(_ error: Error) {
    os_log(.error, log: appLog, "showError: %{public}@", error.localizedDescription)
    if let err = error as? CaptureServiceError {
      switch err {
      case .remoteError(let message):
        let m = message.lowercased()
        if m.contains("screen recording") && (m.contains("not granted") || m.contains("not authorized") || m.contains("not permitted") || m.contains("privacy") || m.contains("tcc")) {
          // Only re-prompt if permission isn't already granted (avoids creating
          // duplicate TCC entries when the XPC service can't see the grant yet).
          if !ScreenRecordingPermission.hasAccess(prompt: false) {
            _ = ScreenRecordingPermission.hasAccess(prompt: true)
          }
          ScreenRecordingPermission.showInstructionsAlert()
          return
        }
      default:
        break
      }
    }

    if let err = error as? ScreenshotCaptureError {
      if case .cancelled = err {
        // User cancelled the interactive selection; don't alert.
        return
      }
      if case .permissionDenied = err {
        // Already displayed instructions.
        return
      }
    }
    if let err = error as? ScreenRecorderError {
      switch err {
      case .failedToStartCapture(let message):
        let m = message.lowercased()
        if m.contains("not authorized") || m.contains("not permitted") || m.contains("permission") || m.contains("screencapturekit") {
          ScreenRecordingPermission.showInstructionsAlert()
          return
        }
      default:
        break
      }
    }

    let alert = NSAlert()
    alert.alertStyle = .warning
    alert.messageText = "SnipSnap"
    // Prefer localized descriptions so we don't show raw enum cases (e.g. remoteError("...")).
    alert.informativeText = (error as NSError).localizedDescription
    alert.runModal()
  }

  private static func capturesDirURL() -> URL {
    let fm = FileManager.default
    let appSupport = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
    let dir = appSupport
      .appendingPathComponent("SnipSnap", isDirectory: true)
      .appendingPathComponent("captures", isDirectory: true)
    try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir
  }

  // MARK: - Overlay Event Forwarding

  /// Start the event tap in the main app (which has permissions) and forward
  /// clicks/keystrokes to the XPC service for baking into the video.
  private func startOverlayEventForwarding() {
    debugLog("Starting overlay event forwarding to XPC service")
    
    // Start the event tap - main app has Accessibility/Input Monitoring permissions
    overlayEventTap.start(promptForAccessibility: false)
    
    // Set up a timer to periodically check for new events and send them to XPC
    // Use a class to hold mutable state that the closure can capture by reference
    final class ForwardingState: @unchecked Sendable {
      var lastForwardTime: CFTimeInterval = CACurrentMediaTime() - 0.1
    }
    let state = ForwardingState()
    
    eventForwardingTimer = Timer.scheduledTimer(withTimeInterval: 0.033, repeats: true) { [weak self] _ in
      guard let self else { return }
      let now = CACurrentMediaTime()
      
      // Get recent clicks and forward them (filter out clicks on the floating stop button)
      let clicks = self.overlayEventTap.recentClicks(since: state.lastForwardTime)
      for click in clicks {
        // Skip clicks on the floating stop button pill (coordinates are in CG/Quartz space)
        if self.floatingStopButton.containsPoint(cgPoint: CGPoint(x: click.x, y: click.y)) {
          continue
        }
        debugLog("Forwarding click: x=\(click.x) y=\(click.y) time=\(click.time)")
        self.captureService.sendClickEvent(x: Double(click.x), y: Double(click.y), time: click.time)
      }
      
      // Get recent keystrokes and forward them
      let keys = self.overlayEventTap.recentKeys(since: state.lastForwardTime)
      for key in keys {
        debugLog("Forwarding key: '\(key.text)' time=\(key.time)")
        self.captureService.sendKeyEvent(text: key.text, time: key.time)
      }
      
      state.lastForwardTime = now
    }
    
    debugLog("Overlay event forwarding started")
  }

  /// Stop the event tap and forwarding timer.
  private func stopOverlayEventForwarding() {
    debugLog("Stopping overlay event forwarding")
    eventForwardingTimer?.invalidate()
    eventForwardingTimer = nil
    overlayEventTap.stop()
    debugLog("Overlay event forwarding stopped")
  }
  
  @objc private func onOpenImage() {
    let panel = NSOpenPanel()
    panel.title = "Open Image"
    panel.message = "Select an image to edit"
    panel.allowedContentTypes = [.png, .jpeg, .heic, .tiff, .bmp, .gif]
    panel.allowsMultipleSelection = false
    panel.canChooseDirectories = false
    
    let response = panel.runModal()
    guard response == .OK, let url = panel.url else { return }
    
    editor.openEditor(for: url)
  }
}
