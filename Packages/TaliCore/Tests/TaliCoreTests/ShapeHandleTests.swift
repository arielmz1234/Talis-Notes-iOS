import Foundation
import Testing
@testable import TaliCore

// Android's ShapeResizeTest, ShapeFormsTest, TriangleShapeTest and SectorShapeTest: what a shape's
// dots are and what dragging them does.

private let tau = Float.pi * 2

private func pts(_ g: ShapeGeometry) -> [Pt] {
  switch g {
  case let .poly(p, _, _, _, _): return p
  case let .triangle(a, b, c, _): return [a, b, c]
  case let .curve(p): return p
  default: return []
  }
}

private func sector(_ g: ShapeGeometry) -> (center: Pt, radius: Float, start: Float, sweep: Float, fraction: Float) {
  guard case let .sector(c, r, s, w) = g else { Issue.record("not a sector: \(g)"); return (.zero, 0, 0, 0, 0) }
  return (c, r, s, w, min(max(abs(w) / tau, 0), 1))
}

private func arc(_ g: ShapeGeometry) -> (center: Pt, radius: Float, start: Float, sweep: Float, degrees: Int) {
  guard case let .arc(c, r, s, w, _) = g else { Issue.record("not an arc: \(g)"); return (.zero, 0, 0, 0, 0) }
  return (c, r, s, w, Int(kround(abs(w) * 180 / .pi)))
}

/// Android's `SectorShape.of`.
private func sectorOf(_ center: Pt, _ toward: Pt, _ fraction: Float) -> ShapeGeometry {
  let sweep = tau * min(max(fraction, 0.01), 1)
  let dir = toward.dist(center) < 0.5 ? -Float.pi / 2 : (toward - center).angle()
  return .sector(center: center, radius: max(4, toward.dist(center)), start: dir - sweep / 2, sweep: sweep)
}

private func near(_ a: Pt, _ b: Pt, _ tol: Float = 0.05) -> Bool { a.dist(b) < tol }
private func close(_ a: Float, _ b: Float, _ tol: Float) -> Bool { abs(a - b) <= tol }

/// Every corner of a 4-gon is a right angle.
private func isRectangle(_ p: [Pt]) -> Bool {
  (0..<4).allSatisfy { i in
    let a = p[(i + 3) % 4] - p[i], b = p[(i + 1) % 4] - p[i]
    return abs(a.dot(b)) < 1e-2 * a.length() * b.length()
  }
}

struct ShapeResizeTests {
  @Test func rectangleSideStretchesOneWay() throws {
    let r = ShapeKind.RECTANGLE.create(Pt(0, 0), Pt(200, 100))
    let right = try #require(r.handles().firstIndex { near($0, Pt(200, 50)) })
    let out = pts(r.withHandle(right, Pt(260, 70)))
    #expect(isRectangle(out))
    #expect(close(out.map(\.x).max()!, 260, 0.05))
    #expect(close(out.map(\.y).max()! - out.map(\.y).min()!, 100, 0.05))
  }

  @Test func turnedRectangleSideKeepsItARectangle() {
    let r = ShapeKind.RECTANGLE.create(Pt(0, 0), Pt(200, 100)).transformed(Affine.rotateAround(Pt(100, 50), 0.5))
    let out = pts(r.withHandle(1, r.handles()[1] + Pt(30, 15)))
    #expect(isRectangle(out))
  }

  @Test func aRectangleDraggedPastItsOtherSideTurnsOver() {
    let r = ShapeKind.RECTANGLE.create(Pt(0, 0), Pt(200, 100))
    // The right side's dot dragged to x = -50: the rectangle now runs from -50 to 0.
    let out = pts(r.withHandle(1, Pt(-50, 50)))
    #expect(isRectangle(out))
    #expect(close(out.map(\.x).min()!, -50, 0.05) && close(out.map(\.x).max()!, 0, 0.05))
  }

