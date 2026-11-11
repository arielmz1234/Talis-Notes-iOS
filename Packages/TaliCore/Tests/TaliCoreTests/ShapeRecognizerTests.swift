import Foundation
import Testing
@testable import TaliCore

/// Android's `ShapeRecognizerTest`, ported (a seeded generator stands in for Kotlin's `Random(7)`).
struct ShapeRecognizerTests {
  final class Rnd {
    var state: UInt64 = 7
    func next() -> Float {
      state &+= 0x9E37_79B9_7F4A_7C15
      var z = state
      z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
      z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
      z ^= z >> 31
      return Float(z >> 40) / Float(1 << 24)
    }
  }
  let rnd = Rnd()

  private func wobbly(_ corners: Pt..., jitter: Float = 2.5) -> [Pt] { wobbly(corners, jitter: jitter) }

  private func wobbly(_ corners: [Pt], jitter: Float = 2.5) -> [Pt] {
    var out: [Pt] = []
    for i in 0..<(corners.count - 1) {
      let a = corners[i], b = corners[i + 1]
      let n = max(Int(a.dist(b) / 3), 2)
      for k in 0..<n {
        let p = a + (b - a) * (Float(k) / Float(n))
        out.append(Pt(p.x + rnd.next() * jitter - jitter / 2, p.y + rnd.next() * jitter - jitter / 2))
      }
    }
    out.append(corners[corners.count - 1])
    return out
  }

  private func wobblyEllipse(_ cx: Float, _ cy: Float, _ rx: Float, _ ry: Float, turns: Float = 1.04) -> [Pt] {
    (0..<160).map { i in
      let t = 2 * Float.pi * turns * Float(i) / 159
      return Pt(cx + rx * cosf(t) + rnd.next() * 3 - 1.5, cy + ry * sinf(t) + rnd.next() * 3 - 1.5)
    }
  }

  private func polyPoints(_ g: ShapeGeometry?) -> [Pt]? {
    switch g {
    case let .poly(p, _, _, _)?: return p
    case let .triangle(a, b, c)?: return [a, b, c]
    default: return nil
    }
  }

  @Test func straightishStrokeBecomesLine() throws {
    guard case let .line(a, b, _, _, _)? = ShapeRecognizer.recognize(wobbly(Pt(0, 0), Pt(300, 6))) else { Issue.record("not a line"); return }
    #expect(abs(a.y - b.y) < 0.01)
    #expect(abs(a.dist(b) - 300) < 3)
  }

  @Test func diagonalLineKeepsAngleWhenNotNearSnap() {
    guard case let .line(a, b, _, _, _)? = ShapeRecognizer.recognize(wobbly(Pt(0, 0), Pt(300, 120))) else { Issue.record("not a line"); return }
    #expect(abs((b - a).angle() * 180 / .pi - 21.8) < 1)
  }

  @Test func shaftWithBarbsBecomesArrow() {
    let tip = Pt(300, 0)
    let g = ShapeRecognizer.recognize(wobbly(Pt(0, 0), tip, Pt(260, -30), tip, Pt(260, 30), jitter: 1.5))
    guard case .line(_, _, _, true, _)? = g else { Issue.record("got \(String(describing: g))"); return }
  }

  @Test func lShapeBecomesOpenPolyline() {
    let g = ShapeRecognizer.recognize(wobbly(Pt(0, 0), Pt(0, 200), Pt(250, 200)))
    guard case let .poly(p, false, _, _)? = g, p.count == 3 else { Issue.record("got \(String(describing: g))"); return }
  }

  @Test func roundLoopBecomesCircle() {
    guard case let .ellipse(_, rx, ry, _)? = ShapeRecognizer.recognize(wobblyEllipse(100, 100, 80, 76)) else { Issue.record("not an ellipse"); return }
    #expect(abs(rx - ry) < 0.01)
    #expect(abs(rx - 78) < 4)
  }

  @Test func flatLoopBecomesEllipse() {
    guard case let .ellipse(_, rx, ry, _)? = ShapeRecognizer.recognize(wobblyEllipse(0, 0, 150, 60)) else { Issue.record("not an ellipse"); return }
    #expect(abs(max(rx, ry) - 150) < 6)
    #expect(abs(min(rx, ry) - 60) < 6)
  }

