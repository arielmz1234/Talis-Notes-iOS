import Testing

@testable import TaliCore

struct SortTests {
  private func nb(_ id: String, _ title: String, _ created: Int64, _ updated: Int64) -> NotebookMeta {
    NotebookMeta(id: id, title: title, created: created, updated: updated, cover: 0, paper: .DOTS)
  }

  private var list: [NotebookMeta] { [nb("a", "Statics 10", 1, 30), nb("b", "statics 2", 3, 10), nb("c", "Hydraulics", 2, 20)] }

  private func ids(_ sort: LibrarySort, _ reversed: Bool, _ opened: [String] = []) -> [String] {
    LibraryOrder.sorted(list, by: sort, reversed: reversed, opened: opened).map(\.id)
  }

  @Test func byName() { #expect(ids(.NAME, false) == ["c", "b", "a"]) }
  @Test func byNameTurnedRound() { #expect(ids(.NAME, true) == ["a", "b", "c"]) }
  @Test func byEdited() { #expect(ids(.EDITED, false) == ["a", "c", "b"]) }
  @Test func byCreatedOldestFirst() { #expect(ids(.CREATED, true) == ["a", "c", "b"]) }
  @Test func byOpenedThenEdited() { #expect(ids(.OPENED, false, ["b"]) == ["b", "a", "c"]) }
}

struct FolderTreeTests {
  private func f(_ id: String, _ parent: String? = nil, _ position: Int = 0) -> Folder {
    Folder(id: id, name: id, color: 0, position: position, parentId: parent)
  }

  private let folders = [
    Folder(id: "civil", name: "Civil", color: 0, position: 0),
    Folder(id: "math", name: "Math", color: 0, position: 1),
    Folder(id: "statics", name: "Statics", color: 0, position: 2, parentId: "civil"),
    Folder(id: "beams", name: "Beams", color: 0, position: 3, parentId: "statics"),
    Folder(id: "fluids", name: "Fluids", color: 0, position: 4, parentId: "civil"),
  ]

  @Test func eachFolderIsFollowedByItsOwn() {
    let tree = FolderTree.ordered(folders)
    #expect(tree.map(\.folder.id) == ["civil", "statics", "beams", "fluids", "math"])
    #expect(tree.map(\.depth) == [0, 1, 2, 1, 0])
  }

  @Test func aFolderWhoseParentIsGoneSitsAtTheTop() {
    #expect(FolderTree.ordered([f("a", "gone"), f("b")]).map(\.folder.id) == ["a", "b"])
  }

  @Test func aLoopDoesNotHang() {
    #expect(FolderTree.ordered([f("a", "b"), f("b", "a")]).isEmpty)
    #expect(FolderTree.path(to: "a", in: [f("a", "b"), f("b", "a")]).map(\.id) == ["b", "a"])
  }

  @Test func descendantsAtAnyDepth() {
    #expect(FolderTree.descendants(of: "civil", in: folders) == ["statics", "beams", "fluids"])
    #expect(FolderTree.descendants(of: "beams", in: folders).isEmpty)
  }

  @Test func pathFromTheTopDown() {
    #expect(FolderTree.path(to: "beams", in: folders).map(\.id) == ["civil", "statics", "beams"])
    #expect(FolderTree.path(to: nil, in: folders).isEmpty)
  }

  @Test func aFolderCannotGoInsideItself() {
    #expect(!FolderTree.canMove("civil", into: "civil", in: folders))
    #expect(!FolderTree.canMove("civil", into: "beams", in: folders))
    #expect(FolderTree.canMove("beams", into: "math", in: folders))
    #expect(FolderTree.canMove("beams", into: nil, in: folders))
  }
}

struct NamesApartTests {
  @Test func theOlderKeepsThePlainName() {
    let renamed = Names.apart([(id: "1", name: "Lab", place: nil), (id: "2", name: "lab ", place: nil), (id: "3", name: "Lab", place: "civil")])
    #expect(renamed.map(\.id) == ["2"])
    #expect(renamed.map(\.name) == ["lab (1)"])
  }

  @Test func eachClashGetsTheNextNumber() {
    let renamed = Names.apart([(id: "1", name: "Notes", place: "x"), (id: "2", name: "Notes", place: "x"), (id: "3", name: "Notes", place: "x")])
    #expect(renamed.map(\.name) == ["Notes (1)", "Notes (2)"])
  }
}
