import Foundation
import Testing
@testable import TaliCore

struct PageMovesTests {
  private let layout = Pages.portrait

  private func ink(_ id: String, y: Float) -> ItemRow {
    let inputs = InkInputs(points: [InkInput(x: 100, y: y, t: 0, pressure: 0.5), InkInput(x: 200, y: y + 10, t: 0.1, pressure: 0.5)])
    return ItemRow(id: id, z: 1, kind: 0, pen: "FINELINER", color: -16_777_216, size: 4, payload: InkCodec.encode(inputs), l: 98, t: y - 2, r: 202, b: y + 12)
  }

  private func text(_ id: String, y: Float) -> ItemRow {
    TextRow(id: id, z: 2, text: "Hi", x: 60, y: y, width: 300, fontSize: 26, color: -16_777_216).row(textHeight: 34)
  }

  private func json(_ r: ItemRow) -> [String: Any] { (try? JSONSerialization.jsonObject(with: r.payload) as? [String: Any]) ?? [:] }

  @Test func everyKindMovesWithItsPage() throws {
    let moved = ink("a", y: 50).translated(5, 100)
    let points = try InkCodec.decode(moved.payload).points
    #expect(points.map(\.y) == [150, 160])
    #expect(points.map(\.x) == [105, 205])
    #expect(moved.t == 148 && moved.l == 103)

    let t = text("t", y: 40).translated(0, 900)
    #expect(TextRow(t)?.y == 940)
    #expect(TextRow(t)?.text == "Hi")

    let pic = ItemRow(
      id: "p", z: 3, kind: 2, pen: nil, color: 0, size: 0,
      payload: Data(#"{"file":"img.jpg","rect":{"left":10,"top":20,"right":110,"bottom":220},"locked":true}"#.utf8), l: 10, t: 20, r: 110, b: 220)
    let r = try #require(json(pic.translated(0, 50))["rect"] as? [String: Any])
    #expect((r["top"] as? NSNumber)?.floatValue == 70)
    #expect((r["bottom"] as? NSNumber)?.floatValue == 270)
    #expect(json(pic.translated(0, 50))["locked"] as? Bool == true)

    let box = ShapeRow(geometry: .ellipse(center: Pt(300, 300), rx: 40, ry: 20, rotation: 0), pen: "FINELINER", color: 0, size: 3, fill: 7).row(id: "s", z: 4)
    let shape = try #require(ShapeRow(box.translated(0, -100)))
    #expect(shape.geometry == .ellipse(center: Pt(300, 200), rx: 40, ry: 20, rotation: 0))
    #expect(shape.fill == 7)
  }

  @Test func aSubjectShapeMovesByItsPlace() throws {
    let row = ItemRow(
      id: "q", z: 1, kind: 1, pen: "FINELINER", color: 0, size: 3,
      payload: Data(#"{"type":"param","template":"pulley","place":{"a":2.0,"d":2.0,"tx":40.0},"w":10,"h":10}"#.utf8), l: 40, t: 0, r: 60, b: 20)
    let o = json(row.translated(10, 30))
    let place = try #require(o["place"] as? [String: Any])
    #expect((place["tx"] as? NSNumber)?.floatValue == 50)
    #expect((place["ty"] as? NSNumber)?.floatValue == 30)
    #expect((place["a"] as? NSNumber)?.floatValue == 2)
    #expect(o["template"] as? String == "pulley")
  }

  @Test func deletingAPageMovesTheOnesAfterUp() {
    let rows = [ink("a", y: 100), ink("b", y: layout.pitch + 100), text("c", y: 2 * layout.pitch + 100)]
    var z: Int64 = 10
    let plan = layout.rearranged(rows, count: 3, order: Pages.withoutPages(3, [1]), newId: { "new" }, nextZ: &z)
    #expect(plan.removed == ["b"])
    #expect(plan.count == 2)
    #expect(plan.written.map(\.id) == ["c"])
    #expect(TextRow(plan.written[0])?.y == layout.pitch + 100)
  }

  @Test func aPageListedTwiceIsCopiedRightAfterIt() throws {
    let rows = [ink("a", y: 100), ink("b", y: layout.pitch + 100)]
    var z: Int64 = 10
    var ids = ["c1"].makeIterator()
    let plan = layout.rearranged(rows, count: 2, order: Pages.withCopies(2, [0]), newId: { ids.next()! }, nextZ: &z)
    #expect(plan.count == 3)
    #expect(plan.removed.isEmpty)
    let copy = try #require(plan.written.first { $0.id == "c1" })
    #expect(try InkCodec.decode(copy.payload).points.first?.y == layout.pitch + 100)
    #expect(copy.z == 11)
    let b = try #require(plan.written.first { $0.id == "b" })
    #expect(try InkCodec.decode(b.payload).points.first?.y == 2 * layout.pitch + 100)
  }

  @Test func deletingEveryPageLeavesOneEmptyPage() {
    var z: Int64 = 0
    let plan = layout.rearranged([ink("a", y: 10)], count: 1, order: [], newId: { "x" }, nextZ: &z)
    #expect(plan.removed == ["a"])
    #expect(plan.count == 1)
  }

  @Test func endlessWritingComesOntoThePages() {
    #expect(layout.shiftOntoPages(nil) == .zero)
    #expect(layout.shiftOntoPages(Rect(100, 100, 600, 400)) == .zero)
    let narrow = layout.shiftOntoPages(Rect(-300, -50, 200, 300))
    #expect(narrow.x == (layout.width - 500) / 2 + 300)
    #expect(narrow.y == 110)
    let wide = layout.shiftOntoPages(Rect(-800, 200, 1400, 300))
    #expect(wide.x == 860)
    #expect(wide.y == 0)
  }
}
