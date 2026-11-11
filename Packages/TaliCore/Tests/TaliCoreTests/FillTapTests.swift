import Foundation
import Testing
@testable import TaliCore

/// What a tap of the fill tool does: which shape it fills, the area it finds, how a fill is stored.
struct FillTapTests {
  private func box(_ id: String, _ l: Float, _ t: Float, _ r: Float, _ b: Float, z: Int64 = 0, locked: Bool = false) -> ShapeRow {
    var s = ShapeRow(id: id, geometry: ShapeKind.RECTANGLE.inBox(Pt(l, t), Pt(r, b)), pen: "FINELINER", color: -1, size: 2, locked: locked)
    s.z = z
    return s
  }

  @Test func theTopmostClosedShapeUnderTheTapIsFilled() {
    let under = box("under", 0, 0, 200, 200, z: 1), over = box("over", 50, 50, 150, 150, z: 2)
    #expect(FillTap.shape(at: Pt(100, 100), in: [over, under])?.id == "over")
    #expect(FillTap.shape(at: Pt(20, 20), in: [over, under])?.id == "under")
    #expect(FillTap.shape(at: Pt(300, 300), in: [over, under]) == nil)
  }

  @Test func linesAndLockedShapesTakeNoFill() {
    let line = ShapeRow(id: "l", geometry: ShapeKind.LINE.inBox(Pt(0, 0), Pt(100, 100)), pen: "FINELINER", color: -1, size: 2)
    #expect(FillTap.shape(at: Pt(50, 50), in: [line]) == nil)
    #expect(FillTap.shape(at: Pt(50, 50), in: [box("locked", 0, 0, 100, 100, locked: true)]) == nil)
  }

  @Test func aLineAcrossAShapeSplitsIt() {
    let shape = box("box", 0, 0, 200, 200)
    let across = ShapeRow(id: "across", geometry: ShapeKind.LINE.inBox(Pt(-20, 100), Pt(220, 100)), pen: "FINELINER", color: -1, size: 2)
    #expect(!FillTap.runsThrough(shape, ink: [], shapes: [shape]))
    #expect(FillTap.runsThrough(shape, ink: [[Pt(100, 20), Pt(100, 180)]], shapes: [shape]), "writing inside it")
    #expect(!FillTap.runsThrough(shape, ink: [[Pt(300, 20), Pt(300, 180)]], shapes: [shape]), "writing beside it")
    #expect(!FillTap.runsThrough(shape, ink: [], shapes: [shape, across]), "a line that only has its ends outside doesn't count: its points decide")
    let inside = ShapeRow(id: "in", geometry: ShapeKind.LINE.inBox(Pt(20, 100), Pt(180, 100)), pen: "FINELINER", color: -1, size: 2)
    #expect(FillTap.runsThrough(shape, ink: [], shapes: [shape, inside]))
  }

  @Test func theWindowKeepsToThePage() {
    let page = Rect(0, 0, 794, 1123)
    #expect(AreaFill.window(around: Pt(400, 500), page: page) == page)
    #expect(AreaFill.window(around: Pt(400, 500), page: nil) == Rect(-700, -600, 1500, 1600))
  }

  /// A square drawn in the window from (100,100) to (300,300), as wall cells on the window's grid.
  private func squareMask(_ window: Rect) -> [Bool] {
    let (k, w, h) = AreaFill.grid(for: window)
    var g = [Bool](repeating: false, count: w * h)
    func cell(_ v: Float, _ from: Float) -> Int { Int((v - from) * k) }
    let x0 = cell(100, window.left), x1 = cell(300, window.left), y0 = cell(100, window.top), y1 = cell(300, window.top)
    for x in x0...x1 {
      g[y0 * w + x] = true
      g[y1 * w + x] = true
    }
    for y in y0...y1 {
      g[y * w + x0] = true
      g[y * w + x1] = true
    }
    return g
  }

  private let squareWalls = [
    AreaFill.Wall(id: "square", paths: [[Pt(100, 100), Pt(300, 100), Pt(300, 300), Pt(100, 300), Pt(100, 100)]], size: 2),
    AreaFill.Wall(id: "far", paths: [[Pt(500, 100), Pt(500, 300)]], size: 2),
  ]

