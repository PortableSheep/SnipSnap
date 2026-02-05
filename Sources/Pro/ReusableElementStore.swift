import Foundation

struct ReusableTextElement: Identifiable, Codable, Hashable {
  var id: UUID
  var title: String
  var text: String

  init(id: UUID = UUID(), title: String, text: String) {
    self.id = id
    self.title = title
    self.text = text
  }
}

@MainActor
final class ReusableElementStore: ObservableObject {
  @Published private(set) var textSnippets: [ReusableTextElement] = [] {
    didSet { persist() }
  }

  private enum Keys {
    static let textSnippets = "pro.reusableElements.textSnippets"
  }

  init() {
    load()
  }

  func addOrReplace(_ el: ReusableTextElement) {
    if let idx = textSnippets.firstIndex(where: { $0.id == el.id }) {
      textSnippets[idx] = el
    } else {
      textSnippets.insert(el, at: 0)
    }
  }

  func remove(id: UUID) {
    textSnippets.removeAll { $0.id == id }
  }

  private func load() {
    guard let data = UserDefaults.standard.data(forKey: Keys.textSnippets) else {
      textSnippets = []
      return
    }
    textSnippets = (try? JSONDecoder().decode([ReusableTextElement].self, from: data)) ?? []
  }

  private func persist() {
    let data = (try? JSONEncoder().encode(textSnippets))
    UserDefaults.standard.set(data, forKey: Keys.textSnippets)
  }
}
