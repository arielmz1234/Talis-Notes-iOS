import Testing
@testable import TaliCore

// Android's Exporter page rules (there's no Android unit test for them; the numbers are its own).
struct ExportPagesTests {
  @Test func aPagedNotebookExportsEveryPageEmptyOnesToo() {
    let pages = ExportPages.pages(.a4Pages, items: [.init(Rect(10, 10, 50, 50))], pages: .portrait, pageCount: 3)
    #expect(pages == Pages.portrait.all(3))
  }

  @Test func a4PagesAreExactlyA4InPoints() {
    #expect(ExportPages.points(Pages.portrait.rect(0)) == (595, 842))
    #expect(ExportPages.points(Pages.landscape.rect(2)) == (842, 595))
  }

  @Test func anEndlessCanvasSkipsEmptyPages() {
    let items = [ExportPages.Item(Rect(0, 0, 100, 100)), .init(Rect(0, 4000, 100, 4100))]
    let pages = ExportPages.pages(.a4Pages, items: items, pages: .portrait, pageCount: nil)
    #expect(pages.count == 2)
    #expect(pages.allSatisfy { abs($0.width - A4.width) < 0.01 && abs($0.height - A4.height) < 0.01 })
    #expect(pages[0].top == -ExportPages.margin)
  }

  @Test func theFixedGridStartsAtTheOrigin() {
    let pages = ExportPages.pages(.a4Pages, items: [.init(Rect(A4.width + 10, 10, A4.width + 20, 20))], pages: .portrait, pageCount: nil, fixedGrid: true)
    #expect(pages == [Rect(A4.width, 0, A4.width * 2, A4.height)])
  }

  @Test func oneLongPageHoldsEverythingWithAMargin() {
    let pages = ExportPages.pages(.onePage, items: [.init(Rect(0, 0, 100, 100)), .init(Rect(200, 3000, 300, 3100))], pages: .portrait, pageCount: 4)
    #expect(pages == [Rect(-48, -48, 348, 3148)])
  }

  @Test func aVeryTallCanvasIsSplit() {
    let pages = ExportPages.pages(.onePage, items: [.init(Rect(0, 0, 100, 40000))], pages: .portrait, pageCount: nil)
    #expect(pages.count == 2)
    #expect(pages[0].height == ExportPages.maxSide)
  }

  @Test func eachSlideTakesTheNotesBelowIt() {
    let items = [
      ExportPages.Item(Rect(0, 0, 960, 540), pdfPage: true), .init(Rect(0, 600, 960, 1140), pdfPage: true),
      .init(Rect(-100, 300, 50, 350)), .init(Rect(100, 560, 200, 590)), .init(Rect(100, 1200, 200, 1300)),
    ]
    let pages = ExportPages.pages(.pdfPages, items: items, pages: .portrait, pageCount: nil)
    #expect(pages == [Rect(-100, 0, 960, 590), Rect(0, 600, 960, 1300)])
  }

  @Test func noSlidesFallsBackToOnePage() {
    let pages = ExportPages.pages(.pdfPages, items: [.init(Rect(0, 0, 100, 100))], pages: .portrait, pageCount: nil)
    #expect(pages == [Rect(-48, -48, 148, 148)])
  }
}
