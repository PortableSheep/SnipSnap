import Testing
import CoreGraphics
@testable import SnipSnap

// MARK: - ImageStitcher Tests

@Suite("ImageStitcher Vertical Stitching")
struct ImageStitcherTests {

    private func solidImage(width: Int = 200, height: Int = 300, red: UInt8 = 128, green: UInt8 = 128, blue: UInt8 = 128) -> CGImage {
        createSolidImage(width: width, height: height, red: red, green: green, blue: blue)
    }

    @Test("Empty array throws noImages error")
    func emptyArrayThrows() throws {
        #expect(throws: ImageStitcher.Error.noImages) {
            try ImageStitcher.stitchVertical([])
        }
    }

    @Test("Single image returns same dimensions")
    func singleImage() throws {
        let image = solidImage()
        let result = try ImageStitcher.stitchVertical([image])

        #expect(result.width == image.width)
        #expect(result.height == image.height)
    }

    @Test("Two images with minimal overlap produce near-combined height")
    func twoImagesMinimalOverlap() throws {
        let img1 = solidImage(height: 200)
        let img2 = solidImage(height: 300)
        let overlaps: [Int?] = [nil, 1]

        let result = try ImageStitcher.stitchVertical([img1, img2], precomputedOverlaps: overlaps)

        #expect(result.width == 200)
        #expect(result.height == 499)
    }

    @Test("Two images with precomputed overlap produce correct height")
    func twoImagesWithOverlap() throws {
        let img1 = solidImage(height: 300)
        let img2 = solidImage(height: 300)
        let overlap = 100
        let overlaps: [Int?] = [nil, overlap]

        let result = try ImageStitcher.stitchVertical([img1, img2], precomputedOverlaps: overlaps)

        #expect(result.width == 200)
        #expect(result.height == 300 + 300 - overlap)
    }

    @Test("Three images with precomputed overlaps produce correct total height")
    func threeImagesWithOverlaps() throws {
        let img1 = solidImage(height: 200)
        let img2 = solidImage(height: 200)
        let img3 = solidImage(height: 200)
        let overlaps: [Int?] = [nil, 50, 75]

        let result = try ImageStitcher.stitchVertical([img1, img2, img3], precomputedOverlaps: overlaps)

        let expectedHeight = 200 + 200 + 200 - 50 - 75
        #expect(result.width == 200)
        #expect(result.height == expectedHeight)
    }

    @Test("Error descriptions are non-empty")
    func errorDescriptions() {
        let errors: [ImageStitcher.Error] = [.noImages, .failedToCreateContext, .failedToMakeImage]
        for error in errors {
            #expect(error.errorDescription?.isEmpty == false)
        }
    }
}
