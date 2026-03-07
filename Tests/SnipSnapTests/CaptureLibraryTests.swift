import Foundation
import Testing
@testable import SnipSnap

@Suite("CaptureLibrary")
struct CaptureLibraryTests {

  private func makeTempDir() throws -> URL {
    let url = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
  }

  private func createFile(in dir: URL, name: String) throws {
    let fileURL = dir.appendingPathComponent(name)
    try Data("test".utf8).write(to: fileURL)
  }

  @Test("Empty directory produces empty items")
  @MainActor func emptyDirectory() throws {
    let tempDir = try makeTempDir()
    defer { try? FileManager.default.removeItem(at: tempDir) }

    let library = CaptureLibrary(capturesDirURL: tempDir)
    #expect(library.items.isEmpty)
  }

  @Test("Finds a single .png file after refresh")
  @MainActor func findsPngFile() throws {
    let tempDir = try makeTempDir()
    defer { try? FileManager.default.removeItem(at: tempDir) }

    let library = CaptureLibrary(capturesDirURL: tempDir)
    try createFile(in: tempDir, name: "screenshot.png")
    library.refresh()

    #expect(library.items.count == 1)
    #expect(library.items.first?.url.lastPathComponent == "screenshot.png")
  }

  @Test("Finds multiple files with different extensions")
  @MainActor func findsMultipleFiles() throws {
    let tempDir = try makeTempDir()
    defer { try? FileManager.default.removeItem(at: tempDir) }

    try createFile(in: tempDir, name: "capture.png")
    try createFile(in: tempDir, name: "recording.mov")

    let library = CaptureLibrary(capturesDirURL: tempDir)
    #expect(library.items.count == 2)

    let extensions = Set(library.items.map { $0.url.pathExtension })
    #expect(extensions.contains("png"))
    #expect(extensions.contains("mov"))
  }

  @Test("Ignores non-matching file extensions")
  @MainActor func ignoresNonMatchingExtensions() throws {
    let tempDir = try makeTempDir()
    defer { try? FileManager.default.removeItem(at: tempDir) }

    try createFile(in: tempDir, name: "notes.txt")
    try createFile(in: tempDir, name: "document.pdf")
    try createFile(in: tempDir, name: "valid.png")

    let library = CaptureLibrary(capturesDirURL: tempDir)
    #expect(library.items.count == 1)
    #expect(library.items.first?.url.lastPathComponent == "valid.png")
  }

  @Test("delete() removes file from disk and items list")
  @MainActor func deleteRemovesFileAndItem() throws {
    let tempDir = try makeTempDir()
    defer { try? FileManager.default.removeItem(at: tempDir) }

    try createFile(in: tempDir, name: "to-delete.png")
    let library = CaptureLibrary(capturesDirURL: tempDir)
    #expect(library.items.count == 1)

    let item = try #require(library.items.first)
    try library.delete(item)

    #expect(library.items.isEmpty)
    #expect(!FileManager.default.fileExists(atPath: item.url.path))
  }
}
