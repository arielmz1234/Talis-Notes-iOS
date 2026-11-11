import Testing
@testable import TaliCore

struct CropTests {
  private let pic = PictureRow(id: "p", z: 1, file: "a.jpg", rect: Rect(100, 100, 500, 400))

  @Test func aCornerMovesTwoSides() {
    let c = CropEdit(pic)
    let f = c.dragged(0, from: c.frame, dx: 50, dy: 30, zoom: 1)
    #expect(f == Rect(150, 130, 500, 400))
  }

  @Test func aSideNearThePicturesEdgeSticksToIt() {
    var c = CropEdit(pic)
    c.frame = Rect(150, 150, 450, 350)
    #expect(c.dragged(7, from: c.frame, dx: -45, dy: 0, zoom: 1).left == 100)
    #expect(c.dragged(7, from: c.frame, dx: -40, dy: 0, zoom: 1).left == 110)
  }

  @Test func theFrameStaysInsideAndNeverTooSmall() {
    var c = CropEdit(pic)
    c.frame = Rect(150, 150, 450, 350)
    #expect(c.dragged(8, from: c.frame, dx: 500, dy: -500, zoom: 1) == Rect(200, 100, 500, 300))
    #expect(c.dragged(3, from: c.frame, dx: -1000, dy: 0, zoom: 2).right == 164)
  }

  @Test func finishingKeepsTheWholePicture() {
    var c = CropEdit(pic)
    c.frame = Rect(200, 100, 500, 250)
    let done = c.finished
    #expect(done.rect == Rect(200, 100, 500, 250))
    #expect(done.crop == Rect(0.25, 0, 1, 0.5))
    #expect(done.whole == pic.rect)
    var reopened = CropEdit(done)
    reopened.frame = reopened.whole
    #expect(reopened.finished.crop == nil && reopened.finished.rect == pic.rect)
  }

  @Test func pdfPagesAndMirroredPicturesArentCropped() {
    var p = pic
    #expect(CropEdit.croppable(p))
    p.pdfPage = true
    #expect(!CropEdit.croppable(p))
    p.pdfPage = false
    p.flipX = true
    #expect(!CropEdit.croppable(p))
  }
}