  @Test func anOlderPolygonsCornerMovesOnItsOwn() {
    let d = ShapeKind.DIAMOND.create(Pt(0, 0), Pt(100, 60))
    guard case let .poly(p, closed, _, _, _) = d else { Issue.record("not a poly"); return }
    let old = ShapeGeometry.poly(points: p, closed: closed)
    let out = pts(old.withHandle(0, Pt(70, -60)))
    #expect(near(out[0], Pt(70, -60)))
    for i in 1..<p.count { #expect(near(out[i], p[i])) }
  }

  @Test func triangleCornersMoveOneAtATime() {
    let t = ShapeKind.TRIANGLE.create(Pt(0, 0), Pt(100, 80))
    let out = t.withHandle(1, Pt(150, 120))
    #expect(pts(t)[0] == pts(out)[0])
    #expect(pts(t)[2] == pts(out)[2])
  }

  @Test func aStarKeepsItsForm() {
    let s = ShapeKind.STAR.create(Pt(0, 0), Pt(100, 100))
    #expect(s.handles().isEmpty)
    #expect(s == s.withHandle(0, pts(s)[0] + Pt(10, -50)))
  }

  @Test func aCircleHasOneRadiusDotAndAnEllipseFour() {
    let c = ShapeKind.CIRCLE.create(Pt(0, 0), Pt(50, 0))
    #expect(c.handles().count == 1)
    guard case let .ellipse(center, rx, ry, rotation, _) = c.withHandle(0, Pt(0, 82)) else { Issue.record("not a circle"); return }
    #expect(center == Pt(0, 0) && close(rx, 82, 1e-3) && rx == ry && close(rotation, .pi / 2, 1e-5))
    let e = ShapeKind.ELLIPSE.create(Pt(0, 0), Pt(100, 100))
    // Drawn round with the Ellipse tool, it keeps its four stretching dots.
    #expect(e.handles().count == 4)
    guard case let .ellipse(_, erx, ery, _, _) = e.withHandle(0, Pt(130, 50)) else { Issue.record("not an ellipse"); return }
    #expect(close(erx, 80, 1e-3) && close(ery, 50, 1e-3))
  }

  @Test func aLoadsEndsKeepTheArrowsSpacedAndItsMiddleDotSetsTheirLength() {
    let l = ShapeGeometry.load(a: Pt(0, 0), b: Pt(100, 0), depth: 40, count: 3)
    guard case let .load(_, b, depth, count) = l.withHandle(1, Pt(280, 0)) else { Issue.record("not a load"); return }
    #expect(b == Pt(280, 0) && depth == 40 && count == 10)
    guard case let .load(_, _, d2, _) = l.withHandle(2, Pt(50, -30)) else { Issue.record("not a load"); return }
    #expect(close(d2, -30, 1e-3))
  }
}

struct ShapeFormsTests {
  let p0 = Pt(0, 0), p1 = Pt(200, 120)

  @Test func pentagonHexagonAndStarHaveNoDots() {
    for k in [ShapeKind.PENTAGON, .HEXAGON, .STAR] {
      let g = k.create(p0, p1)
      #expect(g.handles().isEmpty, "\(k)")
      #expect(g == g.withHandle(0, Pt(500, 500)), "\(k)")
    }
  }

  @Test func aDiamondStretchesEvenlyAndSnapsSquare() {
    let d = ShapeKind.DIAMOND.create(p0, p1)
    #expect(d.handles().count == 2)
    let wider = pts(d.withHandle(0, Pt(260, 60)))
    let c = Pt(100, 60)
    #expect(close(c.x - wider[3].x, wider[1].x - c.x, 0.01))
    #expect(close(wider[1].x - c.x, 160, 0.01))
    #expect(pts(d)[0] == wider[0])
    let square = pts(d.withHandle(1, Pt(100, 60 + 98)))
    #expect(close(abs(square[1].x - c.x), abs(square[2].y - c.y), 0.01))
  }

  @Test func aParallelogramsDotSetsItsSlantAndATrapezoidsItsTop() {
    let par = ShapeKind.PARALLELOGRAM.create(p0, p1)
    #expect(par.handles().count == 1)
    let leaned = pts(par.withHandle(0, Pt(100, 0)))
    #expect(pts(par)[2] == leaned[2])
    #expect(pts(par)[3] == leaned[3])
    #expect(close(leaned[1].x - leaned[0].x, leaned[2].x - leaned[3].x, 0.01))
    let narrow = pts(ShapeKind.TRAPEZOID.create(p0, p1).withHandle(0, Pt(70, 0)))
    #expect(close(narrow[0].x, 70, 0.01))
    #expect(close(narrow[1].x, 130, 0.01))
  }

