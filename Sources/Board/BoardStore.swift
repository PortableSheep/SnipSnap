import AppKit
import Combine
import Foundation
import ImageIO
import UniformTypeIdentifiers
import os.log

private let boardLog = OSLog(subsystem: "com.snipsnap.Snipsnap", category: "Board")

/// Owns the Board document (cards + zones) and its on-disk assets.
///
/// Layout on disk:
///   <root>/board.json
///   <root>/assets/<card-id>.<ext>          (copied images)
///   <root>/assets/<card-id>@thumb.jpg     (thumbnails for fast rendering)
@MainActor
final class BoardStore: ObservableObject {
  @Published private(set) var board: Board

  let rootURL: URL
  let assetsURL: URL
  private var boardFileURL: URL { rootURL.appendingPathComponent("board.json") }

  private let saveDelay: TimeInterval
  private var saveWorkItem: DispatchWorkItem?
  private let imageCache = NSCache<NSString, NSImage>()

  nonisolated static func defaultRootURL() -> URL {
    let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
    return appSupport
      .appendingPathComponent("SnipSnap", isDirectory: true)
      .appendingPathComponent("board", isDirectory: true)
  }

  init(rootURL: URL = BoardStore.defaultRootURL(), saveDelay: TimeInterval = 0.4) {
    self.rootURL = rootURL
    self.assetsURL = rootURL.appendingPathComponent("assets", isDirectory: true)
    self.saveDelay = saveDelay
    try? FileManager.default.createDirectory(at: assetsURL, withIntermediateDirectories: true)
    self.board = Self.load(from: rootURL.appendingPathComponent("board.json"))
  }

  private static func load(from url: URL) -> Board {
    guard let data = try? Data(contentsOf: url) else { return Board() }
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    do {
      return try decoder.decode(Board.self, from: data)
    } catch {
      os_log(.error, log: boardLog, "Failed to decode board.json: %{public}@", error.localizedDescription)
      // Keep the unreadable file around rather than silently overwriting it.
      let backup = url.deletingPathExtension().appendingPathExtension("corrupt-\(Int(Date().timeIntervalSince1970)).json")
      try? FileManager.default.copyItem(at: url, to: backup)
      return Board()
    }
  }

  // MARK: - Saving

  private func scheduleSave() {
    saveWorkItem?.cancel()
    let work = DispatchWorkItem { [weak self] in
      Task { @MainActor in self?.saveNow() }
    }
    saveWorkItem = work
    DispatchQueue.main.asyncAfter(deadline: .now() + saveDelay, execute: work)
  }

  func saveNow() {
    saveWorkItem?.cancel()
    saveWorkItem = nil
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    encoder.dateEncodingStrategy = .iso8601
    do {
      let data = try encoder.encode(board)
      try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
      try data.write(to: boardFileURL, options: [.atomic])
    } catch {
      os_log(.error, log: boardLog, "Failed to save board: %{public}@", error.localizedDescription)
    }
  }

  private func mutate(_ body: (inout Board) -> Void) {
    body(&board)
    scheduleSave()
  }

  // MARK: - Queries

  var cards: [BoardCard] { board.cards.filter { !$0.isArchived } }
  var zones: [BoardZone] { board.zones }

  /// Cards in paint order (lowest zIndex first).
  var cardsInPaintOrder: [BoardCard] { cards.sorted { $0.zIndex < $1.zIndex } }

  func card(_ id: UUID) -> BoardCard? { board.cards.first { $0.id == id } }

  func matchingCardIDs(_ query: String) -> Set<UUID> {
    let terms = query.lowercased().split(whereSeparator: { $0.isWhitespace }).map(String.init)
    guard !terms.isEmpty else { return Set(cards.map(\.id)) }
    return Set(cards.filter { card in
      let haystack = card.searchableText.lowercased()
      return terms.allSatisfy { haystack.contains($0) }
    }.map(\.id))
  }

  // MARK: - Cards

  @discardableResult
  func add(_ card: BoardCard) -> BoardCard {
    var card = card
    card.zIndex = (board.cards.map(\.zIndex).max() ?? 0) + 1
    card.zoneID = zoneID(containing: card.frame.cgRect)
    mutate { $0.cards.append(card) }
    return card
  }

  func update(_ id: UUID, _ body: (inout BoardCard) -> Void) {
    guard let idx = board.cards.firstIndex(where: { $0.id == id }) else { return }
    mutate { board in
      body(&board.cards[idx])
      board.cards[idx].updatedAt = Date()
    }
  }

  func delete(_ ids: Set<UUID>) {
    let removed = board.cards.filter { ids.contains($0.id) }
    mutate { $0.cards.removeAll { ids.contains($0.id) } }
    for card in removed { removeAssets(for: card) }
  }

