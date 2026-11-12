import Foundation
import Testing
@testable import TaliCore

// Ported from Android's LineStyleTest, RoundThreeTest (the pen's three thicknesses) and PencilDroppedTest.
struct ShapeInkTests {
  private func shape(_ pen: String, _ color: UInt32) -> ShapeRow {
    ShapeRow(geometry: .line(a: Pt(0, 0), b: Pt(10, 0), arrowStart: false, arrowEnd: false, ticks: false), pen: pen, color: Int32(bitPattern: color), size: 2)
  }

  @Test func aHighlightersShapeIsSeeThroughLikeItsInk() {
    #expect(UInt32(bitPattern: shape("HIGHLIGHTER", 0xFFFF_D60A).inkColor) == 0x66FF_D60A)
  }

  @Test func otherShapesKeepTheirOpacityAndAColourWithoutAnyIsOpaque() {
    #expect(UInt32(bitPattern: shape("FINELINER", 0x801F_5FD1).inkColor) == 0x801F_5FD1)
    #expect(UInt32(bitPattern: shape("FINELINER", 0x001F_5FD1).inkColor) == 0xFF1F_5FD1)
  }
}

struct LineStyleTests {
  let line = [Pt(0, 0), Pt(600, 0)]

  @Test func shortDashesHaveTheirPatternsLengths() {
    let size: Float = 2
    let pieces = Dashes.cut(line, size: size, line: .SHORT_DASH)
    #expect(pieces.count > 50)
    // Pieces are cut a pen-width short (the round ends add it back); gaps a pen-width long.
    let first = pieces[0]
    #expect(abs((first.last!.x - first.first!.x) - (2.4 - 1) * size) < 1e-3)
    #expect(abs((pieces[1].first!.x - first.last!.x) - (2 + 1) * size) < 1e-3)
  }

  @Test func dotAndDashAlternates() {
    let lengths = Dashes.cut(line, size: 2, line: .DOT_DASH).prefix(4).map { $0.last!.x - $0.first!.x }
    #expect(lengths[0] > 4 && lengths[1] < 0.5 && lengths[2] > 4 && lengths[3] < 0.5)
  }

  @Test func shortPathsStaySolid() {
    let barb = [Pt(0, 0), Pt(12, 0)]
    #expect(Dashes.cut(barb, size: 2, line: .LONG_DASH) == [barb])
  }

  @Test func aDashedShapeIsCutButItsArrowHeadStaysWhole() {
    let arrow = ShapeGeometry.line(a: Pt(0, 0), b: Pt(600, 0), arrowStart: false, arrowEnd: true, ticks: false)
    let solid = ShapeRow(geometry: arrow, pen: "FINELINER", color: 0, size: 2)
    let dashed = ShapeRow(geometry: arrow, pen: "FINELINER", color: 0, size: 2, line: "LONG_DASH")
    let head = solid.strokes.filter { Geo.pathLength($0) < 100 }
    #expect(!head.isEmpty)
    #expect(dashed.strokes.count > 30)
    for barb in head { #expect(dashed.strokes.contains(barb)) }
  }

  @Test func aSolidLineIsLeftWhole() {
    #expect(Dashes.cut(line, size: 2, line: .SOLID) == [line])
  }

  @Test func theOldDashedPenBecomesAFinelinerDrawingShortDashes() {
    let pens = PenSlot.migrated([PenSlot(id: "d", type: .DASHED, color: 0, size: 2)])
    #expect(pens[0].type == .FINELINER)
    #expect(pens[0].lineStyle == .SHORT_DASH)
  }

  @Test func aHighlighterIsAlwaysSolid() {
    #expect(PenSlot(id: "h", type: .HIGHLIGHTER, color: 0, size: 18, line: .DOTTED).lineStyle == .SOLID)
  }

  @Test func theNamesAreTheOnesAndroidStores() {
    #expect(LineStyle.allCases.map(\.rawValue) == ["SOLID", "DOTTED", "LONG_DASH", "SHORT_DASH", "DOT_DASH", "MIXED_DASH"])
  }
}

struct PenSlotTests {
  @Test func threeThicknessesAreKeptApart() {
    let pen = PenSlot(id: "a", type: .FINELINER, color: 0, size: 2.5)
    let sizes = pen.presetSizes
    #expect(sizes.count == 3)
    #expect(sizes[0] < sizes[1] && sizes[1] < sizes[2])
    let thick = pen.pickSize(2)
    #expect(thick.size == sizes[2])
    let changed = thick.withSize(9)
    #expect(changed.presetSizes == [sizes[0], sizes[1], 9])
    #expect(changed.pickSize(0).size == sizes[0])
  }

