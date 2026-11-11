import Foundation
import Testing
@testable import TaliCore

/// Android's SnapTest, ported (the two tests of old group shapes upgrading aren't: that loader isn't ported).
struct SnapTests {
  func rect(_ l: Float, _ t: Float, _ r: Float, _ b: Float) -> ShapeGeometry {
    .poly(points: [Pt(l, t), Pt(r, t), Pt(r, b), Pt(l, b)], closed: true)
  }
  func line(_ a: Pt, _ b: Pt) -> ShapeGeometry { .line(a: a, b: b, arrowStart: false, arrowEnd: false, ticks: false) }
  func close(_ a: Float, _ b: Float, _ tol: Float = 0.01) -> Bool { abs(a - b) <= tol }
  func aligns(_ g: [SnapGuide]) -> [(vertical: Bool, at: Float)] {
    g.compactMap { if case let .align(v, at, _, _) = $0 { (v, at) } else { nil } }
  }

  @Test func aLineEndLocksOntoAnUprightLine() {
    let wall = line(Pt(100, 0), Pt(100, 200)).snapFeatures()
    let beam = line(Pt(0, 80), Pt(94, 80)).snapFeatures()
    let r = Snap.move(beam, [wall], tol: 10)
    #expect(close(r.offset.x, 6) && close(r.offset.y, 0))
    #expect(r.guides.contains { $0.isTouch })
  }

  @Test func anEndOnACornerBeatsAnEdge() {
    let r = Snap.move(line(Pt(0, 0), Pt(96, 97)).snapFeatures(), [rect(100, 100, 200, 160).snapFeatures()], tol: 10)
    #expect(close(r.offset.x, 4) && close(r.offset.y, 3))
  }

  @Test func boxesLineUpTheirTopsAndMiddles() {
    let r = Snap.move(rect(300, -5, 360, 40).snapFeatures(), [rect(0, 0, 100, 50).snapFeatures()], tol: 8)
    #expect(close(r.offset.y, 5) && close(r.offset.x, 0))
    #expect(r.guides.count == 1 && !r.guides[0].isTouch)
  }

  @Test func sameSizeBoxesShowEveryLineThatLinesUp() {
    let r = Snap.move(rect(300, 4, 400, 54).snapFeatures(), [rect(0, 0, 100, 50).snapFeatures()], tol: 8)
    #expect(close(r.offset.y, -4))
    #expect(aligns(r.guides).filter { !$0.vertical }.count == 3)
  }

  @Test func resizingLinesUpTheFarSide() {
    let (s, guides) = Snap.scale(Rect(300, 0, 400, 48), Pt(300, 0), 1.02, [rect(0, 0, 200, 50).snapFeatures()], tol: 4)
    #expect(close(s, 50 / 48, 0.001))
    #expect(aligns(guides).contains { !$0.vertical && $0.at == 50 })
  }

  @Test func nothingNearbyMeansNoNudge() {
    let r = Snap.move(rect(300, 120, 360, 170).snapFeatures(), [rect(0, 0, 100, 50).snapFeatures()], tol: 8)
    #expect(r.offset == Pt(0, 0) && r.guides.isEmpty)
  }

  @Test func aDraggedEndLandsOnASlantedEdge() throws {
    let slope = line(Pt(0, 0), Pt(100, 100)).snapFeatures()
    let p = try #require(Snap.point(Pt(50, 46), [slope], tol: 8))
    #expect(close(p.x, p.y))
    #expect(Snap.point(Pt(50, 30), [slope], tol: 8) == nil)
  }

  @Test func aLineKeepsItsAngleWhenItStopsOnAnEdge() {
    let wall = line(Pt(100, 0), Pt(100, 200)).snapFeatures()
    #expect(Snap.alongLine(Pt(0, 50), Pt(95, 50), [wall], tol: 8) == Pt(100, 50))
    #expect(Snap.corner(Pt(97, 195), [wall], tol: 8) == Pt(100, 200))
  }