  /// Soft-delete: hides cards but keeps their assets so the action can be undone.
  func archive(_ ids: Set<UUID>) {
    mutate { board in
      for i in board.cards.indices where ids.contains(board.cards[i].id) {
        board.cards[i].isArchived = true
        board.cards[i].pin = nil
      }
    }
  }

  func restore(_ ids: Set<UUID>) {
    mutate { board in
      for i in board.cards.indices where ids.contains(board.cards[i].id) {
        board.cards[i].isArchived = false
      }
    }
  }

  /// Permanently removes soft-deleted cards (called on launch).
  func purgeArchived() {
    let ids = Set(board.cards.filter(\.isArchived).map(\.id))
    if !ids.isEmpty { delete(ids) }
  }

  func setFrame(_ id: UUID, _ frame: CGRect) {
    update(id) { card in
      card.frame = CodableRect(frame)
    }
    reassignZone(for: id)
  }

  func move(_ ids: Set<UUID>, by delta: CGSize) {
    guard delta != .zero else { return }
    mutate { board in
      for i in board.cards.indices where ids.contains(board.cards[i].id) {
        board.cards[i].frame.x += delta.width
        board.cards[i].frame.y += delta.height
      }
    }
    for id in ids { reassignZone(for: id) }
  }

  func bringToFront(_ ids: Set<UUID>) {
    var top = board.cards.map(\.zIndex).max() ?? 0
    let ordered = board.cards.filter { ids.contains($0.id) }.sorted { $0.zIndex < $1.zIndex }
    guard !ordered.isEmpty else { return }
    // Skip the write if they're already on top.
    if ordered.count == 1, ordered[0].zIndex == top { return }
    mutate { board in
      for card in ordered {
        top += 1
        if let i = board.cards.firstIndex(where: { $0.id == card.id }) {
          board.cards[i].zIndex = top
        }
      }
    }
  }

  func setTodo(_ ids: Set<UUID>, _ state: TodoState?) {
    mutate { board in
      for i in board.cards.indices where ids.contains(board.cards[i].id) {
        board.cards[i].todo = state
        board.cards[i].updatedAt = Date()
      }
    }
  }

  func setPin(_ id: UUID, _ pin: PinState?) {
    update(id) { $0.pin = pin }
  }

  // MARK: - Zones

  @discardableResult
  func addZone(title: String, frame: CGRect, colorHex: String? = nil) -> BoardZone {
    let color = colorHex ?? BoardPalette.zoneColors[board.zones.count % BoardPalette.zoneColors.count]
    let zone = BoardZone(title: title, frame: CodableRect(frame), colorHex: color)
    mutate { $0.zones.append(zone) }
    reassignAllZones()
    return zone
  }

  func updateZone(_ id: UUID, _ body: (inout BoardZone) -> Void) {
    guard let idx = board.zones.firstIndex(where: { $0.id == id }) else { return }
    mutate { body(&$0.zones[idx]) }
  }

  func setZoneFrame(_ id: UUID, _ frame: CGRect) {
    updateZone(id) { $0.frame = CodableRect(frame) }
    reassignAllZones()
  }

  /// Moves a zone and every card currently assigned to it.
  func moveZone(_ id: UUID, by delta: CGSize) {
    guard delta != .zero else { return }
    mutate { board in
      guard let zi = board.zones.firstIndex(where: { $0.id == id }) else { return }
      board.zones[zi].frame.x += delta.width
      board.zones[zi].frame.y += delta.height
      for i in board.cards.indices where board.cards[i].zoneID == id {
        board.cards[i].frame.x += delta.width
        board.cards[i].frame.y += delta.height
      }
    }
  }

  func deleteZone(_ id: UUID) {
    mutate { board in
      board.zones.removeAll { $0.id == id }
      for i in board.cards.indices where board.cards[i].zoneID == id {
        board.cards[i].zoneID = nil
      }
    }
  }

  /// Adds Todo / Doing / Done zones side by side starting at `origin`.
  func applyTodoTemplate(origin: CGPoint, zoneSize: CGSize = CGSize(width: 320, height: 520)) {
    let titles = ["Todo", "Doing", "Done"]
    let colors = ["#5E9CFF", "#FFB547", "#4CD787"]
    for (i, title) in titles.enumerated() {
      let frame = CGRect(
        x: origin.x + CGFloat(i) * (zoneSize.width + 24),
        y: origin.y,
        width: zoneSize.width,
        height: zoneSize.height
      )
      addZone(title: title, frame: frame, colorHex: colors[i])
    }
  }

  /// Zone whose frame contains the center of `rect` (topmost zone wins).
  func zoneID(containing rect: CGRect) -> UUID? {
    let center = CGPoint(x: rect.midX, y: rect.midY)
    return board.zones.last(where: { $0.frame.cgRect.contains(center) })?.id
  }