  @Test func changingThePenTypeKeepsHerThicknessWithinWhatItCanDo() {
    let wide = PenSlot(id: "h", type: .HIGHLIGHTER, color: 0, size: 36).pickSize(1)
    let pen = wide.withType(.FINELINER)
    #expect(pen.size == 20)
    #expect(pen.presetSizes.allSatisfy { $0 <= 20 && $0 >= 0.5 })
    #expect(PenSlot(id: "f", type: .FINELINER, color: 7, size: 3).withType(.FOUNTAIN).size == 3)
  }

  @Test func theHighlighterDrawsStraightUntilSetToFreehand() {
    let h = PenSlot(id: "h", type: .HIGHLIGHTER, color: 0, size: 18)
    #expect(h.straight && !h.square)
    #expect(!PenSlot(id: "h", type: .HIGHLIGHTER, color: 0, size: 18, freehand: true).straight)
    #expect(PenSlot(id: "h", type: .HIGHLIGHTER, color: 0, size: 18, squareTip: true).square)
    // Only a highlighter has the choices.
    let pen = PenSlot(id: "p", type: .FINELINER, color: 0, size: 2, squareTip: true)
    #expect(!pen.straight && !pen.square)
  }

  @Test func highlighterInkIsSeeThroughAndOtherInkOpaque() {
    #expect(UInt32(bitPattern: PenSlot(id: "h", type: .HIGHLIGHTER, color: Int32(bitPattern: 0xFFFF_D60A), size: 18).inkColor) == 0x66FF_D60A)
    #expect(UInt32(bitPattern: PenSlot(id: "p", type: .FINELINER, color: 0x001B_1F2A, size: 2).inkColor) == 0xFF1B_1F2A)
  }

  @Test func pensSavedBeforeTheNewFieldsStillLoad() throws {
    let old = #"[{"id":"p1","type":"FINELINER","color":-15000022,"size":2.4}]"#
    let pens = try JSONDecoder().decode([PenSlot].self, from: Data(old.utf8))
    #expect(pens[0].line == .SOLID && !pens[0].squareTip && !pens[0].freehand && pens[0].sizeSlot == 1)
    // Android's own JSON for a dotted pen and a square freehand highlighter.
    let android = #"[{"id":"a","type":"FOUNTAIN","color":-1,"size":3.0,"line":"DOTTED"},{"id":"b","type":"HIGHLIGHTER","color":-1,"size":18.0,"squareTip":true,"freehand":true}]"#
    let two = try JSONDecoder().decode([PenSlot].self, from: Data(android.utf8))
    #expect(two[0].lineStyle == .DOTTED)
    #expect(two[1].square && !two[1].straight)
    #expect(try JSONDecoder().decode([PenSlot].self, from: JSONEncoder().encode(two)) == two)
  }

  private let five = [
    PenSlot(id: "p1", type: .FINELINER, color: 0, size: 2.4),
    PenSlot(id: "p2", type: .FOUNTAIN, color: 0, size: 3),
    PenSlot(id: "p3", type: .PENCIL, color: 0, size: 2.6),
    PenSlot(id: "p4", type: .FINELINER, color: 0, size: 2.4),
    PenSlot(id: "p5", type: .HIGHLIGHTER, color: 0, size: 18),
  ]

