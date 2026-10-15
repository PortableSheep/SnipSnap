import AppKit
import ImageIO
import UniformTypeIdentifiers

enum ImageClipboard {
  static func copy(url: URL, to pasteboard: NSPasteboard = .general) throws {
    let data = try Data(contentsOf: url)
    guard let source = CGImageSourceCreateWithData(data as CFData, nil),
          let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
      throw failure("The capture could not be decoded for copying.")
    }
    let originalPNG = CGImageSourceGetType(source).map { $0 as String } == UTType.png.identifier
      ? data : nil
    try copy(image: image, originalPNG: originalPNG, to: pasteboard)
  }

  static func copy(
    image: CGImage, originalPNG: Data? = nil,
    additionalData: [NSPasteboard.PasteboardType: Data] = [:],
    to pasteboard: NSPasteboard = .general
  ) throws {
    let bitmap = NSBitmapImageRep(cgImage: image)
    guard let png = originalPNG ?? bitmap.representation(using: .png, properties: [:]),
          let tiff = bitmap.representation(using: .tiff, properties: [:]) else {
      throw failure("The capture could not be encoded for copying.")
    }
    let item = NSPasteboardItem()
    guard item.setData(png, forType: .png), item.setData(tiff, forType: .tiff) else {
      throw failure("The image could not be prepared for the clipboard.")
    }
    for (type, data) in additionalData where !item.setData(data, forType: type) {
      throw failure("The image could not be prepared for the clipboard.")
    }
    pasteboard.clearContents()
    guard pasteboard.writeObjects([item]) else {
      throw failure("The image could not be written to the clipboard.")
    }
  }

  private static func failure(_ message: String) -> NSError {
    NSError(domain: "SnipSnap", code: 12, userInfo: [NSLocalizedDescriptionKey: message])
  }
}
