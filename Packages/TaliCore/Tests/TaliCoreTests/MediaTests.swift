import Foundation
import Testing
@testable import TaliCore

// Ported from Android's VoiceMemoTest and ImageFrontTest, plus the payloads ItemCodec writes.
struct MediaTests {
  @Test func buttonsInOneColumnKeepTheirDistance() {
    let out = MemoRow.spread([("a", Pt(100, 50)), ("b", Pt(100, 60)), ("c", Pt(100, 300))], spacing: 58, size: 48)
    #expect(out["a"]!.y == 50)
    #expect(out["b"]!.y == 108)
    #expect(out["c"]!.y == 300)
  }

  @Test func buttonsInOtherColumnsAreLeftAlone() {
    let out = MemoRow.spread([("a", Pt(100, 50)), ("b", Pt(400, 55))], spacing: 58, size: 48)
    #expect(out["b"]!.y == 55)
  }

  @Test func aWaveHasItsBarsScaledToTheLoudest() {
    let wave = MemoRow.waveOf((0..<200).map { $0 == 100 ? 0.5 : 0.1 })
    #expect(wave.count == MemoRow.waveBars)
    #expect(wave.max() == 100)
    #expect((15...25).contains(wave.min()!))
  }

  @Test func aShortRecordingIsStretched() {
    let wave = MemoRow.waveOf([0.3, 0.6])
    #expect(wave.count == MemoRow.waveBars)
    #expect(wave.first == 50)
    #expect(wave.last == 100)
  }

  @Test func frontSurvivesSaving() {
    var item = PictureRow(id: "a", z: 42, file: "pic.jpg", rect: Rect(0, 0, 100, 50))
    item.front = true
    let back = PictureRow(item.itemRow)!
    #expect(back.front)
    #expect(back.z == 42)
    #expect(back.file == "pic.jpg")
  }

  @Test func olderPicturesStayBehind() {
    let old = ItemRow(
      id: "b", z: 3, kind: 2, pen: nil, color: 0, size: 0, payload: Data(#"{"file":"x.jpg","rect":{"left":0.0,"top":0.0,"right":10.0,"bottom":10.0}}"#.utf8),
      l: 0, t: 0, r: 10, b: 10)
    let item = PictureRow(old)!
    #expect(!item.front)
    #expect(item.crop == nil)
    #expect(item.rect == Rect(0, 0, 10, 10))
  }

  @Test func aPictureWritesOnlyWhatIsntDefault() throws {
    let row = PictureRow(id: "p", z: 1, file: "a.jpg", rect: Rect(1, 2, 3, 4)).itemRow
    let o = try #require(JSONSerialization.jsonObject(with: row.payload) as? [String: Any])
    #expect(Set(o.keys) == ["file", "rect"])
    #expect(row.kind == 2 && row.pen == nil && row.l == 1 && row.b == 4)
  }

  @Test func aCropKeepsTheWholePicture() {
    let p = PictureRow(id: "p", z: 1, file: "a.jpg", rect: Rect(0, 0, 200, 100))
    let c = p.cropped(Rect(0.25, 0.5, 0.75, 1), shown: Rect(50, 50, 150, 100))
    #expect(c.whole == Rect(0, 0, 200, 100))
    #expect(PictureRow(c.itemRow)!.crop == Rect(0.25, 0.5, 0.75, 1))
  }

  @Test func pdfPagePicturesNameTheirPdfAndPage() {
    let id = "0b1c2d3e-4f50-6172-8394-a5b6c7d8e9f0"
    let file = PictureRow.pdfPageFile(pdf: id, page: 12, unique: "x")
    #expect(PictureRow.pdfSource(of: file)! == (id, 12))
    #expect(PictureRow.pdfSource(of: "pdf-\(id).pdf") == nil)
    #expect(PictureRow.pdfSource(of: "photo.jpg") == nil)
  }

  @Test func aMemoReadsBackAsAndroidWroteIt() throws {
    let payload = #"{"file":"m.m4a","x":1300.5,"y":200.0,"durationMs":4200,"wave":[1,2,3],"created":99,"side":1,"title":"Exam"}"#
    let row = ItemRow(id: "m", z: 7, kind: 4, pen: nil, color: 0, size: 0, payload: Data(payload.utf8), l: 0, t: 0, r: 0, b: 0)
    let m = try #require(MemoRow(row))
    #expect(m.at == Pt(1300.5, 200) && m.durationMs == 4200 && m.wave == [1, 2, 3] && m.created == 99)
    #expect(m.side == MemoRow.left && m.edge == MemoRow.edge && m.title == "Exam" && !m.locked)
    #expect(MemoRow(m.itemRow) == m)
  }

  @Test func aNewMemoWritesOnlyWhatIsntDefault() throws {
    let m = MemoRow(id: "m", z: 1, file: "m.m4a", at: Pt(10, 20), durationMs: 5, wave: [], created: 0)
    let o = try #require(JSONSerialization.jsonObject(with: m.itemRow.payload) as? [String: Any])
    #expect(Set(o.keys) == ["file", "x", "y", "durationMs"])
    #expect(m.itemRow.l == -10 && m.itemRow.r == 30)
  }

  @Test func aMemoDroppedNearerTheLeftGoesLeftOfThePage() {
    let place = MemoPlacement(zoom: 0.5, origin: Pt(100, 0), screen: Pt(1000, 800), pages: .portrait, pageCount: 2, topClearance: 104)
    let m = MemoRow(id: "m", z: 1, file: "m.m4a", at: Pt(1400, 50), durationMs: 5, wave: [], created: 0)
    let left = place.drop(m, at: Pt(200, 400))
    #expect(left.side == MemoRow.left && left.at == Pt(-MemoRow.size, 800))
    let right = place.drop(m, at: Pt(600, 9000))
    #expect(right.side == MemoRow.right && right.at.y == Pages.portrait.pitch + Pages.portrait.height)
  }

  @Test func aMemoSitsBesideThePaperOnScreen() {
    let place = MemoPlacement(zoom: 0.5, origin: Pt(100, 0), screen: Pt(1000, 800), pages: .portrait, pageCount: 1, topClearance: 104)
    let m = MemoRow(id: "m", z: 1, file: "m.m4a", at: Pt(1400, 50), durationMs: 5, wave: [], created: 0)
    let c = place.centre(m, radius: 24, gap: 12)
    #expect(abs(c.x - (100 + Pages.portrait.width * 0.5 + MemoRow.edge)) < 0.01)
    #expect(c.y == 25)
  }

  @Test func newMemosGoBelowTheOnesThere() {
    let place = MemoPlacement(zoom: 1, origin: Pt(0, 0), screen: Pt(1400, 900), pages: .portrait, pageCount: 1, topClearance: 104)
    let first = place.newSpot([], spacing: 70)
    #expect(first.x == Pages.portrait.width + MemoRow.size)
    let m = MemoRow(id: "m", z: 1, file: "m.m4a", at: first, durationMs: 5, wave: [], created: 0)
    #expect(place.newSpot([m], spacing: 70).y == first.y + 70)
  }
}
