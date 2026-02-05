// SPDX-License-Identifier: MIT
// RegionIndicatorWindow.swift – Persistent border showing recording region

import AppKit

/// A transparent window that shows a colored border around the recording region.
/// This stays visible during recording so the user knows what area is being captured.
final class RegionIndicatorWindow: NSPanel {
    
    private static var current: RegionIndicatorWindow?
    
    private let borderWidth: CGFloat = 3
    private let borderColor = NSColor.systemRed
    
    private init(frame: NSRect) {
        super.init(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        
        isOpaque = false
        backgroundColor = .clear
        level = .statusBar
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        ignoresMouseEvents = true
        hasShadow = false
        
        // Create a border view
        let borderView = BorderView(frame: contentView!.bounds, borderWidth: borderWidth, borderColor: borderColor)
        borderView.autoresizingMask = [.width, .height]
        contentView?.addSubview(borderView)
    }
    
    /// Show the indicator around the given region (in screen coordinates).
    /// The region should be in NSScreen coordinate system (origin at bottom-left).
    static func show(region: CGRect) {
        // Dismiss any existing indicator
        dismiss()
        
        // Expand the frame slightly to show border around the region (not inside it)
        let borderWidth: CGFloat = 3
        let expandedFrame = region.insetBy(dx: -borderWidth, dy: -borderWidth)
        
        let window = RegionIndicatorWindow(frame: expandedFrame)
        window.orderFront(nil)
        current = window
        
        debugLog("RegionIndicatorWindow: showing border around region \(region)")
    }
    
    /// Dismiss the indicator.
    static func dismiss() {
        current?.orderOut(nil)
        current = nil
        debugLog("RegionIndicatorWindow: dismissed")
    }
}

// MARK: - Border View

private class BorderView: NSView {
    private let borderWidth: CGFloat
    private let borderColor: NSColor
    
    init(frame: NSRect, borderWidth: CGFloat, borderColor: NSColor) {
        self.borderWidth = borderWidth
        self.borderColor = borderColor
        super.init(frame: frame)
        wantsLayer = true
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        
        // Draw a hollow rectangle (border only, no fill)
        let path = NSBezierPath(rect: bounds.insetBy(dx: borderWidth / 2, dy: borderWidth / 2))
        path.lineWidth = borderWidth
        borderColor.setStroke()
        path.stroke()
        
        // Add corner indicators for better visibility
        let cornerSize: CGFloat = 12
        let cornerPath = NSBezierPath()
        
        // Top-left corner
        cornerPath.move(to: NSPoint(x: borderWidth, y: bounds.height - borderWidth))
        cornerPath.line(to: NSPoint(x: borderWidth, y: bounds.height - borderWidth - cornerSize))
        cornerPath.move(to: NSPoint(x: borderWidth, y: bounds.height - borderWidth))
        cornerPath.line(to: NSPoint(x: borderWidth + cornerSize, y: bounds.height - borderWidth))
        
        // Top-right corner
        cornerPath.move(to: NSPoint(x: bounds.width - borderWidth, y: bounds.height - borderWidth))
        cornerPath.line(to: NSPoint(x: bounds.width - borderWidth, y: bounds.height - borderWidth - cornerSize))
        cornerPath.move(to: NSPoint(x: bounds.width - borderWidth, y: bounds.height - borderWidth))
        cornerPath.line(to: NSPoint(x: bounds.width - borderWidth - cornerSize, y: bounds.height - borderWidth))
        
        // Bottom-left corner
        cornerPath.move(to: NSPoint(x: borderWidth, y: borderWidth))
        cornerPath.line(to: NSPoint(x: borderWidth, y: borderWidth + cornerSize))
        cornerPath.move(to: NSPoint(x: borderWidth, y: borderWidth))
        cornerPath.line(to: NSPoint(x: borderWidth + cornerSize, y: borderWidth))
        
        // Bottom-right corner
        cornerPath.move(to: NSPoint(x: bounds.width - borderWidth, y: borderWidth))
        cornerPath.line(to: NSPoint(x: bounds.width - borderWidth, y: borderWidth + cornerSize))
        cornerPath.move(to: NSPoint(x: bounds.width - borderWidth, y: borderWidth))
        cornerPath.line(to: NSPoint(x: bounds.width - borderWidth - cornerSize, y: borderWidth))
        
        cornerPath.lineWidth = borderWidth + 1
        NSColor.white.setStroke()
        cornerPath.stroke()
    }
}

// Simple debug logging
private func debugLog(_ message: String) {
    let logPath = NSHomeDirectory() + "/snipsnap-debug.log"
    let timestamp = ISO8601DateFormatter().string(from: Date())
    let line = "[\(timestamp)] \(message)\n"
    if let data = line.data(using: .utf8) {
        if FileManager.default.fileExists(atPath: logPath) {
            if let handle = FileHandle(forWritingAtPath: logPath) {
                handle.seekToEndOfFile()
                handle.write(data)
                handle.closeFile()
            }
        } else {
            try? data.write(to: URL(fileURLWithPath: logPath))
        }
    }
}
