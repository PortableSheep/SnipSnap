import AppKit

/// Describes the camera housing ("notch") at the top of a built-in display, in the board's
/// view coordinates (top-left origin, spanning the full screen frame).
struct BoardNotch: Equatable {
  /// Height of the notch / unsafe top band.
  var height: CGFloat
  /// Unobscured width to the left of the notch.
  var leftWidth: CGFloat
  /// Unobscured width to the right of the notch.
  var rightWidth: CGFloat

  @MainActor
  init?(screen: NSScreen) {
    let top = screen.safeAreaInsets.top
    guard top > 0 else { return nil }
    let left = screen.auxiliaryTopLeftArea?.width ?? 0
    let right = screen.auxiliaryTopRightArea?.width ?? 0
    self.init(height: top, leftWidth: left, rightWidth: right)
  }

  init(height: CGFloat, leftWidth: CGFloat, rightWidth: CGFloat) {
    self.height = height
    self.leftWidth = leftWidth
    self.rightWidth = rightWidth
  }
}

/// Places the floating board toolbar so it is never hidden behind a display notch.
enum BoardChromeLayout {
  static let defaultTopMargin: CGFloat = 18
  static let belowNotchMargin: CGFloat = 10
  static let besideNotchVerticalInset: CGFloat = 3
  static let besideNotchHorizontalInset: CGFloat = 12

  /// Returns the toolbar's center point in view coordinates (top-left origin).
  /// Prefers the default top-center spot; on notched screens, tries the band left of the
  /// notch, then right of it, and otherwise drops the toolbar just below the notch.
  static func toolbarCenter(canvasWidth: CGFloat, toolbarSize: CGSize, notch: BoardNotch?) -> CGPoint {
    let size = toolbarSize
    guard let notch else {
      return CGPoint(x: canvasWidth / 2, y: defaultTopMargin + size.height / 2)
    }
    let fitsVertically = size.height > 0 && size.height + besideNotchVerticalInset * 2 <= notch.height
    let neededWidth = size.width + besideNotchHorizontalInset * 2
    if fitsVertically, size.width > 0 {
      if neededWidth <= notch.leftWidth {
        return CGPoint(x: notch.leftWidth / 2, y: notch.height / 2)
      }
      if neededWidth <= notch.rightWidth {
        return CGPoint(x: canvasWidth - notch.rightWidth / 2, y: notch.height / 2)
      }
    }
    return CGPoint(x: canvasWidth / 2, y: notch.height + belowNotchMargin + size.height / 2)
  }
}
