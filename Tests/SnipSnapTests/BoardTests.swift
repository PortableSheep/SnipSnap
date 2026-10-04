import AppKit
import Foundation
import Testing
@testable import SnipSnap

@MainActor
@Suite("BoardStore")
struct BoardStoreTests {
  private func makeStore() -> (BoardStore, URL) {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("board-\(UUID().uuidString)")
    return (BoardStore(rootURL: dir, saveDelay: 0), dir)
  }

  private func note(_ text: String, at p: CGPoint = .zero) -> BoardCard {
    var card = BoardCard(kind: .note, frame: CodableRect(x: p.x, y: p.y, width: 200, height: 150))
    card.text = text
    return card
  }

  @Test("Cards persist across store instances")
  func roundTrip() {
    let (store, dir) = makeStore()
    defer { try? FileManager.default.removeItem(at: dir) }
    let card = store.add(note("Remember the milk"))
    store.setTodo([card.id], .open)
    store.saveNow()

    let reloaded = BoardStore(rootURL: dir, saveDelay: 0)
    #expect(reloaded.cards.count == 1)
    #expect(reloaded.card(card.id)?.text == "Remember the milk")
    #expect(reloaded.card(card.id)?.todo == .open)
  }

  @Test("Adding cards assigns increasing z-order and bringToFront raises them")
  func zOrder() {
    let (store, dir) = makeStore()
    defer { try? FileManager.default.removeItem(at: dir) }
    let a = store.add(note("a"))
    let b = store.add(note("b"))
    #expect(b.zIndex > a.zIndex)
    store.bringToFront([a.id])
    #expect(store.cardsInPaintOrder.last?.id == a.id)
  }

  @Test("Cards are assigned to the zone containing their center and move with it")
  func zones() {
    let (store, dir) = makeStore()
    defer { try? FileManager.default.removeItem(at: dir) }
    let zone = store.addZone(title: "Todo", frame: CGRect(x: 0, y: 0, width: 400, height: 400))
    let inside = store.add(note("in", at: CGPoint(x: 50, y: 50)))
    let outside = store.add(note("out", at: CGPoint(x: 900, y: 900)))
    #expect(store.card(inside.id)?.zoneID == zone.id)
    #expect(store.card(outside.id)?.zoneID == nil)

    store.moveZone(zone.id, by: CGSize(width: 100, height: 10))
    #expect(store.card(inside.id)?.frame.x == 150)
    #expect(store.card(outside.id)?.frame.x == 900)

    store.move([inside.id], by: CGSize(width: 2000, height: 0))
    #expect(store.card(inside.id)?.zoneID == nil)

    store.deleteZone(zone.id)
    #expect(store.zones.isEmpty)
  }

  @Test("Todo template creates three zones")
  func todoTemplate() {
    let (store, dir) = makeStore()
    defer { try? FileManager.default.removeItem(at: dir) }
    store.applyTodoTemplate(origin: .zero)
    #expect(store.zones.map(\.title) == ["Todo", "Doing", "Done"])
  }

  @Test("Archive hides cards and clears pins; restore and purge work")
  func archiveRestorePurge() {
    let (store, dir) = makeStore()
    defer { try? FileManager.default.removeItem(at: dir) }
    let card = store.add(note("x"))
    store.setPin(card.id, PinState(screenFrame: CodableRect(x: 0, y: 0, width: 100, height: 100)))
    store.archive([card.id])
    #expect(store.cards.isEmpty)
    #expect(store.card(card.id)?.pin == nil)

    store.restore([card.id])
    #expect(store.cards.count == 1)

    store.archive([card.id])
    store.purgeArchived()
    #expect(store.card(card.id) == nil)
  }

  @Test("Search matches all terms case-insensitively")
  func search() {
    let (store, dir) = makeStore()
    defer { try? FileManager.default.removeItem(at: dir) }
    let a = store.add(note("Fix the Login bug"))
    var b = note("Unrelated")
    b.ocrText = "error: login timeout"
    let bb = store.add(b)
    #expect(store.matchingCardIDs("login") == [a.id, bb.id])
    #expect(store.matchingCardIDs("LOGIN bug") == [a.id])
    #expect(store.matchingCardIDs("nothing").isEmpty)
  }

  @Test("Tidy up keeps zoned cards inside their zone without overlap")
  func tidy() {
    let (store, dir) = makeStore()
    defer { try? FileManager.default.removeItem(at: dir) }
    let zone = store.addZone(title: "Z", frame: CGRect(x: 0, y: 0, width: 460, height: 200))
    let ids = (0..<4).map { i in store.add(note("\(i)", at: CGPoint(x: 100 + i, y: 100))).id }
    store.tidyUp()
    let zf = store.zones.first { $0.id == zone.id }!.frame.cgRect
    let frames = ids.compactMap { store.card($0)?.frame.cgRect }
    for f in frames { #expect(zf.contains(f)) }
    for i in frames.indices {
      for j in frames.indices where j > i {
        #expect(!frames[i].intersects(frames[j]))
      }
    }
  }
}

@Suite("TextDetector")
struct TextDetectorTests {
  @Test("Detects links, emails and phone numbers without duplicates")
  func detect() {
    let text = "See https://example.com/a and https://example.com/a, mail bob@example.com or call (555) 123-4567"
    let items = TextDetector.detect(in: text)
    #expect(items.filter { $0.kind == .link }.count == 1)
    #expect(items.contains(DetectedItem(kind: .email, value: "bob@example.com")))
    #expect(items.contains { $0.kind == .phone })
  }

