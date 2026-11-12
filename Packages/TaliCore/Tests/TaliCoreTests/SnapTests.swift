import Foundation
import Testing
@testable import TaliCore

// Ported from Android's SnapTest.
struct SnapTests {
  private func rect(_ l: Float, _ t: Float, _ r: Float, _ b: Float) -> ShapeGeometry {
    .poly(points: [Pt(l, t), Pt(r, t), Pt(r, b), Pt(l, b)], closed: true)
  }

  private func line(_ a: Pt, _ b: Pt) -> ShapeGeometry { .line(a: a, b: b, arrowStart: false, arrowEnd: false, ticks: false) }

  private func close(_ a: Float, _ b: Float, _ tol: Float = 0.01) -> Bool { abs(a - b) <= tol }

  private func levelGuides(_ guides: [SnapGuide]) -> [Float] {
    guides.compactMap { g in
      if case let .align(false, at, _, _) = g { return at }
      return nil
    }
  }

  @Test func aLineEndLocksOntoAnUprightLine() {
    let wall = line(Pt(100, 0), Pt(100, 200)).snapFeatures()
    // A level line whose right end stops 6 units short of the wall.
    let beam = line(Pt(0, 80), Pt(94, 80)).snapFeatures()
    let r = Snap.move(beam, [wall], tol: 10)
    #expect(close(r.offset.x, 6) && close(r.offset.y, 0))
    #expect(r.guides.contains { $0.isTouch })
  }

  @Test func anEndOnACornerBeatsAnEdge() {
    let box = rect(100, 100, 200, 160).snapFeatures()
    let r = Snap.move(line(Pt(0, 0), Pt(96, 97)).snapFeatures(), [box], tol: 10)
    #expect(close(r.offset.x, 4) && close(r.offset.y, 3))
  }

  @Test func boxesLineUpTheirTopsAndMiddles() {
    let a = rect(0, 0, 100, 50).snapFeatures()
    // Far to the right, its top 5 above the first one's top.
    let r = Snap.move(rect(300, -5, 360, 40).snapFeatures(), [a], tol: 8)
    #expect(close(r.offset.y, 5) && close(r.offset.x, 0))
    #expect(r.guides.count == 1 && !r.guides[0].isTouch)
  }

  @Test func sameSizeBoxesShowEveryLineThatLinesUp() {
    let a = rect(0, 0, 100, 50).snapFeatures()
    let r = Snap.move(rect(300, 4, 400, 54).snapFeatures(), [a], tol: 8)
    #expect(close(r.offset.y, -4))
    #expect(levelGuides(r.guides).count == 3, "top, middle and bottom all line up")
  }

  @Test func resizingLinesUpTheFarSide() {
    let target = rect(0, 0, 200, 50).snapFeatures()
    // A box beside it, being resized from its top-left corner: its bottom (48 × 1.02 = 49) locks to the target's bottom at 50.
    let (s, guides) = Snap.scale(Rect(300, 0, 400, 48), anchor: Pt(300, 0), 1.02, [target], tol: 4)
    #expect(close(s, 50 / 48, 0.001))
    #expect(levelGuides(guides).contains(50))
  }

  @Test func nothingNearbyMeansNoNudge() {
    let a = rect(0, 0, 100, 50).snapFeatures()
    let r = Snap.move(rect(300, 120, 360, 170).snapFeatures(), [a], tol: 8)
    #expect(r.offset == .zero && r.guides.isEmpty)
  }

  @Test func aDraggedEndLandsOnASlantedEdge() throws {
    let slope = line(Pt(0, 0), Pt(100, 100)).snapFeatures()
    let p = try #require(Snap.point(Pt(50, 46), [slope], tol: 8))
    #expect(close(p.x, p.y))
    #expect(Snap.point(Pt(50, 30), [slope], tol: 8) == nil)
  }

  @Test func aLineKeepsItsAngleWhenItStopsOnAnEdge() {
    let wall = line(Pt(100, 0), Pt(100, 200)).snapFeatures()
    // Drawn level from (0, 50) and stopping just short of the wall.
    #expect(Snap.alongLine(Pt(0, 50), Pt(95, 50), [wall], tol: 8) == Pt(100, 50))
    #expect(Snap.corner(Pt(97, 195), [wall], tol: 8) == Pt(100, 200))
  }

