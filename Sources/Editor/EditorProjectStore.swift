import AppKit
import Foundation
import SwiftUI

struct EditorProject: Codable {
  let version: Int
  let sourceFilename: String
  let imageSize: CGSize
  let cropRect: CGRect?
  let annotations: [EditorProjectAnnotation]
}

struct StoredColor: Codable {
  let red: CGFloat
  let green: CGFloat
  let blue: CGFloat
  let alpha: CGFloat

  init(_ color: Color) throws {
    guard let color = NSColor(color).usingColorSpace(.sRGB) else {
      throw EditorProjectStoreError.unsupportedColor
    }
    red = color.redComponent
    green = color.greenComponent
    blue = color.blueComponent
    alpha = color.alphaComponent
  }

  var color: Color { Color(.sRGB, red: red, green: green, blue: blue, opacity: alpha) }
}

struct StoredStroke: Codable {
  let color: StoredColor
  let lineWidth: CGFloat

  init(_ stroke: StrokeStyleModel) throws {
    color = try StoredColor(stroke.color)
    lineWidth = stroke.lineWidth
  }

  var style: StrokeStyleModel { StrokeStyleModel(color: color.color, lineWidth: lineWidth) }
}

struct StoredFill: Codable {
  let color: StoredColor
  let enabled: Bool

  init(_ fill: FillStyleModel) throws {
    color = try StoredColor(fill.color)
    enabled = fill.enabled
  }

  var style: FillStyleModel { FillStyleModel(color: color.color, enabled: enabled) }
}

struct EditorProjectAnnotation: Codable {
  enum Kind: String, Codable {
    case rect, ellipse, line, arrow, freehand, text, callout, blur
    case spotlight, step, counter, emoji, measurement, imageLayer, loupe
  }

  let kind: Kind
  let id: UUID
  var rect: CGRect? = nil
  var start: CGPoint? = nil
  var end: CGPoint? = nil
  var bendPoint: CGPoint? = nil
  var points: [CGPoint]? = nil
  var position: CGPoint? = nil
  var center: CGPoint? = nil
  var tailTip: CGPoint? = nil
  var stroke: StoredStroke? = nil
  var fill: StoredFill? = nil
  var headStyle: ArrowHeadStyle? = nil
  var text: String? = nil
  var color: StoredColor? = nil
  var textColor: StoredColor? = nil
  var highlightColor: StoredColor? = nil
  var highlightOpacity: CGFloat? = nil
  var fontSize: CGFloat? = nil
  var highlighted: Bool? = nil
  var isHighlighter: Bool? = nil
  var recognizedShape: RecognizedFreehandShape? = nil
  var blurMode: BlurMode? = nil
  var amount: CGFloat? = nil
  var spotlightShape: SpotlightShape? = nil
  var dimmingOpacity: CGFloat? = nil
  var borderStroke: StoredStroke? = nil
  var number: Int? = nil
  var counterMode: CounterMode? = nil
  var radius: CGFloat? = nil
  var fillColor: StoredColor? = nil
  var borderColor: StoredColor? = nil
  var borderWidth: CGFloat? = nil
  var value: String? = nil
  var emoji: String? = nil
  var size: CGFloat? = nil
  var measurementUnit: MeasurementUnit? = nil
  var ppi: CGFloat? = nil
  var baseFontSize: CGFloat? = nil
  var showExtensionLines: Bool? = nil
  var labelOffset: CGPoint? = nil
  var imageData: Data? = nil
  var magnification: CGFloat? = nil

