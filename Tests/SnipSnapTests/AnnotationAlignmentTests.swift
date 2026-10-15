import Foundation
import Testing
@testable import SnipSnap

@Suite("Annotation alignment")
struct AnnotationAlignmentTests {
  @Test("Snap edges and centers independently on each axis")
  func alignsAxes() {
    let result = AnnotationAlignment.snap(
      bounds: CGRect(x: 48, y: 103, width: 20, height: 20),
      targets: [CGRect(x: 50, y: 100, width: 20, height: 20)], tolerance: 5
    )
    #expect(result.offset == CGSize(width: 2, height: -3))
    #expect(result.verticalGuide != nil)
    #expect(result.horizontalGuide != nil)
  }

  @Test("Distant annotations do not attract the selection")
  func outsideThreshold() {
    let result = AnnotationAlignment.snap(
      bounds: CGRect(x: 20, y: 20, width: 20, height: 20),
      targets: [CGRect(x: 100, y: 100, width: 20, height: 20)], tolerance: 5
    )
    #expect(result.offset == .zero)
    #expect(result.verticalGuide == nil)
    #expect(result.horizontalGuide == nil)
  }

  @Test("Group bounds can align with the screenshot center")
  func centersGroup() {
    let result = AnnotationAlignment.snap(
      bounds: CGRect(x: 78, y: 39, width: 40, height: 20),
      targets: [CGRect(x: 0, y: 0, width: 200, height: 100)], tolerance: 5
    )
    #expect(result.offset == CGSize(width: 2, height: 1))
    #expect(result.verticalGuide == 100)
    #expect(result.horizontalGuide == 50)
  }

  @Test("Closest target wins and null geometry is ignored")
  func nearestTarget() {
    let result = AnnotationAlignment.snap(
      bounds: CGRect(x: 20, y: 30, width: 10, height: 10),
      targets: [.null, CGRect(x: 22, y: 100, width: 10, height: 10),
                CGRect(x: 24, y: 150, width: 10, height: 10)], tolerance: 5
    )
    #expect(result.offset.width == -1)
    #expect(result.horizontalGuide == nil)
  }
}
