import Foundation
import Observation
import UIKit
import TaliCore

/// What the library shows on the left: every notebook, starred ones, Recently deleted, or a folder.
enum Shelf: Hashable {
  case all, starred, trash
  case folder(String)
}

/// The library's state: notebooks and folders from the database, kept in step after every change.
@MainActor @Observable
final class Library {
  let db: NotesDb
  private(set) var notebooks: [NotebookMeta] = []
  private(set) var trash: [NotebookMeta] = []
  private(set) var folders: [Folder] = []
  var shelf: Shelf = .all
  var search = ""
  var sort: LibrarySort {
    didSet { UserDefaults.standard.set(sort.rawValue, forKey: "librarySort") }
  }
  var sortReversed: Bool {
    didSet { UserDefaults.standard.set(sortReversed, forKey: "librarySortReversed") }
  }
  var starred: Set<String> {
    didSet { UserDefaults.standard.set(Array(starred), forKey: "starredNotebooks") }
  }
  var opened: [String] {
    didSet { UserDefaults.standard.set(opened, forKey: "recentNotebooks") }
  }

  init(db: NotesDb) {
    self.db = db
    let d = UserDefaults.standard
    sort = LibrarySort(rawValue: d.string(forKey: "librarySort") ?? "") ?? .EDITED
    sortReversed = d.bool(forKey: "librarySortReversed")
    starred = Set(d.stringArray(forKey: "starredNotebooks") ?? [])
    opened = d.stringArray(forKey: "recentNotebooks") ?? []
    reload()
    separateNames()
    sweepTrash()
  }

  /// Opens the app's database (a fresh one for UI tests).
  static func open() -> Library {
    let fm = FileManager.default
    let path: String
    if ProcessInfo.processInfo.arguments.contains("-uitest") {
      path = fm.temporaryDirectory.appendingPathComponent("uitest-\(UUID().uuidString).db").path
    } else {
      let dir = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
      try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
      path = dir.appendingPathComponent("notes.db").path
    }
    // swiftlint:disable:next force_try
    let lib = Library(db: try! NotesDb(path: path))
    if ProcessInfo.processInfo.arguments.contains("-seed") { lib.seed() }
    return lib
  }

  func reload() {
    let all = (try? db.notebooks()) ?? []
    notebooks = all.filter { $0.deleted == nil && !$0.draft }
    trash = all.filter { $0.deleted != nil }.sorted { ($0.deleted ?? 0) > ($1.deleted ?? 0) }
    folders = (try? db.folders()) ?? []
    if shelf == .trash && trash.isEmpty { shelf = .all }
  }

  /// What the main area shows for the current shelf, search and sort.
  var shown: [NotebookMeta] {
    let base: [NotebookMeta]
    switch shelf {
    case .all: base = notebooks
    case .starred: base = notebooks.filter { starred.contains($0.id) }
    case .trash: return filtered(trash)
    case .folder(let id): base = notebooks.filter { $0.folderId == id }
    }
    return LibraryOrder.sorted(filtered(base), by: sort, reversed: sortReversed, opened: opened)
  }

  private func filtered(_ list: [NotebookMeta]) -> [NotebookMeta] {
    let q = search.trimmingCharacters(in: .whitespaces)
    return q.isEmpty ? list : list.filter { $0.title.localizedCaseInsensitiveContains(q) }
  }

  /// Folders inside the open folder (at the top level, folders are only in the sidebar, as on Android).
  var subfoldersOfOpenFolder: [Folder] {
    if case .folder(let id) = shelf { return folders.filter { $0.parentId == id } }
    return []
  }

  func folder(_ id: String?) -> Folder? { folders.first { $0.id == id } }

  /// The folder being looked at, if any.
  var openFolder: Folder? {
    if case .folder(let id) = shelf { return folder(id) }
    return nil
  }

  /// Notebooks in [folder], and with [deep] in the folders inside it too (the sidebar's count).
  func count(in folder: String, deep: Bool = false) -> Int {
    let inside = deep ? FolderTree.descendants(of: folder, in: folders) : []
    return notebooks.filter { $0.folderId == folder || $0.folderId.map(inside.contains) == true }.count
  }

  /// What a new notebook is called when she leaves the name empty: "New notebook", or the next
  /// free one among the notebooks in the folder it goes into.
  var freeNotebookName: String { Names.numbered(English.newNotebook, taken: takenTitles(in: openFolder?.id)) }

  /// The same for a new folder, among the folders beside it.
  func freeFolderName(in parent: String?) -> String {
    Names.numbered(English.newFolder, taken: folders.filter { $0.parentId == parent }.map(\.name))
  }

