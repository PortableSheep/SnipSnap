import CoreImage
import CoreImage.CIFilterBuiltins
import Foundation

enum ImageFilters {
  static let ciContext = CIContext(options: [
    .cacheIntermediates: true
  ])

  static func filteredRegion(
    source: CGImage,
    rect: CGRect,
    mode: BlurMode,
    amount: CGFloat
  ) -> CGImage? {
    let sourceW = CGFloat(source.width)
    let sourceH = CGFloat(source.height)

    // Clamp rect to image bounds
    let r = rect
      .intersection(CGRect(x: 0, y: 0, width: sourceW, height: sourceH))
      .integral

    if r.isEmpty { return nil }

    let ci = CIImage(cgImage: source)

    // Crop region (CI uses bottom-left origin in pixel coords; our coords match CG drawing space)
    let cropped = ci.cropped(to: r)

    let out: CIImage
    switch mode {
    case .blur:
      let f = CIFilter.gaussianBlur()
      f.inputImage = cropped
      f.radius = Float(max(0, amount))
      // Gaussian blur expands bounds, re-crop back.
      out = (f.outputImage ?? cropped).cropped(to: r)

    case .pixelate:
      let f = CIFilter.pixellate()
      f.inputImage = cropped
      f.scale = Float(max(1, amount))
      // Pixellate also expands; re-crop.
      out = (f.outputImage ?? cropped).cropped(to: r)
      
    case .redact:
      // For "redact" mode, return nil - will be drawn as a filled rect
      return nil
    }

    return ciContext.createCGImage(out, from: r)
  }
}
