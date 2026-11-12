import Foundation
import Testing
@testable import TaliCore

struct LockTests {
  private func picture(_ json: String) -> ItemRow {
    ItemRow(id: "p", z: 3, kind: 2, pen: nil, color: 0, size: 0, payload: Data(json.utf8), l: 0, t: 0, r: 10, b: 10)
  }

  @Test func inkKeepsItsLockLastInThePenColumn() {
    #expect(InkTags.with(["DOTTED", "SQUARE"], locked: true) == ["DOTTED", "SQUARE", "LOCKED"])
    #expect(InkTags.with(["LOCKED", "DOTTED"], locked: true) == ["DOTTED", "LOCKED"])
    #expect(InkTags.with(["DOTTED", "LOCKED"], locked: false) == ["DOTTED"])
    #expect(InkTags.isLocked(["LOCKED"]) && !InkTags.isLocked(["DOTTED"]))
  }

  @Test func aShapesLockIsAKeyInItsJson() throws {
    var s = ShapeRow(id: "s", geometry: .line(a: Pt(0, 0), b: Pt(10, 0), arrowStart: false, arrowEnd: false, ticks: false), pen: "FINELINER", color: -1, size: 2)
    #expect(try JSONSerialization.jsonObject(with: s.itemRow.payload) as? [String: Any] != nil)
    #expect(!String(decoding: s.itemRow.payload, as: UTF8.self).contains("locked"))
    s.locked = true
    #expect(ShapeRow(s.itemRow)?.locked == true)
  }

  @Test func picturesAndTextKeepTheirLockInTheirPayload() throws {
    var p = try #require(PictureRow(picture(#"{"file":"a.jpg","rect":{"left":0,"top":0,"right":10,"bottom":10}}"#)))
    #expect(!p.locked)
    p.locked = true
    #expect(PictureRow(p.itemRow)?.locked == true)
    var t = TextRow(id: "t", text: "hi", x: 0, y: 0, width: 100, fontSize: 26, color: -1)
    t.locked = true
    #expect(TextRow(t.row(textHeight: 30))?.locked == true)
  }

  @Test func movingUnlocksWritingShapesAndTextButNotPictures() throws {
    let by = Affine.translate(5, 5)
    let shape = ShapeRow(id: "s", geometry: .line(a: Pt(0, 0), b: Pt(10, 0), arrowStart: false, arrowEnd: false, ticks: false), pen: "FINELINER", color: -1, size: 2, locked: true)
    #expect(!shape.transformed(by).locked)
    #expect(!TextRow(id: "t", text: "hi", x: 0, y: 0, width: 100, fontSize: 26, color: -1, locked: true).transformed(by).locked)
    var p = try #require(PictureRow(picture(#"{"file":"a.jpg","rect":{"left":0,"top":0,"right":10,"bottom":10},"locked":true}"#)))
    p = p.transformed(by)
    #expect(p.locked && p.rect == Rect(5, 5, 15, 15))
    #expect(!p.copy(id: "q", z: 9, walls: []).locked, "a copy starts unlocked")
  }
}

struct PictureSelectingTests {
  private let pic = PictureRow(id: "a", z: 7, file: "pic.jpg", rect: Rect(0, 0, 100, 50))

  // Ported from Android's ImageFrontTest.
  @Test func frontSurvivesSaving() throws {
    let back = try #require(PictureRow(pic.inFront(true, z: 42).itemRow))
    #expect(back.front && back.z == 42 && back.file == "pic.jpg")
  }

