import Foundation
import Testing
@testable import SnipSnap

@Suite("Strip layout")
struct StripLayoutTests {
  private let positions: [StripDockPosition] = [.left, .right, .top, .bottom]

  @Test
  func preservesEdgeAcrossDisplayGeometries() {
    let visibleFrames = [
      CGRect(x: 0, y: 70, width: 1512, height: 880),
      CGRect(x: -2560, y: 100, width: 2560, height: 1340),
      CGRect(x: 1512, y: -1080, width: 1920, height: 1055)
    ]
    for visible in visibleFrames {
      for position in positions {
        let frame = StripLayout.dockedFrame(position: position, visible: visible)
        #expect(visible.contains(frame))
        #expect((frame.height > frame.width) == position.isVertical)
        switch position {
        case .left:
          #expect(frame.minX == visible.minX + StripLayout.margin)
          #expect(frame.midY == visible.midY)
        case .right:
          #expect(frame.maxX == visible.maxX - StripLayout.margin)
          #expect(frame.midY == visible.midY)
        case .top:
          #expect(frame.maxY == visible.maxY - StripLayout.margin)
          #expect(frame.midX == visible.midX)
        case .bottom:
          #expect(frame.minY == visible.minY + StripLayout.margin)
          #expect(frame.midX == visible.midX)
        }
      }
    }
  }

  @Test
  func avoidsSideDock() {
    let screen = CGRect(x: -1920, y: 0, width: 1920, height: 1080)
    for visible in [
      CGRect(x: -1850, y: 0, width: 1850, height: 1055),
      CGRect(x: -1920, y: 0, width: 1850, height: 1055)
    ] {
      for position in positions {
        let frame = StripLayout.dockedFrame(position: position, visible: visible)
        #expect(visible.contains(frame))
        #expect(screen.contains(frame))
      }
    }
  }

  @Test
  func tabHasOnlySmallEdgeHitArea() {
    let screen = CGRect(x: -1920, y: -300, width: 1920, height: 1080)
    let visible = CGRect(x: -1920, y: -230, width: 1920, height: 985)
    for position in positions {
      let frame = StripLayout.tabFrame(position: position, screen: screen, visible: visible)
      #expect(frame.size == (position.isVertical ? CGSize(width: 14, height: 44) : CGSize(width: 44, height: 14)))
      #expect(screen.contains(frame))
      switch position {
      case .left: #expect(frame.minX == screen.minX)
      case .right: #expect(frame.maxX == screen.maxX)
      case .top: #expect(frame.maxY == visible.maxY)
      case .bottom: #expect(frame.minY == visible.minY)
      }
    }
  }

  @Test
  func snapsToEachEdgeAfterDrag() {
    let screen = CGRect(x: -1920, y: 0, width: 1920, height: 1080)
    let visible = CGRect(x: -1920, y: 70, width: 1920, height: 985)
    for position in positions {
      let frame = StripLayout.dockedFrame(position: position, visible: visible)
      #expect(StripLayout.nearestEdge(frame: frame, screen: screen, visible: visible) == position)
    }
  }

  @Test
  func snapThresholdIs44Points() {
    let screen = CGRect(x: 0, y: 0, width: 1920, height: 1080)
    let visible = CGRect(x: 0, y: 70, width: 1920, height: 985)
    let frame = StripLayout.dockedFrame(position: .left, visible: visible)
    #expect(StripLayout.nearestEdge(frame: frame.offsetBy(dx: 44, dy: 0), screen: screen, visible: visible) == .left)
    #expect(StripLayout.nearestEdge(frame: frame.offsetBy(dx: 45, dy: 0), screen: screen, visible: visible) == nil)
    #expect(StripLayout.nearestEdge(frame: CGRect(x: 800, y: 300, width: 112, height: 400),
                                  screen: screen, visible: visible) == nil)
  }
}