  init(_ annotation: Annotation) throws {
    switch annotation {
    case .rect(let a):
      kind = .rect; id = a.id; rect = a.rect
      stroke = try StoredStroke(a.stroke); fill = try StoredFill(a.fill)
    case .ellipse(let a):
      kind = .ellipse; id = a.id; rect = a.rect
      stroke = try StoredStroke(a.stroke); fill = try StoredFill(a.fill)
    case .line(let a):
      kind = .line; id = a.id; start = a.start; end = a.end
      stroke = try StoredStroke(a.stroke)
    case .arrow(let a):
      kind = .arrow; id = a.id; start = a.start; end = a.end; bendPoint = a.bendPoint
      stroke = try StoredStroke(a.stroke); headStyle = a.headStyle
    case .freehand(let a):
      kind = .freehand; id = a.id; points = a.points
      stroke = try StoredStroke(a.stroke); isHighlighter = a.isHighlighter
      recognizedShape = a.recognizedShape
    case .text(let a):
      kind = .text; id = a.id; position = a.position; text = a.text; fontSize = a.fontSize
      color = try StoredColor(a.color); highlighted = a.highlighted
      highlightColor = try StoredColor(a.highlightColor); highlightOpacity = a.highlightOpacity
    case .callout(let a):
      kind = .callout; id = a.id; rect = a.rect; text = a.text; fontSize = a.fontSize
      tailTip = a.tailTip
      stroke = try StoredStroke(a.stroke); fill = try StoredFill(a.fill)
      textColor = try StoredColor(a.textColor)
    case .blur(let a):
      kind = .blur; id = a.id; rect = a.rect; blurMode = a.mode; amount = a.amount
    case .spotlight(let a):
      kind = .spotlight; id = a.id; rect = a.rect; spotlightShape = a.shape
      dimmingOpacity = a.dimmingOpacity; borderStroke = try a.borderStroke.map(StoredStroke.init)
    case .step(let a):
      kind = .step; id = a.id; center = a.center; number = a.number; counterMode = a.mode
      radius = a.radius; fillColor = try StoredColor(a.fillColor); textColor = try StoredColor(a.textColor)
      borderColor = try StoredColor(a.borderColor); borderWidth = a.borderWidth
    case .counter(let a):
      kind = .counter; id = a.id; center = a.center; value = a.value; radius = a.radius
      fillColor = try StoredColor(a.fillColor); textColor = try StoredColor(a.textColor)
      borderColor = try StoredColor(a.borderColor); borderWidth = a.borderWidth
    case .emoji(let a):
      kind = .emoji; id = a.id; position = a.position; emoji = a.emoji; size = a.size
    case .measurement(let a):
      kind = .measurement; id = a.id; start = a.start; end = a.end
      measurementUnit = a.unit; ppi = a.ppi; baseFontSize = a.baseFontSize
      stroke = try StoredStroke(a.stroke); showExtensionLines = a.showExtensionLines
      labelOffset = a.labelOffset
    case .imageLayer(let a):
      kind = .imageLayer; id = a.id; rect = a.rect; imageData = a.imageData
    case .loupe(let a):
      kind = .loupe; id = a.id; center = a.center; radius = a.radius
      magnification = a.magnification
    }
  }

