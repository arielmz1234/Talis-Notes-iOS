import Foundation
import Testing
@testable import TaliCore

private let tau = Float.pi * 2

private func near(_ a: Pt, _ b: Pt, _ tol: Float = 0.05) -> Bool { a.dist(b) < tol }

private func corners(_ g: ShapeGeometry) -> [Pt] {
  switch g {
  case let .poly(p, _, _, _, _): return p
  case let .triangle(a, b, c, _): return [a, b, c]
  case let .curve(p): return p
  default: return []
  }
}

private func box(_ g: ShapeGeometry) -> (w: Float, h: Float) {
  let r = Rect.around(corners(g)) ?? Rect(0, 0, 0, 0)
  return (r.width, r.height)
}

private func radii(_ g: ShapeGeometry) -> (center: Pt, rx: Float, ry: Float) {
  guard case let .ellipse(c, rx, ry, _, _) = g else { return (.zero, 0, 0) }
  return (c, rx, ry)
}

private func arc(_ g: ShapeGeometry) -> (center: Pt, radius: Float, start: Float, sweep: Float) {
  switch g {
  case let .arc(c, r, start, sweep, _), let .sector(c, r, start, sweep): return (c, r, start, sweep)
  default: return (.zero, 0, 0, 0)
  }
}

/// Dragging a shape's dots resizes it and keeps it the same kind of shape (Android's `ShapeResizeTest`).
struct ShapeResizeTests {
  /// Every corner of a 4-gon is a right angle.
  private func isRectangle(_ p: [Pt]) -> Bool {
    (0..<4).allSatisfy { i in
      let a = p[(i + 3) % 4] - p[i], b = p[(i + 1) % 4] - p[i]
      return abs(a.dot(b)) < 1e-2 * a.length() * b.length()
    }
  }

  @Test func rectangleSideStretchesOneWay() throws {
    let r = ShapeKind.RECTANGLE.create(Pt(0, 0), Pt(200, 100))
    let right = try #require(r.handles().firstIndex { near($0, Pt(200, 50)) })
    let out = corners(r.withHandle(right, Pt(260, 70)))
    #expect(isRectangle(out))
    #expect(abs(out.map(\.x).max()! - 260) < 0.05)
    #expect(abs(out.map(\.y).max()! - out.map(\.y).min()! - 100) < 0.05)
  }

  @Test func turnedRectangleSideKeepsItARectangle() {
    let r = ShapeKind.RECTANGLE.create(Pt(0, 0), Pt(200, 100)).transformed(.rotateAround(Pt(100, 50), 0.5))
    let out = r.withHandle(1, r.handles()[1] + Pt(30, 15))
    #expect(isRectangle(corners(out)))
  }

  @Test func anOlderPolygonsCornerMovesOnItsOwn() {
    // A polygon without a form (drawn before forms, or recognised from her drawing) keeps free corners.
    let d = ShapeGeometry.poly(points: corners(ShapeKind.DIAMOND.create(Pt(0, 0), Pt(100, 60))), closed: true)
    let out = corners(d.withHandle(0, Pt(70, -60)))
    #expect(near(out[0], Pt(70, -60)))
    for i in 1..<4 { #expect(near(out[i], corners(d)[i])) }
  }

  @Test func triangleCornersMoveOneAtATime() {
    let t = corners(ShapeKind.TRIANGLE.create(Pt(0, 0), Pt(100, 80)))
    let out = corners(ShapeKind.TRIANGLE.create(Pt(0, 0), Pt(100, 80)).withHandle(1, Pt(150, 120)))
    #expect(t[0] == out[0])
    #expect(t[2] == out[2])
  }

  @Test func aStarKeepsItsForm() {
    let s = ShapeKind.STAR.create(Pt(0, 0), Pt(100, 100))
    #expect(s.handles().isEmpty)
    #expect(s == s.withHandle(0, corners(s)[0] + Pt(10, -50)))
  }
}

/// Android's `TriangleShapeTest`.
struct TriangleShapeTests {
  private let t = ShapeGeometry.triangle(a: Pt(0, 0), b: Pt(200, 0), c: Pt(100, -150))

  private func anglesOf(_ g: ShapeGeometry) -> [Int] { g.triangleAngles.map { Int($0.rounded()) } }

  @Test func aCornerMovesOnItsOwn() {
    let moved = corners(t.withHandle(2, Pt(60, -170)))
    #expect(moved[0] == Pt(0, 0))
    #expect(moved[1] == Pt(200, 0))
    #expect(moved[2].dist(Pt(60, -170)) < 20)
  }

