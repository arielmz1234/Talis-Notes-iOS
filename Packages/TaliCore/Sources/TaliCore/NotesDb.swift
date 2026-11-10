import Foundation
import SQLite3

/// Plain SQLite with exactly the Android app's schema (`data/NotesDb.kt`, VERSION 8), so a backup's
/// database file opens on either platform. `PRAGMA user_version` holds the version, as Android's
/// SQLiteOpenHelper does.
public final class NotesDb: @unchecked Sendable {
  public static let version: Int32 = 8
  private var db: OpaquePointer?
  /// Every statement runs on this queue, one at a time, so writes land in order.
  private let queue = DispatchQueue(label: "notes.db")

  public enum DbError: Error { case open(String), sql(String) }

  /// Opens (or creates) the database at [path]; ":memory:" for tests.
  public init(path: String) throws {
    var handle: OpaquePointer?
    if sqlite3_open_v2(path, &handle, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX, nil) != SQLITE_OK {
      throw DbError.open(String(cString: sqlite3_errmsg(handle)))
    }
    db = handle
    try exec("PRAGMA journal_mode=WAL")
    try exec("PRAGMA foreign_keys=ON")
    try migrate()
  }

  deinit { sqlite3_close(db) }

  private func migrate() throws {
    let v = Int32(try scalarInt("PRAGMA user_version") ?? 0)
    if v == 0 {
      try exec(
        """
        CREATE TABLE notebooks (
          id TEXT PRIMARY KEY, title TEXT NOT NULL, created INTEGER NOT NULL, updated INTEGER NOT NULL,
          cover INTEGER NOT NULL, paper TEXT NOT NULL, viewport TEXT, thumb INTEGER NOT NULL DEFAULT 0,
          folder_id TEXT, deleted INTEGER, pages INTEGER, dark INTEGER NOT NULL DEFAULT 0,
          landscape INTEGER NOT NULL DEFAULT 0, draft INTEGER NOT NULL DEFAULT 0, kind TEXT, page_aspect REAL
        )
        """)
      try exec("CREATE TABLE folders (id TEXT PRIMARY KEY, name TEXT NOT NULL, color INTEGER NOT NULL, created INTEGER NOT NULL, position INTEGER NOT NULL, parent_id TEXT)")
      try exec(
        """
        CREATE TABLE items (
          id TEXT PRIMARY KEY, notebook_id TEXT NOT NULL REFERENCES notebooks(id) ON DELETE CASCADE,
          z INTEGER NOT NULL, kind INTEGER NOT NULL, pen TEXT, color INTEGER NOT NULL, size REAL NOT NULL,
          payload BLOB NOT NULL, l REAL NOT NULL, t REAL NOT NULL, r REAL NOT NULL, b REAL NOT NULL
        )
        """)
      try exec("CREATE INDEX items_by_notebook ON items(notebook_id, z)")
    } else {
      // Databases written by older Android versions (from a backup).
      if v < 2 {
        try exec("ALTER TABLE notebooks ADD COLUMN folder_id TEXT")
        try exec("CREATE TABLE folders (id TEXT PRIMARY KEY, name TEXT NOT NULL, color INTEGER NOT NULL, created INTEGER NOT NULL, position INTEGER NOT NULL, parent_id TEXT)")
      }
      if v < 3 { try exec("ALTER TABLE notebooks ADD COLUMN deleted INTEGER") }
      if v < 4 {
        try exec("ALTER TABLE notebooks ADD COLUMN pages INTEGER")
        try exec("ALTER TABLE notebooks ADD COLUMN dark INTEGER NOT NULL DEFAULT 0")
        if v >= 2 { try exec("ALTER TABLE folders ADD COLUMN parent_id TEXT") }
      }
      if v < 5 { try exec("ALTER TABLE notebooks ADD COLUMN landscape INTEGER NOT NULL DEFAULT 0") }
      if v < 6 { try exec("ALTER TABLE notebooks ADD COLUMN draft INTEGER NOT NULL DEFAULT 0") }
      if v < 7 { try exec("ALTER TABLE notebooks ADD COLUMN kind TEXT") }
      if v < 8 { try exec("ALTER TABLE notebooks ADD COLUMN page_aspect REAL") }
    }
    try exec("PRAGMA user_version = \(NotesDb.version)")
  }

  // MARK: Notebooks

  static let customPrefix = "custom:"
  private static let notebookColumns = "id, title, created, updated, cover, paper, viewport, thumb, folder_id, deleted, pages, dark, landscape, draft, kind, page_aspect"

