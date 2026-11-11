import Foundation
import Testing
@testable import TaliCore

/// The Shapes tool's style and choice of shape, and Android's `ShapeFillTest` (a shape's fill and
/// line survive saving).
struct ShapeLookTests {
  private let circle = ShapeGeometry.ellipse(center: Pt(50, 50), rx: 40, ry: 40, rotation: 0)
  private let black = Int32(bitPattern: 0xFF00_0000)

  @Test func fillSurvivesSaving() throws {
    let fill = Int32(bitPattern: 0xB39D_B8F5)
    let item = ShapeRow(geometry: circle, pen: "FINELINER", color: black, size: 2, fill: fill)
    let back = try #require(ShapeRow(item.row(id: "s", z: 3)))
    #expect(back.fill == fill)
    #expect(back.geometry == circle)
  }

  @Test func olderShapesHaveNoFill() throws {
    let back = try #require(ShapeRow(ShapeRow(geometry: circle, pen: "FINELINER", color: black, size: 2).row(id: "s", z: 3)))
    #expect(back.fill == nil)
  }

  @Test func lineStyleSurvivesSaving() throws {
    let dashed = ShapeRow(geometry: circle, pen: "FINELINER", color: black, size: 2, line: "DOT_DASH")
    #expect(try #require(ShapeRow(dashed.row(id: "s", z: 3))).line == "DOT_DASH")
    #expect(try #require(ShapeRow(ShapeRow(geometry: circle, pen: "FINELINER", color: 0, size: 2).row(id: "s", z: 3))).line == "SOLID")
  }

  @Test func opacitiesGoIntoTheColours() {
    let style = ShapeLook(color: Int32(bitPattern: 0xFF1F_5FD1), size: 3, fill: Int32(bitPattern: 0xFFFF_D60A), opacity: 0.5, fillOpacity: 0.2)
    #expect(UInt32(bitPattern: style.outlineArgb) == 0x7F1F_5FD1)
    #expect(style.fillArgb.map(UInt32.init(bitPattern:)) == 0x33FF_D60A)
    #expect(UInt32(bitPattern: ShapeLook.withOpacity(black, 0)) == 0x1900_0000, "never fainter than 10%")
    #expect(UInt32(bitPattern: FillColour.argb(Int32(bitPattern: 0xFF9D_B8F5), opacity: 0.7)) == 0xB29D_B8F5)
    #expect(UInt32(bitPattern: FillColour.argb(black, opacity: 0)) == 0x2600_0000, "the fill tool never goes under 15%")
  }

  @Test func onlyClosedShapesTakeTheFill() {
    let style = ShapeLook(color: black, size: 3, line: "DOTTED", fill: Int32(bitPattern: 0xFFFF_D60A))
    let box = style.row(ShapeKind.RECTANGLE.inBox(Pt(0, 0), Pt(80, 40)))
    #expect(box.fill.map(UInt32.init(bitPattern:)) == 0x7FFF_D60A)
    #expect(box.pen == "FINELINER")
    #expect(box.line == "DOTTED")
    #expect(style.row(ShapeKind.ARROW.inBox(Pt(0, 0), Pt(80, 40))).fill == nil)
  }

  @Test func likeThePenKeepsItsOwnFillAndOpacities() {
    let own = ShapeLook(color: black, size: 3, fill: 7, opacity: 0.4, fillOpacity: 0.3)
    let look = own.following(color: Int32(bitPattern: 0x66FF_D60A), size: 18, line: "LONG_DASH")
    #expect(UInt32(bitPattern: look.color) == 0xFFFF_D60A)
    #expect(look.size == ShapeLook.maxSize)
    #expect(look.line == "LONG_DASH")
    #expect(look.fill == 7 && look.opacity == 0.4 && look.fillOpacity == 0.3)
  }

  @Test func styleKeepsAndroidsJson() throws {
    let style = ShapeLook(color: Int32(bitPattern: 0xFF1B_1F2A), size: 2.4, line: "SHORT_DASH", fill: -1, opacity: 0.5, fillOpacity: 0.7)
    let data = try JSONSerialization.data(withJSONObject: style.json)
    let read = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    #expect(ShapeLook(json: read) == style)
    let plain = try #require(ShapeLook(json: ["color": -14_999_766, "size": 2.4]))
    #expect(plain == ShapeLook(color: -14_999_766, size: 2.4))
    #expect(Set(ShapeLook(color: 1, size: 2).json.keys) == ["color", "size"], "defaults are left out, as kotlinx does")
  }