  @Test func itMovesAWholeDegreeAtATime() {
    for x: Float in [30, 70, 123, 151] {
      let g = t.withHandle(2, Pt(x, -113))
      for a in g.triangleAngles { #expect(abs(a - a.rounded()) < 0.05, "angle \(a) from x=\(x)") }
      #expect(anglesOf(g).reduce(0, +) == 180)
    }
  }

  @Test func anglesLockOnToTheUsualOnes() {
    #expect(TriangleShape.lockAngle(43.2) == 45)
    #expect(TriangleShape.lockAngle(31.9) == 30)
    #expect(TriangleShape.lockAngle(40.7) == 40)
    // Between them it just moves by whole degrees.
    #expect(TriangleShape.lockAngle(37.3) == 37)
    #expect(TriangleShape.lockAngle(51.8) == 52)
  }

  @Test func nearbyPositionsGiveDifferentTriangles() {
    // Small moves still change it: it isn't stuck to a coarse grid.
    let seen = Set((0..<12).map { k in anglesOf(t.withHandle(2, Pt(140 + Float(k) * 2, -120))) })
    #expect(seen.count >= 6, "only \(seen.count) different triangles")
  }

  @Test func nearlyRightAngleBecomesExact() {
    #expect(anglesOf(t.withHandle(2, Pt(6, -120)))[0] == 90)
  }

  @Test func nearlyRightAngleAtTheMovingCornerBecomesExact() {
    // On (almost) the circle over the base: a right angle at the corner being dragged.
    let g = t.withHandle(2, Pt(100 + 99 * cosf(2.2), -99 * sinf(2.2)))
    #expect(anglesOf(g)[2] == 90)
  }

  @Test func nearlyIsoscelesBecomesExact() {
    let a = anglesOf(t.withHandle(2, Pt(104, -90)))
    #expect(a[0] == a[1])
  }

  @Test func oldTrianglesBecomeTriangleShapes() {
    let old = ShapeGeometry.poly(points: [Pt(0, 0), Pt(10, 0), Pt(0, 10)], closed: true)
    guard case .triangle? = ShapeRecognizer.asTriangle(old) else { Issue.record("not a triangle"); return }
    let square = ShapeGeometry.poly(points: [Pt(0, 0), Pt(10, 0), Pt(10, 10), Pt(0, 10)], closed: true)
    #expect(ShapeRecognizer.asTriangle(square) == square)
  }
}

/// Android's `SectorShapeTest`: part circles and arcs.
struct SectorShapeTests {
  @Test func halfCircleFacesTheWayYouDrag() {
    let s = SectorShape.of(Pt(0, 0), Pt(0, -100), 0.5)
    #expect(abs(s.sectorFraction - 0.5) < 1e-4)
    #expect(abs(arc(s).radius - 100) < 1e-3)
    // The middle of the curve is at the top, where she dragged.
    let mid = s.handles()[2]
    #expect(abs(mid.x) < 1e-3 && abs(mid.y + 100) < 1e-3)
  }

  @Test func halfCircleIsClosedThroughTheCentre() {
    let path = SectorShape.of(Pt(0, 0), Pt(100, 0), 0.5).paths(2)[0]
    #expect(path.first == Pt(0, 0) && path.last == Pt(0, 0))
  }

  @Test func wholeCircleHasNoRadii() {
    let path = SectorShape.of(Pt(0, 0), Pt(100, 0), 1).paths(2)[0]
    #expect(path[0].dist(Pt(0, 0)) > 50)
  }

  @Test func endDotsSnapToQuarters() {
    #expect(abs(SectorShape.snapSweep(0.27 * tau) - 0.25 * tau) < 1e-4)
    #expect(abs(SectorShape.snapSweep(0.73 * tau) - 0.75 * tau) < 1e-4)
    // Near a 5% step but far from a quarter: whole 5%.
    #expect(abs(SectorShape.snapSweep(0.405 * tau) - 0.40 * tau) < 1e-4)
    // In between: left as it is.
    #expect(abs(SectorShape.snapSweep(0.37 * tau) - 0.37 * tau) < 1e-4)
  }

  @Test func draggingAnEndChangesTheAmountKeepingTheOtherEnd() {
    let s = SectorShape.of(Pt(0, 0), Pt(100, 0), 0.5)
    let fixed = s.handles()[0]
    // Drag the far end a quarter turn further round.
    let e = s.withHandle(1, Pt.polar(100, arc(s).start + 0.75 * tau))
    #expect(abs(e.sectorFraction - 0.75) < 1e-3)
    #expect(near(e.handles()[0], fixed, 1e-3))
  }