  @Test("ssh-style user@ip is not treated as an email")
  func sshTargetNotEmail() {
    #expect(!TextDetector.detect(in: "ssh deploy@10.0.0.4").contains { $0.kind == .email })
  }

  @Test("singleWebURL only accepts a lone web URL")
  func singleURL() {
    #expect(TextDetector.singleWebURL(in: "  https://github.com/x \n")?.host == "github.com")
    #expect(TextDetector.singleWebURL(in: "www.apple.com")?.absoluteString == "https://www.apple.com")
    #expect(TextDetector.singleWebURL(in: "see https://github.com") == nil)
    #expect(TextDetector.singleWebURL(in: "file:///tmp/x") == nil)
  }
}

@MainActor
@Suite("CardFactory")
struct CardFactoryTests {
  private func makeFactory() -> (CardFactory, BoardStore, URL) {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("board-\(UUID().uuidString)")
    let store = BoardStore(rootURL: dir, saveDelay: 0)
    return (CardFactory(store: store, tilt: { false }), store, dir)
  }

  @Test("Plain text becomes a text card with source context")
  func textFromPasteboard() {
    let (factory, _, dir) = makeFactory()
    defer { try? FileManager.default.removeItem(at: dir) }
    let pb = NSPasteboard(name: NSPasteboard.Name("board-test-\(UUID().uuidString)"))
    pb.clearContents()
    pb.setString("call bob tomorrow", forType: .string)
    let source = SourceContext(appName: "Slack", bundleID: "com.tinyspeck.slackmacgap")
    let cards = factory.cards(from: pb, at: .zero, source: source)
    #expect(cards.count == 1)
    #expect(cards.first?.kind == .text)
    #expect(cards.first?.text == "call bob tomorrow")
    #expect(cards.first?.source?.appName == "Slack")
    pb.releaseGlobally()
  }

  @Test("A lone URL string becomes a link card")
  func linkFromPasteboard() {
    let (factory, _, dir) = makeFactory()
    defer { try? FileManager.default.removeItem(at: dir) }
    let pb = NSPasteboard(name: NSPasteboard.Name("board-test-\(UUID().uuidString)"))
    pb.clearContents()
    pb.setString("https://github.com/PortableSheep/SnipSnap", forType: .string)
    let cards = factory.cards(from: pb, at: .zero, source: nil)
    #expect(cards.first?.kind == .link)
    #expect(cards.first?.url?.host == "github.com")
    pb.releaseGlobally()
  }

  @Test("Image data becomes a capture card with stored assets")
  func imageFromPasteboard() throws {
    let (factory, store, dir) = makeFactory()
    defer { try? FileManager.default.removeItem(at: dir) }
    let image = NSImage(size: NSSize(width: 400, height: 200))
    image.lockFocus()
    NSColor.red.setFill()
    NSRect(x: 0, y: 0, width: 400, height: 200).fill()
    image.unlockFocus()
    let rep = NSBitmapImageRep(data: try #require(image.tiffRepresentation))
    let png = try #require(rep?.representation(using: .png, properties: [:]))

    let pb = NSPasteboard(name: NSPasteboard.Name("board-test-\(UUID().uuidString)"))
    pb.clearContents()
    pb.setData(png, forType: .png)
    let card = try #require(factory.cards(from: pb, at: .zero, source: nil).first)
    #expect(card.kind == .capture)
    let asset = try #require(card.imageAsset)
    #expect(FileManager.default.fileExists(atPath: store.assetURL(asset).path))
    #expect(card.frame.width > card.frame.height)
    pb.releaseGlobally()
  }
}

@Suite("BrowserTabReader")
struct BrowserTabReaderTests {
  @Test("Parses URL and title output")
  func parse() {
    let tab = BrowserTabReader.parse("https://example.com/page\nExample Page\n")
    #expect(tab?.url.absoluteString == "https://example.com/page")
    #expect(tab?.title == "Example Page")
  }

  @Test("Rejects empty and non-web output")
  func parseRejects() {
    #expect(BrowserTabReader.parse("") == nil)
    #expect(BrowserTabReader.parse("chrome://newtab/\nNew Tab") == nil)
    #expect(BrowserTabReader.parse("https://example.com\n")?.title == nil)
  }

  @Test("Only known browsers are supported")
  func supported() {
    #expect(BrowserTabReader.isSupported("com.apple.Safari"))
    #expect(BrowserTabReader.isSupported("com.google.Chrome"))
    #expect(!BrowserTabReader.isSupported("com.apple.finder"))
  }
}

@MainActor
@Suite("HotCornerMonitor")
struct HotCornerMonitorTests {
  @Test("Corner rects sit at the screen corners")
  func cornerRects() {
    let frame = CGRect(x: 100, y: 50, width: 1000, height: 800)
    #expect(HotCornerMonitor.cornerRect(.bottomLeft, in: frame, size: 2) == CGRect(x: 100, y: 50, width: 2, height: 2))
    #expect(HotCornerMonitor.cornerRect(.topRight, in: frame, size: 2) == CGRect(x: 1098, y: 848, width: 2, height: 2))
    #expect(HotCornerMonitor.cornerRect(.none, in: frame, size: 2) == .zero)
  }
}
