import AppKit
import ScreenCaptureKit

/// Represents a window that can be selected for recording.
struct WindowInfo: Identifiable {
  let id: CGWindowID
  let title: String
  let ownerName: String
  let frame: CGRect
  var displayName: String {
    if title.isEmpty {
      return ownerName
    }
    return "\(ownerName) – \(title)"
  }
}

/// A window picker that shows available windows for the user to select.
/// This runs in the main app to provide the UI that XPC services cannot show.
@available(macOS 13.0, *)
final class WindowPicker {
  
  // Static reference to keep the panel alive during selection
  private static var activePanel: WindowSelectionPanel?
  
  /// Shows a window picker and returns the selected window ID, or nil if cancelled.
  @MainActor
  static func pickWindow() async -> CGWindowID? {
    debugLog("WindowPicker: Starting window selection")
    
    // Get available windows using ScreenCaptureKit
    let windows: [WindowInfo]
    do {
      let content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true)
      windows = content.windows.compactMap { scWindow -> WindowInfo? in
        // Skip windows that are too small or have no title/owner
        guard scWindow.frame.width >= 50, scWindow.frame.height >= 50 else { return nil }
        guard let app = scWindow.owningApplication else { return nil }
        
        // Skip SnipSnap's own windows
        if app.bundleIdentifier.lowercased().contains("snipsnap") { return nil }
        
        let ownerName = app.applicationName
        let title = scWindow.title ?? ""
        
        return WindowInfo(
          id: scWindow.windowID,
          title: title,
          ownerName: ownerName,
          frame: scWindow.frame
        )
      }
      debugLog("WindowPicker: Found \(windows.count) windows")
    } catch {
      debugLog("WindowPicker: Failed to get windows: \(error)")
      return nil
    }
    
    guard !windows.isEmpty else {
      debugLog("WindowPicker: No windows available")
      showNoWindowsAlert()
      return nil
    }
    
    // Show selection UI
    return await showWindowSelectionPanel(windows: windows)
  }
  
  @MainActor
  private static func showNoWindowsAlert() {
    let alert = NSAlert()
    alert.messageText = "No Windows Available"
    alert.informativeText = "There are no recordable windows currently visible. Please open a window and try again."
    alert.alertStyle = .warning
    alert.addButton(withTitle: "OK")
    alert.runModal()
  }
  
  @MainActor
  private static func showWindowSelectionPanel(windows: [WindowInfo]) async -> CGWindowID? {
    await withCheckedContinuation { continuation in
      let panel = WindowSelectionPanel(windows: windows) { selectedWindowID in
        debugLog("WindowPicker: User selected window ID: \(selectedWindowID?.description ?? "nil")")
        activePanel = nil  // Release the panel
        continuation.resume(returning: selectedWindowID)
      }
      activePanel = panel  // Keep strong reference
      panel.show()
    }
  }
}

/// A panel that displays available windows for selection.
@MainActor
private final class WindowSelectionPanel: NSObject, NSTableViewDataSource, NSTableViewDelegate {
  private var panel: NSPanel?
  private var tableView: NSTableView?
  private let windows: [WindowInfo]
  private let completion: (CGWindowID?) -> Void
  private var hasCompleted = false
  
  init(windows: [WindowInfo], completion: @escaping (CGWindowID?) -> Void) {
    self.windows = windows
    self.completion = completion
    super.init()
  }
  
  func show() {
    let panelWidth: CGFloat = 400
    let panelHeight: CGFloat = 350
    
    let panel = NSPanel(
      contentRect: NSRect(x: 0, y: 0, width: panelWidth, height: panelHeight),
      styleMask: [.titled, .closable],
      backing: .buffered,
      defer: false
    )
    panel.title = "Select Window to Record"
    panel.isFloatingPanel = true
    panel.level = .modalPanel
    panel.center()
    
    // Create scroll view with table
    let scrollView = NSScrollView(frame: NSRect(x: 20, y: 60, width: panelWidth - 40, height: panelHeight - 100))
    scrollView.hasVerticalScroller = true
    scrollView.autohidesScrollers = true
    scrollView.borderType = .bezelBorder
    
    let tableView = NSTableView(frame: scrollView.bounds)
    tableView.dataSource = self
    tableView.delegate = self
    tableView.headerView = nil
    tableView.rowHeight = 30
    tableView.allowsMultipleSelection = false
    tableView.doubleAction = #selector(onDoubleClick)
    tableView.target = self
    
    let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("window"))
    column.width = scrollView.bounds.width - 20
    tableView.addTableColumn(column)
    