  @Test func findsTheAreaTheWritingClosesIn() {
    let window = Rect(0, 0, 600, 400)
    guard case let .area(area) = AreaFill.find(mask: squareMask(window), window: window, at: Pt(200, 200), walls: squareWalls) else {
      Issue.record("expected an area")
      return
    }
    #expect(abs(area.rect.left - 100) <= 3 && abs(area.rect.right - 301) <= 3, "it tucks under the lines round it")
    #expect(abs(area.rect.top - 100) <= 3 && abs(area.rect.bottom - 301) <= 3)
    #expect(area.cells.count == area.width * area.height)
    #expect(area.cells[area.height / 2 * area.width + area.width / 2])
    #expect(area.outline == ["square"], "only the lines round it move with it")
  }

  @Test func outsideTheSquareNothingIsClosed() {
    let window = Rect(0, 0, 600, 400)
    #expect(AreaFill.find(mask: squareMask(window), window: window, at: Pt(450, 200), walls: squareWalls) == .open)
    #expect(AreaFill.find(mask: squareMask(window), window: window, at: Pt(100, 200), walls: squareWalls) == .open, "a tap on the line")
  }

  @Test func nearlyAllOfAShapeFillsTheShapeItself() {
    let window = Rect(0, 0, 600, 400)
    let whole: Float = 200 * 200 * 0.9
    #expect(AreaFill.find(mask: squareMask(window), window: window, at: Pt(200, 200), walls: squareWalls, whole: whole) == .wholeShape)
    guard case .area = AreaFill.find(mask: squareMask(window), window: window, at: Pt(200, 200), walls: squareWalls, whole: 400 * 400) else {
      Issue.record("a part of a bigger shape is an area of its own")
      return
    }
  }

  @Test func aFillIsStoredAsAndroidStoresIt() throws {
    let name = FillRow.fileName(colour: Int32(bitPattern: 0xB39D_B8F5), unique: "0f8fad5b-d9cb-469f-a165-70867728950e")
    #expect(name == "fill-b39db8f5-0f8fad5b-d9c.png")
    let fill = FillRow(id: "f", z: 9, file: name, rect: Rect(10, 20, 110.5, 220), walls: ["b", "a"])
    #expect(fill.row.kind == 2 && fill.row.pen == nil && fill.row.l == 10 && fill.row.b == 220)
    let o = try #require(JSONSerialization.jsonObject(with: fill.row.payload) as? [String: Any])
    #expect(Set(o.keys) == ["file", "rect", "walls"])
    #expect((o["rect"] as? [String: Double]) == ["left": 10, "top": 20, "right": 110.5, "bottom": 220])
    let back = try #require(FillRow(fill.row))
    #expect(back == fill)
    #expect(back.walls == ["a", "b"])
  }

  @Test func onlyFillPicturesAreFills() {
    func picture(_ json: String) -> ItemRow { ItemRow(id: "p", z: 1, kind: 2, pen: nil, color: 0, size: 0, payload: Data(json.utf8), l: 0, t: 0, r: 10, b: 10) }
    #expect(FillRow(picture(#"{"file":"photo-1.jpg","rect":{"left":0,"top":0,"right":10,"bottom":10}}"#)) == nil)
    let mirrored = FillRow(picture(#"{"file":"fill-ff000000-abc.png","rect":{"left":0,"top":0,"right":10,"bottom":10},"locked":true,"flipX":true}"#))
    #expect(mirrored?.flipX == true && mirrored?.flipY == false)
    #expect(mirrored?.walls == [])
  }

  @Test func aMirroredFillIsReadMirrored() throws {
    let plain = FillRow(id: "f", z: 1, file: "fill-ff000000-abc.png", rect: Rect(100, 100, 200, 300), walls: [])
    #expect(plain.cell(at: Pt(110, 290), width: 10, height: 20) == (1, 19))
    let json = #"{"file":"fill-ff000000-abc.png","rect":{"left":100,"top":100,"right":200,"bottom":300},"flipX":true,"flipY":true}"#
    let flipped = try #require(FillRow(ItemRow(id: "f", z: 1, kind: 2, pen: nil, color: 0, size: 0, payload: Data(json.utf8), l: 100, t: 100, r: 200, b: 300)))
    #expect(flipped.cell(at: Pt(110, 290), width: 10, height: 20) == (8, 0))
  }
}
