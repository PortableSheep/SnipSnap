import Testing
import Foundation
import CoreGraphics
@testable import SnipSnap

// MARK: - Test Helpers

func createSolidImage(width: Int, height: Int, red: UInt8, green: UInt8, blue: UInt8) -> CGImage {
    let bytesPerRow = width * 4
    var pixels = [UInt8](repeating: 0, count: bytesPerRow * height)
    for i in 0..<(width * height) {
        pixels[i * 4] = red
        pixels[i * 4 + 1] = green
        pixels[i * 4 + 2] = blue
        pixels[i * 4 + 3] = 255
    }
    let data = Data(pixels)
    let provider = CGDataProvider(data: data as CFData)!
    return CGImage(
        width: width, height: height,
        bitsPerComponent: 8, bitsPerPixel: 32,
        bytesPerRow: bytesPerRow,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
        provider: provider,
        decode: nil, shouldInterpolate: false, intent: .defaultIntent
    )!
}

/// Creates an image where each row has a unique color pattern derived from the row index.
/// This makes overlapping regions between cropped pieces reliably detectable.
func createGradientImage(width: Int, height: Int) -> CGImage {
    let bytesPerRow = width * 4
    var pixels = [UInt8](repeating: 0, count: bytesPerRow * height)
    for y in 0..<height {
        let r = UInt8(y % 256)
        let g = UInt8((y * 7) % 256)
        let b = UInt8((y * 13) % 256)
        for x in 0..<width {
            let offset = (y * width + x) * 4
            pixels[offset] = r
            pixels[offset + 1] = g
            pixels[offset + 2] = UInt8((Int(b) + x) % 256)
            pixels[offset + 3] = 255
        }
    }
    let data = Data(pixels)
    let provider = CGDataProvider(data: data as CFData)!
    return CGImage(
        width: width, height: height,
        bitsPerComponent: 8, bitsPerPixel: 32,
        bytesPerRow: bytesPerRow,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
        provider: provider,
        decode: nil, shouldInterpolate: false, intent: .defaultIntent
    )!
}

// MARK: - FeatureMatcher Tests

@Suite("FeatureMatcher Overlap Detection")
struct FeatureMatcherTests {

    @Test("Identical images produce high-confidence overlap")
    func identicalImages() {
        let image = createGradientImage(width: 200, height: 400)
        let result = FeatureMatcher.findOverlap(top: image, bottom: image)

        #expect(result != nil)
        if let match = result {
            #expect(match.confidence >= 0.7)
            #expect(match.offset > 0)
        }
    }

    @Test("Completely different solid-color images return nil")
    func differentSolidColors() {
        let red = createSolidImage(width: 200, height: 400, red: 255, green: 0, blue: 0)
        let blue = createSolidImage(width: 200, height: 400, red: 0, green: 0, blue: 255)
        let result = FeatureMatcher.findOverlap(top: red, bottom: blue)

        #expect(result == nil)
    }

    @Test("Overlapping cropped regions produce correct offset")
    func overlappingCroppedRegions() {
        let fullHeight = 600
        let overlapPixels = 150
        let full = createGradientImage(width: 200, height: fullHeight)

        let topHeight = 400
        let bottomHeight = fullHeight - topHeight + overlapPixels
        let bottomStartY = topHeight - overlapPixels

        guard let topImage = full.cropping(to: CGRect(x: 0, y: 0, width: 200, height: topHeight)),
              let bottomImage = full.cropping(to: CGRect(x: 0, y: bottomStartY, width: 200, height: bottomHeight)) else {
            Issue.record("Failed to crop test images")
            return
        }

        let result = FeatureMatcher.findOverlap(top: topImage, bottom: bottomImage)

        #expect(result != nil)
        if let match = result {
            #expect(match.confidence >= 0.7)
            let tolerance = 20
            #expect(abs(match.offset - overlapPixels) <= tolerance)
        }
    }

    @Test("Very small images are handled gracefully")
    func verySmallImages() {
        let small = createGradientImage(width: 50, height: 50)
        let result = FeatureMatcher.findOverlap(top: small, bottom: small)
        // May return nil or a match; must not crash
        if let match = result {
            #expect(match.confidence >= 0.0)
            #expect(match.confidence <= 1.0)
        }
    }

    @Test("Images of different widths are handled gracefully")
    func differentWidths() {
        let wide = createGradientImage(width: 300, height: 400)
        let narrow = createGradientImage(width: 200, height: 400)
        let result = FeatureMatcher.findOverlap(top: wide, bottom: narrow)
        // Should not crash; result is implementation-dependent
        if let match = result {
            #expect(match.confidence >= 0.0)
            #expect(match.confidence <= 1.0)
        }
    }
}
