import Foundation
import Testing
@testable import TaliCore

/// The selection's chips, rotate handle and a shape's dots on screen, and what dragging them does.
struct SelectionHandleTests {
  private let frame = Rect(100, 100, 300, 200)

  @Test func theChipsSitJustOffTheBottomCorners() {
    #expect(SelectionHandles.resizeChip(frame) == Pt(314, 214))
    #expect(SelectionHandles.moveChip(frame) == Pt(86, 214))
  }

  @Test func theRotateHandleHangsBelowTheMiddleAndBelowADotThere() {
    #expect(SelectionHandles.rotateHandle(frame) == Pt(200, 230))
    // A dot under the middle (a triangle's apex pointing down): the handle hangs below it instead.
    #expect(SelectionHandles.rotateHandle(frame, dots: [Pt(205, 210), Pt(110, 110)]) == Pt(200, 240))
    // A dot off to the side doesn't push it down.
    #expect(SelectionHandles.rotateHandle(frame, dots: [Pt(290, 215)]) == Pt(200, 230))
  }

  @Test func aTouchTakesTheNearestDotWithinReach() {
    let dots = [Pt(100, 150), Pt(300, 150)]
    let chips = [SelectionHandles.resizeChip(frame), SelectionHandles.moveChip(frame)]
    #expect(SelectionHandles.dot(at: Pt(290, 155), dots: dots, shapeSize: 200, area: frame, chips: chips) == 1)
    #expect(SelectionHandles.dot(at: Pt(88, 150), dots: dots, shapeSize: 200, area: frame, chips: chips) == 0)
    #expect(SelectionHandles.dot(at: Pt(200, 150), dots: dots, shapeSize: 200, area: frame, chips: chips) == nil)
  }

  @Test func theMiddleOfASmallShapeMovesItAndATinyOneHasNoDots() {
    // 40 across: the dots reach 12, but a touch nearer the middle than a dot carries the shape.
    let small = Rect(100, 100, 140, 140)
    let dots = [Pt(100, 120), Pt(140, 120)]
    #expect(SelectionHandles.dot(at: Pt(118, 120), dots: dots, shapeSize: 40, area: small, chips: []) == nil)
    #expect(SelectionHandles.dot(at: Pt(104, 120), dots: dots, shapeSize: 40, area: small, chips: []) == 0)
    #expect(SelectionHandles.dot(at: Pt(100, 120), dots: dots, shapeSize: 30, area: small, chips: []) == nil)
  }

  @Test func aChipNearerThanTheDotTakesTheTouch() {
    let chip = SelectionHandles.resizeChip(frame)
    let dots = [Pt(300, 200)]
    #expect(SelectionHandles.dot(at: Pt(310, 210), dots: dots, shapeSize: 200, area: frame, chips: [chip]) == nil)
    #expect(SelectionHandles.dot(at: Pt(303, 203), dots: dots, shapeSize: 200, area: frame, chips: [chip]) == 0)
  }

  @Test func dotsAreSizedByTheShapeOnScreen() {
    let line = ShapeGeometry.line(a: Pt(0, 0), b: Pt(200, 0), arrowStart: false, arrowEnd: false, ticks: false)
    #expect(SelectionHandles.shapeSize(line, on: Rect(0, -1, 200, 1)) == 200)
    #expect(SelectionHandles.shapeSize(ShapeKind.RECTANGLE.create(Pt(0, 0), Pt(200, 40)), on: Rect(0, 0, 200, 40)) == 40)
    #expect(SelectionHandles.dotRadius(shapeSize: 200) == 6.5)
    #expect(SelectionHandles.dotRadius(shapeSize: 33) == 4.5)
  }

  @Test func theResizeChipScalesEvenlyFromTheTopLeft() {
    let b = Rect(100, 100, 300, 200)
    let grab = Pt(300, 200)
    let twice = SelectionHandles.scale(b, from: grab, to: Pt(500, 300))
    #expect(twice.apply(Pt(100, 100)) == Pt(100, 100))
    #expect(twice.apply(Pt(300, 200)).dist(Pt(500, 300)) < 0.01)
    #expect(abs(SelectionHandles.scale(b, from: grab, to: Pt(9000, 9000)).scaleFactor - 10) < 1e-4)
    #expect(abs(SelectionHandles.scale(b, from: grab, to: Pt(101, 100)).scaleFactor - 0.1) < 1e-4)
    // Something small is never scaled down to nothing.
    #expect(SelectionHandles.scale(Rect(0, 0, 20, 10), from: Pt(20, 10), to: Pt(1, 0)) == .identity)
  }

