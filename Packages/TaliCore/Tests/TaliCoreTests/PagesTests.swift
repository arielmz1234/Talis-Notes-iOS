import Foundation
import Testing
@testable import TaliCore

// Ported from Android's MovePageTest and the page layout rules in canvas/Pages.kt.
struct PagesTests {
  private func order(_ n: Int, _ from: Int, _ to: Int) -> [Int] {
    var out = Array(repeating: 0, count: n)
    for p in 0..<n { out[Pages.movedIndex(p, from: from, to: to)] = p }
    return out
  }

  @Test func moveDown() { #expect(order(5, 0, 2) == [1, 2, 0, 3, 4]) }
  @Test func moveUp() { #expect(order(5, 4, 1) == [0, 4, 1, 2, 3]) }
  @Test func stayPut() { #expect(order(3, 1, 1) == [0, 1, 2]) }
  @Test func deleteSome() { #expect(Pages.withoutPages(5, [1, 3]) == [0, 2, 4]) }
  @Test func deleteAll() { #expect(Pages.withoutPages(3, [0, 1, 2]) == []) }
  @Test func copiesSitAfterTheirPage() { #expect(Pages.withCopies(4, [1, 3]) == [0, 1, 1, 2, 3, 3]) }

  @Test func a4MatchesAndroid() {
    #expect(abs(A4.width - 1322.2222) < 0.01)
    #expect(abs(A4.height - 1871.1111) < 0.01)
    #expect(Pages.landscape.width == A4.height)
  }

  @Test func gapBelowAPageCountsAsThatPage() {
    let p = Pages.portrait
    #expect(p.indexAt(p.height + 10) == 0)
    #expect(p.indexAt(p.pitch + 1) == 1)
    #expect(p.contains(2, 10, p.pitch + 5))
    #expect(!p.contains(2, 10, p.height + 10))
    #expect(!p.contains(1, 10, p.pitch + 5))
  }

  @Test func ownShapePagesAreAsLongAsA4() {
    let wide = Pages.of(landscape: false, aspect: 16.0 / 9.0)
    #expect(wide.width == A4.height)
    #expect(abs(wide.aspect - 16.0 / 9.0) < 0.001)
    let tall = Pages.of(landscape: true, aspect: 0.5)
    #expect(tall.height == A4.height)
    #expect(Pages.of(landscape: true, aspect: nil) == .landscape)
    #expect(Pages.of(landscape: false, aspect: .nan) == .portrait)
  }

  @Test func clipKeepsAStrokeOnItsPage() {
    let p = Pages.portrait
    #expect(p.clip(anchorY: p.pitch + 3, count: 3, between: false) == p.rect(1))
    #expect(p.clip(anchorY: 99_999, count: 3, between: false) == p.rect(2))
    #expect(p.clip(anchorY: 5, count: 3, between: true) == Rect(0, 0, p.width, p.rect(2).bottom))
    #expect(p.needed(nil) == 1)
    #expect(p.needed(Rect(0, 0, 10, p.pitch * 2 + 1)) == 3)
  }
}

struct NamesTests {
  @Test func theNameItselfWhenFree() { #expect(Names.numbered("New notebook", taken: ["Statics"]) == "New notebook") }
  @Test func theNextNumberWhenTaken() {
    #expect(Names.numbered("New notebook", taken: ["new notebook", "New notebook (1) ", "New notebook (3)"]) == "New notebook (2)")
  }
  @Test func aGapIsFilled() { #expect(Names.numbered("New folder", taken: ["New folder", "New folder (2)"]) == "New folder (1)") }
  @Test func aNumberedNameCountsOnFromItsStem() { #expect(Names.numbered("Slides (1)", taken: ["Slides", "Slides (1)"]) == "Slides (2)") }
  @Test func caseAndSpacesDontMakeANameDifferent() { #expect(Names.numbered(" Statics ", taken: ["statics"]) == "Statics (1)") }

  @Test func naturalOrder() {
    let names = ["Notebook 10", "notebook 2", "Algebra", "Notebook 1"]
    #expect(names.sorted { Names.naturalCompare($0, $1) < 0 } == ["Algebra", "Notebook 1", "notebook 2", "Notebook 10"])
    #expect(Names.naturalCompare("a02", "a2") == 0)
  }

  @Test func greetings() {
    #expect(Greeting.forHour(5) == .good_morning)
    #expect(Greeting.forHour(12) == .good_afternoon)
    #expect(Greeting.forHour(20) == .good_evening)
    #expect(Greeting.forHour(2) == .good_night)
  }
}

struct NotesDbTests {
  @Test func notebooksAndFoldersRoundTrip() throws {
    let db = try NotesDb(path: ":memory:")
    let n = NotebookMeta(
      id: "n1", title: "Statics", created: 1, updated: 2, cover: 0xFF9B_7BE0, paper: .GRID, customPaper: "p9",
      viewport: Viewport(x: 3, y: 4, zoom: 1.5), folderId: "f1", pages: 3, dark: true, landscape: true, kind: .pdf, pageAspect: 1.5)
    try db.insert(Folder(id: "f1", name: "Uni", color: 0xFF7F_B5F0, position: 0))
    try db.insert(n)
    let back = try db.notebooks()
    #expect(back == [NotebookMeta(
      id: "n1", title: "Statics", created: 1, updated: 2, cover: 0xFF9B_7BE0, paper: .BLANK, customPaper: "p9",
      viewport: Viewport(x: 3, y: 4, zoom: 1.5), folderId: "f1", pages: 3, dark: true, landscape: true, kind: .pdf, pageAspect: 1.5)])
    #expect(try db.folders().map(\.name) == ["Uni"])
    try db.deleteFolder("f1")
    #expect(try db.notebooks().first?.folderId == nil)
  }

  @Test func itemsGoWithTheirNotebook() throws {
    let db = try NotesDb(path: ":memory:")
    try db.insert(NotebookMeta(id: "n1", title: "A", created: 1, updated: 1, cover: 0, paper: .DOTS))
    let row = ItemRow(id: "i1", z: 1, kind: 0, pen: "FINELINER", color: -16_777_216, size: 2, payload: Data([1, 2, 3]), l: 0, t: 0, r: 5, b: 5)
    try db.put(row, in: "n1")
    #expect(try db.items(of: "n1") == [row])
    try db.erase("n1")
    #expect(try db.items(of: "n1").isEmpty)
  }

  @Test func schemaVersionIsAndroids() throws {
    let db = try NotesDb(path: ":memory:")
    #expect(try db.scalarInt("PRAGMA user_version") == 8)
  }
}