  /// The cover the next notebook gets unless she picks another.
  var nextCover: UInt32 { Covers.soft[notebooks.count % Covers.soft.count] }

  /// The colour a new folder in [parent] starts with: its parent's, or the next cover colour.
  func nextFolderColor(in parent: String?) -> UInt32 {
    folder(parent)?.color ?? Covers.soft[folders.count % Covers.soft.count]
  }

  /// Names already used beside a notebook going into [folder] (names are kept apart per place).
  private func takenTitles(in folder: String?, except id: String? = nil) -> [String] {
    notebooks.filter { $0.folderId == folder && $0.id != id }.map(\.title)
  }

  @discardableResult
  func create(title: String, paper: PaperChoice, pages: Bool, landscape: Bool, dark: Bool = false, cover: UInt32) -> NotebookMeta {
    let folder: String? = if case .folder(let id) = shelf { id } else { nil }
    let name = Names.numbered(title.isEmpty ? English.newNotebook : title, taken: takenTitles(in: folder))
    let now = nowMillis()
    let n = NotebookMeta(
      id: newId(), title: name, created: now, updated: now, cover: cover, paper: paper.style, customPaper: paper.customId, folderId: folder, pages: pages ? 1 : nil,
      dark: dark, landscape: pages && landscape)
    try? db.insert(n)
    if shelf == .starred { starred.insert(n.id) }
    reload()
    return n
  }

  func rename(_ id: String, to title: String) {
    guard let n = notebooks.first(where: { $0.id == id }) else { return }
    let name = Names.numbered(title.isEmpty ? English.untitled : title, taken: takenTitles(in: n.folderId, except: id))
    try? db.setTitle(id, name, at: nowMillis())
    reload()
  }

  func duplicate(_ id: String) {
    guard var n = notebooks.first(where: { $0.id == id }) else { return }
    let rows = (try? db.items(of: id)) ?? []
    n.id = newId()
    n.title = Names.numbered(n.title, taken: takenTitles(in: n.folderId))
    n.created = nowMillis()
    n.updated = n.created
    try? db.insert(n)
    for var r in rows {
      r.id = newId()
      try? db.put(r, in: n.id)
    }
    reload()
  }

  func moveToTrash(_ id: String) {
    try? db.setDeleted(id, nowMillis())
    reload()
  }

  func restore(_ id: String) {
    guard let n = trash.first(where: { $0.id == id }) else { return }
    try? db.setDeleted(id, nil)
    // Back from Recently deleted, a name already taken meanwhile gets a number.
    let name = Names.numbered(n.title, taken: takenTitles(in: n.folderId, except: id))
    if name != n.title { try? db.setTitle(id, name, at: n.updated) }
    reload()
  }

  func eraseForGood(_ id: String) {
    try? db.erase(id)
    starred.remove(id)
    reload()
  }

  func emptyTrash() {
    shelf = .all
    for n in trash { try? db.erase(n.id) }
    reload()
  }

  func move(_ id: String, to folder: String?) {
    guard let n = notebooks.first(where: { $0.id == id }) else { return }
    try? db.setFolder(id, folder)
    let name = Names.numbered(n.title, taken: takenTitles(in: folder, except: id))
    if name != n.title { try? db.setTitle(id, name, at: n.updated) }
    reload()
  }

  func setCover(_ id: String, _ color: UInt32) {
    try? db.setCover(id, color, at: nowMillis())
    reload()
  }

  func toggleStar(_ id: String) {
    if starred.contains(id) { starred.remove(id) } else { starred.insert(id) }
  }

  /// Makes a folder inside [parent] (or at the top level). A top-level folder opens straight away;
  /// one made inside a folder appears among that folder's folders, so she can make several.
  @discardableResult
  func createFolder(name: String, color: UInt32, parent: String?) -> Folder {
    let f = Folder(
      id: newId(), name: Names.numbered(name.isEmpty ? freeFolderName(in: parent) : name, taken: siblingNames(in: parent)), color: color,
      position: (folders.map(\.position).max() ?? -1) + 1, parentId: parent, created: nowMillis())
    try? db.insert(f)
    reload()
    if parent == nil { shelf = .folder(f.id) }
    return f
  }

  private func siblingNames(in parent: String?, except id: String? = nil) -> [String] {
    folders.filter { $0.parentId == parent && $0.id != id }.map(\.name)
  }

  func renameFolder(_ id: String, to name: String) {
    guard var f = folder(id) else { return }
    f.name = Names.numbered(name.trimmingCharacters(in: .whitespaces).isEmpty ? L("folder") : name, taken: siblingNames(in: f.parentId, except: id))
    try? db.insert(f)
    reload()
  }

