import Testing
@testable import TaliCore

struct PlacingTests {
  @Test func aBigPictureTakesAtMostSixtyPercentOfTheView() {
    let r = Placing.picture(size: Pt(4000, 3000), visible: Rect(0, 0, 1000, 800), at: nil, index: 0, zoom: 1, maxUnitsPerPixel: 1)
    #expect(r.width == 600 && r.height == 450)
    #expect(r.center == Pt(500, 400))
  }

  @Test func aSmallPictureKeepsItsPixels() {
    let r = Placing.picture(size: Pt(100, 50), visible: Rect(0, 0, 1000, 800), at: Pt(300, 300), index: 1, zoom: 2, maxUnitsPerPixel: 1)
    #expect(r == Rect(268, 293, 368, 343))
  }

  @Test func aPictureInTheGapMovesOntoThePage() {
    let p = Pages.portrait
    let r = Placing.ontoPage(Rect(100, p.height - 50, 300, p.height + 30), pages: p, count: 2)
    #expect(r.bottom == p.height)
    let inside = Rect(100, 100, 200, 200)
    #expect(Placing.ontoPage(inside, pages: p, count: 2) == inside)
  }

  @Test func pdfPagesFillTheEmptyLastPageFirst() {
    let p = Pages.portrait
    let (start, rects) = Placing.pdfOnPages([Pt(960, 540), Pt(960, 540)], pages: p, count: 3, lastIsEmpty: true)
    #expect(start == 2)
    #expect(rects[0].top == p.rect(2).top && rects[1].top == p.rect(3).top)
    #expect(abs(rects[0].width - p.width) < 0.01)
  }

  @Test func pdfPagesGoBelowTheWriting() {
    let rects = Placing.pdfOnCanvas([Pt(800, 600), Pt(400, 600)], content: Rect(0, 0, 1000, 500), visible: Rect(0, 0, 1200, 900))
    #expect(rects[0] == Rect(100, 660, 900, 1260))
    #expect(rects[1] == Rect(300, 1300, 700, 1900))
  }
}