  private func reassignZone(for id: UUID) {
    guard let idx = board.cards.firstIndex(where: { $0.id == id }) else { return }
    let newZone = zoneID(containing: board.cards[idx].frame.cgRect)
    if board.cards[idx].zoneID != newZone {
      mutate { $0.cards[idx].zoneID = newZone }
    }
  }

  private func reassignAllZones() {
    mutate { board in
      for i in board.cards.indices {
        let center = CGPoint(x: board.cards[i].frame.cgRect.midX, y: board.cards[i].frame.cgRect.midY)
        board.cards[i].zoneID = board.zones.last(where: { $0.frame.cgRect.contains(center) })?.id
      }
    }
  }

  // MARK: - Layout helpers

  /// Arranges cards into tidy grids: zoned cards inside their zone (growing it as needed),
  /// loose cards to the right of all zones.
  func tidyUp(spacing: CGFloat = 18, headerHeight: CGFloat = 44) {
    mutate { board in
      for zi in board.zones.indices {
        let zone = board.zones[zi]
        let zf = zone.frame.cgRect
        let members = board.cards.indices
          .filter { board.cards[$0].zoneID == zone.id && !board.cards[$0].isArchived }
          .sorted { board.cards[$0].createdAt < board.cards[$1].createdAt }
        var x = zf.minX + spacing
        var y = zf.minY + headerHeight
        var rowHeight: CGFloat = 0
        var maxY = y
        for ci in members {
          let size = board.cards[ci].frame.cgRect.size
          if x + size.width > zf.maxX - spacing, x > zf.minX + spacing {
            x = zf.minX + spacing
            y += rowHeight + spacing
            rowHeight = 0
          }
          board.cards[ci].frame.x = x
          board.cards[ci].frame.y = y
          board.cards[ci].rotation = 0
          x += size.width + spacing
          rowHeight = max(rowHeight, size.height)
          maxY = y + rowHeight
        }
        let neededHeight = maxY + spacing - zf.minY
        if neededHeight > zf.height {
          board.zones[zi].frame.height = neededHeight
        }
      }

      let looseStartX = (board.zones.map { $0.frame.cgRect.maxX }.max() ?? 0) + (board.zones.isEmpty ? 60 : 48)
      let loose = board.cards.indices
        .filter { board.cards[$0].zoneID == nil && !board.cards[$0].isArchived }
        .sorted { board.cards[$0].createdAt < board.cards[$1].createdAt }
      let columns = max(1, Int(ceil(sqrt(Double(loose.count)))))
      var x = looseStartX
      var y: CGFloat = 90
      var rowHeight: CGFloat = 0
      for (n, ci) in loose.enumerated() {
        if n > 0, n % columns == 0 {
          x = looseStartX
          y += rowHeight + spacing
          rowHeight = 0
        }
        let size = board.cards[ci].frame.cgRect.size
        board.cards[ci].frame.x = x
        board.cards[ci].frame.y = y
        board.cards[ci].rotation = 0
        x += size.width + spacing
        rowHeight = max(rowHeight, size.height)
      }
    }
  }

  /// Picks a free-ish spot for a new card: cascades from the top-left of `visibleRect`.
  func insertionOrigin(in visibleRect: CGRect) -> CGPoint {
    let base = CGPoint(x: visibleRect.minX + 60, y: visibleRect.minY + 100)
    var candidate = base
    let occupied = Set(cards.map { "\(Int($0.frame.x)):\(Int($0.frame.y))" })
    var step = 0
    while occupied.contains("\(Int(candidate.x)):\(Int(candidate.y))"), step < 40 {
      step += 1
      candidate = CGPoint(x: base.x + CGFloat(step) * 28, y: base.y + CGFloat(step) * 28)
    }
    return candidate
  }

  func setViewport(_ viewport: BoardViewport) {
    guard viewport != board.viewport else { return }
    mutate { $0.viewport = viewport }
  }

  // MARK: - Assets

  func assetURL(_ name: String) -> URL { assetsURL.appendingPathComponent(name) }

  /// Full-size image for a card (prefers an annotated version written by the editor).
  func imageURL(for card: BoardCard) -> URL? {
    guard let name = card.imageAsset else { return nil }
    let url = assetURL(name)
    let annotated = url.deletingPathExtension().appendingPathExtension("annotated.png")
    return FileManager.default.fileExists(atPath: annotated.path) ? annotated : url
  }

  func image(named name: String?) -> NSImage? {
    guard let name else { return nil }
    if let cached = imageCache.object(forKey: name as NSString) { return cached }
    guard let img = NSImage(contentsOf: assetURL(name)) else { return nil }
    imageCache.setObject(img, forKey: name as NSString)
    return img
  }

  func thumbnail(for card: BoardCard) -> NSImage? {
    image(named: card.thumbAsset) ?? image(named: card.imageAsset)
  }