  @Test func olderPicturesStayBehind() throws {
    let old = ItemRow(
      id: "b", z: 3, kind: 2, pen: nil, color: 0, size: 0, payload: Data(#"{"file":"x.jpg","rect":{"left":0.0,"top":0.0,"right":10.0,"bottom":10.0}}"#.utf8), l: 0, t: 0, r: 10, b: 10)
    #expect(try #require(PictureRow(old)).front == false)
  }

  @Test func aResizedPictureKeepsItsBoxTheRightWayRound() {
    let p = pic.transformed(.scaleAround(Pt(0, 0), 2))
    #expect(p.rect == Rect(0, 0, 200, 100))
    #expect(pic.transformed(.scaleAround(Pt(50, 25), -1, 1)).rect == Rect(0, 0, 100, 50))
  }

  @Test func mirroredAPictureMovesButOnlyAFillFlips() {
    // Mirrored left to right about x = 200.
    let m = Affine.scaleAround(Pt(200, 0), -1, 1)
    let moved = pic.mirrored(m, horizontal: true)
    #expect(moved.rect == Rect(300, 0, 400, 50) && !moved.flipX)
    var fill = pic
    fill.file = "fill-ff000000-abc.png"
    let flipped = fill.mirrored(m, horizontal: true)
    #expect(flipped.rect == Rect(300, 0, 400, 50) && flipped.flipX && !flipped.flipY)
    #expect(!flipped.mirrored(m, horizontal: true).flipX, "mirrored again it faces the first way")
  }
}

struct FillGroupTests {
  private let fills = [FillGroup.Fill(id: "f", walls: ["a", "b", "c"]), FillGroup.Fill(id: "g", walls: ["c", "d"]), FillGroup.Fill(id: "old", walls: [])]
  private func noneLocked(_: String) -> Bool? { false }

  @Test func aLineOfItsOutlineBringsTheFillAndTheRestOfTheOutline() {
    #expect(FillGroup.with(["a"], fills: [fills[0]], isLocked: noneLocked, pickLocked: false) == ["a", "f", "b", "c"])
  }

  @Test func theFillBringsItsOutline() {
    #expect(Set(FillGroup.with(["f"], fills: [fills[0]], isLocked: noneLocked, pickLocked: false)) == ["f", "a", "b", "c"])
  }

  @Test func fillsSharingALineComeTogether() {
    #expect(Set(FillGroup.with(["a"], fills: fills, isLocked: noneLocked, pickLocked: false)) == ["a", "f", "b", "c", "g", "d"])
  }

  @Test func writingThatOutlinesNothingStaysAlone() {
    #expect(FillGroup.with(["x"], fills: fills, isLocked: noneLocked, pickLocked: false) == ["x"])
    #expect(FillGroup.with(["old"], fills: fills, isLocked: noneLocked, pickLocked: false) == ["old"], "a fill made before outlines were kept")
  }

  @Test func lockedPartsStayBehindUnlessLockedThingsArePickedUp() {
    func locked(_ id: String) -> Bool? { id == "b" ? true : (id == "c" ? nil : false) }
    #expect(FillGroup.with(["a"], fills: [fills[0]], isLocked: locked, pickLocked: false) == ["a", "f"], "b is locked and c is gone")
    #expect(FillGroup.with(["a"], fills: [fills[0]], isLocked: locked, pickLocked: true) == ["a", "f", "b"])
    let lockedFill = [FillGroup.Fill(id: "f", walls: ["a"], locked: true)]
    #expect(FillGroup.with(["a"], fills: lockedFill, isLocked: noneLocked, pickLocked: false) == ["a"])
    #expect(FillGroup.with(["a"], fills: lockedFill, isLocked: noneLocked, pickLocked: true) == ["a", "f"])
  }

  @Test func aCopiedFillOutlinesTheCopies() {
    #expect(FillGroup.copiedWalls(["a", "b", "gone"], ids: ["a": "a2", "b": "b2", "f": "f2"]) == ["a2", "b2"])
  }

  @Test func aCutOutlineKeepsItsPieces() {
    // The precise eraser cut "b" in two and took "c" whole; "x" was cut from a line of another drawing.
    let walls = FillGroup.wallsAfterErasing(["a", "b", "c"], gone: ["b", "c", "z"], pieces: ["b1": "b", "b2": "b", "x": "z"])
    #expect(walls == ["a", "b1", "b2"])
  }

  @Test func aFillWhoseOutlineWasNotErasedIsLeftAsItIs() {
    #expect(FillGroup.wallsAfterErasing(["a", "b"], gone: ["z"], pieces: ["x": "z"]) == nil)
    #expect(FillGroup.wallsAfterErasing([], gone: ["z"], pieces: [:]) == nil)
  }

  @Test func thePiecesOfACutOutlineArePickedUpWithTheFill() {
    let cut = FillGroup.wallsAfterErasing(["a", "b"], gone: ["b"], pieces: ["b1": "b", "b2": "b"]) ?? []
    let picked = FillGroup.with(["b1"], fills: [FillGroup.Fill(id: "f", walls: cut)], isLocked: { _ in false }, pickLocked: false)
    #expect(Set(picked) == ["b1", "f", "a", "b2"])
  }
}

struct ArrangeTests {
  private func ink(_ id: String, _ z: Int64) -> Arrange.Item { Arrange.Item(id: id, z: z) }

  @Test func broughtToTheFrontItGoesAboveEverythingKeepingItsOrder() throws {
    let plan = try #require(Arrange.plan([ink("b", 2), ink("a", 1)], others: [ink("c", 3)], toFront: true, top: 3))
    #expect(plan.map(\.id) == ["a", "b"] && plan.map(\.z) == [4, 5])
  }

  @Test func sentToTheBackItGoesBelowEverything() throws {
    let plan = try #require(Arrange.plan([ink("b", 5), ink("c", 6)], others: [ink("a", 1)], toFront: false, top: 6))
    #expect(plan.map(\.z) == [-1, 0] && plan.allSatisfy { !$0.front })
  }

  @Test func alreadyThereChangesNothing() {
    #expect(Arrange.plan([ink("c", 3)], others: [ink("a", 1), ink("b", 2)], toFront: true, top: 3) == nil)
    #expect(Arrange.plan([ink("a", 1)], others: [ink("b", 2)], toFront: false, top: 2) == nil)
  }

  @Test func aPictureBehindTheWritingCanAlwaysComeForward() throws {
    // It has the highest place, but sits behind all writing until it's brought forward.
    let picture = Arrange.Item(id: "p", z: 9, picture: true)
    let plan = try #require(Arrange.plan([picture], others: [ink("a", 1)], toFront: true, top: 9))
    #expect(plan[0].front && plan[0].z == 10)
    // Other pictures behind the writing don't count as above it.
    #expect(Arrange.plan([ink("a", 1)], others: [picture], toFront: true, top: 9) == nil)
    // Brought forward, it can be sent back again.
    let forward = Arrange.Item(id: "p", z: 0, picture: true, front: true)
    #expect(try #require(Arrange.plan([forward], others: [ink("a", 1)], toFront: false, top: 1))[0].front == false)
  }
}

struct FreeFormLoopTests {
  private func circle(_ r: Float, upTo turn: Float = 2 * .pi) -> [Pt] { (0...40).map { Pt.polar(r, turn * Float($0) / 40) } }

  @Test func aPathThatComesBackRoundIsALoop() { #expect(Lasso.loopCloses(circle(100), zoom: 1)) }
  @Test func anOpenPathIsNot() { #expect(!Lasso.loopCloses(circle(100, upTo: .pi), zoom: 1)) }
  @Test func aShortWiggleIsNot() { #expect(!Lasso.loopCloses(circle(10), zoom: 1)) }
  @Test func itIsMeasuredOnScreen() {
    // The same small circle zoomed in is long enough to be a loop; a wide gap zoomed in is no longer closed.
    #expect(Lasso.loopCloses(circle(10), zoom: 4))
    let nearly = circle(100, upTo: 2 * .pi - 0.2)
    #expect(Lasso.loopCloses(nearly, zoom: 1) && !Lasso.loopCloses(nearly, zoom: 4))
  }
}

struct ScreenshotLassoTests {
  @Test func atLeastTwiceTheScreensSharpness() {
    let area = Rect(0, 0, 400, 300)
    #expect(ScreenshotLasso.pixelsPerUnit(area, zoom: 0.5, screenScale: 2) == 4)
    #expect(ScreenshotLasso.pixelsPerUnit(area, zoom: 3, screenScale: 2) == 6)
  }

  @Test func neverMoreThanAboutSixteenMillionPixels() {
    let px = ScreenshotLasso.pixelsPerUnit(Rect(0, 0, 4000, 4000), zoom: 3, screenScale: 2)
    #expect(abs(px - 1) < 0.001)
  }

  @Test func aTinyAreaIsNoPicture() {
    #expect(ScreenshotLasso.tooSmall(Rect(0, 0, 10, 200), zoom: 1))
    #expect(!ScreenshotLasso.tooSmall(Rect(0, 0, 10, 200), zoom: 2))
  }
}

struct TextBoxSideTests {
  private let box = TextRow(id: "t", text: "hi", x: 100, y: 200, width: 300, fontSize: 26, color: -1)

  @Test func theLeftSideSetsTheWidthFromTheRight() {
    let t = box.withSide(0, draggedBy: Pt(-50, 0), content: 40, text: 34)
    #expect(t.width == 350 && t.x == 50 && t.fontSize == 26)
  }

  @Test func theRightSideSetsTheWidthFromTheLeft() {
    let t = box.withSide(1, draggedBy: Pt(-500, 0), content: 40, text: 34)
    #expect(t.width == TextRow.minWidth && t.x == 100)
  }

  @Test func theTopNeverGoesBelowTheText() {
    // Dragged down past the text: the box is as tall as the text, its bottom where it was.
    let t = box.withSide(2, draggedBy: Pt(0, 30), content: 40, text: 34)
    #expect(t.height == 34 && t.y == 206)
    let taller = box.withSide(2, draggedBy: Pt(0, -60), content: 40, text: 34)
    #expect(taller.height == 100 && taller.y == 140)
  }

  @Test func theBottomSetsTheHeight() {
    #expect(box.withSide(3, draggedBy: Pt(0, 60), content: 40, text: 34).height == 100)
  }

  @Test func theCornerFollowsTheFingerAndTheTextKeepsItsSize() {
    let t = box.withCorner(draggedBy: Pt(100, 60), content: 40)
    #expect(t.width == 400 && t.height == 100 && t.fontSize == 26 && t.x == 100 && t.y == 200)
  }
}

struct JointDotTests {
  @Test func aSubjectShapeOffersItsJointsAsDots() throws {
    let jointed = ShapePacks.all.flatMap(\.shapes).compactMap { s -> ShapeGeometry? in
      let g = s.create(Pt(40, 60), Pt(240, 200))
      if case .param = g, !g.handles().isEmpty { return g }
      return nil
    }
    let g = try #require(jointed.first)
    let dot = g.handles()[0]
    #expect(g.withHandle(0, dot + Pt(40, 30)) != g, "dragging a joint changes the shape")
    #expect(g.facing != nil)
  }
}
