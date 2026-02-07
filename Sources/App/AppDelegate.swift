import Cocoa
import Combine
import os.log

private let appLog = OSLog(subsystem: "com.snipsnap.Snipsnap", category: "AppDelegate")

private func debugLog(_ message: String) {
  let logFile = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("snipsnap-debug.log")
  let timestamp = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
  let line = "[\(timestamp)] AppDelegate: \(message)\n"
  if let data = line.data(using: .utf8) {
    if FileManager.default.fileExists(atPath: logFile.path) {
      if let fileHandle = try? FileHandle(forWritingTo: logFile) {
        fileHandle.seekToEndOfFile()
        fileHandle.write(data)
        fileHandle.closeFile()
      }
    } else {
      try? data.write(to: logFile)
    }
  }
}

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

  private let hotkeys = HotKeyManager()
  private var recordingStartedAt: Date?
  private var ticker: Timer?

  private let overlayPrefs = OverlayPreferencesStore()
  private let proPrefs = ProPreferencesStore()
  private let prefsWindow = PreferencesWindowController()

  private let presentation = PresentationWindowController()
  
  /// Floating stop button shown during recording (excluded from capture)
  private let floatingStopButton = FloatingStopButtonController()

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

    // Strip starts hidden - only shows when a new capture is created (like CleanShot)
    stripState.isVisible = false
    stripController = StripWindowController(state: stripState, library: captureLibrary, editor: editor, presentation: presentation)

    // Global hotkeys (requires Accessibility permissions on many systems).
    if AccessibilityPermission.isTrusted(prompt: false) {
      startHotkeys()
    }

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
        }
      }
      .store(in: &cancellables)
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
  
  private var stripWasVisibleBeforeRecording = false
  
  /// Hide SnipSnap UI elements that shouldn't appear in recording
  private func hideUIForRecording() {
    // Hide the capture strip from screen during recording
    stripWasVisibleBeforeRecording = stripController?.isVisible ?? false
    stripController?.hide()
    
    // Show floating stop button (excluded from capture)
    floatingStopButton.show { [weak self] in
      Task { @MainActor [weak self] in
        try? await self?.stopActiveRecording()
        self?.refreshMenu()
      }
    }
  }
  
  /// Restore UI elements after recording stops
  private func restoreUIAfterRecording() {
    floatingStopButton.hide()
    if stripWasVisibleBeforeRecording {
      stripController?.show()
    }
  }

  private func startFullScreenRecording() async throws {
    os_log(.info, log: appLog, "startFullScreenRecording called")
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
    // Capture permissions are owned by the capture service (XPC). The main app only sends overlay settings.
    return CaptureServiceSettings.from(
      showClickOverlay: overlayPrefs.showClickOverlay,
      showKeystrokeHUD: overlayPrefs.showKeystrokeHUD,
      showCursor: overlayPrefs.showCursor,
      hudPlacement: overlayPrefs.hudPlacement,
      clickColor: NSColor(overlayPrefs.clickColor)
    )
  }

  private func startRegionRecording(region: CGRect) async throws {
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

    let anchor = statusItem?.button
    debugLog("Presenting preflight controller...")
    guard let res = await RecordingPreflightController.present(anchor: anchor, prefDefaults: overlayPrefs) else { 
      debugLog("Preflight cancelled")
      return 
    }
    debugLog("Preflight result: mode=\(res.mode)")
    let mode = forceMode ?? res.mode
    applyPreflight(res)

    if res.showClicks || res.showKeys {
      let hasAX = AccessibilityPermission.isTrusted(prompt: true)
      let hasInput = InputMonitoringPermission.hasAccess(prompt: true)
      if !hasAX { AccessibilityPermission.showInstructionsAlert() }
      if !hasInput { InputMonitoringPermission.showInstructionsAlert() }
    }

    debugLog("Starting recording with mode: \(mode)")
    switch mode {
    case .fullscreen:
      try await startFullScreenRecording()
      recordingStartedAt = Date()
      startTicker()
    case .window:
      debugLog("Showing window picker...")
      if let windowID = await WindowPicker.pickWindow() {
        debugLog("Window selected: \(windowID) - starting recording")
        try await startWindowRecording(windowID: windowID)
        recordingStartedAt = Date()
        startTicker()
      } else {
        debugLog("Window selection cancelled")
      }
    case .region:
      debugLog("Showing region selection overlay...")
      if let rect = await RegionSelectionOverlay.select() {
        debugLog("Region selected: \(rect) - starting recording")
        try await startRegionRecording(region: rect)
        recordingStartedAt = Date()
        startTicker()
      } else {
        debugLog("Region selection cancelled or failed")
      }
    }

    refreshMenu()
  }

  private func captureRegionScreenshot() async throws {
    let url = try await captureService.captureRegionScreenshot()
    lastCaptureURL = url
  }

  private func captureWindowScreenshot() async throws {
    let url = try await captureService.captureWindowScreenshot()
    lastCaptureURL = url
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
      }
    }
    hotkeys.start()
  }

  private func refreshMenu() {
    let menu = NSMenu()

    let prefs = NSMenuItem(title: "Preferences…", action: #selector(onPreferences), keyEquivalent: ",")
    prefs.keyEquivalentModifierMask = [.command]
    prefs.target = self
    menu.addItem(prefs)

    let donate = NSMenuItem(title: "Support Development", action: #selector(onDonate), keyEquivalent: "")
    donate.target = self
    donate.image = NSImage(systemSymbolName: "gift.fill", accessibilityDescription: "Donate")
    menu.addItem(donate)

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

      let shotRegion = NSMenuItem(title: "Capture Region…", action: #selector(onCaptureRegionScreenshot), keyEquivalent: "5")
      shotRegion.keyEquivalentModifierMask = [.command, .shift]
      shotRegion.target = self
      menu.addItem(shotRegion)

      let shotWindow = NSMenuItem(title: "Capture Window…", action: #selector(onCaptureWindowScreenshot), keyEquivalent: "4")
      shotWindow.keyEquivalentModifierMask = [.command, .shift]
      shotWindow.target = self
      menu.addItem(shotWindow)
      
      // Delayed capture submenu for context menus etc.
      let delayMenu = NSMenu()
      let delay3 = NSMenuItem(title: "3 seconds", action: #selector(onDelayedCapture3), keyEquivalent: "")
      delay3.target = self
      delayMenu.addItem(delay3)
      let delay5 = NSMenuItem(title: "5 seconds", action: #selector(onDelayedCapture5), keyEquivalent: "")
      delay5.target = self
      delayMenu.addItem(delay5)
      let delay10 = NSMenuItem(title: "10 seconds", action: #selector(onDelayedCapture10), keyEquivalent: "")
      delay10.target = self
      delayMenu.addItem(delay10)
      
      let delayItem = NSMenuItem(title: "Delayed Capture…", action: nil, keyEquivalent: "")
      delayItem.submenu = delayMenu
      menu.addItem(delayItem)
    }

    menu.addItem(.separator())

    let diag = NSMenuItem(title: "Permission Diagnostics…", action: #selector(onShowDiagnostics), keyEquivalent: "")
    diag.target = self
    menu.addItem(diag)

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
    prefsWindow.show(prefs: overlayPrefs, proPrefs: proPrefs)
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
        try await captureRegionScreenshot()
        stripController?.refresh()
        refreshMenu()
      } catch {
        showError(error)
      }
    }
  }

  @objc private func onCaptureWindowScreenshot() {
    Task { @MainActor in
      do {
        try await captureWindowScreenshot()
        stripController?.refresh()
        refreshMenu()
      } catch {
        showError(error)
      }
    }
  }
  
  // MARK: - Delayed Capture
  
  @objc private func onDelayedCapture3() {
    startDelayedCapture(seconds: 3)
  }
  
  @objc private func onDelayedCapture5() {
    startDelayedCapture(seconds: 5)
  }
  
  @objc private func onDelayedCapture10() {
    startDelayedCapture(seconds: 10)
  }
  
  private func startDelayedCapture(seconds: Int) {
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

  @objc private func onShowDiagnostics() {
    PermissionDiagnostics.showDiagnosticsPanel()
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
          Task { [captureService] in
            _ = try? await captureService.requestScreenRecordingPermission()
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
}