  @Test func aWholeCircleOpensWhicheverWayAnEndIsDragged() {
    let full = SectorShape.of(Pt(0, 0), Pt(100, 0), 1)
    for index in 0...1 {
      for by: Float in [-0.1, 0.1] {
        let at = Pt.polar(100, full.handles()[index].angle() + by * tau)
        let e = full.withHandle(index, at)
        #expect(e.sectorFraction < 0.95, "dot \(index) by \(by) gave \(e.sectorFraction)")
      }
    }
  }

  @Test func goingPastAFullTurnStartsAgainFromNothing() {
    let s = SectorShape.of(Pt(0, 0), Pt(100, 0), 0.5)
    // 361° round from the fixed end is 1°.
    let e = s.withHandle(1, Pt.polar(100, arc(s).start + tau + 0.02 * tau))
    #expect(abs(e.sectorFraction - 0.02) < 1e-3)
  }

  @Test func arcEndsWrapInsteadOfWindingIntoACircle() {
    let a = ShapeGeometry.arc(center: Pt(0, 0), radius: 100, start: .pi, sweep: .pi, arrowEnd: false)
    // The start dragged backwards round past the other end: a small arc, never more than a turn.
    for k in 1...40 {
      let moved = arc(a.withHandle(0, Pt.polar(100, .pi - Float(k) * 0.05 * tau)))
      #expect(moved.sweep > 0 && moved.sweep <= tau + 1e-4, "k=\(k) sweep \(moved.sweep)")
      #expect(abs(moved.start + moved.sweep - .pi * 2) < 1e-3)
    }
    #expect(a.withHandle(1, Pt.polar(100, .pi + 1.25 * tau)).arcDegrees == 90)
  }

  @Test func arcEndsKeepItsSizeAndTheMiddleDotResizes() {
    let a = ShapeGeometry.arc(center: Pt(0, 0), radius: 100, start: 0, sweep: .pi / 2, arrowEnd: false)
    // An end dragged far out or close in only slides round: same centre, same size.
    let far = a.withHandle(1, Pt.polar(260, .pi))
    #expect(abs(arc(far).radius - 100) < 1e-4 && arc(far).center == Pt(0, 0))
    #expect(far.arcDegrees == 180)
    let close = a.withHandle(0, Pt.polar(20, -.pi / 2))
    #expect(abs(arc(close).radius - 100) < 1e-4)
    #expect(close.arcDegrees == 180)
    // The middle dot: bigger, same turn.
    #expect(a.handles().count == 3)
    let big = a.withHandle(2, Pt.polar(150, .pi / 4))
    #expect(abs(arc(big).radius - 150) < 1e-3)
    #expect(big.arcDegrees == 90)
  }

  @Test func aMomentKeepsItsForm() {
    #expect(ShapeKind.MOMENT.create(Pt(0, 0), Pt(40, 0)).handles().isEmpty)
  }
}

/// The basic shapes keep their form (only the dots that make sense), and the curve bends anywhere
/// (Android's `ShapeFormsTest`).
struct ShapeFormsTests {
  private let p0 = Pt(0, 0), p1 = Pt(200, 120)

  @Test func pentagonHexagonAndStarHaveNoDots() {
    for k in [ShapeKind.PENTAGON, .HEXAGON, .STAR] {
      let g = k.create(p0, p1)
      #expect(g.handles().isEmpty, "\(k)")
      #expect(g.withHandle(0, Pt(500, 500)) == g, "\(k)")
    }
  }

  @Test func aDiamondStretchesEvenlyAndSnapsSquare() {
    let d = ShapeKind.DIAMOND.create(p0, p1)
    #expect(d.handles().count == 2)
    let wider = corners(d.withHandle(0, Pt(260, 60)))
    // Still a diamond: left and right the same distance from the middle, top and bottom unmoved.
    let c = Pt(100, 60)
    #expect(abs((c.x - wider[3].x) - (wider[1].x - c.x)) < 0.01)
    #expect(abs(wider[1].x - c.x - 160) < 0.01)
    #expect(corners(d)[0] == wider[0])
    // Close to square: snaps.
    let square = corners(d.withHandle(1, Pt(100, 60 + 98)))
    #expect(abs(abs(square[1].x - c.x) - abs(square[2].y - c.y)) < 0.01)
  }