  @Test func newSettingsStartWithFourPens() {
    #expect(PenSlot.defaults.count == 4)
    #expect(!PenSlot.defaults.contains { $0.type == .PENCIL })
  }

  @Test func theBuiltInPencilLeavesSavedSettings() {
    #expect(PenSlot.migrated(five).map(\.id) == ["p1", "p2", "p4", "p5"])
  }

  @Test func aPencilSheAddedOrMadeStays() {
    var pens = five
    pens[2].type = .FOUNTAIN
    pens.append(PenSlot(id: "a1b2c3d4", type: .PENCIL, color: 0, size: 2))
    #expect(PenSlot.migrated(pens).count == 6)
  }

  @Test func aNewPenIsAFinelinerInHerFirstColourUpToEightPens() throws {
    let five = try #require(PenSlot.adding(id: "n1", firstColor: 0xFFD8_3A3A, to: PenSlot.defaults))
    #expect(five.count == 5)
    #expect(five[4] == PenSlot(id: "n1", type: .FINELINER, color: Int32(bitPattern: 0xFFD8_3A3A), size: 2.5))
    let eight = (0..<4).reduce(PenSlot.defaults) { pens, i in PenSlot.adding(id: "x\(i)", firstColor: nil, to: pens) ?? pens }
    #expect(eight.count == 8)
    #expect(PenSlot.adding(id: "ninth", firstColor: nil, to: eight) == nil)
  }

  @Test func aPenCanBeRemovedButNotTheLastOne() {
    #expect(PenSlot.removing("p2", from: PenSlot.defaults)?.map(\.id) == ["p1", "p4", "p5"])
    #expect(PenSlot.removing("p1", from: [PenSlot.defaults[0]]) == nil)
  }

  @Test func everyPenGetsItsOwnId() {
    let pens = PenSlot.migrated([PenSlot(id: "x", type: .FINELINER, color: 0, size: 2), PenSlot(id: "x", type: .FOUNTAIN, color: 0, size: 3)])
    #expect(Set(pens.map(\.id)).count == 2)
  }
}

// The straight highlighter's rules, from Android's `straightTo` and `StrokeFactory.straightLine`.
struct StraightLineTests {
  private func degrees(_ a: Pt, _ b: Pt) -> Double { Double(atan2f(b.y - a.y, b.x - a.x)) * 180 / .pi }

  @Test func aNearlyLevelLineSnapsLevelAndKeepsItsLength() {
    let start = Pt(100, 100)
    let pen = start + Pt.polar(200, Float(3.5 * .pi / 180))
    let end = StraightLine.end(from: start, to: pen)
    #expect(abs(end.y - 100) < 1e-3)
    #expect(abs(end.dist(start) - 200) < 1e-2)
  }

  @Test func aNearlyUprightLineSnapsUpright() {
    let start = Pt(100, 100)
    for angle in [87.0, 93.0, -88.0] {
      let end = StraightLine.end(from: start, to: start + Pt.polar(150, Float(angle * .pi / 180)))
      #expect(abs(end.x - 100) < 1e-2)
    }
    // Leftwards too.
    let left = StraightLine.end(from: start, to: start + Pt.polar(150, Float(178.0 * .pi / 180)))
    #expect(abs(left.y - 100) < 1e-2 && left.x < 0)
  }

  @Test func pastFourDegreesItKeepsItsAngle() {
    let start = Pt(0, 0)
    let pen = Pt.polar(200, Float(5.0 * .pi / 180))
    #expect(StraightLine.end(from: start, to: pen) == pen)
    let steep = Pt.polar(200, Float(40.0 * .pi / 180))
    #expect(abs(degrees(start, StraightLine.end(from: start, to: steep)) - 40) < 1e-3)
  }

  @Test func aTapLeavesAShortMark() {
    let end = StraightLine.end(from: Pt(50, 50), to: Pt(50, 50))
    #expect(end == Pt(50.1, 50))
  }