  @Test func aCurveHasDotsAllAlongAndEachBendsIt() {
    let c = ShapeKind.CURVE.create(Pt(0, 100), Pt(300, 100))
    #expect(c.handles().count == curveDots)
    #expect(pts(c).first == Pt(0, 100))
    #expect(pts(c).last == Pt(300, 100))
    let bent = c.withHandle(1, Pt(75, 180))
    #expect(pts(bent)[1] == Pt(75, 180))
    #expect(bent.paths(1)[0].contains { $0.dist(Pt(75, 180)) < 1 })
  }

  @Test func formsAndCurvesAreSavedAndReadBack() throws {
    for g in [ShapeKind.DIAMOND.create(p0, p1), ShapeKind.STAR.create(p0, p1), ShapeKind.CURVE.create(p0, p1), ShapeKind.ELLIPSE.create(p0, p1)] {
      let data = try JSONSerialization.data(withJSONObject: g.json)
      let back = ShapeGeometry.decode(try JSONSerialization.jsonObject(with: data))
      #expect(back == g)
    }
    let old = try #require(ShapeGeometry.decode(try JSONSerialization.jsonObject(
      with: Data(#"{"type":"poly","points":[{"x":0,"y":0},{"x":10,"y":0},{"x":5,"y":9}],"closed":true}"#.utf8))))
    #expect(old.handles().count == 3)
  }

  @Test func aSubjectShapeGoesBackToAndroidUnchanged() throws {
    let json = #"{"type":"param","template":"civil.beam","place":{"a":2,"tx":10.5,"ty":-3},"w":120,"h":40,"v":[1,0.5]}"#
    let g = try #require(ShapeGeometry.decode(try JSONSerialization.jsonObject(with: Data(json.utf8))))
    let again = try #require(ShapeGeometry.decode(try JSONSerialization.jsonObject(with: try JSONSerialization.data(withJSONObject: g.json))))
    #expect(again == g)
    guard case let .param(q) = g.transformed(.translate(5, 5)) else { Issue.record("not param"); return }
    #expect(q.template == "civil.beam" && q.place.tx == 15.5 && q.place.ty == 2 && q.place.a == 2 && q.v == [1, 0.5])
  }
}

struct TriangleShapeTests {
  let t = ShapeGeometry.triangle(a: Pt(0, 0), b: Pt(200, 0), c: Pt(100, -150))

  func anglesOf(_ g: ShapeGeometry) -> [Int] { g.triangleAngles!.map { Int(kround($0)) } }

  @Test func aCornerMovesOnItsOwn() {
    let moved = pts(t.withHandle(2, Pt(60, -170)))
    #expect(moved[0] == Pt(0, 0) && moved[1] == Pt(200, 0))
    #expect(moved[2].dist(Pt(60, -170)) < 20)
  }

  @Test func itMovesAWholeDegreeAtATime() {
    for x: Float in [30, 70, 123, 151] {
      let g = t.withHandle(2, Pt(x, -113))
      for a in g.triangleAngles! { #expect(abs(a - kround(a)) <= 0.05, "angle \(a) from x=\(x)") }
      #expect(anglesOf(g).reduce(0, +) == 180)
    }
  }

  @Test func anglesLockOnToTheUsualOnes() {
    #expect(ShapeGeometry.lockAngle(43.2) == 45)
    #expect(ShapeGeometry.lockAngle(31.9) == 30)
    #expect(ShapeGeometry.lockAngle(40.7) == 40)
    #expect(ShapeGeometry.lockAngle(37.3) == 37)
    #expect(ShapeGeometry.lockAngle(51.8) == 52)
  }

  @Test func nearbyPositionsGiveDifferentTriangles() {
    let seen = Set((0..<12).map { k in anglesOf(t.withHandle(2, Pt(140 + Float(k) * 2, -120))) })
    #expect(seen.count >= 6, "only \(seen.count) different triangles")
  }

  @Test func nearlyRightAngleBecomesExact() {
    #expect(anglesOf(t.withHandle(2, Pt(6, -120)))[0] == 90)
  }

  @Test func nearlyRightAngleAtTheMovingCornerBecomesExact() {
    let g = t.withHandle(2, Pt(100 + 99 * cosf(2.2), -99 * sinf(2.2)))
    #expect(anglesOf(g)[2] == 90)
  }

  @Test func nearlyIsoscelesBecomesExact() {
    let a = anglesOf(t.withHandle(2, Pt(104, -90)))
    #expect(a[0] == a[1])
  }
}

struct SectorShapeTests {
  @Test func halfCircleFacesTheWayYouDrag() {
    let s = sectorOf(Pt(0, 0), Pt(0, -100), 0.5)
    #expect(close(sector(s).fraction, 0.5, 1e-4))
    #expect(close(sector(s).radius, 100, 1e-3))
    let mid = s.handles()[2]
    #expect(close(mid.x, 0, 1e-3) && close(mid.y, -100, 1e-3))
  }

