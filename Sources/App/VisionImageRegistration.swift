import Foundation
import CoreGraphics
import Vision

/// Wraps Apple's Vision framework for precise image registration (overlap detection).
/// Used to determine the translational offset between consecutive scroll capture frames.
enum VisionImageRegistration {

  struct RegistrationResult {
    /// Vertical translation in pixels (positive = bottom image shifted down relative to top).
    let yTranslation: CGFloat
    /// Horizontal translation (should be near-zero for vertical scrolling).
    let xTranslation: CGFloat
  }

  /// Find the translational offset between two images using Vision framework.
  /// - Parameters:
  ///   - reference: The earlier (top) frame.
  ///   - target: The later (bottom) frame that overlaps with the bottom of reference.
  /// - Returns: The translation needed to align target onto reference, or nil if registration fails.
  static func findTranslation(reference: CGImage, target: CGImage) -> RegistrationResult? {
    // VNTranslationalImageRegistrationRequest finds how to align the *targeted* image
    // onto the image provided to the request handler (the *reference*).
    let request = VNTranslationalImageRegistrationRequest(targetedCGImage: target)

    let handler = VNImageRequestHandler(cgImage: reference, options: [:])
    do {
      try handler.perform([request])
    } catch {
      debugLog("VisionImageRegistration: perform failed: \(error.localizedDescription)")
      return nil
    }

    guard let observation = request.results?.first as? VNImageTranslationAlignmentObservation else {
      debugLog("VisionImageRegistration: No alignment observation returned")
      return nil
    }

    let transform = observation.alignmentTransform
    let result = RegistrationResult(
      yTranslation: transform.ty,
      xTranslation: transform.tx
    )

    debugLog("VisionImageRegistration: tx=\(String(format: "%.1f", result.xTranslation)), ty=\(String(format: "%.1f", result.yTranslation))")
    return result
  }

  /// Compute the overlap in pixels between two vertically-adjacent frames.
  /// The overlap is how many rows from the bottom of `top` match the top of `bottom`.
  /// - Returns: Overlap in pixels, or nil if registration fails.
  static func computeOverlap(top: CGImage, bottom: CGImage) -> Int? {
    guard let result = findTranslation(reference: top, target: bottom) else {
      return nil
    }

    // Vision reports translation in the reference image's coordinate space.
    // For a downward scroll, the target (later frame) is shifted downward relative
    // to the reference, so ty is negative. The overlap is the frame height minus
    // the absolute vertical shift.
    let frameHeight = CGFloat(top.height)
    let shift = abs(result.yTranslation)

    // Sanity: horizontal drift should be small
    if abs(result.xTranslation) > CGFloat(top.width) * 0.05 {
      debugLog("VisionImageRegistration: Excessive horizontal drift (\(result.xTranslation)px), rejecting")
      return nil
    }

    let overlap = Int(frameHeight - shift)

    // Sanity: overlap must be positive and less than the full frame
    guard overlap > 0, overlap < Int(frameHeight) else {
      debugLog("VisionImageRegistration: Implausible overlap \(overlap) for frame height \(Int(frameHeight))")
      return nil
    }

    debugLog("VisionImageRegistration: Computed overlap = \(overlap)px (shift=\(String(format: "%.1f", shift)))")
    return overlap
  }

  /// Check whether two frames are effectively duplicates (near-zero scroll movement).
  /// - Parameter threshold: Maximum vertical shift in pixels to consider a duplicate (default 5).
  static func isDuplicate(frame1: CGImage, frame2: CGImage, threshold: CGFloat = 5) -> Bool {
    guard let result = findTranslation(reference: frame1, target: frame2) else {
      // If Vision can't register them, fall back to assuming they're NOT duplicates
      return false
    }
    return abs(result.yTranslation) < threshold && abs(result.xTranslation) < threshold
  }
}
