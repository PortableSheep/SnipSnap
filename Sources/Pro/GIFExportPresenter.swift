import AppKit
import Foundation

@MainActor
enum GIFExportPresenter {
  static func exportGIF(fromVideoURL videoURL: URL) {
    let panel = NSSavePanel()
    panel.allowedContentTypes = [.gif]
    panel.nameFieldStringValue = videoURL.deletingPathExtension().lastPathComponent + ".gif"
    panel.canCreateDirectories = true

    panel.begin { resp in
      guard resp == .OK, let outURL = panel.url else { return }

      Task { @MainActor in
        do {
          let exporter = GIFExporter()
          try await exporter.exportVideo(at: videoURL, to: outURL)

          // Reveal output for a nice “done” affordance.
          FinderReveal.reveal(outURL)
        } catch {
          let alert = NSAlert()
          alert.alertStyle = .warning
          alert.messageText = "GIF Export Failed"
          alert.informativeText = String(describing: error)
          alert.runModal()
        }
      }
    }
  }
}
