import Foundation

@MainActor
final class AnnotationTemplateStore: ObservableObject {
  @Published private(set) var templates: [AnnotationTemplate] = [] {
    didSet { persist() }
  }

  private enum Keys {
    static let templates = "pro.annotationTemplates"
  }

  init() {
    load()
  }

  func addOrReplace(_ template: AnnotationTemplate) {
    if let idx = templates.firstIndex(where: { $0.id == template.id }) {
      templates[idx] = template
    } else {
      templates.insert(template, at: 0)
    }
  }

  func remove(id: UUID) {
    templates.removeAll { $0.id == id }
  }

  private func load() {
    guard let data = UserDefaults.standard.data(forKey: Keys.templates) else {
      templates = []
      return
    }
    templates = (try? JSONDecoder().decode([AnnotationTemplate].self, from: data)) ?? []
  }

  private func persist() {
    let data = (try? JSONEncoder().encode(templates))
    UserDefaults.standard.set(data, forKey: Keys.templates)
  }
}
