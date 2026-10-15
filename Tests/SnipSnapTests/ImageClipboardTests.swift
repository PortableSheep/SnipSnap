import AppKit
import Testing
@testable import SnipSnap

@MainActor
@Suite("Image clipboard transparency")
struct ImageClipboardTests {
  @Test("PNG and TIFF preserve transparent rounded corners and full pixel dimensions")
  func transparentCorners() throws {
    let context = try #require(CGContext(
      data: nil, width: 80, height: 60, bitsPerComponent: 8, bytesPerRow: 0,
      space: CGColorSpaceCreateDeviceRGB(),
      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ))
    let rect = CGRect(x: 0, y: 0, width: 80, height: 60)
    context.addPath(CGPath(roundedRect: rect, cornerWidth: 16, cornerHeight: 16, transform: nil))
    context.clip()
    context.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
    context.fill(rect)
    let image = try #require(context.makeImage())
    let png = try #require(NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]))
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("clipboard-\(UUID()).png")
    try png.write(to: url)
    defer { try? FileManager.default.removeItem(at: url) }
    let pasteboard = NSPasteboard.withUniqueName()
    defer { pasteboard.releaseGlobally() }
    try ImageClipboard.copy(url: url, to: pasteboard)
    #expect(pasteboard.data(forType: .png) == png)
    for type in [NSPasteboard.PasteboardType.png, .tiff] {
      let data = try #require(pasteboard.data(forType: type))
      let bitmap = try #require(NSBitmapImageRep(data: data))
      #expect(bitmap.pixelsWide == 80)
      #expect(bitmap.pixelsHigh == 60)
      #expect(try #require(bitmap.colorAt(x: 0, y: 0)).alphaComponent == 0)
      #expect(try #require(bitmap.colorAt(x: 40, y: 30)).alphaComponent == 1)
    }
  }

  @Test("Decode failure leaves the previous clipboard intact")
  func failedCopy() throws {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("invalid-\(UUID()).png")
    try Data("not an image".utf8).write(to: url)
    defer { try? FileManager.default.removeItem(at: url) }
    let pasteboard = NSPasteboard.withUniqueName()
    defer { pasteboard.releaseGlobally() }
    pasteboard.setString("Keep this", forType: .string)
    #expect(throws: (any Error).self) { try ImageClipboard.copy(url: url, to: pasteboard) }
    #expect(pasteboard.string(forType: .string) == "Keep this")
  }
}