  public func notebooks(where clause: String = "1", _ args: [Value] = []) throws -> [NotebookMeta] {
    try query("SELECT \(NotesDb.notebookColumns) FROM notebooks WHERE \(clause) ORDER BY updated DESC", args) { r in
      let paperText = r.text(5) ?? ""
      let custom = paperText.hasPrefix(NotesDb.customPrefix) ? String(paperText.dropFirst(NotesDb.customPrefix.count)) : nil
      let paper = custom != nil ? PaperStyle.BLANK : (PaperStyle(rawValue: paperText) ?? .DOTS)
      let viewport = r.text(6).flatMap { try? JSONDecoder().decode(Viewport.self, from: Data($0.utf8)) }
      return NotebookMeta(
        id: r.text(0) ?? "", title: r.text(1) ?? "", created: r.int(2), updated: r.int(3), cover: UInt32(truncatingIfNeeded: r.int(4)),
        paper: paper, customPaper: custom, viewport: viewport, thumbVersion: r.int(7), folderId: r.text(8),
        deleted: r.isNull(9) ? nil : r.int(9), pages: r.isNull(10) ? nil : Int(r.int(10)), dark: r.int(11) != 0,
        landscape: r.int(12) != 0, draft: r.int(13) != 0, kind: DocKind.of(r.text(14)), pageAspect: r.isNull(15) ? nil : Float(r.double(15)))
    }
  }

  public func insert(_ n: NotebookMeta) throws {
    let paper = n.customPaper.map { NotesDb.customPrefix + $0 } ?? n.paper.rawValue
    let viewport = n.viewport.flatMap { try? String(data: JSONEncoder().encode($0), encoding: .utf8) }
    try run(
      "INSERT OR REPLACE INTO notebooks (\(NotesDb.notebookColumns)) VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)",
      [
        .text(n.id), .text(n.title), .int(n.created), .int(n.updated), .int(Int64(Int32(bitPattern: n.cover))), .text(paper),
        viewport.map(Value.text) ?? .null, .int(n.thumbVersion), n.folderId.map(Value.text) ?? .null, n.deleted.map(Value.int) ?? .null,
        n.pages.map { .int(Int64($0)) } ?? .null, .int(n.dark ? 1 : 0), .int(n.landscape ? 1 : 0), .int(n.draft ? 1 : 0),
        n.kind.stored.map(Value.text) ?? .null, n.pageAspect.map { .double(Double($0)) } ?? .null,
      ])
  }

  public func setTitle(_ id: String, _ title: String, at now: Int64) throws {
    try run("UPDATE notebooks SET title=?, updated=? WHERE id=?", [.text(title), .int(now), .text(id)])
  }

  public func setDeleted(_ id: String, _ when: Int64?) throws {
    try run("UPDATE notebooks SET deleted=? WHERE id=?", [when.map(Value.int) ?? .null, .text(id)])
  }

  public func setFolder(_ id: String, _ folder: String?) throws {
    try run("UPDATE notebooks SET folder_id=? WHERE id=?", [folder.map(Value.text) ?? .null, .text(id)])
  }

  public func erase(_ id: String) throws { try run("DELETE FROM notebooks WHERE id=?", [.text(id)]) }

  // MARK: Folders

  public func folders() throws -> [Folder] {
    try query("SELECT id, name, color, position, parent_id, created FROM folders ORDER BY position", []) { r in
      Folder(id: r.text(0) ?? "", name: r.text(1) ?? "", color: UInt32(truncatingIfNeeded: r.int(2)), position: Int(r.int(3)), parentId: r.text(4), created: r.int(5))
    }
  }

  public func insert(_ f: Folder) throws {
    try run(
      "INSERT OR REPLACE INTO folders (id, name, color, created, position, parent_id) VALUES (?,?,?,?,?,?)",
      [.text(f.id), .text(f.name), .int(Int64(Int32(bitPattern: f.color))), .int(f.created), .int(Int64(f.position)), f.parentId.map(Value.text) ?? .null])
  }

  public func deleteFolder(_ id: String) throws {
    try run("UPDATE notebooks SET folder_id=NULL WHERE folder_id=?", [.text(id)])
    try run("UPDATE folders SET parent_id=NULL WHERE parent_id=?", [.text(id)])
    try run("DELETE FROM folders WHERE id=?", [.text(id)])
  }

  // MARK: Items