  @Test func turningSnapsToFortyFivesByTheWayItFaces() {
    let pivot = Pt(0, 0)
    let quarter = SelectionHandles.turn(about: pivot, from: Pt(0, 100), to: Pt(-100, 0), facing: 0)
    #expect(abs(quarter - .pi / 2) < 1e-4)
    let nearly = SelectionHandles.turn(about: pivot, from: Pt(100, 0), to: Pt.polar(100, 43 * .pi / 180), facing: 0)
    #expect(abs(nearly - .pi / 4) < 1e-4)
    let free = SelectionHandles.turn(about: pivot, from: Pt(100, 0), to: Pt.polar(100, 30 * .pi / 180), facing: 0)
    #expect(abs(free - 30 * .pi / 180) < 1e-4)
    // Already facing 10° round: 33° more would leave it at 43°, so it lands on 45°.
    let leaning = SelectionHandles.turn(about: pivot, from: Pt(100, 0), to: Pt.polar(100, 33 * .pi / 180), facing: 10 * .pi / 180)
    #expect(abs(leaning - 35 * .pi / 180) < 1e-4)
  }

  @Test func theTurningAngleReadsCounterClockwise() {
    // Screen y points down, so a negative turn is counter-clockwise on the page.
    #expect(SelectionHandles.turnDegrees(-.pi / 4, line: false) == 45)
    #expect(SelectionHandles.turnDegrees(.pi / 4, line: false) == -45)
    #expect(SelectionHandles.turnDegrees(.pi, line: false) == -180)
    // A line turned half round is the same line.
    #expect(SelectionHandles.turnDegrees(.pi, line: true) == 0)
    #expect(SelectionHandles.turnDegrees(.pi / 4, line: true) == 135)
  }

  @Test func shapesFaceTheirOwnWay() {
    let down = ShapeGeometry.line(a: Pt(0, 0), b: Pt(0, 10), arrowStart: false, arrowEnd: false, ticks: false)
    #expect(abs((down.facing ?? 0) - .pi / 2) < 1e-4)
    let turned = ShapeKind.RECTANGLE.create(Pt(0, 0), Pt(200, 100)).transformed(.rotateAround(Pt(100, 50), 0.5))
    #expect(abs((turned.facing ?? 0) - 0.5) < 1e-4)
    let triangle = ShapeKind.TRIANGLE.create(Pt(0, 0), Pt(100, 80)).transformed(.rotateAround(Pt(50, 40), 0.25))
    #expect(abs((triangle.facing ?? 0) - 0.25) < 1e-4)
    #expect(ShapeKind.ARC.create(Pt(0, 0), Pt(100, 80)).facing == nil)
  }
}

/// The measuring badges (Android's `drawMeasure`).
struct MeasureTests {
  private let same: (Pt) -> Pt = { $0 }
  private let wide: (String) -> Float = { _ in 100 }

  private func line(_ a: Pt, _ b: Pt) -> ShapeGeometry { .line(a: a, b: b, arrowStart: false, arrowEnd: false, ticks: false) }

  @Test func aLineReadsItsAngleFromLevelAndItsPrintedLength() {
    // 160 units print an inch long.
    #expect(Measure.line(Pt(0, 0), Pt(160, 0)) == "0°  ·  2.5 cm")
    #expect(Measure.line(Pt(0, 0), Pt(100, -100)) == "45°  ·  2.2 cm")
    #expect(Measure.line(Pt(0, 0), Pt(100, 100)) == "135°  ·  2.2 cm")
    #expect(Measure.line(Pt(0, 0), Pt(-160, 0)) == "0°  ·  2.5 cm")
    #expect(Measure.line(Pt(0, 0), Pt(0.5, 0)) == nil)
  }