  struct ImportedImage {
    var asset: String
    var thumb: String?
    var pixelSize: CGSize
  }

  /// Copies an image file into the board's asset folder and generates a thumbnail.
  func importImage(at fileURL: URL, cardID: UUID) throws -> ImportedImage {
    let ext = fileURL.pathExtension.isEmpty ? "png" : fileURL.pathExtension.lowercased()
    let name = "\(cardID.uuidString).\(ext)"
    let dest = assetURL(name)
    try? FileManager.default.removeItem(at: dest)
    try FileManager.default.copyItem(at: fileURL, to: dest)
    return finishImport(name: name, url: dest, cardID: cardID)
  }

  /// Writes raw image data (PNG/TIFF/etc.) into the asset folder as PNG.
  func importImage(data: Data, cardID: UUID) throws -> ImportedImage {
    let name = "\(cardID.uuidString).png"
    let dest = assetURL(name)
    guard let src = CGImageSourceCreateWithData(data as CFData, nil),
          let cg = CGImageSourceCreateImageAtIndex(src, 0, nil),
          let destRef = CGImageDestinationCreateWithURL(dest as CFURL, UTType.png.identifier as CFString, 1, nil) else {
      throw CocoaError(.fileWriteUnknown)
    }
    CGImageDestinationAddImage(destRef, cg, nil)
    guard CGImageDestinationFinalize(destRef) else { throw CocoaError(.fileWriteUnknown) }
    return finishImport(name: name, url: dest, cardID: cardID)
  }

  /// Saves arbitrary image data (e.g. favicon / link preview) as a PNG asset.
  func writeImageAsset(_ image: NSImage, name: String) -> String? {
    guard let tiff = image.tiffRepresentation,
          let rep = NSBitmapImageRep(data: tiff),
          let png = rep.representation(using: .png, properties: [:]) else { return nil }
    do {
      try png.write(to: assetURL(name), options: [.atomic])
      imageCache.removeObject(forKey: name as NSString)
      return name
    } catch {
      return nil
    }
  }

  private func finishImport(name: String, url: URL, cardID: UUID) -> ImportedImage {
    let size = Self.pixelSize(of: url) ?? CGSize(width: 800, height: 600)
    let thumb = writeThumbnail(from: url, cardID: cardID)
    return ImportedImage(asset: name, thumb: thumb, pixelSize: size)
  }

  @discardableResult
  func writeThumbnail(from url: URL, cardID: UUID, maxPixel: Int = 720) -> String? {
    let name = "\(cardID.uuidString)@thumb.jpg"
    let dest = assetURL(name)
    guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
    let opts: [CFString: Any] = [
      kCGImageSourceCreateThumbnailFromImageAlways: true,
      kCGImageSourceCreateThumbnailWithTransform: true,
      kCGImageSourceThumbnailMaxPixelSize: maxPixel,
    ]
    guard let thumb = CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary),
          let destRef = CGImageDestinationCreateWithURL(dest as CFURL, UTType.jpeg.identifier as CFString, 1, nil) else {
      return nil
    }
    CGImageDestinationAddImage(destRef, thumb, [kCGImageDestinationLossyCompressionQuality: 0.85] as CFDictionary)
    guard CGImageDestinationFinalize(destRef) else { return nil }
    imageCache.removeObject(forKey: name as NSString)
    return name
  }

  /// Regenerates a capture card's thumbnail (e.g. after it was annotated in the editor).
  func refreshThumbnail(for id: UUID) {
    guard let card = card(id), let url = imageURL(for: card) else { return }
    let thumb = writeThumbnail(from: url, cardID: id)
    update(id) { $0.thumbAsset = thumb }
  }

  /// Finds the card that owns an asset file (used to react to editor saves).
  func cardID(forAssetURL url: URL) -> UUID? {
    let name = url.lastPathComponent
    return board.cards.first { $0.imageAsset == name }?.id
  }

  private func removeAssets(for card: BoardCard) {
    let fm = FileManager.default
    for name in [card.imageAsset, card.thumbAsset, card.faviconAsset, card.previewAsset].compactMap({ $0 }) {
      try? fm.removeItem(at: assetURL(name))
      imageCache.removeObject(forKey: name as NSString)
    }
    if let name = card.imageAsset {
      let base = assetURL(name)
      try? fm.removeItem(at: base.deletingPathExtension().appendingPathExtension("annotated.png"))
      try? fm.removeItem(at: base.appendingPathExtension("snipsnap.json"))
    }
  }

  static func pixelSize(of url: URL) -> CGSize? {
    guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
          let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any],
          let w = props[kCGImagePropertyPixelWidth] as? Double,
          let h = props[kCGImagePropertyPixelHeight] as? Double else { return nil }
    return CGSize(width: w, height: h)
  }
}
