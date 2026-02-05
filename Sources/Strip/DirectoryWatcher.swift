import Foundation

final class DirectoryWatcher {
  private var source: DispatchSourceFileSystemObject?
  private var fd: CInt = -1

  func start(url: URL, onChange: @escaping () -> Void) {
    stop()

    fd = open(url.path, O_EVTONLY)
    guard fd >= 0 else { return }

    let src = DispatchSource.makeFileSystemObjectSource(
      fileDescriptor: fd,
      eventMask: [.write, .delete, .rename, .attrib, .extend],
      queue: DispatchQueue.global(qos: .utility)
    )

    src.setEventHandler(handler: onChange)
    src.setCancelHandler { [fd] in
      if fd >= 0 { close(fd) }
    }

    source = src
    src.resume()
  }

  func stop() {
    source?.cancel()
    source = nil
    fd = -1
  }

  deinit {
    stop()
  }
}
