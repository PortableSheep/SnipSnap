import Foundation
import SwiftUI

/// Measurement units for dimension annotations
enum MeasurementUnit: String, CaseIterable, Identifiable {
  case pixels
  case points
  case rem
  case em
  case inches
  case centimeters

  var id: String { rawValue }

  var label: String {
    switch self {
    case .pixels: return "px"
    case .points: return "pt"
    case .rem: return "rem"
    case .em: return "em"
    case .inches: return "in"
    case .centimeters: return "cm"
    }
  }

  var fullName: String {
    switch self {
    case .pixels: return "Pixels"
    case .points: return "Points"
    case .rem: return "Root EM"
    case .em: return "EM"
    case .inches: return "Inches"
    case .centimeters: return "Centimeters"
    }
  }

  /// Convert pixel distance to this unit
  func convert(pixels: CGFloat, ppi: CGFloat = 72, baseFontSize: CGFloat = 16) -> CGFloat {
    switch self {
    case .pixels:
      return pixels
    case .points:
      return pixels * 72.0 / ppi
    case .rem, .em:
      return pixels / baseFontSize
    case .inches:
      return pixels / ppi
    case .centimeters:
      return pixels / ppi * 2.54
    }
  }

  /// Format a value with appropriate precision
  func format(_ value: CGFloat) -> String {
    switch self {
    case .pixels:
      return String(format: "%.0f%@", value, label)
    case .points:
      return String(format: "%.1f%@", value, label)
    case .rem, .em:
      return String(format: "%.2f%@", value, label)
    case .inches:
      return String(format: "%.2f%@", value, label)
    case .centimeters:
      return String(format: "%.2f%@", value, label)
    }
  }
}

/// Orientation for measurement display
enum MeasurementOrientation: String, Hashable {
  case horizontal
  case vertical
  case diagonal

  static func from(start: CGPoint, end: CGPoint) -> MeasurementOrientation {
    let dx = abs(end.x - start.x)
    let dy = abs(end.y - start.y)

    if dy < 10 { return .horizontal }
    if dx < 10 { return .vertical }
    return .diagonal
  }
}

struct MeasurementTool: EditorTool {
  let id: AnnotationTool = .measurement
  let requiredFeature: ProFeature? = .measurementAnnotations
  let capabilities: ToolCapabilities = [.usesDrag]

  func begin(doc: AnnotationDocument, at point: CGPoint, isShiftDown: Bool) -> ToolBeginResult {
    // Prepare snapping when measurement tool starts
    if doc.measurementSnapEnabled {
      doc.snapGuideManager.prepareSnapping(for: doc.cgImage)
    }
    return .startDrag
  }

  func preview(doc: AnnotationDocument, start: CGPoint, current: CGPoint, isShiftDown: Bool) -> Annotation? {
    let rawDx = current.x - start.x
    let rawDy = current.y - start.y
    var snappedStart = start
    var snappedEnd = current

    // Apply edge snapping if enabled
    if doc.measurementSnapEnabled {
      if let snap = doc.snapGuideManager.snapPoint(near: start, in: doc.cgImage, threshold: 12) {
        snappedStart = snap
      }
      if let snap = doc.snapGuideManager.snapPoint(near: current, in: doc.cgImage, threshold: 12) {
        snappedEnd = snap
      }

      // If the user is basically dragging horizontally/vertically, keep the measurement axis-aligned.
      // This avoids a "diagonal" feel when snapping to opposing edges with tiny cursor drift.
      let axisLockThreshold: CGFloat = 12
      if abs(rawDy) <= axisLockThreshold {
        snappedEnd.y = snappedStart.y
      } else if abs(rawDx) <= axisLockThreshold {
        snappedEnd.x = snappedStart.x
      }
    }

    // Apply axis constraint if shift is held
    if isShiftDown {
      snappedEnd = snapToAxis(from: snappedStart, to: snappedEnd)
    }

    return .measurement(MeasurementAnnotation(
      start: snappedStart,
      end: snappedEnd,
      unit: doc.measurementUnit,
      ppi: doc.measurementPPI,
      baseFontSize: doc.measurementBaseFontSize,
      stroke: doc.stroke,
      showExtensionLines: doc.measurementShowExtensionLines
    ))
  }

  func commit(doc: AnnotationDocument, start: CGPoint, end: CGPoint, isShiftDown: Bool) {
    let rawDx = end.x - start.x
    let rawDy = end.y - start.y
    var snappedStart = start
    var snappedEnd = end

    // Apply edge snapping if enabled
    if doc.measurementSnapEnabled {
      if let snap = doc.snapGuideManager.snapPoint(near: start, in: doc.cgImage, threshold: 12) {
        snappedStart = snap
      }
      if let snap = doc.snapGuideManager.snapPoint(near: end, in: doc.cgImage, threshold: 12) {
        snappedEnd = snap
      }

      let axisLockThreshold: CGFloat = 12
      if abs(rawDy) <= axisLockThreshold {
        snappedEnd.y = snappedStart.y
      } else if abs(rawDx) <= axisLockThreshold {
        snappedEnd.x = snappedStart.x
      }
    }

    // Apply axis constraint if shift is held
    if isShiftDown {
      snappedEnd = snapToAxis(from: snappedStart, to: snappedEnd)
    }

    let distance = hypot(snappedEnd.x - snappedStart.x, snappedEnd.y - snappedStart.y)

    if distance >= 5 {
      doc.pushUndoCheckpoint()
      doc.annotations.append(.measurement(MeasurementAnnotation(
        start: snappedStart,
        end: snappedEnd,
        unit: doc.measurementUnit,
        ppi: doc.measurementPPI,
        baseFontSize: doc.measurementBaseFontSize,
        stroke: doc.stroke,
        showExtensionLines: doc.measurementShowExtensionLines
      )))
      doc.selectedID = doc.annotations.last?.id
    }
  }

  /// Snap to horizontal or vertical axis if close enough
  private func snapToAxis(from start: CGPoint, to end: CGPoint) -> CGPoint {
    let dx = end.x - start.x
    let dy = end.y - start.y

    // If shift is held, snap to nearest 45° angle
    let angle = atan2(dy, dx)
    let step = CGFloat.pi / 4
    let snappedAngle = round(angle / step) * step
    let len = hypot(dx, dy)

    return CGPoint(
      x: start.x + cos(snappedAngle) * len,
      y: start.y + sin(snappedAngle) * len
    )
  }
}