  @Test func aLevelLinesEndSlidesAlongToLineUpWithABox() {
    let box = rect(0, 100, 200, 200).snapFeatures()
    let (side, sideGuides) = Snap.alongAngle(Pt(-80, 40), Pt(205, 40), [box], tol: 8)
    #expect(close(side.x, 200) && close(side.y, 40))
    #expect(aligns(sideGuides).count == 1 && aligns(sideGuides)[0].vertical)
    let (middle, _) = Snap.alongAngle(Pt(-80, 40), Pt(96, 40), [box], tol: 8)
    #expect(close(middle.x, 100) && close(middle.y, 40))
    let (up, _) = Snap.alongAngle(Pt(300, 400), Pt(300, 104), [box], tol: 8)
    #expect(close(up.x, 300) && close(up.y, 100))
    let (diag, _) = Snap.alongAngle(Pt(-100, -100), Pt(-3, -3), [box], tol: 8)
    #expect(close(diag.x, diag.y) && close(diag.x, 0))
    let (free, none) = Snap.alongAngle(Pt(-80, 40), Pt(150, 40), [box], tol: 8)
    #expect(close(free.x, 150) && none.isEmpty)
  }

  @Test func aDotLinesUpWithAnotherShapesSide() {
    let (p, guides) = Snap.alignPoint(Pt(103, 200), [rect(0, 0, 100, 50).snapFeatures()], tol: 6)
    #expect(close(p.x, 100) && close(p.y, 200))
    #expect(guides.count == 1 && !guides[0].isTouch)
  }

  @Test func engineeringSymbolsAttachAtTheirPoint() throws {
    let f = ShapeKind.PIN_SUPPORT.create(Pt(200, 100), Pt(200, 180)).snapFeatures()
    #expect(f.points.contains { $0.dist(Pt(200, 100)) < 0.01 })
    #expect(f.points.count < 12)
    #expect(close(try #require(f.box).bottom, 180, 25))
    let wall = ShapeKind.FIXED_SUPPORT.create(Pt(0, 0), Pt(0, 100)).snapFeatures()
    #expect(wall.points.contains(Pt(0, 0)) && wall.points.contains(Pt(0, 100)))
    #expect(wall.segments.count == 1)
  }

  @Test func touchingHoldsFromFurtherThanLiningUp() {
    let s = SnapSession(contact: 10, align: 5)
    let box = rect(0, 0, 100, 50).snapFeatures()
    #expect(close(Snap.move(rect(107, 10, 160, 40).snapFeatures(), [box], s).offset.x, -7))
    s.begin()
    #expect(close(Snap.move(rect(107, 300, 160, 340).snapFeatures(), [box], s).offset.x, 0))
  }

  @Test func aShapeInsideAnotherLocksFirmlyOnItsMiddle() {
    let s = SnapSession(contact: 10, align: 5)
    let r = Snap.move(rect(78, 37, 138, 77).snapFeatures(), [rect(0, 0, 200, 100).snapFeatures()], s)
    #expect(close(r.offset.x, -8) && close(r.offset.y, -7))
    #expect(aligns(r.guides).count == 2)
  }

  @Test func pulledFreeOfALockItLetsGoUntilSheMovesAway() {
    let s = SnapSession(contact: 10, align: 5)
    let corner = [rect(100, 100, 200, 160).snapFeatures()]
    func at(_ x: Float, _ y: Float) -> Pt? {
      s.begin()
      defer { s.end() }
      return Snap.point(Pt(x, y), corner, s)
    }
    #expect(at(96, 97) == Pt(100, 100))
    #expect(at(85, 85) == nil)
    #expect(at(95, 95) == nil)
    #expect(at(97, 98) == nil)
    #expect(at(40, 40) == nil)
    #expect(at(96, 97) == Pt(100, 100))
  }

