import Foundation
import Testing
@testable import TaliCore

/// Android's `ShapeMatcherTest`, ported (a seeded generator stands in for Kotlin's `Random(11)`),
/// plus hold-to-shape matching the starred subjects' shapes and saved shapes' storage.
struct ShapeMatcherTests {
  final class Rnd {
    var state: UInt64 = 11
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

  private func wobbly(_ corners: Pt..., jitter: Float = 3) -> [Pt] { wobbly(corners, jitter: jitter) }

  private func wobbly(_ corners: [Pt], jitter: Float = 3) -> [Pt] {
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

  private func circle(_ cx: Float, _ cy: Float, _ r: Float, turns: Float = 1.03) -> [Pt] {
    (0..<140).map { i in
      let t = Float(2 * Double.pi * Double(turns) * Double(i) / 139)
      return Pt(cx + r * cosf(t) + rnd.next() * 3 - 1.5, cy + r * sinf(t) + rnd.next() * 3 - 1.5)
    }
  }

  private static func custom(_ name: String, _ g: ShapeGeometry) -> CustomShape { CustomShape(id: name, name: name, geometry: CustomShape.normalized(g)!) }

  private static func plain(_ a: Pt, _ b: Pt) -> ShapeGeometry { .line(a: a, b: b, arrowStart: false, arrowEnd: false, ticks: false) }

  // A house: square walls with a triangular roof.
  private let house = custom(
    "house",
    .group([
      .poly(points: [Pt(0, 60), Pt(100, 60), Pt(100, 160), Pt(0, 160)], closed: true),
      .poly(points: [Pt(0, 60), Pt(50, 0), Pt(100, 60)], closed: false),
    ]))

  private static let beamOutline = [
    Pt(0, 0), Pt(100, 0), Pt(100, 18), Pt(60, 18), Pt(60, 102), Pt(100, 102), Pt(100, 120), Pt(0, 120), Pt(0, 102), Pt(40, 102), Pt(40, 18), Pt(0, 18),
  ]

  // An I-beam cross-section outline.
  private let beam = custom("beam", .poly(points: beamOutline, closed: true))

  // A circle with a cross through it (like a pin joint symbol).
  private let crossed = custom(
    "crossed", .group([.ellipse(center: Pt(50, 50), rx: 50, ry: 50, rotation: 0), plain(Pt(0, 50), Pt(100, 50)), plain(Pt(50, 0), Pt(50, 100))]))

  private var all: [CustomShape] { [house, beam, crossed] }

  private var houseStroke: [Pt] {
    wobbly(Pt(300, 400), Pt(300, 600), Pt(500, 600), Pt(500, 400), Pt(300, 400), Pt(400, 280), Pt(500, 400))
  }

  @Test func houseDrawnInOneStrokeMatchesHouse() {
    // Walls first, then up over the roof, at a different size and position.
    #expect(ShapeRecognizer.bestCustom(houseStroke, all)?.id == "house")
  }

  @Test func sloppyHouseStillMatches() {
    // Taller roof, leaning walls, and the roof drawn off-centre.
    let stroke = wobbly(Pt(310, 390), Pt(296, 600), Pt(508, 596), Pt(492, 404), Pt(310, 390), Pt(430, 240), Pt(492, 404), jitter: 6)
    #expect(ShapeRecognizer.bestCustom(stroke, all)?.id == "house")
  }

  @Test func beamMatchesBeam() {
    let c = Self.beamOutline + [Pt(0, 0)]
    let stroke = wobbly(c.map { Pt(200 + $0.x * 1.6, 100 + $0.y * 1.6) }, jitter: 4)
    #expect(ShapeRecognizer.bestCustom(stroke, all)?.id == "beam")
  }

  @Test func plainCircleDoesNotMatchCrossedCircle() {
    let stroke = circle(300, 300, 90)
    #expect(ShapeRecognizer.bestCustom(stroke, all) == nil)
    guard case .ellipse? = ShapeRecognizer.recognize(stroke, custom: all) else { Issue.record("not an ellipse"); return }
  }

  @Test func plainSquareAndTriangleDoNotMatchHouse() {
    let square = wobbly(Pt(0, 0), Pt(200, 0), Pt(200, 200), Pt(0, 200), Pt(0, 0))
    let triangle = wobbly(Pt(0, 200), Pt(100, 20), Pt(200, 200), Pt(0, 200))
    #expect(ShapeRecognizer.bestCustom(square, all) == nil)
    #expect(ShapeRecognizer.bestCustom(triangle, all) == nil)
  }

  @Test func crossedCircleDrawnInOneStrokeMatches() {
    // Around the circle, then across and down through the middle with connecting travel.
    let ring = circle(300, 300, 100, turns: 1)
    let stroke = ring + wobbly(Pt(400, 300), Pt(200, 300), Pt(300, 300), Pt(300, 200), Pt(300, 400))
    #expect(ShapeRecognizer.bestCustom(stroke, all)?.id == "crossed")
  }

  @Test func straightLineStaysALine() {
    let line = wobbly(Pt(0, 0), Pt(300, 4))
    guard case .line? = ShapeRecognizer.recognize(line, custom: all) else { Issue.record("not a line"); return }
  }

  @Test func placedShapeCoversTheStroke() throws {
    let g = try #require(ShapeRecognizer.recognize(houseStroke, custom: all))
    let box = try #require(Rect.around(g.paths(2).joined()))
    #expect(abs(box.center.x - 400) < 12)
    #expect(abs(box.width - 200) < 20)
    #expect(abs(box.height - 320) < 30)
  }

  @Test func aStarredSubjectsShapeIsRecognisedAndAnUnstarredOneIsNot() throws {
    // A spring drawn by hand in one stroke, bigger than its template and somewhere else.
    let coil = try #require(ShapeTemplates.spring.icon.paths(CustomShape.referencePen).first)
    let stroke = wobbly(coil.map { Pt(100 + $0.x * 1.5, 300 + $0.y * 1.5) }, jitter: 2)
    let mechanical = try #require(ShapePacks.all.first { $0.id == "mechanical" }).shapes
    guard case let .param(p)? = ShapeRecognizer.recognize(stroke, custom: [], packs: mechanical) else { Issue.record("not a subject shape"); return }
    #expect(p.template == "spring")
    let ends = try #require(p.lineEnds)
    #expect(ends.0.dist(stroke[0]) < 0.01 && ends.1.dist(stroke[stroke.count - 1]) < 0.01)
    if case .param? = ShapeRecognizer.recognize(stroke, custom: [], packs: []) { Issue.record("matched a subject that isn't starred") }
    let law = try #require(ShapePacks.all.first { $0.id == "law" }).shapes
    if case .param? = ShapeRecognizer.recognize(stroke, custom: [], packs: law) { Issue.record("matched another subject's shape") }
  }

  @Test func aSavedShapeKeepsItsGeometryWhenStored() throws {
    let o = try #require(JSONSerialization.jsonObject(with: JSONSerialization.data(withJSONObject: house.json)) as? [String: Any])
    #expect(CustomShape(json: o) == house)
    #expect(o["id"] as? String == "house" && o["name"] as? String == "house")
    #expect((o["geometry"] as? [String: Any])?["type"] as? String == "group")
  }

  @Test func aSelectionBecomesOneNormalisedShape() throws {
    let ink: [Pt] = (0...40).map { Pt(200 + Float($0) * 5, 300 + 40 * sinf(Float($0) / 6)) }
    let box = ShapeGeometry.poly(points: [Pt(200, 400), Pt(400, 400), Pt(400, 500), Pt(200, 500)], closed: true)
    let g = try #require(CustomShape.geometryFrom([.shape(box), .ink(ink)], bounds: Rect(200, 260, 400, 500)))
    let b = try #require(Rect.around(g.paths(CustomShape.referencePen).joined()))
    // (A smooth line is sampled afresh at each size, so its box is right to a fraction of a unit.)
    #expect(abs(b.left) < 0.1 && abs(b.top) < 0.1 && abs(max(b.width, b.height) - CustomShape.size) < 0.1, "\(b)")
    guard case let .group(parts, _) = g, parts.count == 2, case .poly(_, true, false, _, _) = parts[0], case .poly(_, false, true, _, _) = parts[1] else {
      Issue.record("\(g)")
      return
    }
    #expect(CustomShape.geometryFrom([.ink([Pt(0, 0), Pt(3, 3)])], bounds: Rect(0, 0, 3, 3)) == nil)
    #expect(CustomShape.geometryFrom([], bounds: Rect(0, 0, 300, 300)) == nil)
  }

  @Test func aSavedShapeFitsTheDraggedBox() throws {
    let g = house.fitInto(Pt(100, 100), Pt(300, 500))
    let b = try #require(Rect.around(g.paths(2).joined()))
    #expect(abs(b.width - 200) < 0.5 && abs(b.center.x - 200) < 0.5 && abs(b.center.y - 300) < 0.5)
    #expect(b.height < 400)
  }
}
