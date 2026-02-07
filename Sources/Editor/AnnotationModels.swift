import Foundation
import SwiftUI

enum AnnotationTool: String, CaseIterable, Identifiable {
  case select
  case rect
  case line
  case arrow
  case freehand
  case text
  case callout
  case blur
  case spotlight
  case step
  case counter
  case emoji
  case measurement

  var id: String { rawValue }

  var label: String {
    switch self {
    case .select: return "Select"
    case .rect: return "Rectangle"
    case .line: return "Line"
    case .arrow: return "Arrow"
    case .freehand: return "Marker"
    case .text: return "Text"
    case .callout: return "Callout"
    case .blur: return "Blur"
    case .spotlight: return "Spotlight"
    case .step: return "Steps"
    case .counter: return "Counter"
    case .emoji: return "Emoji"
    case .measurement: return "Measure"
    }
  }

  var icon: String {
    switch self {
    case .select: return "arrow.up.left.and.arrow.down.right"
    case .rect: return "rectangle"
    case .line: return "line.diagonal"
    case .arrow: return "arrow.up.right"
    case .freehand: return "pencil.tip"
    case .text: return "textformat"
    case .callout: return "text.bubble"
    case .blur: return "square.dashed"
    case .spotlight: return "flashlight.on.fill"
    case .step: return "list.number"
    case .counter: return "number.circle"
    case .emoji: return "face.smiling"
    case .measurement: return "ruler"
    }
  }

  var shortcutKey: String? {
    switch self {
    case .select: return "V"
    case .rect: return "R"
    case .line: return "L"
    case .arrow: return "A"
    case .freehand: return "M"
    case .text: return "T"
    case .callout: return "C"
    case .blur: return "B"
    case .spotlight: return "S"
    case .step: return "N"  // N for Numbered steps
    case .counter: return "#"  // # for manual number badge
    case .emoji: return "E"
    case .measurement: return "D"
    }
  }

  /// Whether this tool uses stroke settings (color, width)
  var usesStroke: Bool {
    switch self {
    case .rect, .line, .arrow, .freehand, .callout:
      return true
    default:
      return false
    }
  }

  /// Whether this tool uses fill settings
  var usesFill: Bool {
    switch self {
    case .rect, .callout:
      return true
    default:
      return false
    }
  }
}

enum BlurMode: String, CaseIterable, Identifiable {
  case blur
  case pixelate
  case remove

  var id: String { rawValue }

  var label: String {
    switch self {
    case .blur: return "Blur"
    case .pixelate: return "Pixelate"
    case .remove: return "Remove"
    }
  }
}

enum ArrowHeadStyle: String, CaseIterable, Identifiable {
  case filled
  case open
  case none

  var id: String { rawValue }

  var label: String {
    switch self {
    case .filled: return "Filled"
    case .open: return "Open"
    case .none: return "None"
    }
  }
}

enum CounterMode: String, CaseIterable, Identifiable {
  case numbers
  case letters
  case custom

  var id: String { rawValue }

  var label: String {
    switch self {
    case .numbers: return "1, 2, 3..."
    case .letters: return "A, B, C..."
    case .custom: return "Custom"
    }
  }

  func value(for index: Int) -> String {
    switch self {
    case .numbers:
      return "\(index)"
    case .letters:
      let letters = "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
      if index <= 26 {
        return String(letters[letters.index(letters.startIndex, offsetBy: index - 1)])
      }
      return "\(index)"  // Fall back to numbers if > 26
    case .custom:
      return "•"
    }
  }
}

struct StrokeStyleModel: Hashable {
  var color: Color = .white
  var lineWidth: CGFloat = 4
}

struct FillStyleModel: Hashable {
  var color: Color = .black.opacity(0.3)
  var enabled: Bool = false
}

struct RectAnnotation: Identifiable, Hashable {
  let id: UUID
  var rect: CGRect
  var stroke: StrokeStyleModel
  var fill: FillStyleModel

  init(id: UUID = UUID(), rect: CGRect, stroke: StrokeStyleModel, fill: FillStyleModel) {
    self.id = id
    self.rect = rect
    self.stroke = stroke
    self.fill = fill
  }
}

struct ArrowAnnotation: Identifiable, Hashable {
  let id: UUID
  var start: CGPoint
  var end: CGPoint
  var stroke: StrokeStyleModel
  var headStyle: ArrowHeadStyle

  init(id: UUID = UUID(), start: CGPoint, end: CGPoint, stroke: StrokeStyleModel, headStyle: ArrowHeadStyle) {
    self.id = id
    self.start = start
    self.end = end
    self.stroke = stroke
    self.headStyle = headStyle
  }
}