  @Test func aLockSheSlidesOutOfIntoAnotherDoesntLetGo() {
    let s = SnapSession(contact: 10, align: 5)
    let wall = [line(Pt(100, 0), Pt(100, 400)).snapFeatures()]
    func at(_ x: Float, _ y: Float) -> Pt? {
      s.begin()
      defer { s.end() }
      return Snap.point(Pt(x, y), wall, s)
    }
    #expect(close(at(104, 100)?.x ?? -1, 100))
    #expect(close(at(104, 200)?.x ?? -1, 100))
    #expect(close(at(97, 300)?.x ?? -1, 100))
  }

  @Test func moveShowsOneCrossWhereItTouches() {
    let floor = line(Pt(0, 100), Pt(300, 100)).snapFeatures()
    let wall = line(Pt(0, 0), Pt(0, 100)).snapFeatures()
    let r = Snap.move(rect(3, 40, 63, 97).snapFeatures(), [floor, wall], tol: 10)
    #expect(close(r.offset.x, -3) && close(r.offset.y, 3))
    #expect(r.guides.filter(\.isTouch).count == 1)
  }

  @Test func resizingALevelLineDoesntJumpToAnotherShapesHeight() {
    let other = line(Pt(200, 50), Pt(200, 150)).snapFeatures()
    let (s, _) = Snap.scale(Rect(0, 100, 200, 100), Pt(0, 98.8), 1.3, [other], tol: 10)
    #expect(close(s, 1.3, 0.001))
  }

  @Test func handwritingLinesUpItsMiddleOnly() {
    let r = Snap.move(SnapFeatures.middleOf(Rect(2, 300, 196, 340)), [rect(0, 0, 200, 100).snapFeatures()], tol: 8)
    #expect(close(r.offset.x, 1) && close(r.offset.y, 0))
  }

  @Test func handwritingsMiddleLinesUpWithAShapesSides() {
    let box = rect(0, 0, 200, 100).snapFeatures()
    #expect(close(Snap.move(SnapFeatures.middleOf(Rect(154, 300, 254, 340)), [box], tol: 8).offset.x, -4))
    #expect(close(Snap.move(SnapFeatures.middleOf(Rect(500, -60, 600, -2)), [box], tol: 8).offset.y, 0))
  }

  @Test func resizingHandwritingLinesUpOnlyItsMiddle() {
    let target = rect(0, 0, 200, 60).snapFeatures()
    let box = Rect(300, 10, 400, 58)
    #expect(close(Snap.scale(box, Pt(300, 10), 1.02, [target], SnapSession(contact: 4)).0, 50 / 48, 0.001))
    #expect(close(Snap.scale(box, Pt(300, 10), 1.02, [target], SnapSession(contact: 4), middleOnly: true).0, 1.02, 0.001))
  }

  @Test func aRectanglesSideDraggedPastTheOtherTurnsItOver() {
    let g = rect(0, 0, 100, 50).withHandle(1, Pt(-40, 25))
    guard case let .poly(p, _, _, _, _) = g else { Issue.record("not a poly"); return }
    #expect(close(p.map(\.x).min()!, -40) && close(p.map(\.x).max()!, 0))
    #expect(close(g.handles()[1].x, -40))
  }

  @Test func aDistributedLoadGainsArrowsAsItLengthens() {
    let load = ShapeKind.DISTRIBUTED_LOAD.create(Pt(0, 0), Pt(112, 40))
    guard case let .load(_, _, _, count) = load else { Issue.record("not a load"); return }
    #expect(count == 4)
    let longer = load.withHandle(1, Pt(224, 0))
    guard case let .load(_, _, _, c2) = longer else { Issue.record("not a load"); return }
    #expect(c2 == 8)
    #expect(close(longer.handles()[2].y, 40))
  }

  @Test func dimensionHasDotsAtItsEnds() {
    #expect(ShapeKind.DIMENSION.create(Pt(0, 0), Pt(100, 0)).handles().count == 2)
  }
}