  @Test func circlesArcsAndPartCirclesReadTheirSize() {
    let circle = ShapeGeometry.ellipse(center: Pt(0, 0), rx: 100, ry: 100, rotation: 0)
    #expect(Measure.badges(circle, .changing(dot: 0), toScreen: same, width: wide).map(\.label) == ["r 1.6 cm  ·  ⌀ 3.2 cm"])
    let arc = ShapeGeometry.arc(center: Pt(0, 0), radius: 100, start: 0, sweep: .pi / 2, arrowEnd: false)
    #expect(Measure.badges(arc, .changing(dot: 1), toScreen: same, width: wide) == [Measure.Badge(label: "90°  ·  r 1.6 cm", at: Pt(0, 0))])
    let half = SectorShape.of(Pt(0, 0), Pt(100, 0), 0.5)
    #expect(Measure.badges(half, .changing(dot: nil), toScreen: same, width: wide).map(\.label) == ["50%  ·  180°  ·  r 1.6 cm"])
    // An ellipse and a moment show nothing.
    #expect(Measure.badges(ShapeKind.ELLIPSE.create(Pt(0, 0), Pt(100, 60)), .changing(dot: 0), toScreen: same, width: wide).isEmpty)
    #expect(Measure.badges(ShapeKind.MOMENT.create(Pt(0, 0), Pt(40, 0)), .changing(dot: nil), toScreen: same, width: wide).isEmpty)
  }

  @Test func aSmallSliceKeepsItsBadgeBehindItsCorner() throws {
    let slice = SectorShape.of(Pt(0, 0), Pt(100, 0), 0.25)
    let at = try #require(Measure.badges(slice, .changing(dot: 1), toScreen: same, width: wide).first?.at)
    #expect(at.x < -50 && abs(at.y) < 0.01)
    let most = SectorShape.of(Pt(0, 0), Pt(100, 0), 0.75)
    #expect(Measure.badges(most, .changing(dot: 1), toScreen: same, width: wide).first?.at == Pt(0, 0))
  }

  @Test func aLinesBadgeStaysClearOfThePen() throws {
    let long = line(Pt(0, 0), Pt(400, 0))
    // Beside the middle, on the upper side.
    let beside = try #require(Measure.badges(long, .changing(dot: 1), toScreen: same, width: wide).first?.at)
    #expect(beside == Pt(200, -22))
    // Short: past the end that isn't moving.
    let short = line(Pt(0, 0), Pt(120, 0))
    #expect(Measure.badges(short, .changing(dot: 1), toScreen: same, width: wide).first?.at == Pt(-64, 0))
    #expect(Measure.badges(short, .changing(dot: 0), toScreen: same, width: wide).first?.at == Pt(184, 0))
    // Just showing its dots: under the chips and the rotate handle.
    let frame = Rect(-8, -8, 408, 8)
    #expect(Measure.badges(long, .idle(frame: frame), toScreen: same, width: wide).first?.at == Pt(200, 72))
  }

  @Test func aTrianglesAnglesShowOnlyWhileItChanges() {
    let t = ShapeGeometry.triangle(a: Pt(0, 0), b: Pt(200, 0), c: Pt(0, -200))
    #expect(Measure.badges(t, .idle(frame: Rect(0, -200, 200, 0)), toScreen: same, width: wide).isEmpty)
    #expect(Measure.badges(t, .changing(dot: 2), toScreen: same, width: wide).map(\.label) == ["90°", "45°", "45°"])
  }

  @Test func aBadgeMovesAsideFromAChipAndStaysOnScreen() {
    let screen: (w: Float, h: Float) = (400, 300)
    let chip: (at: Pt, radius: Float) = (Pt(200, 150), 17)
    #expect(Measure.clearSpot(Pt(200, 150), w: 100, h: 24, screen: screen, avoid: [], menu: nil) == Pt(200, 150))
    let moved = Measure.clearSpot(Pt(200, 150), w: 100, h: 24, screen: screen, avoid: [chip], menu: nil)
    #expect(moved != Pt(200, 150))
    #expect(abs(moved.x - 200) > 50 + 17 || abs(moved.y - 150) > 12 + 17)
    #expect(Measure.clearSpot(Pt(-500, 900), w: 100, h: 24, screen: screen, avoid: [], menu: nil) == Pt(54, 284))
  }
}