struct TextAnnotation: Identifiable, Hashable {
  let id: UUID
  var position: CGPoint
  var text: String
  var color: Color
  var fontSize: CGFloat
  var highlighted: Bool
  var highlightColor: Color
  var highlightOpacity: CGFloat

  init(
    id: UUID = UUID(),
    position: CGPoint,
    text: String,
    color: Color,
    fontSize: CGFloat,
    highlighted: Bool = false,
    highlightColor: Color = .yellow,
    highlightOpacity: CGFloat = 0.35
  ) {
    self.id = id
    self.position = position
    self.text = text
    self.color = color
    self.fontSize = fontSize
    self.highlighted = highlighted
    self.highlightColor = highlightColor
    self.highlightOpacity = highlightOpacity
  }
}

struct CalloutAnnotation: Identifiable, Hashable {
  let id: UUID
  var rect: CGRect
  var text: String
  var stroke: StrokeStyleModel
  var fill: FillStyleModel
  var textColor: Color
  var fontSize: CGFloat

  init(
    id: UUID = UUID(),
    rect: CGRect,
    text: String,
    stroke: StrokeStyleModel,
    fill: FillStyleModel,
    textColor: Color,
    fontSize: CGFloat
  ) {
    self.id = id
    self.rect = rect
    self.text = text
    self.stroke = stroke
    self.fill = fill
    self.textColor = textColor
    self.fontSize = fontSize
  }
}

struct BlurAnnotation: Identifiable, Hashable {
  let id: UUID
  var rect: CGRect
  var mode: BlurMode
  // Roughly maps to blur radius (blur) or pixel scale (pixelate)
  var amount: CGFloat

  init(id: UUID = UUID(), rect: CGRect, mode: BlurMode, amount: CGFloat) {
    self.id = id
    self.rect = rect
    self.mode = mode
    self.amount = amount
  }
}

struct StepAnnotation: Identifiable, Hashable {
  let id: UUID
  var center: CGPoint
  var number: Int
  var radius: CGFloat
  var fillColor: Color
  var textColor: Color
  var borderColor: Color
  var borderWidth: CGFloat

  init(
    id: UUID = UUID(),
    center: CGPoint,
    number: Int,
    radius: CGFloat,
    fillColor: Color,
    textColor: Color,
    borderColor: Color,
    borderWidth: CGFloat
  ) {
    self.id = id
    self.center = center
    self.number = number
    self.radius = radius
    self.fillColor = fillColor
    self.textColor = textColor
    self.borderColor = borderColor
    self.borderWidth = borderWidth
  }
}

struct MeasurementAnnotation: Identifiable, Hashable {
  let id: UUID
  var start: CGPoint
  var end: CGPoint
  var unit: MeasurementUnit
  var ppi: CGFloat
  var baseFontSize: CGFloat
  var stroke: StrokeStyleModel
  var showExtensionLines: Bool
  var labelOffset: CGPoint?  // nil = auto-position, set = custom offset from midpoint

  init(
    id: UUID = UUID(),
    start: CGPoint,
    end: CGPoint,
    unit: MeasurementUnit,
    ppi: CGFloat = 72,
    baseFontSize: CGFloat = 16,
    stroke: StrokeStyleModel,
    showExtensionLines: Bool = true,
    labelOffset: CGPoint? = nil
  ) {
    self.id = id
    self.start = start
    self.end = end
    self.unit = unit
    self.ppi = ppi
    self.baseFontSize = baseFontSize
    self.stroke = stroke
    self.showExtensionLines = showExtensionLines
    self.labelOffset = labelOffset
  }

  /// Calculate the pixel distance between start and end
  var pixelDistance: CGFloat {
    hypot(end.x - start.x, end.y - start.y)
  }

  /// Get formatted measurement string
  var formattedMeasurement: String {
    let converted = unit.convert(pixels: pixelDistance, ppi: ppi, baseFontSize: baseFontSize)
    return unit.format(converted)
  }

  /// Orientation of this measurement
  var orientation: MeasurementOrientation {
    MeasurementOrientation.from(start: start, end: end)
  }

  /// Midpoint of the measurement line
  var midpoint: CGPoint {
    CGPoint(x: (start.x + end.x) / 2, y: (start.y + end.y) / 2)
  }

