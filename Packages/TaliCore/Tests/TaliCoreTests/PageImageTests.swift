import Testing
@testable import TaliCore

// Android has no unit test for Quad or the looks; these pin the behaviour its camera relies on.
struct PageImageTests {
  @Test func aQuarterTurnMovesTheCornersRound() {
    let q = Quad(UnitPt(0.1, 0.2), UnitPt(0.9, 0.1), UnitPt(0.8, 0.9), UnitPt(0.2, 0.8))
    let t = q.turned(1)
    #expect(t.tl == UnitPt(1 - 0.8, 0.2))
    #expect(q.turned(4) == q)
    #expect(q.turned(-1) == q.turned(3))
  }

  @Test func crossedCornersArentConvex() {
    #expect(Quad.whole(inset: 0.1).convex)
    let crossed = Quad.whole().with(1, UnitPt(1, 1)).with(2, UnitPt(1, 0))
    #expect(!crossed.convex)
  }

  @Test func aStraightenedPageTakesItsLongerSides() {
    let q = Quad(UnitPt(0, 0), UnitPt(1, 0), UnitPt(0.75, 1), UnitPt(0.25, 1))
    let s = q.straightenedSize(400, 300, maxSide: 4000)
    #expect(s.width == 400)
    #expect(abs(s.height - (100 * 100 + 300 * 300).squareRoot()) < 0.01)
    #expect(q.straightenedSize(4000, 3000, maxSide: 1000).width == 1000)
  }

  private func page(_ w: Int, _ h: Int, paper: (Int, Int) -> UInt8, inkAt: (Int, Int) -> Bool) -> [UInt8] {
    var px = [UInt8](repeating: 255, count: w * h * 4)
    for y in 0..<h {
      for x in 0..<w {
        let o = (y * w + x) * 4
        let v = inkAt(x, y) ? 40 : paper(x, y)
        px[o] = v
        px[o + 1] = v
        px[o + 2] = inkAt(x, y) ? 160 : v
      }
    }
    return px
  }

  @Test func documentWhitensAShadowAndKeepsInkColour() {
    let w = 96, h = 96
    // Paper darker towards the right (a shadow), a blue ink line down the middle.
    let src = page(w, h, paper: { x, _ in UInt8(230 - x) }, inkAt: { x, _ in x == 48 })
    let out = PageLooks.looked(src, width: w, height: h, .document)
    #expect(out[(10 * w + 4) * 4] >= 250)
    #expect(out[(10 * w + 90) * 4] >= 240)
    let ink = (10 * w + 48) * 4
    #expect(out[ink + 2] > out[ink])
  }

  @Test func blackAndWhiteIsOnlyBlackAndWhiteMostly() {
    let w = 64, h = 64
    let src = page(w, h, paper: { _, _ in 200 }, inkAt: { x, y in x == y })
    let out = PageLooks.looked(src, width: w, height: h, .blackWhite)
    #expect(out[(5 * w + 40) * 4] == 255)
    #expect(out[(20 * w + 20) * 4] == 0)
    #expect(PageLooks.looked(src, width: w, height: h, .original) == src)
  }
}