  @Test func aParallelogramsDotSetsItsSlantAndATrapezoidsItsTop() {
    let par = ShapeKind.PARALLELOGRAM.create(p0, p1)
    #expect(par.handles().count == 1)
    let leaned = corners(par.withHandle(0, Pt(100, 0)))
    // The bottom stays, the top slides as one: still parallel sides of equal length.
    #expect(corners(par)[2] == leaned[2] && corners(par)[3] == leaned[3])
    #expect(abs((leaned[1].x - leaned[0].x) - (leaned[2].x - leaned[3].x)) < 0.01)
    let narrow = corners(ShapeKind.TRAPEZOID.create(p0, p1).withHandle(0, Pt(70, 0)))
    #expect(abs(narrow[0].x - 70) < 0.01)
    #expect(abs(narrow[1].x - 130) < 0.01)
  }

  @Test func aCurveHasDotsAllAlongAndEachBendsIt() {
    let c = ShapeKind.CURVE.create(Pt(0, 100), Pt(300, 100))
    #expect(c.handles().count == curveDots)
    #expect(corners(c).first == Pt(0, 100) && corners(c).last == Pt(300, 100))
    let bent = c.withHandle(1, Pt(75, 180))
    #expect(corners(bent)[1] == Pt(75, 180))
    // The curve passes through its dots.
    #expect(bent.paths(1)[0].contains { $0.dist(Pt(75, 180)) < 1 })
  }

  @Test func formsAndCurvesAreSavedAndReadBack() throws {
    for g in [ShapeKind.DIAMOND.create(p0, p1), ShapeKind.STAR.create(p0, p1), ShapeKind.CURVE.create(p0, p1), ShapeKind.ELLIPSE.create(p0, p1)] {
      let data = try JSONSerialization.data(withJSONObject: g.json)
      #expect(ShapeGeometry.decode(try JSONSerialization.jsonObject(with: data)) == g)
    }
    let turned = ShapeGeometry.triangle(a: Pt(0, 0), b: Pt(10, 0), c: Pt(0, 10), turn: 0.5)
    #expect(ShapeGeometry.decode(turned.json) == turned)
    // An older polygon (no form) still loads with its free corners.
    let json = #"{"type":"poly","points":[{"x":0,"y":0},{"x":10,"y":0},{"x":5,"y":9}],"closed":true}"#
    let old = try #require(ShapeGeometry.decode(try JSONSerialization.jsonObject(with: Data(json.utf8))))
    #expect(old.handles().count == 3)
  }

  @Test func androidsFormAndStretchableAreKept() throws {
    let diamond = #"{"type":"poly","points":[{"x":50,"y":0},{"x":100,"y":30},{"x":50,"y":60},{"x":0,"y":30}],"closed":true,"form":"DIAMOND"}"#
    let d = try #require(ShapeGeometry.decode(try JSONSerialization.jsonObject(with: Data(diamond.utf8))))
    #expect(d.handles().count == 2)
    #expect(d.json["form"] as? String == "DIAMOND")
    let ellipse = #"{"type":"ellipse","center":{"x":0,"y":0},"rx":40,"ry":40,"stretchable":true}"#
    let e = try #require(ShapeGeometry.decode(try JSONSerialization.jsonObject(with: Data(ellipse.utf8))))
    #expect(e.handles().count == 4)
    #expect(e.json["stretchable"] as? Bool == true)
  }
}

/// The shape parts of Android's `RoundThreeTest`.
struct ShapeDotTests {
  private let rect = ShapeGeometry.poly(points: [Pt(0, 0), Pt(100, 0), Pt(100, 60), Pt(0, 60)], closed: true)

  @Test func rectangleHasSideDots() {
    // Only the side dots: its corners only resized it, which is the resize chip's job now.
    #expect(rect.handles().count == 4)
    #expect(rect.handles()[1] == Pt(100, 30))
  }

  @Test func sideDotStretchesOneWayOnly() {
    let out = rect.withHandle(1, Pt(150, 10))
    #expect(abs(box(out).w - 150) < 0.01 && abs(box(out).h - 60) < 0.01)
    #expect(abs(corners(out).map(\.x).min()!) < 0.01)
  }

  @Test func sideDotSnapsToSquare() {
    let out = rect.withHandle(2, Pt(50, 98))
    #expect(abs(box(out).w - box(out).h) < 0.01)
  }

  @Test func aSideDraggedPastTheOtherSideTurnsOver() {
    let out = rect.withHandle(1, Pt(-40, 30))
    #expect(abs(corners(out).map(\.x).min()! + 40) < 0.01)
    #expect(abs(corners(out).map(\.x).max()!) < 0.01)
  }