  /// Calculate label position (either custom or auto)
  func labelPosition(estimatedLabelWidth: CGFloat) -> (position: CGPoint, needsLeader: Bool) {
    // If custom offset is set, use it
    if let offset = labelOffset {
      let pos = CGPoint(x: midpoint.x + offset.x, y: midpoint.y + offset.y)
      let needsLeader = hypot(offset.x, offset.y) > 10
      return (pos, needsLeader)
    }

    // Auto-position: check if label fits on the line
    let needsOffset = pixelDistance < estimatedLabelWidth + 20

    if needsOffset {
      let angle = atan2(end.y - start.y, end.x - start.x)
      let perpAngle = angle + .pi / 2
      let offsetDistance: CGFloat = 45
      let offsetDir: CGFloat = (perpAngle > 0 && perpAngle < .pi) ? 1 : -1
      let pos = CGPoint(
        x: midpoint.x + cos(perpAngle) * offsetDistance * offsetDir,
        y: midpoint.y + sin(perpAngle) * offsetDistance * offsetDir
      )
      return (pos, true)
    } else {
      return (midpoint, false)
    }
  }
}

// MARK: - Line Annotation (simple line without arrowhead)
struct LineAnnotation: Identifiable, Hashable {
  let id: UUID
  var start: CGPoint
  var end: CGPoint
  var stroke: StrokeStyleModel

  init(id: UUID = UUID(), start: CGPoint, end: CGPoint, stroke: StrokeStyleModel) {
    self.id = id
    self.start = start
    self.end = end
    self.stroke = stroke
  }
}

// MARK: - Freehand/Marker Annotation
struct FreehandAnnotation: Identifiable, Hashable {
  let id: UUID
  var points: [CGPoint]
  var stroke: StrokeStyleModel
  var isHighlighter: Bool  // If true, uses lower opacity and wider stroke

  init(id: UUID = UUID(), points: [CGPoint], stroke: StrokeStyleModel, isHighlighter: Bool = false) {
    self.id = id
    self.points = points
    self.stroke = stroke
    self.isHighlighter = isHighlighter
  }

  // Smooth the path using Catmull-Rom interpolation for better drawing
  var smoothedPath: [CGPoint] {
    guard points.count > 2 else { return points }
    return points  // Can add Catmull-Rom smoothing later
  }
}

// MARK: - Spotlight Annotation (dims everything except highlighted area)
struct SpotlightAnnotation: Identifiable, Hashable {
  let id: UUID
  var rect: CGRect
  var shape: SpotlightShape
  var dimmingOpacity: CGFloat
  var borderStroke: StrokeStyleModel?

  init(
    id: UUID = UUID(),
    rect: CGRect,
    shape: SpotlightShape = .roundedRect,
    dimmingOpacity: CGFloat = 0.65,
    borderStroke: StrokeStyleModel? = nil
  ) {
    self.id = id
    self.rect = rect
    self.shape = shape
    self.dimmingOpacity = dimmingOpacity
    self.borderStroke = borderStroke
  }
}

enum SpotlightShape: String, CaseIterable, Identifiable, Hashable {
  case rectangle
  case roundedRect
  case ellipse

  var id: String { rawValue }

  var label: String {
    switch self {
    case .rectangle: return "Rectangle"
    case .roundedRect: return "Rounded"
    case .ellipse: return "Ellipse"
    }
  }
}

// MARK: - Counter Badge Annotation (like Step but independent numbering)
struct CounterAnnotation: Identifiable, Hashable {
  let id: UUID
  var center: CGPoint
  var value: String  // Can be number, letter, or custom text
  var radius: CGFloat
  var fillColor: Color
  var textColor: Color
  var borderColor: Color
  var borderWidth: CGFloat

  init(
    id: UUID = UUID(),
    center: CGPoint,
    value: String,
    radius: CGFloat = 18,
    fillColor: Color = .blue,
    textColor: Color = .white,
    borderColor: Color = .white,
    borderWidth: CGFloat = 2
  ) {
    self.id = id
    self.center = center
    self.value = value
    self.radius = radius
    self.fillColor = fillColor
    self.textColor = textColor
    self.borderColor = borderColor
    self.borderWidth = borderWidth
  }
}

// MARK: - Emoji Annotation
struct EmojiAnnotation: Identifiable, Hashable {
  let id: UUID
  var position: CGPoint
  var emoji: String
  var size: CGFloat

  init(id: UUID = UUID(), position: CGPoint, emoji: String, size: CGFloat = 48) {
    self.id = id
    self.position = position
    self.emoji = emoji
    self.size = size
  }
}

enum Annotation: Identifiable, Hashable {
  case rect(RectAnnotation)
  case line(LineAnnotation)
  case arrow(ArrowAnnotation)
  case freehand(FreehandAnnotation)
  case text(TextAnnotation)
  case callout(CalloutAnnotation)
  case blur(BlurAnnotation)
  case spotlight(SpotlightAnnotation)
  case step(StepAnnotation)
  case counter(CounterAnnotation)
  case emoji(EmojiAnnotation)
  case measurement(MeasurementAnnotation)