  func recolorFolder(_ id: String, _ color: UInt32) {
    guard var f = folder(id) else { return }
    f.color = color
    try? db.insert(f)
    reload()
  }

  /// Moves a folder into [parent], or to the top level; never inside itself or its own folders.
  func moveFolder(_ id: String, to parent: String?) {
    guard var f = folder(id), FolderTree.canMove(id, into: parent, in: folders) else { return }
    f.parentId = parent
    f.name = Names.numbered(f.name, taken: siblingNames(in: parent, except: id))
    try? db.insert(f)
    reload()
  }

  func deleteFolder(_ id: String) {
    // Nothing inside is deleted: its notebooks and folders move up a level, as on Android.
    let parent = folder(id)?.parentId
    for n in notebooks + trash where n.folderId == id { try? db.setFolder(n.id, parent) }
    for var f in folders where f.parentId == id {
      f.parentId = parent
      try? db.insert(f)
    }
    try? db.deleteFolder(id)
    if shelf == .folder(id) { shelf = parent.map(Shelf.folder) ?? .all }
    reload()
    // What moved up may share a name with what was already there.
    separateNames()
  }

  /// Numbers any notebooks and folders that share a name with an older one in the same place (at
  /// start-up and after a folder is deleted). The older one keeps the plain name.
  private func separateNames() {
    let byAge: (Int64, String, Int64, String) -> Bool = { a, ida, b, idb in a != b ? a < b : ida < idb }
    let books = notebooks.sorted { byAge($0.created, $0.id, $1.created, $1.id) }
    let changed = Names.apart(books.map { (id: $0.id, name: $0.title, place: $0.folderId) })
    for (id, name) in changed {
      if let n = notebooks.first(where: { $0.id == id }) { try? db.setTitle(id, name, at: n.updated) }
    }
    let shelves = folders.sorted { byAge($0.created, $0.id, $1.created, $1.id) }
    let renamed = Names.apart(shelves.map { (id: $0.id, name: $0.name, place: $0.parentId) })
    for (id, name) in renamed {
      guard var f = folder(id) else { continue }
      f.name = name
      try? db.insert(f)
    }
    if !changed.isEmpty || !renamed.isEmpty { reload() }
  }

  func noteOpened(_ id: String) {
    opened = [id] + opened.filter { $0 != id }.prefix(79)
  }

  /// Notebooks wait in Recently deleted for 30 days.
  private func sweepTrash() {
    let cutoff = nowMillis() - Int64(trashDays) * 24 * 3600 * 1000
    for n in trash where (n.deleted ?? 0) < cutoff { try? db.erase(n.id) }
    reload()
  }

  /// Sample notebooks for screenshots.
  private func seed() {
    let uni = createFolder(name: "Statics", color: Covers.soft[1], parent: nil)
    _ = createFolder(name: "Calculus", color: Covers.soft[4], parent: nil)
    let titles = ["Beam deflection", "Week 3 lecture", "Truss problems", "Lab report", "Fluid mechanics", "Exam revision"]
    for (i, t) in titles.enumerated() {
      shelf = i < 2 ? .folder(uni.id) : .all
      let n = create(title: t, paper: .style([.GRID, .LINES, .ENGINEERING, .DOTS][i % 4]), pages: true, landscape: i == 3, cover: Covers.soft[i % Covers.soft.count])
      if i == 0 { starred.insert(n.id) }
    }
    shelf = .all
    // A PDF of two slides, imported as she would from her files (shows the PDF item and its badge).
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("Lecture slides.pdf")
    let slide = CGRect(x: 0, y: 0, width: 960, height: 540)
    let data = UIGraphicsPDFRenderer(bounds: slide).pdfData { ctx in
      for i in 1...2 {
        ctx.beginPage()
        UIColor(red: 0.93, green: 0.95, blue: 1, alpha: 1).setFill()
        ctx.fill(CGRect(x: 0, y: 0, width: 960, height: 120))
        ("Moment of inertia, part \(i)" as NSString).draw(
          at: CGPoint(x: 48, y: 40), withAttributes: [.font: UIFont.boldSystemFont(ofSize: 40), .foregroundColor: UIColor.darkGray])
        UIColor.systemBlue.setStroke()
        let beam = UIBezierPath(rect: CGRect(x: 120, y: 260, width: 720, height: 60))
        beam.lineWidth = 4
        beam.stroke()
      }
    }
    try? data.write(to: url)
    Task { try? await self.importPDF(url) }
  }
}