  @Test func aLevelLinesEndSlidesAlongToLineUpWithABox() {
    // A level line above a box: its end lines up with the box's side and middle, staying level.
    let box = rect(0, 100, 200, 200).snapFeatures()
    let side = Snap.alongAngle(Pt(-80, 40), Pt(205, 40), [box], tol: 8)
    #expect(close(side.at.x, 200) && close(side.at.y, 40))
    #expect(side.guides == [.align(vertical: true, at: 200, from: 40, to: 200)])
    let middle = Snap.alongAngle(Pt(-80, 40), Pt(96, 40), [box], tol: 8)
    #expect(close(middle.at.x, 100) && close(middle.at.y, 40))
    // An upright line's end stops level with the box's top; a 45° line keeps its angle.
    let up = Snap.alongAngle(Pt(300, 400), Pt(300, 104), [box], tol: 8)
    #expect(close(up.at.x, 300) && close(up.at.y, 100))
    let diag = Snap.alongAngle(Pt(-100, -100), Pt(-3, -3), [box], tol: 8)
    #expect(close(diag.at.x, diag.at.y) && close(diag.at.x, 0))
    // Nothing near: it stays where it was.
    let free = Snap.alongAngle(Pt(-80, 40), Pt(150, 40), [box], tol: 8)
    #expect(close(free.at.x, 150) && free.guides.isEmpty)
  }

  @Test func aDotLinesUpWithAnotherShapesSide() {
    let box = rect(0, 0, 100, 50).snapFeatures()
    let (p, guides) = Snap.alignPoint(Pt(103, 200), [box], tol: 6)
    #expect(close(p.x, 100) && close(p.y, 200))
    #expect(guides.count == 1 && !guides[0].isTouch)
  }

  @Test func engineeringSymbolsAttachAtTheirPoint() throws {
    // A support drawn from its tip: the tip is where the pen landed, and it snaps (its hatching doesn't).
    let f = ShapeKind.PIN_SUPPORT.create(Pt(200, 100), Pt(200, 180)).snapFeatures()
    #expect(f.points.contains { $0.dist(Pt(200, 100)) < 0.01 })
    #expect(f.points.count < 12)
    #expect(close(try #require(f.box).bottom, 180, 25))
    // A fixed support's wall runs from start to end.
    let wall = ShapeKind.FIXED_SUPPORT.create(Pt(0, 0), Pt(0, 100)).snapFeatures()
    #expect(wall.points.contains(Pt(0, 0)) && wall.points.contains(Pt(0, 100)))
    #expect(wall.segments.count == 1)
  }

  @Test func touchingHoldsFromFurtherThanLiningUp() {
    let s = SnapSession(10, align: 5)
    let box = rect(0, 0, 100, 50).snapFeatures()
    // 7 away: a corner landing on the box's side catches (a touch)...
    #expect(close(Snap.move(rect(107, 10, 160, 40).snapFeatures(), [box], s).offset.x, -7))
    // ...but a box far below with its side 7 off the box's side doesn't line up (softer).
    s.begin()
    #expect(close(Snap.move(rect(107, 300, 160, 340).snapFeatures(), [box], s).offset.x, 0))
  }

  @Test func aShapeInsideAnotherLocksFirmlyOnItsMiddle() {
    let s = SnapSession(10, align: 5)
    let outer = rect(0, 0, 200, 100).snapFeatures()
    // A small box 8 right and 7 down of the middle: further than sides catch, but middles hold firmly.
    let r = Snap.move(rect(78, 37, 138, 77).snapFeatures(), [outer], s)
    #expect(close(r.offset.x, -8) && close(r.offset.y, -7))
    #expect(r.guides.filter { !$0.isTouch }.count == 2)
  }

  @Test func pulledFreeOfALockItLetsGoUntilSheMovesAway() {
    let s = SnapSession(10, align: 5)
    let corner = [rect(100, 100, 200, 160).snapFeatures()]
    func at(_ x: Float, _ y: Float) -> Pt? {
      s.begin()
      defer { s.end() }
      return Snap.point(Pt(x, y), corner, s)
    }
    // Onto the corner, then pulled away past where it catches, then back near it: left free.
    #expect(at(96, 97) == Pt(100, 100))
    #expect(at(85, 85) == nil)
    #expect(at(95, 95) == nil)
    // The edges meeting there don't pull it back onto the corner either.
    #expect(at(97, 98) == nil)
    // Far away and back: it catches again.
    #expect(at(40, 40) == nil)
    #expect(at(96, 97) == Pt(100, 100))
  }

