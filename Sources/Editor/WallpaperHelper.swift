import AppKit
import Foundation

@MainActor
struct WallpaperHelper {
  /// Get the desktop wallpaper image for the main screen
  static func getDesktopWallpaper() -> NSImage? {
    guard let screen = NSScreen.main else { return nil }
    
    // Try to get the wallpaper URL from the workspace
    if let imageURL = NSWorkspace.shared.desktopImageURL(for: screen) {
      return NSImage(contentsOf: imageURL)
    }
    
    // Fallback: try reading from preferences
    if let wallpaperPath = getWallpaperPathFromPreferences() {
      return NSImage(contentsOfFile: wallpaperPath)
    }
    
    return nil
  }
  
  /// Get all available screen wallpapers (for multi-monitor setups)
  static func getAllDesktopWallpapers() -> [NSImage] {
    var wallpapers: [NSImage] = []
    
    for screen in NSScreen.screens {
      if let imageURL = NSWorkspace.shared.desktopImageURL(for: screen),
         let image = NSImage(contentsOf: imageURL) {
        wallpapers.append(image)
      }
    }
    
    return wallpapers
  }
  
  /// Fallback method to get wallpaper path from system preferences
  private static func getWallpaperPathFromPreferences() -> String? {
    // Read from com.apple.desktop preferences
    let task = Process()
    task.launchPath = "/usr/bin/defaults"
    task.arguments = ["read", "com.apple.desktop", "Background"]
    
    let pipe = Pipe()
    task.standardOutput = pipe
    
    do {
      try task.run()
      task.waitUntilExit()
      
      let data = pipe.fileHandleForReading.readDataToEndOfFile()
      if let output = String(data: data, encoding: .utf8) {
        return output.trimmingCharacters(in: .whitespacesAndNewlines)
      }
    } catch {
      return nil
    }
    
    return nil
  }
}
