import Foundation
import os.log

/// XPC Service entry point.
/// This is the main() for the XPC service bundle.

private let mainLog = OSLog(subsystem: "com.snipsnap.CaptureService", category: "main")
os_log(.info, log: mainLog, "CaptureService XPC starting...")

let delegate = CaptureServiceDelegate()
let listener = NSXPCListener.service()
listener.delegate = delegate
listener.resume()

os_log(.info, log: mainLog, "CaptureService listener resumed")

// Run the service until terminated
RunLoop.current.run()