  @Test func aLockSheSlidesOutOfIntoAnotherDoesntLetGo() {
    let s = SnapSession(10, align: 5)
    let wall = [line(Pt(100, 0), Pt(100, 400)).snapFeatures()]
    func at(_ x: Float, _ y: Float) -> Pt? {
      s.begin()
      defer { s.end() }
      return Snap.point(Pt(x, y), wall, s)
    }
    // Sliding along the wall stays on it the whole way.
    #expect(at(104, 100)?.x == 100)
    #expect(at(104, 200)?.x == 100)
    #expect(at(97, 300)?.x == 100)
  }

  @Test func moveShowsOneCrossWhereItTouches() {
    // A box resting in a corner touches both walls at once: one cross.
    let floor = line(Pt(0, 100), Pt(300, 100)).snapFeatures()
    let wall = line(Pt(0, 0), Pt(0, 100)).snapFeatures()
    let r = Snap.move(rect(3, 40, 63, 97).snapFeatures(), [floor, wall], tol: 10)
    #expect(close(r.offset.x, -3) && close(r.offset.y, 3))
    #expect(r.guides.filter { $0.isTouch }.count == 1)
  }

  @Test func resizingALevelLineDoesntJumpToAnotherShapesHeight() {
    // A level line touching another line, resized from its left end: its height is nothing, so lining
    // its "bottom" up with the other line's would have thrown its length wildly.
    let other = line(Pt(200, 50), Pt(200, 150)).snapFeatures()
    let (s, _) = Snap.scale(Rect(0, 100, 200, 100), anchor: Pt(0, 98.8), 1.3, [other], tol: 10)
    #expect(close(s, 1.3, 0.001))
  }

  @Test func handwritingLinesUpItsMiddleOnly() {
    let box = rect(0, 0, 200, 100).snapFeatures()
    // Writing whose middle is 1 off the box's middle lines up; its own left edge 2 off the box's doesn't count.
    let r = Snap.move(.middleOf(Rect(2, 300, 196, 340)), [box], tol: 8)
    #expect(close(r.offset.x, 1) && close(r.offset.y, 0))
  }

  @Test func handwritingsMiddleLinesUpWithAShapesSides() {
    let box = rect(0, 0, 200, 100).snapFeatures()
    // Writing whose middle is 4 right of the box's right side: it lines up there; its own edges never do.
    #expect(close(Snap.move(.middleOf(Rect(154, 300, 254, 340)), [box], tol: 8).offset.x, -4))
    // Its bottom 2 off the box's top doesn't count.
    #expect(close(Snap.move(.middleOf(Rect(500, -60, 600, -2)), [box], tol: 8).offset.y, 0))
  }

  @Test func resizingHandwritingLinesUpOnlyItsMiddle() {
    let target = rect(0, 0, 200, 60).snapFeatures()
    // Its bottom (10 + 48 × 1.02) comes within 1 of the target's bottom: a shape locks on there...
    let box = Rect(300, 10, 400, 58)
    #expect(close(Snap.scale(box, anchor: Pt(300, 10), 1.02, [target], SnapSession(4)).scale, 50 / 48, 0.001))
    // ...handwriting doesn't (its middle isn't near anything).
    #expect(close(Snap.scale(box, anchor: Pt(300, 10), 1.02, [target], SnapSession(4), middleOnly: true).scale, 1.02, 0.001))
  }

  @Test func aRectanglesSideDraggedPastTheOtherTurnsItOver() {
    // The right side's dot (index 1) dragged to x = -40: the rectangle now runs from -40 to 0.
    let g = rect(0, 0, 100, 50).withHandle(1, Pt(-40, 25))
    guard case let .poly(points, _, _, _, _) = g else {
      Issue.record("not a rectangle any more")
      return
    }
    #expect(close(points.map(\.x).min() ?? 0, -40) && close(points.map(\.x).max() ?? 1, 0))
    // The dot she's dragging is still under the pen.
    #expect(close(g.handles()[1].x, -40))
  }

  @Test func aDistributedLoadGainsArrowsAsItLengthens() {
    guard case let .load(_, _, _, count) = ShapeKind.DISTRIBUTED_LOAD.create(Pt(0, 0), Pt(112, 40)) else {
      Issue.record("not a load")
      return
    }
    #expect(count == 4)
    // The right end dragged out to 224: twice as many gaps, same spacing; arrows still hang down.
    let longer = ShapeKind.DISTRIBUTED_LOAD.create(Pt(0, 0), Pt(112, 40)).withHandle(1, Pt(224, 0))
    guard case let .load(_, _, _, more) = longer else {
      Issue.record("not a load")
      return
    }
    #expect(more == 8)
    #expect(close(longer.handles()[2].y, 40))
  }