  @Test func halfCircleIsClosedThroughTheCentre() {
    let path = sectorOf(Pt(0, 0), Pt(100, 0), 0.5).paths(2)
    #expect(path.count == 1 && path[0].first == Pt(0, 0) && path[0].last == Pt(0, 0))
  }

  @Test func wholeCircleHasNoRadii() {
    #expect(sectorOf(Pt(0, 0), Pt(100, 0), 1).paths(2)[0].first!.dist(Pt(0, 0)) > 50)
  }

  @Test func endDotsSnapToQuarters() {
    #expect(close(ShapeGeometry.snapSweep(0.27 * tau), 0.25 * tau, 1e-4))
    #expect(close(ShapeGeometry.snapSweep(0.73 * tau), 0.75 * tau, 1e-4))
    #expect(close(ShapeGeometry.snapSweep(0.405 * tau), 0.40 * tau, 1e-4))
    #expect(close(ShapeGeometry.snapSweep(0.37 * tau), 0.37 * tau, 1e-4))
  }

  @Test func draggingAnEndChangesTheAmountKeepingTheOtherEnd() {
    let s = sectorOf(Pt(0, 0), Pt(100, 0), 0.5)
    let fixed = s.handles()[0]
    let e = s.withHandle(1, Pt.polar(100, sector(s).start + 0.75 * tau))
    #expect(close(sector(e).fraction, 0.75, 1e-3))
    #expect(close(fixed.x, e.handles()[0].x, 1e-3) && close(fixed.y, e.handles()[0].y, 1e-3))
  }

  @Test func aWholeCircleOpensWhicheverWayAnEndIsDragged() {
    let full = sectorOf(Pt(0, 0), Pt(100, 0), 1)
    for index in 0...1 {
      for by: Float in [-0.1, 0.1] {
        let at = Pt.polar(100, full.handles()[index].angle() + by * tau)
        let f = sector(full.withHandle(index, at)).fraction
        #expect(f < 0.95, "dot \(index) by \(by) gave \(f)")
      }
    }
  }

  @Test func goingPastAFullTurnStartsAgainFromNothing() {
    let s = sectorOf(Pt(0, 0), Pt(100, 0), 0.5)
    let e = s.withHandle(1, Pt.polar(100, sector(s).start + tau + 0.02 * tau))
    #expect(close(sector(e).fraction, 0.02, 1e-3))
  }

  @Test func arcEndsWrapInsteadOfWindingIntoACircle() {
    let a0 = ShapeGeometry.arc(center: Pt(0, 0), radius: 100, start: .pi, sweep: .pi, arrowEnd: false)
    for k in 1...40 {
      let a = arc(a0.withHandle(0, Pt.polar(100, .pi - Float(k) * 0.05 * tau)))
      #expect(a.sweep > 0 && a.sweep <= tau + 1e-4, "k=\(k) sweep \(a.sweep)")
      #expect(close(a.start + a.sweep, .pi * 2, 1e-3))
    }
    #expect(arc(a0.withHandle(1, Pt.polar(100, .pi + 1.25 * tau))).degrees == 90)
  }

  @Test func arcEndsKeepItsSizeAndTheMiddleDotResizes() {
    let a0 = ShapeGeometry.arc(center: Pt(0, 0), radius: 100, start: 0, sweep: .pi / 2, arrowEnd: false)
    let far = arc(a0.withHandle(1, Pt.polar(260, .pi)))
    #expect(close(far.radius, 100, 1e-4) && far.center == Pt(0, 0) && far.degrees == 180)
    let nearer = arc(a0.withHandle(0, Pt.polar(20, -.pi / 2)))
    #expect(close(nearer.radius, 100, 1e-4) && nearer.degrees == 180)
    #expect(a0.handles().count == 3)
    let big = arc(a0.withHandle(2, Pt.polar(150, .pi / 4)))
    #expect(close(big.radius, 150, 1e-3) && big.degrees == 90)
  }
}
