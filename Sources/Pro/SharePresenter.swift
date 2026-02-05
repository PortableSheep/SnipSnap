import AppKit
import Foundation

@MainActor
enum SharePresenter {
  static func share(url: URL) {
    guard let window = NSApp.keyWindow ?? NSApp.windows.first(where: { $0.isVisible }) else {
      return
    }
    guard let contentView = window.contentView else { return }

    let picker = NSSharingServicePicker(items: [url])
    picker.show(relativeTo: contentView.bounds, of: contentView, preferredEdge: .minY)
  }
}
