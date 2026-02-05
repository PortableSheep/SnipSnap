import Foundation

enum ProFeature: String, CaseIterable {
  case advancedAnnotations
  case ocrIndexing
  case cloudSync
  case shareLinks
  case smartRedaction
  case recordingUpgrades
  case annotationTemplates
  case reusableElements
  case presentationMode
  case measurementAnnotations

  var title: String {
    switch self {
    case .advancedAnnotations:
      return "Advanced annotations"
    case .ocrIndexing:
      return "OCR indexing"
    case .cloudSync:
      return "Cloud sync"
    case .shareLinks:
      return "Share"
    case .smartRedaction:
      return "Smart redaction"
    case .recordingUpgrades:
      return "Recording upgrades"
    case .annotationTemplates:
      return "Annotation templates"
    case .reusableElements:
      return "Reusable elements"
    case .presentationMode:
      return "Presentation mode"
    case .measurementAnnotations:
      return "Measurement annotations"
    }
  }
}