  @Test func theSamplesAreFineAtBothEndsAndSparseInTheMiddle() {
    let a = Pt(0, 0), b = Pt(1000, 0)
    let pts = StraightLine.inputs(a, b).points
    #expect(pts.first!.x == 0 && pts.last!.x == 1000)
    #expect(abs(pts[1].x - 0.25) < 1e-4)
    #expect(pts.allSatisfy { $0.pressure == 0.55 })
    #expect(zip(pts, pts.dropFirst()).allSatisfy { $0.x < $1.x && abs(($1.t - $0.t) - 0.002) < 1e-5 })
    // 8 units of fine steps at each end, about 24 long steps between.
    let middle = pts.filter { $0.x > 8.5 && $0.x < 991.5 }
    #expect(middle.count >= 20 && middle.count <= 26)
    // A line across a page costs no more than a short one's ends plus the middle steps.
    #expect(pts.count < 100)
  }

  @Test func aShortLineIsAllFineSteps() {
    let pts = StraightLine.inputs(Pt(0, 0), Pt(4, 0)).points
    #expect(pts.first!.x == 0 && pts.last!.x == 4)
    #expect(zip(pts, pts.dropFirst()).allSatisfy { $1.x - $0.x <= 0.26 })
  }
}

// The precise eraser's cutting, from Android's `StrokeFactory.split` and `eraseSegment`.
struct StrokeCutTests {
  private func stroke(_ xs: [Float], pressure: (Float) -> Float? = { _ in 0.5 }) -> InkInputs {
    InkInputs(points: xs.enumerated().map { i, x in InkInput(x: x, y: 0, t: Float(i) * 0.01, pressure: pressure(x)) }, tool: .stylus)
  }

  /// The eraser resting at [c] with [reach].
  private func under(_ c: Pt, _ reach: Float) -> (Float, Float) -> Bool {
    { x, y in Geo.distToSegment(Pt(x, y), c, c) <= reach }
  }

  @Test func cuttingThroughTheMiddleLeavesTwoPieces() {
    let s = stroke(stride(from: Float(0), through: 100, by: 5).map { $0 })
    let pieces = StrokeCut.split(s, maxGap: 2, erased: under(Pt(50, 0), 6))!
    #expect(pieces.count == 2)
    #expect(pieces[0].points.first!.x == 0 && pieces[0].points.last!.x < 44.01)
    #expect(pieces[1].points.first!.x > 55.99 && pieces[1].points.last!.x == 100)
    // Nothing under the eraser is left.
    #expect(pieces.allSatisfy { p in p.points.allSatisfy { abs($0.x - 50) > 6 } })
  }

  @Test func aStrokeTheEraserMissesIsLeftAlone() {
    #expect(StrokeCut.split(stroke([0, 50, 100]), maxGap: 2, erased: under(Pt(50, 40), 6)) == nil)
  }

  @Test func aGapBetweenSparseSamplesCanStillBeCut() {
    // Two samples 100 apart: the eraser passes between them.
    let pieces = StrokeCut.split(stroke([0, 100]), maxGap: 2, erased: under(Pt(50, 0), 6))!
    #expect(pieces.count == 2)
    #expect(pieces[0].points.last!.x < 44.01 && pieces[0].points.last!.x > 40)
    #expect(pieces[1].points.first!.x > 55.99 && pieces[1].points.first!.x < 60)
  }

  @Test func piecesKeepTheirPressureAndTiming() {
    let s = stroke([0, 100]) { $0 / 100 }
    let pieces = StrokeCut.split(s, maxGap: 5, erased: under(Pt(50, 0), 6))!
    let p = pieces[0].points.last!
    #expect(abs(p.pressure! - p.x / 100) < 1e-4)
    #expect(abs(p.t - 0.01 * p.x / 100) < 1e-5)
    #expect(pieces[1].points.first!.t > p.t)
    #expect(pieces.allSatisfy { $0.tool == .stylus })
  }