  @Test func wobblySquareBecomesExactSquare() {
    let g = ShapeRecognizer.recognize(wobbly(Pt(0, 0), Pt(200, 4), Pt(198, 205), Pt(-3, 200), Pt(2, 3)))
    guard case let .poly(p, true, _, _)? = g, p.count == 4 else { Issue.record("got \(String(describing: g))"); return }
    let sides = p.indices.map { p[$0].dist(p[($0 + 1) % 4]) }
    for s in sides { #expect(abs(s - sides[0]) < 0.5) }
    #expect(abs(p[0].y - p[1].y) < 0.5 || abs(p[0].x - p[1].x) < 0.5)
  }

  @Test func rectangleKeepsAspect() throws {
    let p = try #require(polyPoints(ShapeRecognizer.recognize(wobbly(Pt(0, 0), Pt(320, 0), Pt(320, 140), Pt(0, 140), Pt(0, 0)))))
    let sides = p.indices.map { p[$0].dist(p[($0 + 1) % 4]) }.sorted()
    #expect(abs(sides[0] - 140) < 8)
    #expect(abs(sides[3] - 320) < 8)
  }

  @Test func triangleIsRecognized() {
    let g = ShapeRecognizer.recognize(wobbly(Pt(100, 0), Pt(220, 180), Pt(-10, 175), Pt(100, 0)))
    guard case .triangle? = g else { Issue.record("got \(String(describing: g))"); return }
  }

  @Test func rightTriangleGetsExactRightAngle() throws {
    let g = ShapeRecognizer.recognize(wobbly(Pt(0, 0), Pt(4, 200), Pt(260, 196), Pt(0, 0)))
    guard case .triangle? = g else { Issue.record("got \(String(describing: g))"); return }
    let t = try #require(polyPoints(g))
    #expect(t.indices.contains { i in abs(Geo.interiorAngle(t[(i + 2) % 3], t[i], t[(i + 1) % 3]) - .pi / 2) < 0.01 })
  }

  @Test func tiltedRectangleSnapsToAxes() throws {
    let p = try #require(polyPoints(ShapeRecognizer.recognize(wobbly(Pt(0, 0), Pt(295, 52), Pt(268, 210), Pt(-24, 152), Pt(0, 0)))))
    #expect(p.count == 4)
    for i in p.indices {
      let e = p[(i + 1) % 4] - p[i]
      #expect(abs(e.x) < 0.5 || abs(e.y) < 0.5)
    }
  }

  @Test func lopsidedTriangleBecomesLevelIsosceles() throws {
    let t = try #require(polyPoints(ShapeRecognizer.recognize(wobbly(Pt(110, 0), Pt(210, 190), Pt(10, 170), Pt(110, 0)))))
    let sides = t.indices.map { t[$0].dist(t[($0 + 1) % 3]) }.sorted()
    #expect(abs(sides[0] - sides[1]) < 0.5 || abs(sides[1] - sides[2]) < 0.5)
    #expect(t.indices.contains { abs(t[$0].y - t[($0 + 1) % 3].y) < 0.5 })
  }

  @Test func aSideThatDriftsUpPartwayIsStillOneSide() {
    let step = wobbly(Pt(0, 0), Pt(150, 0), Pt(175, -22), Pt(320, -26), Pt(322, 160), Pt(-2, 162), Pt(0, 0))
    let a = ShapeRecognizer.recognize(step)
    guard case let .poly(p, true, _, _)? = a, p.count == 4 else { Issue.record("got \(String(describing: a))"); return }
    let bump = wobbly(Pt(0, 0), Pt(300, 0), Pt(302, 80), Pt(322, 100), Pt(300, 120), Pt(300, 200), Pt(0, 200), Pt(0, 0))
    let b = ShapeRecognizer.recognize(bump)
    guard case let .poly(q, true, _, _)? = b, q.count == 4 else { Issue.record("got \(String(describing: b))"); return }
  }

  @Test func aWaveBecomesACurve() {
    let wave = (0..<120).map { i in Pt(Float(i) * 3, 60 * Float(sin(Double(i) / 119 * 4 * .pi)) + rnd.next() * 2) }
    let g = ShapeRecognizer.recognize(wave)
    guard case let .curve(points)? = g else { Issue.record("got \(String(describing: g))"); return }
    #expect(points.first!.dist(wave.first!) < 3 && points.last!.dist(wave.last!) < 3)
    let path = g!.paths(1)[0]
    #expect(wave.allSatisfy { p in path.map { $0.dist(p) }.min()! < 15 })
    let s = (0..<100).map { i in
      let t = Double(i) / 99 * .pi
      return Pt(80 * Float(sin(2 * t)), Float(i) * 3)
    }
    guard case .curve? = ShapeRecognizer.recognize(s) else { Issue.record("an S: got \(String(describing: ShapeRecognizer.recognize(s)))"); return }
  }

  @Test func pentagonKeepsItsCorners() {
    let corners = (0..<6).map { i in Pt(100 * Float(cos(-Double.pi / 2 + 2 * .pi * Double(i) / 5)), 100 * Float(sin(-Double.pi / 2 + 2 * .pi * Double(i) / 5))) }
    let g = ShapeRecognizer.recognize(wobbly(corners, jitter: 2))
    guard case let .poly(p, _, _, _)? = g, p.count == 5 else { Issue.record("got \(String(describing: g))"); return }
  }

  @Test func hexagonIsNotMistakenForCircle() {
    let corners = (0..<7).map { i in Pt(100 * Float(cos(2 * .pi * Double(i) / 6)), 100 * Float(sin(2 * .pi * Double(i) / 6))) }
    let g = ShapeRecognizer.recognize(wobbly(corners, jitter: 2))
    guard case let .poly(p, _, _, _)? = g, p.count == 6 else { Issue.record("got \(String(describing: g))"); return }
  }

  @Test func starIsRecognized() {
    let corners = (0..<11).map { i -> Pt in
      let r: Double = i % 2 == 0 ? 120 : 50
      let a = -Double.pi / 2 + 2 * .pi * Double(i) / 10
      return Pt(Float(r * cos(a)), Float(r * sin(a)))
    }
    let g = ShapeRecognizer.recognize(wobbly(corners, jitter: 1.5))
    guard case let .poly(p, _, _, _)? = g, p.count == 10 else { Issue.record("got \(String(describing: g))"); return }
  }

  private func arch(_ r: Float, _ sweepDeg: Double, hooks: Bool = false) -> [Pt] {
    let half = sweepDeg / 2 * .pi / 180
    let pts = (0..<90).map { i in
      let a = Double.pi + (Double.pi / 2 - half) + 2 * half * Double(i) / 89
      return Pt(r * Float(cos(a)) + rnd.next() * 2, r * Float(sin(a)) + rnd.next() * 2)
    }
    if !hooks { return pts }
    let first = pts.first!, last = pts.last!
    return [first + Pt(8, 6), first + Pt(4, 3)] + pts + [last + Pt(-5, -2), last + Pt(-9, -3)]
  }

  @Test func anArchBecomesAnArc() {
    guard case let .arc(_, radius, _, _, _)? = ShapeRecognizer.recognize(arch(100, 140)) else { Issue.record("not an arc"); return }
    #expect(abs(radius - 100) < 6)
    let halfG = ShapeRecognizer.recognize(arch(120, 172))
    guard case let .arc(_, _, _, sweep, _)? = halfG else { Issue.record("half: not an arc"); return }
    #expect(abs(abs(sweep) - .pi) < 0.001)
    let ends = halfG!.paths(1)[0]
    #expect(abs(ends.first!.y - ends.last!.y) < 0.5)
    let hooked = ShapeRecognizer.recognize(arch(100, 160, hooks: true))
    guard case .arc? = hooked else { Issue.record("hooked: got \(String(describing: hooked))"); return }
  }

  @Test func manyJointedStrokesStayInk() {
    let zigzag = wobbly(Pt(0, 0), Pt(40, 80), Pt(80, 0), Pt(120, 80), Pt(160, 0), Pt(200, 80), Pt(240, 0), jitter: 1.5)
    #expect(ShapeRecognizer.recognize(zigzag) == nil)
    let lopsided = wobbly(Pt(0, 0), Pt(200, 10), Pt(230, 120), Pt(90, 200), Pt(-20, 90), Pt(0, 0), jitter: 1.5)
    if case let .poly(p, _, _, _)? = ShapeRecognizer.recognize(lopsided) { #expect(p.count != 5) }
  }

  @Test func scribbleStaysInk() {
    let scribble = (0..<120).map { i in Pt(Float(i) * 3, i % 2 == 0 ? 0 : 60 + rnd.next() * 40) }
    #expect(ShapeRecognizer.recognize(scribble) == nil)
  }

  @Test func tinyDotStaysInk() {
    #expect(ShapeRecognizer.recognize([Pt(0, 0), Pt(1, 1), Pt(2, 1)]) == nil)
  }

  @Test func aRecognisedShapeIsStoredAsAndroidWritesIt() throws {
    let row = ShapeRow(geometry: .poly(points: [Pt(0, 0), Pt(10, 0), Pt(10, 5), Pt(0, 5)], closed: true, rotation: 0), pen: "FINELINER", color: -16_777_216, size: 2)
      .row(id: "x", z: 3)
    let back = try #require(ShapeRow(row))
    #expect(back.geometry == .poly(points: [Pt(0, 0), Pt(10, 0), Pt(10, 5), Pt(0, 5)], closed: true))
    let text = String(decoding: row.payload, as: UTF8.self)
    #expect(text.contains(#""type":"poly""#))
    #expect(!text.contains("rotation"))
    #expect(row.l == -1 && row.r == 11)
    let line = ShapeRow(geometry: .line(a: Pt(0.1, 0), b: Pt(5, 5), arrowStart: false, arrowEnd: true, ticks: false), pen: "FINELINER", color: 0, size: 1, line: "DOTTED")
    let lt = String(decoding: line.row(id: "l", z: 1).payload, as: UTF8.self)
    #expect(lt.contains(#""x":0.1"#) && lt.contains(#""arrowEnd":true"#) && lt.contains(#""line":"DOTTED""#))
  }
}