  @Test func aLinesEndGoesToACornerThenAnEdgeThenItsTidyAngle() {
    let box = [rect(100, 100, 200, 160).snapFeatures()]
    // Near the corner: onto it.
    let corner = Snap.lineEnd(fixed: Pt(0, 0), raw: Pt(97, 103), box, SnapSession(10))
    #expect(corner.at == Pt(100, 100) && corner.on)
    // Level from the left, stopping short of the box's left side: it stops on the side, still level.
    let edge = Snap.lineEnd(fixed: Pt(0, 130), raw: Pt(95, 131), box, SnapSession(10))
    #expect(edge.on && close(edge.at.x, 100) && close(edge.at.y, 130))
    // Nothing near: free, on its tidy angle.
    let free = Snap.lineEnd(fixed: Pt(0, 300), raw: Pt(60, 301), box, SnapSession(10))
    #expect(!free.on && close(free.at.y, 300))
  }

  @Test func aLinesDotLocksOntoAnotherShapesCorner() {
    let box = [rect(100, 100, 200, 160).snapFeatures()]
    let (g, guides) = line(Pt(0, 0), Pt(50, 50)).dragging(1, to: Pt(97, 102), snappingTo: box, SnapSession(10))
    #expect(g == line(Pt(0, 0), Pt(100, 100)))
    #expect(guides == [.touch(Pt(100, 100))])
    // Away from everything it's as if nothing were there: free, on its tidy angle.
    let free = line(Pt(0, 0), Pt(50, 50)).dragging(1, to: Pt(60, 1), snappingTo: box, SnapSession(10))
    #expect(free.shape == line(Pt(0, 0), Pt(50, 50)).dragging(1, to: Pt(60, 1)) && free.guides.isEmpty)
  }

  @Test func aTrianglesCornerLinesUpWithItsOtherCorners() {
    let triangle = ShapeGeometry.triangle(a: Pt(0, 100), b: Pt(200, 100), c: Pt(90, 0))
    // The top corner dragged nearly level with nothing else around: it lines up above corner a (x = 0).
    let (g, guides) = triangle.dragging(2, to: Pt(3, -40), snappingTo: [], SnapSession(10))
    guard case let .triangle(_, _, c, _) = g else {
      Issue.record("not a triangle any more")
      return
    }
    #expect(close(c.x, 0) && close(c.y, -40))
    #expect(guides.count == 1 && !guides[0].isTouch)
  }

  @Test func aNewBoxsCornerGoesOntoACornerOrLinesUp() {
    let box = [rect(100, 100, 200, 160).snapFeatures()]
    let on = Snap.shapeEnd(start: Pt(300, 300), raw: Pt(203, 158), fromPoint: false, asLine: false, box, SnapSession(10))
    #expect(on.at == Pt(200, 160) && on.guides == [.touch(Pt(200, 160))])
    // Shapes drawn out from a point only snap where they start.
    let support = Snap.shapeEnd(start: Pt(300, 300), raw: Pt(203, 158), fromPoint: true, asLine: false, box, SnapSession(10))
    #expect(support.at == Pt(203, 158) && support.guides.isEmpty)
    // A new shape starts on the corner it's begun at.
    let start = Snap.shapeStart(Pt(98, 103), box, contact: 10, align: 5)
    #expect(start.at == Pt(100, 100) && start.stuck)
  }

  @Test func aLiveLinesEndStopsOnAnEdgeItReaches() {
    let wall = [line(Pt(100, 0), Pt(100, 200)).snapFeatures()]
    let end = Snap.liveLineEnd(from: Pt(0, 50), pen: Pt(96, 51), wall, SnapSession(10))
    #expect(close(end.at.x, 100) && close(end.at.y, 50) && end.guides.contains { $0.isTouch })
    let free = Snap.liveLineEnd(from: Pt(0, 50), pen: Pt(40, 51), wall, SnapSession(10))
    #expect(close(free.at.y, 50) && free.guides.isEmpty)
  }

  @Test func aPictureOffersItsCornersSidesAndMiddle() {
    let f = SnapFeatures.ofBox(Rect(10, 20, 110, 80))
    #expect(f.points.count == 5 && f.points.contains(Pt(60, 50)))
    #expect(f.segments.count == 4)
    #expect(f.box == Rect(10, 20, 110, 80))
  }
}
