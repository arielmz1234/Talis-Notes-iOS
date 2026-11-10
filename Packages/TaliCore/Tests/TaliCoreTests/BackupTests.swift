import Foundation
import Testing
@testable import TaliCore

struct BackupTests {
  private func folders() -> BackupArchive.Folders {
    let base = FileManager.default.temporaryDirectory.appendingPathComponent("backup-test-\(UUID().uuidString)")
    let f = BackupArchive.Folders(
      images: base.appendingPathComponent("images"), thumbs: base.appendingPathComponent("thumbs"), audio: base.appendingPathComponent("audio"),
      work: base.appendingPathComponent("work"))
    for d in [f.images, f.thumbs, f.audio, f.work] { try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true) }
    return f
  }

  private func notebook(_ id: String, _ title: String, updated: Int64, folder: String? = nil) -> NotebookMeta {
    NotebookMeta(id: id, title: title, created: updated, updated: updated, cover: Covers.soft[0], paper: .GRID, folderId: folder)
  }

  private func row(_ id: String) -> ItemRow {
    ItemRow(id: id, z: 1, kind: 0, pen: "FINELINER", color: -1, size: 2.4, payload: InkCodecTests.androidStroke, l: 0, t: 0, r: 1, b: 1)
  }

  @Test func aBackupRestoresIntoAnotherDevice() throws {
    let here = folders()
    let db = try NotesDb(path: ":memory:")
    try db.insert(Folder(id: "f", name: "Statics", color: 1, position: 0))
    try db.insert(notebook("a", "Beams", updated: 10, folder: "f"))
    try db.put(row("i1"), in: "a")
    try Data([9, 9]).write(to: here.images.appendingPathComponent("pic.jpg"))
    try Data([7]).write(to: here.thumbs.appendingPathComponent("a.png"))
    let zip = try BackupArchive.write(db: db, settingsJSON: #"{"pens":[]}"#, folders: here, now: 123)

    let there = folders()
    let other = try NotesDb(path: ":memory:")
    let (result, settings) = try BackupArchive.restore(zip, into: other, folders: there)
    #expect(result.added == 1)
    #expect(settings == #"{"pens":[]}"#)
    #expect(try other.notebooks().map(\.title) == ["Beams"])
    #expect(try other.folders().map(\.name) == ["Statics"])
    #expect(try other.items(of: "a").first?.payload == InkCodecTests.androidStroke)
    #expect(FileManager.default.contents(atPath: there.images.appendingPathComponent("pic.jpg").path) == Data([9, 9]))
    #expect(FileManager.default.contents(atPath: there.thumbs.appendingPathComponent("a.png").path) == Data([7]))
  }

  @Test func mergingKeepsTheNewerCopyAndNeverDeletes() throws {
    let f = folders()
    let backup = try NotesDb(path: ":memory:")
    try backup.insert(notebook("a", "Old here, newer in backup", updated: 50))
    try backup.insert(notebook("b", "Newer here", updated: 5))
    let zip = try BackupArchive.write(db: backup, settingsJSON: nil, folders: f, now: 1)

    let db = try NotesDb(path: ":memory:")
    try db.insert(notebook("a", "Old here, newer in backup", updated: 10))
    try db.insert(notebook("b", "Newer here", updated: 99))
    try db.insert(notebook("c", "Only here", updated: 1))
    let (r, _) = try BackupArchive.restore(zip, into: db, folders: folders())
    #expect(r.updated == 1)
    #expect(r.kept == 1)
    #expect(r.changed == ["a"])
    let byId = Dictionary(uniqueKeysWithValues: try db.notebooks().map { ($0.id, $0) })
    #expect(byId["a"]?.updated == 50)
    #expect(byId["b"]?.updated == 99)
    #expect(byId["c"] != nil)
  }

  @Test func namesFromABackupAreKeptApart() throws {
    let f = folders()
    let backup = try NotesDb(path: ":memory:")
    try backup.insert(notebook("x", "Statics", updated: 5))
    let zip = try BackupArchive.write(db: backup, settingsJSON: nil, folders: f, now: 1)
    let db = try NotesDb(path: ":memory:")
    try db.insert(NotebookMeta(id: "y", title: "Statics", created: 1, updated: 1, cover: 0, paper: .DOTS))
    _ = try BackupArchive.restore(zip, into: db, folders: folders())
    #expect(Set(try db.notebooks().map(\.title)) == ["Statics", "Statics (1)"])
  }

  /// A backup from an Android version with schema 7 (no page_aspect column).
  @Test func anOlderSchemaRestores() throws {
    let f = folders()
    let path = f.work.appendingPathComponent("v7.db").path
    let old = try NotesDb(rawPath: path)
    try old.exec(
      "CREATE TABLE notebooks (id TEXT PRIMARY KEY, title TEXT NOT NULL, created INTEGER NOT NULL, updated INTEGER NOT NULL, cover INTEGER NOT NULL, paper TEXT NOT NULL, viewport TEXT, thumb INTEGER NOT NULL DEFAULT 0, folder_id TEXT, deleted INTEGER, pages INTEGER, dark INTEGER NOT NULL DEFAULT 0, landscape INTEGER NOT NULL DEFAULT 0, draft INTEGER NOT NULL DEFAULT 0, kind TEXT)"
    )
    try old.exec("CREATE TABLE folders (id TEXT PRIMARY KEY, name TEXT NOT NULL, color INTEGER NOT NULL, created INTEGER NOT NULL, position INTEGER NOT NULL, parent_id TEXT)")
    try old.exec(
      "CREATE TABLE items (id TEXT PRIMARY KEY, notebook_id TEXT NOT NULL, z INTEGER NOT NULL, kind INTEGER NOT NULL, pen TEXT, color INTEGER NOT NULL, size REAL NOT NULL, payload BLOB NOT NULL, l REAL NOT NULL, t REAL NOT NULL, r REAL NOT NULL, b REAL NOT NULL)"
    )
    try old.exec("INSERT INTO notebooks (id,title,created,updated,cover,paper,pages) VALUES ('n','History essay',1,2,-1729608,'LINES',1)")
    try old.exec("PRAGMA user_version = 7")
    var z = Zip.Writer()
    z.add("manifest.json", Data(#"{"format":1,"created":1791837393452,"notebooks":1}"#.utf8))
    z.add("notes.db", try old.copyBytes())
    let db = try NotesDb(path: ":memory:")
    let (r, _) = try BackupArchive.restore(z.finished(), into: db, folders: f)
    #expect(r.added == 1)
    let n = try db.notebooks().first
    #expect(n?.title == "History essay")
    #expect(n?.paper == .LINES)
    #expect(n?.pageAspect == nil)
    #expect(n?.cover == UInt32(bitPattern: -1_729_608))
  }

  @Test func refusesWhatIsntABackup() throws {
    var z = Zip.Writer()
    z.add("hello.txt", Data("hi".utf8))
    #expect(throws: BackupArchive.Failure.notABackup) { try BackupArchive.restore(z.finished(), into: try NotesDb(path: ":memory:"), folders: folders()) }
    var newer = Zip.Writer()
    newer.add("manifest.json", Data(#"{"format":2,"created":1,"notebooks":0}"#.utf8))
    #expect(throws: BackupArchive.Failure.tooNew) { try BackupArchive.restore(newer.finished(), into: try NotesDb(path: ":memory:"), folders: folders()) }
  }

  @Test func fileNameIsAndroids() {
    #expect(BackupArchive.fileName(Date(timeIntervalSince1970: 1_791_837_393)).hasPrefix("Tali's Notes backup 2026-"))
  }
}
