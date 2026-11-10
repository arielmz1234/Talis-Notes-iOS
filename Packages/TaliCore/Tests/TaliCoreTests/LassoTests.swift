import Testing
@testable import TaliCore

// Ported from Android's LassoTest and FreeSelectTest.
struct LassoTests {
  /// A small square loop around (100..140, 100..140).
  let loop = [Pt(100, 100), Pt(140, 100), Pt(140, 140), Pt(100, 140)]

  @Test func circlingTheTipOfALongLineTakesIt() {
    let line = (0...50).map { Pt(120 + Float($0) * 20, 120) }
    #expect(Lasso.touchesPath(line, loop))
  }
  @Test func aLineThatOnlyCrossesTheLoopCounts() { #expect(Lasso.touchesPath([Pt(50, 120), Pt(200, 120)], loop)) }
  @Test func somethingElsewhereIsLeftAlone() { #expect(!Lasso.touchesPath([Pt(300, 300), Pt(400, 320)], loop)) }
  @Test func pictureTouchedByTheLoopCounts() {
    #expect(Lasso.touchesRect(Rect(130, 130, 300, 300), loop))
    #expect(Lasso.touchesRect(Rect(110, 110, 120, 120), loop))
  }
  @Test func loopDrawnInsideAPictureLeavesThePicture() { #expect(!Lasso.touchesRect(Rect(0, 0, 500, 500), loop)) }
}

struct FreeSelectTests {
  let stroke = [Pt(0, 0), Pt(100, 0)]
  @Test func tracingAcrossPicksItUp() { #expect(Lasso.nearPath(stroke, [Pt(50, -40), Pt(50, 40)], 5)) }
  @Test func passingCloseCounts() { #expect(Lasso.nearPath(stroke, [Pt(-20, 8), Pt(120, 8)], 10)) }
  @Test func passingFarDoesNot() { #expect(!Lasso.nearPath(stroke, [Pt(-20, 30), Pt(120, 30)], 10)) }
  @Test func touchingASinglePoint() { #expect(Lasso.nearPath(stroke, [Pt(30, 4)], 5)) }
  @Test func pictureTouched() { #expect(Lasso.nearRect(Rect(0, 0, 50, 50), [Pt(-30, 25), Pt(80, 25)], 5)) }
  @Test func pictureMissed() { #expect(!Lasso.nearRect(Rect(0, 0, 50, 50), [Pt(-30, 90), Pt(80, 90)], 5)) }
}