  @Test func rubbingOutAnEndLeavesOnePiece() {
    let pieces = StrokeCut.split(stroke(stride(from: Float(0), through: 100, by: 5).map { $0 }), maxGap: 2, erased: under(Pt(0, 0), 10))!
    #expect(pieces.count == 1)
    #expect(pieces[0].points.first!.x > 10 && pieces[0].points.last!.x == 100)
  }

  @Test func aStrokeWhollyUnderTheEraserLeavesNothing() {
    #expect(StrokeCut.split(stroke([48, 50, 52]), maxGap: 2, erased: under(Pt(50, 0), 10))! == [])
  }

  @Test func aSingleSampleLeftOverIsDropped() {
    // Everything but the last sample is under the eraser: one point can't be a stroke.
    let pieces = StrokeCut.split(stroke([0, 1, 2, 30]), maxGap: 40, erased: { x, _ in x < 10 })!
    #expect(pieces.isEmpty)
  }

  @Test func theEraserTouchesALineItCrossesOrPassesNear() {
    let line = [Pt(0, 0), Pt(100, 0)]
    #expect(StrokeCut.touches(line, Pt(50, -30), Pt(50, 30), reach: 1))
    #expect(StrokeCut.touches(line, Pt(40, 5), Pt(60, 5), reach: 6))
    #expect(!StrokeCut.touches(line, Pt(40, 9), Pt(60, 9), reach: 6))
    #expect(!StrokeCut.touches(line, Pt(120, -30), Pt(120, 30), reach: 6))
    #expect(StrokeCut.touches([Pt(5, 5)], Pt(0, 0), Pt(10, 0), reach: 6))
  }
}

// The laser's timing, from Android's `drawLaser` (LASER_IDLE_MS 1000, LASER_FADE_MS 450).
struct LaserTests {
  @Test func itStaysLitWhilePointingAndForASecondAfter() {
    var l = Laser()
    l.start(Pt(0, 0))
    l.move(Pt(10, 0))
    let lit1 = l.step(at: 60)
    #expect(lit1)
    #expect(Laser.life(l.trails[0], at: 60) == 1)
    l.end(at: 100)
    let lit2 = l.step(at: 100.99)
    #expect(lit2)
    #expect(Laser.life(l.trails[0], at: 100.99) == 1)
  }

  @Test func thenEverythingFadesTogetherAndIsGone() {
    var l = Laser()
    l.start(Pt(0, 0))
    l.move(Pt(10, 0))
    l.end(at: 10)
    l.start(Pt(0, 20))
    l.move(Pt(10, 20))
    l.end(at: 12)
    let lit3 = l.step(at: 13.225)
    #expect(lit3)
    // Both strokes fade on the same clock, counted from the last lift.
    #expect(l.trails.count == 2)
    #expect(l.trails.allSatisfy { abs(Laser.life($0, at: 13.225) - 0.25) < 1e-3 })
    let lit4 = l.step(at: 13.46)
    #expect(!lit4)
    #expect(l.trails.isEmpty)
  }

  @Test func pointingAgainRelightsWhatWasFading() {
    var l = Laser()
    l.start(Pt(0, 0))
    l.move(Pt(10, 0))
    l.end(at: 0)
    let lit5 = l.step(at: 1.2)
    #expect(lit5)
    #expect(Laser.life(l.trails[0], at: 1.2) < 1)
    l.start(Pt(5, 5))
    #expect(l.trails.count == 2)
    #expect(l.trails.allSatisfy { Laser.life($0, at: 1.3) == 1 })
    #expect(l.down && l.tip == Pt(5, 5))
  }

  @Test func itDimsQuicklyThenLingers() {
    let t = Laser.Trail(dots: [], fadeAt: 0)
    #expect(Laser.life(t, at: 0) == 1)
    #expect(abs(Laser.life(t, at: Laser.fade / 2) - 0.25) < 1e-4)
    #expect(Laser.life(t, at: Laser.fade) == 0)
    #expect(Laser.glow(1).width == 12 && Laser.core(1).width == 3.5)
    #expect(Laser.glow(0).width == 8 && abs(Laser.core(0).width - 2.2) < 1e-5)
  }
}