    scrollView.documentView = tableView
    self.tableView = tableView
    
    // Create buttons
    let cancelButton = NSButton(frame: NSRect(x: panelWidth - 180, y: 15, width: 75, height: 30))
    cancelButton.title = "Cancel"
    cancelButton.bezelStyle = .rounded
    cancelButton.target = self
    cancelButton.action = #selector(onCancel)
    
    let recordButton = NSButton(frame: NSRect(x: panelWidth - 95, y: 15, width: 75, height: 30))
    recordButton.title = "Record"
    recordButton.bezelStyle = .rounded
    recordButton.keyEquivalent = "\r"
    recordButton.target = self
    recordButton.action = #selector(onRecord)
    
    // Create label
    let label = NSTextField(labelWithString: "Select a window to record:")
    label.frame = NSRect(x: 20, y: panelHeight - 35, width: panelWidth - 40, height: 20)
    
    panel.contentView?.addSubview(scrollView)
    panel.contentView?.addSubview(cancelButton)
    panel.contentView?.addSubview(recordButton)
    panel.contentView?.addSubview(label)
    
    // Handle window close
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(onPanelClose),
      name: NSWindow.willCloseNotification,
      object: panel
    )
    
    self.panel = panel
    
    NSApp.activate(ignoringOtherApps: true)
    panel.makeKeyAndOrderFront(nil)
    
    // Select first row
    if !windows.isEmpty {
      tableView.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
    }
  }
  
  @objc private func onCancel() {
    debugLog("WindowSelectionPanel: Cancel clicked")
    complete(with: nil)
  }
  
  @objc private func onRecord() {
    debugLog("WindowSelectionPanel: Record clicked")
    guard let tableView, tableView.selectedRow >= 0, tableView.selectedRow < windows.count else {
      debugLog("WindowSelectionPanel: No valid selection")
      complete(with: nil)
      return
    }
    let selectedID = windows[tableView.selectedRow].id
    debugLog("WindowSelectionPanel: Selected window ID \(selectedID)")
    complete(with: selectedID)
  }
  
  @objc private func onDoubleClick() {
    debugLog("WindowSelectionPanel: Double click")
    onRecord()
  }
  
  @objc private func onPanelClose(_ notification: Notification) {
    debugLog("WindowSelectionPanel: Panel closing")
    complete(with: nil)
  }
  
  private func complete(with windowID: CGWindowID?) {
    guard !hasCompleted else { 
      debugLog("WindowSelectionPanel: Already completed, ignoring")
      return 
    }
    hasCompleted = true
    debugLog("WindowSelectionPanel: Completing with windowID=\(windowID?.description ?? "nil")")
    panel?.close()
    completion(windowID)
  }
  
  // MARK: - NSTableViewDataSource
  
  func numberOfRows(in tableView: NSTableView) -> Int {
    windows.count
  }
  
  // MARK: - NSTableViewDelegate
  
  func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
    let identifier = NSUserInterfaceItemIdentifier("WindowCell")
    var cell = tableView.makeView(withIdentifier: identifier, owner: self) as? NSTextField
    if cell == nil {
      cell = NSTextField(labelWithString: "")
      cell?.identifier = identifier
      cell?.lineBreakMode = .byTruncatingTail
    }
    
    let window = windows[row]
    cell?.stringValue = window.displayName
    
    return cell
  }
}

private func debugLog(_ message: String) {
  let logFile = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("snipsnap-debug.log")
  let timestamp = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
  let line = "[\(timestamp)] \(message)\n"
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
