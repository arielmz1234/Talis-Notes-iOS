import Foundation
import Testing
@testable import TaliCore

struct PenFilterTests {
  @Test func everyPenIsTakenUntilSwitchedOff() {
    var filter = PenFilter()
    for pen in PenType.allCases { #expect(filter.hits(pen)) }
    filter.set(.PENCIL, false)
    #expect(!filter.hits(.PENCIL))
    #expect(filter.hits(.FINELINER))
    filter.set(.PENCIL, true)
    #expect(filter.hits(.PENCIL))
  }

  @Test func itIsStoredAsAndroidStoresIt() {
    var filter = PenFilter()
    filter.set(.HIGHLIGHTER, false)
    #expect(filter.choices == ["HIGHLIGHTER": false])
    #expect(!PenFilter(["HIGHLIGHTER": false, "FOUNTAIN": true]).hits(.HIGHLIGHTER))
  }
}

struct EraserTests {
  /// A level line from x = 0 to 100, 2 thick, sampled every 10.
  let line = InkInputs(points: (0...10).map { InkInput(x: Float($0) * 10, y: 0, t: Float($0) * 0.01, pressure: 0.5) })

  @Test func theStrokeEraserTakesAStrokeItCrossesWhole() {
    #expect(Eraser.hit(line, size: 2, mode: .STROKE, from: Pt(50, -10), to: Pt(50, 10), radius: 3) == .whole)
  }

  @Test func aStrokesOwnThicknessCounts() {
    // Radius 3 and half the stroke's 2: anything within 4 of its middle line is touched.
    #expect(Eraser.hit(line, size: 2, mode: .STROKE, from: Pt(20, 3.5), to: Pt(60, 3.5), radius: 3) == .whole)
    #expect(Eraser.hit(line, size: 2, mode: .STROKE, from: Pt(20, 4.5), to: Pt(60, 4.5), radius: 3) == .missed)
  }

  @Test func anEraserFarAwayMisses() {
    #expect(Eraser.hit(line, size: 2, mode: .STROKE, from: Pt(50, 40), to: Pt(60, 60), radius: 3) == .missed)
    #expect(Eraser.hit(line, size: 2, mode: .AREA, from: Pt(50, 40), to: Pt(60, 60), radius: 3) == .missed)
  }

  @Test func thePreciseEraserCutsOutOnlyWhereItPasses() throws {
    guard case .pieces(let left) = Eraser.hit(line, size: 2, mode: .AREA, from: Pt(50, -10), to: Pt(50, 10), radius: 3) else {
      Issue.record("the stroke should have been cut")
      return
    }
    try #require(left.count == 2)
    // Everything within 4 of the eraser's path is gone, and nothing further than a sample's gap (1.5) beyond that.
    let end = try #require(left[0].points.last).x, start = try #require(left[1].points.first).x
    #expect(end < 46 && end >= 44.5)
    #expect(start > 54 && start <= 55.5)
    #expect(left[0].points.first?.x == 0)
    #expect(left[1].points.last?.x == 100)
  }

  @Test func aStrokeRubbedOutCompletelyLeavesNoPieces() {
    let dot = InkInputs(points: [InkInput(x: 49, y: 0, t: 0), InkInput(x: 51, y: 0, t: 0.01)])
    #expect(Eraser.hit(dot, size: 2, mode: .AREA, from: Pt(50, -10), to: Pt(50, 10), radius: 3) == .pieces([]))
  }
}

struct StrokeAlongTests {
  let corner = [Pt(0, 0), Pt(30, 0), Pt(30, 30)]

  @Test func itKeepsEveryCornerAndNeverStepsFurtherThanThree() {
    let points = StrokeAlong.inputs(corner).points.map { Pt($0.x, $0.y) }
    #expect(points.first == Pt(0, 0))
    #expect(points.contains(Pt(30, 0)))
    #expect(points.last == Pt(30, 30))
    for (a, b) in zip(points, points.dropFirst()) { #expect(a.dist(b) <= 3.001) }
  }

  @Test func thePenMovesSlowlyAndEvenly() throws {
    let inputs = StrokeAlong.inputs(corner)
    // 60 units at 0.08 units a millisecond.
    #expect(abs(try #require(inputs.points.last).t - 0.75) < 0.002)
    #expect(inputs.points.allSatisfy { $0.pressure == 0.55 })
    for (a, b) in zip(inputs.points, inputs.points.dropFirst()) { #expect(b.t > a.t) }
  }
}
