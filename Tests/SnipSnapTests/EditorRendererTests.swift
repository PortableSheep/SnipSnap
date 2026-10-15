import AppKit
import Testing
@testable import SnipSnap

@MainActor
@Suite("Loupe rendering")
struct EditorRendererTests {
  @Test("Export magnifies the source pixels beneath the circular lens")
  func magnifiesSourcePixels() throws {
    let width = 120
    let height = 100
    let bitmapContext = try #require(CGContext(
      data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
      space: CGColorSpaceCreateDeviceRGB(),
      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ))
    bitmapContext.setFillColor(CGColor(gray: 1, alpha: 1))
    bitmapContext.fill(CGRect(x: 0, y: 0, width: width, height: height))
    bitmapContext.setFillColor(CGColor(gray: 0, alpha: 1))
    bitmapContext.fill(CGRect(x: 52, y: 35, width: 4, height: 30))
    let sourceImage = try #require(bitmapContext.makeImage())

    let sourceURL = FileManager.default.temporaryDirectory
      .appendingPathComponent("loupe-\(UUID().uuidString).png")
    defer {
      try? FileManager.default.removeItem(at: sourceURL)
      try? FileManager.default.removeItem(at: EditorProjectStore.projectURL(for: sourceURL))
    }
    let sourceData = try #require(NSBitmapImageRep(cgImage: sourceImage)
      .representation(using: .png, properties: [:]))
    try sourceData.write(to: sourceURL)

    let doc = try AnnotationDocument(sourceURL: sourceURL)
    doc.annotations = [.loupe(LoupeAnnotation(
      center: CGPoint(x: 60, y: 50), radius: 30, magnification: 2
    ))]
    let exported = try #require(EditorRenderer.renderAnnotatedCGImage(doc: doc))
    let rendered = NSBitmapImageRep(cgImage: exported)
    let magnifiedPixel = try #require(rendered.colorAt(x: 46, y: 50)?
      .usingColorSpace(.deviceRGB))
    let outsideStripePixel = try #require(rendered.colorAt(x: 56, y: 50)?
      .usingColorSpace(.deviceRGB))

    #expect(magnifiedPixel.redComponent < 0.25)
    #expect(outsideStripePixel.redComponent > 0.8)
  }
}
