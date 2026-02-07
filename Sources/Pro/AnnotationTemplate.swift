import Foundation
import SwiftUI

struct AnnotationTemplate: Identifiable, Codable, Hashable {
  var id: UUID
  var name: String

  var strokeColor: RGBAColor
  var strokeWidth: Double

  var fillEnabled: Bool
  var fillColor: RGBAColor

  var arrowHeadStyle: String

  var textColor: RGBAColor
  var textFontSize: Double

  var blurMode: String
  var blurAmount: Double

  var stepRadius: Double
  var stepFillColor: RGBAColor
  var stepTextColor: RGBAColor
  var stepBorderColor: RGBAColor
  var stepBorderWidth: Double

  init(
    id: UUID = UUID(),
    name: String,
    strokeColor: RGBAColor,
    strokeWidth: Double,
    fillEnabled: Bool,
    fillColor: RGBAColor,
    arrowHeadStyle: String,
    textColor: RGBAColor,
    textFontSize: Double,
    blurMode: String,
    blurAmount: Double,
    stepRadius: Double,
    stepFillColor: RGBAColor,
    stepTextColor: RGBAColor,
    stepBorderColor: RGBAColor,
    stepBorderWidth: Double
  ) {
    self.id = id
    self.name = name
    self.strokeColor = strokeColor
    self.strokeWidth = strokeWidth
    self.fillEnabled = fillEnabled
    self.fillColor = fillColor
    self.arrowHeadStyle = arrowHeadStyle
    self.textColor = textColor
    self.textFontSize = textFontSize
    self.blurMode = blurMode
    self.blurAmount = blurAmount
    self.stepRadius = stepRadius
    self.stepFillColor = stepFillColor
    self.stepTextColor = stepTextColor
    self.stepBorderColor = stepBorderColor
    self.stepBorderWidth = stepBorderWidth
  }
}

extension AnnotationTemplate {
  static func from(doc: AnnotationDocument, name: String) -> AnnotationTemplate {
    AnnotationTemplate(
      name: name,
      strokeColor: doc.stroke.color.toRGBA(),
      strokeWidth: Double(doc.stroke.lineWidth),
      fillEnabled: doc.fill.enabled,
      fillColor: doc.fill.color.toRGBA(default: .init(r: 0, g: 0, b: 0, a: 0.3)),
      arrowHeadStyle: doc.arrowHeadStyle.rawValue,
      textColor: doc.textColor.toRGBA(),
      textFontSize: Double(doc.textFontSize),
      blurMode: doc.blurMode.rawValue,
      blurAmount: Double(doc.blurAmount),
      stepRadius: Double(doc.stepRadius),
      stepFillColor: doc.stepFillColor.toRGBA(),
      stepTextColor: doc.stepTextColor.toRGBA(),
      stepBorderColor: doc.stepBorderColor.toRGBA(),
      stepBorderWidth: Double(doc.stepBorderWidth)
    )
  }

  func apply(to doc: AnnotationDocument) {
    doc.stroke = StrokeStyleModel(color: strokeColor.toColor(), lineWidth: CGFloat(strokeWidth))
    doc.fill = FillStyleModel(color: fillColor.toColor(), enabled: fillEnabled)
    doc.arrowHeadStyle = ArrowHeadStyle(rawValue: arrowHeadStyle) ?? .filled
    doc.textColor = textColor.toColor()
    doc.textFontSize = CGFloat(textFontSize)
    doc.blurMode = BlurMode(rawValue: blurMode) ?? .pixelate
    doc.blurAmount = CGFloat(blurAmount)
    doc.stepRadius = CGFloat(stepRadius)
    doc.stepFillColor = stepFillColor.toColor()
    doc.stepTextColor = stepTextColor.toColor()
    doc.stepBorderColor = stepBorderColor.toColor()
    doc.stepBorderWidth = CGFloat(stepBorderWidth)
  }
}
