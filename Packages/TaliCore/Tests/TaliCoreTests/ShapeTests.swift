import Foundation
import Testing
@testable import TaliCore

/// Shapes as the Android app stored them (payloads copied from a real backup).
struct ShapeTests {
  private func row(_ json: String, fill: Bool = false) -> ItemRow {
    ItemRow(id: "s", z: 1, kind: 1, pen: "FINELINER", color: -14_999_766, size: 2.4, payload: Data(json.utf8), l: 0, t: 0, r: 1, b: 1)
  }

  @Test func readsALine() throws {
    let s = try #require(ShapeRow(row(#"{"type":"line","a":{"x":239.1246,"y":305.23642},"b":{"x":942.43506,"y":305.23642}}"#)))
    #expect(s.geometry.paths(2.4) == [[Pt(239.1246, 305.23642), Pt(942.43506, 305.23642)]])
  }

  @Test func readsAGroupWithAClosedPolyAndExtraKeys() throws {
    let json =
      #"{"type":"group","parts":[{"type":"poly","points":[{"x":0,"y":0},{"x":10,"y":0},{"x":5,"y":8}],"closed":true},{"type":"line","a":{"x":0,"y":10},"b":{"x":10,"y":10}}],"fill":-16776961,"line":"DOTTED","locked":true}"#
    let s = try #require(ShapeRow(row(json)))
    #expect(s.geometry.paths(1).count == 2)
    #expect(s.geometry.paths(1)[0].count == 4)
    #expect(s.fill == -16_776_961)
    #expect(s.line == "DOTTED")
    #expect(s.locked)
  }

  @Test func arrowHeadsAreAtLeastTwentyUnits() {
    let p = ShapeGeometry.line(a: Pt(0, 0), b: Pt(200, 0), arrowStart: false, arrowEnd: true, ticks: false).paths(1)
    #expect(p.count == 2)
    let barb = p[1]
    #expect(abs(barb[1].dist(barb[0]) - 20) < 0.01)
  }

  @Test func aWholeSectorIsACircleWithoutRadii() {
    let whole = ShapeGeometry.sector(center: .zero, radius: 50, start: 0, sweep: 2 * .pi).paths(1)[0]
    #expect(whole.first! != .zero)
    let half = ShapeGeometry.sector(center: .zero, radius: 50, start: 0, sweep: .pi).paths(1)[0]
    #expect(half.first! == .zero && half.last! == .zero)
  }

  @Test func smoothKeepsItsEnds() {
    let pts = [Pt(0, 0), Pt(10, 5), Pt(20, 0), Pt(30, 5)]
    let s = Geo.smooth(pts)
    #expect(s.first == pts.first)
    #expect(s.last!.dist(pts.last!) < 0.001)
  }

  @Test func unknownTypesAreSkipped() {
    #expect(ShapeRow(row(#"{"type":"hologram"}"#)) == nil)
  }
}

struct TextRowTests {
  @Test func readsAndWritesAndroidsTextPayload() throws {
    let json = #"{"text":"Σ M = 0\nשלום","x":120.5,"y":300,"width":800,"height":90}"#
    let row = ItemRow(id: "t", z: 4, kind: 3, pen: nil, color: -16_777_216, size: 26, payload: Data(json.utf8), l: 0, t: 0, r: 1, b: 1)
    let t = try #require(TextRow(row))
    #expect(t.text == "Σ M = 0\nשלום" && t.x == 120.5 && t.width == 800 && t.height == 90 && t.fontSize == 26)
    let back = t.row(textHeight: 60)
    #expect(TextRow(back) == t)
    #expect(back.b == 300 + 90)
    let plain = TextRow(text: "a", x: 0, y: 0, width: 100, fontSize: 20, color: 0).row(textHeight: 10)
    #expect(!String(decoding: plain.payload, as: UTF8.self).contains("height"))
    #expect(abs(plain.b - 26) < 0.01)
  }
}
