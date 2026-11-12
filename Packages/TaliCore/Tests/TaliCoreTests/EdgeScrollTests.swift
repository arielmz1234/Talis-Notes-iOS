import Testing

@testable import TaliCore

struct EdgeScrollTests {
  private let screen = Pt(1000, 800)

  @Test func nothingScrollsAwayFromTheEdges() {
    #expect(EdgeScroll.selection.velocity(at: Pt(500, 400), screen: screen, topClearance: 0) == .zero)
    #expect(EdgeScroll.selection.velocity(at: Pt(101, 699), screen: screen, topClearance: 0) == .zero)
  }

  @Test func eachEdgeScrollsItsOwnWayFasterTheDeeperIn() {
    let s = EdgeScroll.selection
    #expect(s.velocity(at: Pt(500, 750), screen: screen, topClearance: 0) == Pt(0, 225), "half way into the bottom zone: a quarter of the fastest")
    #expect(s.velocity(at: Pt(500, 800), screen: screen, topClearance: 0) == Pt(0, 900))
    #expect(s.velocity(at: Pt(500, 50), screen: screen, topClearance: 0) == Pt(0, -225))
    #expect(s.velocity(at: Pt(0, 400), screen: screen, topClearance: 0) == Pt(-900, 0))
    #expect(s.velocity(at: Pt(950, 400), screen: screen, topClearance: 0) == Pt(225, 0))
  }

  @Test func theTopZoneReachesBelowTheToolbars() {
    // Toolbars down to 160: the zone is 180 deep there, so 150 from the top already scrolls up.
    #expect(EdgeScroll.selection.velocity(at: Pt(500, 150), screen: screen, topClearance: 160).y < 0)
    #expect(EdgeScroll.selection.velocity(at: Pt(500, 150), screen: screen, topClearance: 0).y == 0)
  }

  @Test func aMemoScrollsFromFurtherIn() {
    #expect(EdgeScroll.memo.velocity(at: Pt(500, 680), screen: screen, topClearance: 0).y > 0)
    #expect(EdgeScroll.selection.velocity(at: Pt(500, 680), screen: screen, topClearance: 0).y == 0)
  }

  @Test func itScrollsOnlyAfterRestingAtTheEdge() {
    var s = EdgeScroll.selection
    let edge = Pt(500, 800)
    #expect(s.step(now: 10.00, at: edge, screen: screen, topClearance: 0) == .zero)
    #expect(s.step(now: 10.05, at: edge, screen: screen, topClearance: 0) == .zero, "still within the wait")
    let moved = s.step(now: 10.13, at: edge, screen: screen, topClearance: 0)
    #expect(moved.y > 0, "after 0.12 s it scrolls")
    #expect(abs(moved.y - 900 * 0.032) < 0.01, "a late frame scrolls no more than 32 ms' worth")
    #expect(abs(s.step(now: 10.146, at: edge, screen: screen, topClearance: 0).y - 900 * 0.016) < 0.01)
  }

  @Test func passingAnEdgeDoesNotScroll() {
    var s = EdgeScroll.selection
    _ = s.step(now: 1.00, at: Pt(500, 790), screen: screen, topClearance: 0)
    _ = s.step(now: 1.10, at: Pt(500, 400), screen: screen, topClearance: 0)
    #expect(s.step(now: 1.20, at: Pt(500, 790), screen: screen, topClearance: 0) == .zero, "the wait starts again once it has left the zone")
  }
}