  public func items(of notebook: String) throws -> [ItemRow] {
    try query("SELECT id, z, kind, pen, color, size, payload, l, t, r, b FROM items WHERE notebook_id=? ORDER BY z", [.text(notebook)]) { r in
      ItemRow(
        id: r.text(0) ?? "", z: r.int(1), kind: Int(r.int(2)), pen: r.text(3), color: Int32(truncatingIfNeeded: r.int(4)), size: Float(r.double(5)),
        payload: r.blob(6), l: Float(r.double(7)), t: Float(r.double(8)), r: Float(r.double(9)), b: Float(r.double(10)))
    }
  }

  public func put(_ row: ItemRow, in notebook: String) throws {
    try run(
      "INSERT OR REPLACE INTO items (id, notebook_id, z, kind, pen, color, size, payload, l, t, r, b) VALUES (?,?,?,?,?,?,?,?,?,?,?,?)",
      [
        .text(row.id), .text(notebook), .int(row.z), .int(Int64(row.kind)), row.pen.map(Value.text) ?? .null, .int(Int64(row.color)),
        .double(Double(row.size)), .blob(row.payload), .double(Double(row.l)), .double(Double(row.t)), .double(Double(row.r)), .double(Double(row.b)),
      ])
  }

  public func removeItem(_ id: String) throws { try run("DELETE FROM items WHERE id=?", [.text(id)]) }

  // MARK: Plumbing

  public enum Value: Sendable {
    case null, int(Int64), double(Double), text(String), blob(Data)
  }

  public struct Row {
    let stmt: OpaquePointer
    func isNull(_ i: Int32) -> Bool { sqlite3_column_type(stmt, i) == SQLITE_NULL }
    func int(_ i: Int32) -> Int64 { sqlite3_column_int64(stmt, i) }
    func double(_ i: Int32) -> Double { sqlite3_column_double(stmt, i) }
    func text(_ i: Int32) -> String? { sqlite3_column_text(stmt, i).map { String(cString: $0) } }
    func blob(_ i: Int32) -> Data {
      guard let p = sqlite3_column_blob(stmt, i) else { return Data() }
      return Data(bytes: p, count: Int(sqlite3_column_bytes(stmt, i)))
    }
  }

  nonisolated(unsafe) private static let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

  public func exec(_ sql: String) throws {
    try queue.sync {
      if sqlite3_exec(db, sql, nil, nil, nil) != SQLITE_OK { throw DbError.sql(String(cString: sqlite3_errmsg(db))) }
    }
  }

  public func run(_ sql: String, _ args: [Value]) throws {
    _ = try query(sql, args) { _ in () }
  }

  public func scalarInt(_ sql: String, _ args: [Value] = []) throws -> Int64? {
    try query(sql, args) { $0.int(0) }.first
  }

  public func query<T>(_ sql: String, _ args: [Value], _ map: (Row) throws -> T) throws -> [T] {
    try queue.sync {
      var stmt: OpaquePointer?
      guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK, let stmt else { throw DbError.sql(String(cString: sqlite3_errmsg(db))) }
      defer { sqlite3_finalize(stmt) }
      for (i, a) in args.enumerated() {
        let n = Int32(i + 1)
        switch a {
        case .null: sqlite3_bind_null(stmt, n)
        case .int(let v): sqlite3_bind_int64(stmt, n, v)
        case .double(let v): sqlite3_bind_double(stmt, n, v)
        case .text(let v): sqlite3_bind_text(stmt, n, v, -1, NotesDb.transient)
        case .blob(let v): _ = v.withUnsafeBytes { sqlite3_bind_blob(stmt, n, $0.baseAddress, Int32(v.count), NotesDb.transient) }
        }
      }
      var out: [T] = []
      while true {
        let rc = sqlite3_step(stmt)
        if rc == SQLITE_ROW {
          out.append(try map(Row(stmt: stmt)))
        } else if rc == SQLITE_DONE {
          break
        } else {
          throw DbError.sql(String(cString: sqlite3_errmsg(db)))
        }
      }
      return out
    }
  }
}

/// A stored item row, as on Android (`ItemRow`): the backup carries these as they are.
public struct ItemRow: Hashable, Sendable {
  public var id: String
  public var z: Int64
  public var kind: Int
  public var pen: String?
  public var color: Int32
  public var size: Float
  public var payload: Data
  public var l: Float, t: Float, r: Float, b: Float

  public init(id: String, z: Int64, kind: Int, pen: String?, color: Int32, size: Float, payload: Data, l: Float, t: Float, r: Float, b: Float) {
    self.id = id
    self.z = z
    self.kind = kind
    self.pen = pen
    self.color = color
    self.size = size
    self.payload = payload
    self.l = l
    self.t = t
    self.r = r
    self.b = b
  }
}