  @Test func squareCanBecomeARectangle() {
    let square = ShapeGeometry.poly(points: [Pt(0, 0), Pt(80, 0), Pt(80, 80), Pt(0, 80)], closed: true)
    #expect(square.isSquare)
    let out = square.withHandle(1, Pt(140, 40))
    #expect(abs(box(out).w - 140) < 0.01 && abs(box(out).h - 80) < 0.01)
  }

  @Test func aCircleHasOneRadiusDotAndHandDrawnLinesNone() {
    let circle = ShapeGeometry.ellipse(center: Pt(0, 0), rx: 40, ry: 40, rotation: 0)
    #expect(circle.handles().count == 1)
    // Its dot sets the radius around the same centre and goes round with the pen.
    let bigger = circle.withHandle(0, Pt(0, 70))
    #expect(radii(bigger).center == Pt(0, 0))
    #expect(abs(radii(bigger).rx - 70) < 0.01 && abs(radii(bigger).ry - 70) < 0.01)
    #expect(near(bigger.handles()[0], Pt(0, 70), 0.01))
    #expect(ShapeGeometry.ellipse(center: Pt(0, 0), rx: 60, ry: 40, rotation: 0).handles().count == 4)
    #expect(ShapeGeometry.poly(points: [Pt(0, 0), Pt(10, 5), Pt(20, 0)], closed: false, smooth: true).handles().isEmpty)
  }

  @Test func linesSnapOnlyToFortyFives() {
    func angle(_ g: ShapeGeometry) -> Float {
      guard case let .line(a, b, _, _, _) = g else { return .nan }
      return (b - a).angle() * 180 / .pi
    }
    #expect(abs(angle(ShapeRecognizer.snappedLine(Pt(0, 0), Pt.polar(100, 31 * .pi / 180))) - 31) < 0.01)
    #expect(abs(angle(ShapeRecognizer.snappedLine(Pt(0, 0), Pt.polar(100, 41 * .pi / 180))) - 45) < 0.01)
  }

  @Test func rectangleToolSnapsToASquare() {
    #expect(ShapeKind.RECTANGLE.create(Pt(0, 0), Pt(100, 97)).isSquare)
    #expect(!ShapeKind.RECTANGLE.create(Pt(0, 0), Pt(100, 70)).isSquare)
    #expect(!ShapeKind.offered.contains(.SQUARE))
  }

  @Test func ellipseSnapsRoundAndKeepsItsDots() {
    let e = ShapeKind.ELLIPSE.create(Pt(0, 0), Pt(100, 60))
    // Pull the top dot almost to a circle.
    let round = e.withHandle(1, Pt(50, 30 - 49))
    #expect(round.round)
    #expect(round.handles().count == 4)
    #expect(!round.withHandle(0, Pt(130, 30)).round)
  }

  @Test func aLineEndStretchesAlongItsOwnDirection() {
    let line = ShapeGeometry.line(a: Pt(0, 0), b: Pt(100, 0), arrowStart: false, arrowEnd: true, ticks: false)
    // A degree off its direction: its angle stays exact, only its length changes.
    guard case let .line(a, b, _, true, _) = line.withHandle(1, Pt(200, 3)) else { Issue.record("not a line"); return }
    #expect(a == Pt(0, 0) && b == Pt(200, 0))
    // Well off it: the end goes where it's dragged.
    guard case let .line(_, free, _, _, _) = line.withHandle(1, Pt(100, 80)) else { Issue.record("not a line"); return }
    #expect(free == Pt(100, 80))
  }

  @Test func aLoadsEndsKeepItsArrowsSpacedAndItsMiddleDotSetsTheirLength() {
    let load = ShapeKind.DISTRIBUTED_LOAD.create(Pt(0, 0), Pt(140, 40))
    #expect(load.handles().count == 3)
    guard case let .load(_, _, depth, count) = load.withHandle(1, Pt(280, 0)) else { Issue.record("not a load"); return }
    #expect(count == ShapeKind.loadArrows(280) && depth == 40)
    guard case let .load(_, _, deeper, _) = load.withHandle(2, Pt(70, 90)) else { Issue.record("not a load"); return }
    #expect(abs(deeper - 90) < 0.01)
  }

  @Test func aMirroredLoadHangsItsArrowsTheOtherSide() {
    let load = ShapeGeometry.load(a: Pt(0, 0), b: Pt(100, 0), depth: 30, count: 3)
    let tip = load.handles()[2]
    let flipped = load.transformed(.scaleAround(Pt(50, 0), 1, -1))
    #expect(near(flipped.handles()[2], Pt(tip.x, -tip.y)))
  }
}
