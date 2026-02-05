import Cocoa

let app = NSApplication.shared

// Keep delegate in global scope to prevent deallocation
nonisolated(unsafe) var appDelegate: AppDelegate?

MainActor.assumeIsolated {
	appDelegate = AppDelegate()
	app.delegate = appDelegate
}

app.setActivationPolicy(.accessory)
app.run()