  var id: UUID {
    switch self {
    case .rect(let a): return a.id
    case .line(let a): return a.id
    case .arrow(let a): return a.id
    case .freehand(let a): return a.id
    case .text(let a): return a.id
    case .callout(let a): return a.id
    case .blur(let a): return a.id
    case .spotlight(let a): return a.id
    case .step(let a): return a.id
    case .counter(let a): return a.id
    case .emoji(let a): return a.id
    case .measurement(let a): return a.id
    }
  }
}

// MARK: - Device Frame Models

enum DeviceFrame: String, CaseIterable, Identifiable {
  case none
  case iPhonePro
  case iPhoneProMax
  case iPhoneSE
  case iPadPro11
  case iPadPro13
  case macBookPro14
  case macBookAir
  case studioDisplay
  case browser
  case window

  var id: String { rawValue }

  var label: String {
    switch self {
    case .none: return "None"
    case .iPhonePro: return "iPhone Pro"
    case .iPhoneProMax: return "iPhone Pro Max"
    case .iPhoneSE: return "iPhone SE"
    case .iPadPro11: return "iPad Pro 11\""
    case .iPadPro13: return "iPad Pro 13\""
    case .macBookPro14: return "MacBook Pro 14\""
    case .macBookAir: return "MacBook Air"
    case .studioDisplay: return "Studio Display"
    case .browser: return "Browser Window"
    case .window: return "macOS Window"
    }
  }

  var icon: String {
    switch self {
    case .none: return "xmark.circle"
    case .iPhonePro, .iPhoneProMax, .iPhoneSE: return "iphone"
    case .iPadPro11, .iPadPro13: return "ipad"
    case .macBookPro14, .macBookAir: return "laptopcomputer"
    case .studioDisplay: return "display"
    case .browser: return "globe"
    case .window: return "macwindow"
    }
  }

  /// Returns the bezel/frame color for the device
  var bezelColor: Color {
    switch self {
    case .none: return .clear
    case .iPhonePro, .iPhoneProMax, .iPhoneSE: return Color(white: 0.15)
    case .iPadPro11, .iPadPro13: return Color(white: 0.12)
    case .macBookPro14, .macBookAir: return Color(white: 0.18)
    case .studioDisplay: return Color(white: 0.1)
    case .browser: return Color(white: 0.92)
    case .window: return Color(white: 0.95)
    }
  }

  /// Approximate aspect ratio for the device screen (width / height)
  var screenAspectRatio: CGFloat {
    switch self {
    case .none: return 1.0
    case .iPhonePro: return 393.0 / 852.0
    case .iPhoneProMax: return 430.0 / 932.0
    case .iPhoneSE: return 375.0 / 667.0
    case .iPadPro11: return 834.0 / 1194.0
    case .iPadPro13: return 1024.0 / 1366.0
    case .macBookPro14: return 3024.0 / 1964.0
    case .macBookAir: return 2560.0 / 1664.0
    case .studioDisplay: return 5120.0 / 2880.0
    case .browser, .window: return 16.0 / 10.0  // Flexible
    }
  }
}

enum DeviceFrameColor: String, CaseIterable, Identifiable {
  case black
  case silver
  case gold
  case custom

  var id: String { rawValue }

  var label: String {
    switch self {
    case .black: return "Black"
    case .silver: return "Silver"
    case .gold: return "Gold"
    case .custom: return "Custom"
    }
  }
}

// MARK: - Background Models

enum BackgroundStyle: String, CaseIterable, Identifiable {
  case none
  case solid
  case gradient
  case mesh
  case wallpaper

  var id: String { rawValue }

  var label: String {
    switch self {
    case .none: return "None"
    case .solid: return "Solid"
    case .gradient: return "Gradient"
    case .mesh: return "Mesh"
    case .wallpaper: return "Desktop Wallpaper"
    }
  }
}

enum GradientDirection: String, CaseIterable, Identifiable {
  case topToBottom
  case leftToRight
  case topLeftToBottomRight
  case radial

  var id: String { rawValue }

  var label: String {
    switch self {
    case .topToBottom: return "Vertical"
    case .leftToRight: return "Horizontal"
    case .topLeftToBottomRight: return "Diagonal"
    case .radial: return "Radial"
    }
  }
}

struct BackgroundSettings {
  var style: BackgroundStyle = .none
  var solidColor: Color = .gray
  var gradientStartColor: Color = Color(hue: 0.6, saturation: 0.8, brightness: 0.9)
  var gradientEndColor: Color = Color(hue: 0.8, saturation: 0.8, brightness: 0.9)
  var gradientDirection: GradientDirection = .topLeftToBottomRight
  var padding: CGFloat = 48
  var cornerRadius: CGFloat = 16
  var shadowEnabled: Bool = true
  var shadowRadius: CGFloat = 24
  var shadowOpacity: CGFloat = 0.3
}
