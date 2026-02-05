import AppKit

final class CaptureAgentAppDelegate: NSObject, NSApplicationDelegate {
  private var server: CaptureAgentServer?

  func applicationDidFinishLaunching(_ notification: Notification) {
    NSApp.setActivationPolicy(.accessory)

    let server = CaptureAgentServer()
    self.server = server
    server.start()
  }
}

let app = NSApplication.shared
let delegate = CaptureAgentAppDelegate()
app.delegate = delegate
app.run()
