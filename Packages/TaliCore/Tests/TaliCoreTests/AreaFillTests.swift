import Foundation
import Testing
@testable import TaliCore

/// Android's `AreaFillTest`, ported, plus which lines outline a filled area.
struct AreaFillTests {
  private let w = 100
  private let h = 100

  /// A square outline from (20,20) to (80,80), optionally with a gap of [gap] cells in its right side.
  private func square(gap: Int = 0) -> [Bool] {
    var g = [Bool](repeating: false, count: w * h)
    for i in 20...80 {
      g[20 * w + i] = true
      g[80 * w + i] = true
      g[i * w + 20] = true
      if gap == 0 || !(50..<(50 + gap)).contains(i) { g[i * w + 80] = true }
    }
    return g
  }

  @Test func fillsInsideAClosedOutline() throws {
    let f = try #require(AreaFill.fill(square(), w, h, 50, 50, bridge: 2))
    #expect(f[50 * w + 50])
    #expect(f[50 * w + 79], "tucks under the line")
    #expect(!f[50 * w + 90], "stays inside")
  }

  @Test func bridgesASmallGap() {
    #expect(AreaFill.fill(square(gap: 3), w, h, 50, 30, bridge: 2) != nil)
  }

  @Test func refusesAnOpenArea() {
    #expect(AreaFill.fill(square(gap: 12), w, h, 50, 30, bridge: 2) == nil)
  }

  @Test func refusesATapOnTheLine() {
    #expect(AreaFill.fill(square(), w, h, 20, 50, bridge: 2) == nil)
  }

  @Test func outsideEverythingIsNotAnArea() {
    #expect(AreaFill.fill(square(), w, h, 5, 5, bridge: 2) == nil)
    #expect(AreaFill.fill(square(), w, h, -1, 5, bridge: 2) == nil)
  }

  @Test func theFilledBoxIsFoundForThePicture() throws {
    let f = try #require(AreaFill.fill(square(), w, h, 50, 50, bridge: 2))
    let e = try #require(AreaFill.extent(f, w, h))
    #expect(e.x0 <= 21 && e.y0 <= 21 && e.x1 >= 79 && e.y1 >= 79)
    #expect(e.x0 >= 17 && e.x1 <= 83)
    #expect(e.cells == f.count { $0 })
    #expect(AreaFill.extent([Bool](repeating: false, count: 16), 4, 4) == nil)
  }

  @Test func theMaskIsNoBiggerThanItsLimit() {
    let page = AreaFill.grid(for: Rect(0, 0, 1322, 1871))
    #expect(abs(page.k - 1400 / 1871) < 1e-5 && page.h == 1400 && page.w == Int(Float(1322) * (1400 / 1871)))
    let small = AreaFill.grid(for: Rect(0, 0, 400, 300))
    #expect(small.k == 1 && small.w == 400 && small.h == 300)
    #expect(AreaFill.bridgeCells(1) == 3 && AreaFill.bridgeCells(0.2) == 1)
  }

  @Test func onlyTheLinesRoundTheAreaOutlineIt() throws {
    let f = try #require(AreaFill.fill(square(), w, h, 50, 50, bridge: 2))
    let window = Rect(0, 0, 100, 100)
    let box = AreaFill.Wall(id: "box", paths: [[Pt(20, 20), Pt(80, 20), Pt(80, 80), Pt(20, 80), Pt(20, 20)]], size: 1)
    let label = AreaFill.Wall(id: "label", paths: [[Pt(40, 50), Pt(60, 50)]], size: 1)
    let passing = AreaFill.Wall(id: "passing", paths: [[Pt(50, 0), Pt(50, 15)]], size: 1)
    #expect(AreaFill.outline(of: [box, label, passing], f, w, h, window: window, k: 1) == ["box"])
  }

  @Test func aPolygonsAreaIsSignedByItsDirection() {
    let sq = [Pt(0, 0), Pt(10, 0), Pt(10, 10), Pt(0, 10)]
    #expect(Geo.polygonArea(sq) == 100)
    #expect(Geo.polygonArea(sq.reversed()) == -100)
  }
}