  @Test func theChoiceIsKeptAsAndroidKeepsIt() {
    #expect(ShapeChoice(stored: "ELLIPSE") == .kind(.ELLIPSE))
    #expect(ShapeChoice(stored: "SQUARE") == .kind(.RECTANGLE), "the Square tile went: the rectangle snaps to a square")
    #expect(ShapeChoice(stored: "nothing") == .kind(.LINE))
    #expect(ShapeChoice(stored: "pack:resistor") == .pack("resistor"))
    #expect(ShapeChoice(stored: "pack:gone") == .kind(.LINE), "a subject shape this version doesn't have")
    #expect(ShapeChoice(stored: "custom:ab12cd34") == .custom("ab12cd34"))
    for choice in [ShapeChoice.kind(.STAR), .pack("resistor"), .custom("ab12cd34")] { #expect(ShapeChoice(stored: choice.stored) == choice) }
  }

  @Test func aSavedShapeThatIsGoneFallsBackToTheStandardOne() {
    guard case .kind(.TRIANGLE) = ShapeChoice.custom("gone").source(custom: [], kind: .TRIANGLE) else {
      Issue.record("expected the standard shape")
      return
    }
  }

  @Test func aSubjectShapeDrawnLikeALineKeepsToTidyAngles() throws {
    let resistor = try #require(ShapePacks.shape("resistor"))
    guard case let .param(drawn) = ShapeSource.pack(resistor).drawn(Pt(100, 100), Pt(300, 104)), let ends = drawn.lineEnds else {
      Issue.record("expected a shape with joints, drawn like a line")
      return
    }
    #expect(abs(ends.1.y - 100) < 0.01, "a nearly level drag is level")
    guard case let .param(kept) = ShapeSource.pack(resistor).drawn(Pt(100, 100), Pt(300, 104), keepEnd: true), let keptEnds = kept.lineEnds else {
      Issue.record("expected a shape with joints")
      return
    }
    #expect(abs(keptEnds.1.y - 104) < 0.01, "an end that locked onto something stays there")
  }

  @Test func aSavedShapeFitsTheDraggedBox() throws {
    let saved = CustomShape(id: "a", name: "A", geometry: try #require(CustomShape.normalized(ShapeKind.TRIANGLE.inBox(Pt(0, 0), Pt(40, 80)))))
    let box = try #require(ShapeSource.custom(saved).drawn(Pt(100, 100), Pt(300, 200)).bounds(0))
    #expect(abs(box.height - 100) < 1 && abs(box.width - 50) < 1, "as big as the box allows, keeping its proportions")
    #expect(abs(box.center.x - 200) < 0.5 && abs(box.center.y - 150) < 0.5)
  }

  @Test func aRectangleNearlySquareSnapsSquare() {
    guard case let .poly(points, _, _, _) = ShapeSource.kind(.RECTANGLE).drawn(Pt(0, 0), Pt(100, 97)) else {
      Issue.record("expected a rectangle")
      return
    }
    #expect(points[2] == Pt(100, 100))
    guard case let .poly(wide, _, _, _) = ShapeSource.kind(.RECTANGLE).drawn(Pt(0, 0), Pt(100, 90)) else { return }
    #expect(wide[2] == Pt(100, 90), "outside 4% it stays as dragged")
  }

  @Test func aSquareAndACircleShowTheyLockedOn() throws {
    let square = try #require(ShapeSource.kind(.RECTANGLE).drawn(Pt(0, 0), Pt(100, 98)).squareHint)
    #expect(square.0 == Pt(0, 0) && square.1 == Pt(100, 100), "corner to corner")
    #expect(ShapeSource.kind(.RECTANGLE).drawn(Pt(0, 0), Pt(100, 60)).squareHint == nil)
    #expect(ShapeSource.kind(.DIAMOND).drawn(Pt(0, 0), Pt(100, 100)).squareHint == nil, "only a rectangle")
    let round = try #require(ShapeSource.kind(.ELLIPSE).drawn(Pt(0, 0), Pt(100, 98)).squareHint)
    #expect(abs(round.0.dist(round.1) - 100) < 0.01, "a diameter")
    #expect(abs((round.1 - round.0).x + (round.1 - round.0).y) < 0.01, "at 45 degrees")
    #expect(ShapeSource.kind(.ELLIPSE).drawn(Pt(0, 0), Pt(100, 60)).squareHint == nil)
  }
}