  func annotation() throws -> Annotation {
    switch kind {
    case .rect:
      return .rect(RectAnnotation(id: id, rect: try required(rect, "rect"), stroke: try required(stroke, "stroke").style, fill: try required(fill, "fill").style))
    case .ellipse:
      return .ellipse(EllipseAnnotation(id: id, rect: try required(rect, "rect"), stroke: try required(stroke, "stroke").style, fill: try required(fill, "fill").style))
    case .line:
      return .line(LineAnnotation(id: id, start: try required(start, "start"), end: try required(end, "end"), stroke: try required(stroke, "stroke").style))
    case .arrow:
      return .arrow(ArrowAnnotation(id: id, start: try required(start, "start"), end: try required(end, "end"), stroke: try required(stroke, "stroke").style, headStyle: try required(headStyle, "headStyle"), bendPoint: bendPoint))
    case .freehand:
      return .freehand(FreehandAnnotation(
        id: id, points: try required(points, "points"), stroke: try required(stroke, "stroke").style,
        isHighlighter: try required(isHighlighter, "isHighlighter"), recognizedShape: recognizedShape
      ))
    case .text:
      return .text(TextAnnotation(id: id, position: try required(position, "position"), text: try required(text, "text"), color: try required(color, "color").color, fontSize: try required(fontSize, "fontSize"), highlighted: try required(highlighted, "highlighted"), highlightColor: try required(highlightColor, "highlightColor").color, highlightOpacity: try required(highlightOpacity, "highlightOpacity")))
    case .callout:
      return .callout(CalloutAnnotation(id: id, rect: try required(rect, "rect"), text: try required(text, "text"), stroke: try required(stroke, "stroke").style, fill: try required(fill, "fill").style, textColor: try required(textColor, "textColor").color, fontSize: try required(fontSize, "fontSize"), tailTip: tailTip))
    case .blur:
      return .blur(BlurAnnotation(id: id, rect: try required(rect, "rect"), mode: try required(blurMode, "blurMode"), amount: try required(amount, "amount")))
    case .spotlight:
      return .spotlight(SpotlightAnnotation(id: id, rect: try required(rect, "rect"), shape: try required(spotlightShape, "spotlightShape"), dimmingOpacity: try required(dimmingOpacity, "dimmingOpacity"), borderStroke: borderStroke?.style))
    case .step:
      return .step(StepAnnotation(id: id, center: try required(center, "center"), number: try required(number, "number"), mode: try required(counterMode, "counterMode"), radius: try required(radius, "radius"), fillColor: try required(fillColor, "fillColor").color, textColor: try required(textColor, "textColor").color, borderColor: try required(borderColor, "borderColor").color, borderWidth: try required(borderWidth, "borderWidth")))
    case .counter:
      return .counter(CounterAnnotation(id: id, center: try required(center, "center"), value: try required(value, "value"), radius: try required(radius, "radius"), fillColor: try required(fillColor, "fillColor").color, textColor: try required(textColor, "textColor").color, borderColor: try required(borderColor, "borderColor").color, borderWidth: try required(borderWidth, "borderWidth")))
    case .emoji:
      return .emoji(EmojiAnnotation(id: id, position: try required(position, "position"), emoji: try required(emoji, "emoji"), size: try required(size, "size")))
    case .measurement:
      return .measurement(MeasurementAnnotation(id: id, start: try required(start, "start"), end: try required(end, "end"), unit: try required(measurementUnit, "measurementUnit"), ppi: try required(ppi, "ppi"), baseFontSize: try required(baseFontSize, "baseFontSize"), stroke: try required(stroke, "stroke").style, showExtensionLines: try required(showExtensionLines, "showExtensionLines"), labelOffset: labelOffset))
    case .imageLayer:
      return .imageLayer(ImageLayerAnnotation(id: id, rect: try required(rect, "rect"), imageData: try required(imageData, "imageData")))
    case .loupe:
      return .loupe(LoupeAnnotation(
        id: id, center: try required(center, "center"), radius: try required(radius, "radius"),
        magnification: try required(magnification, "magnification")
      ))
    }
  }

  private func required<T>(_ value: T?, _ field: String) throws -> T {
    guard let value else { throw EditorProjectStoreError.missingField(kind.rawValue, field) }
    return value
  }
}

enum EditorProjectStoreError: LocalizedError, Equatable {
  case unsupportedColor
  case unsupportedVersion(Int)
  case wrongSource
  case missingField(String, String)

  var errorDescription: String? {
    switch self {
    case .unsupportedColor: return "A color in this project could not be converted to a device-independent color."
    case .unsupportedVersion(let version): return "This SnipSnap project uses an unsupported format version (\(version))."
    case .wrongSource: return "The editable project does not match this capture."
    case .missingField(let kind, let field): return "The \(kind) annotation is missing required data (\(field))."
    }
  }
}

enum EditorProjectStore {
  static func projectURL(for sourceURL: URL) -> URL {
    sourceURL.deletingPathExtension().appendingPathExtension("snipsnap.json")
  }

  static func load(sourceURL: URL, imageSize: CGSize) throws -> EditorProject? {
    let url = projectURL(for: sourceURL)
    guard FileManager.default.fileExists(atPath: url.path) else { return nil }
    let project = try JSONDecoder().decode(EditorProject.self, from: Data(contentsOf: url))
    guard project.version == 1 else { throw EditorProjectStoreError.unsupportedVersion(project.version) }
    guard project.sourceFilename == sourceURL.lastPathComponent, project.imageSize == imageSize else {
      throw EditorProjectStoreError.wrongSource
    }
    return project
  }

  static func save(
    sourceURL: URL, imageSize: CGSize, cropRect: CGRect?, annotations: [Annotation]
  ) throws {
    let project = EditorProject(
      version: 1, sourceFilename: sourceURL.lastPathComponent, imageSize: imageSize,
      cropRect: cropRect, annotations: try annotations.map(EditorProjectAnnotation.init)
    )
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    try encoder.encode(project).write(to: projectURL(for: sourceURL), options: .atomic)
  }
}
