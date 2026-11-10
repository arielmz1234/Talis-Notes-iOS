import Foundation

/// What a merge brought in.
public struct MergeResult: Sendable, Equatable {
  public var added = 0
  public var updated = 0
  public var kept = 0
  /// Notebooks that came from the backup (added or newer there).
  public var changed: Set<String> = []
  public init() {}
}

extension NotesDb {
  /// Merges the notebooks database at [path] into this one, as Android's `mergeFrom`: folders are
  /// added if new; a notebook is added if new here or replaces this one if the backup's copy was
  /// edited later; nothing here is deleted or overwritten with an older copy. Backups from older
  /// schemas work (missing columns get their defaults).
  public func merge(from path: String) throws -> MergeResult {
    try exec("ATTACH DATABASE '\(path.replacingOccurrences(of: "'", with: "''"))' AS bk")
    defer { try? exec("DETACH DATABASE bk") }
    let nbCols = Set(try query("PRAGMA bk.table_info(notebooks)", []) { $0.text(1) ?? "" })
    let folderCols = Set(try query("PRAGMA bk.table_info(folders)", []) { $0.text(1) ?? "" })
    func col(_ name: String, _ fallback: String) -> String { nbCols.contains(name) ? name : fallback }
    var result = MergeResult()
    try exec("BEGIN")
    do {
      if !folderCols.isEmpty {
        let parent = folderCols.contains("parent_id") ? "parent_id" : "NULL"
        try exec("INSERT OR IGNORE INTO folders (id,name,color,created,position,parent_id) SELECT id,name,color,created,position,\(parent) FROM bk.folders")
      }
      let notDraft = nbCols.contains("draft") ? " AND b.draft = 0" : ""
      let incoming = try query(
        "SELECT b.id, m.id IS NOT NULL, b.updated > IFNULL(m.updated, 0) FROM bk.notebooks b LEFT JOIN main.notebooks m ON m.id = b.id WHERE b.deleted IS NULL\(notDraft)",
        []
      ) { r in (r.text(0) ?? "", r.int(1) == 1, r.int(2) == 1) }
      var bring: [(String, Bool)] = []
      for (id, exists, newer) in incoming {
        if !exists {
          bring.append((id, false))
          result.added += 1
        } else if newer {
          bring.append((id, true))
          result.updated += 1
        } else {
          result.kept += 1
        }
      }
      for (id, exists) in bring {
        if exists {
          try run("DELETE FROM main.items WHERE notebook_id = ?", [.text(id)])
          try run("DELETE FROM main.notebooks WHERE id = ?", [.text(id)])
        }
        let folder = col("folder_id", "NULL")
        try run(
          """
          INSERT INTO main.notebooks (id,title,created,updated,cover,paper,viewport,thumb,folder_id,deleted,pages,dark,landscape,kind,page_aspect)
          SELECT id,title,created,updated,cover,paper,viewport,thumb+1,\(folder),NULL,\(col("pages", "NULL")),\(col("dark", "0")),\(col("landscape", "0")),\(col("kind", "NULL")),\(col("page_aspect", "NULL"))
          FROM bk.notebooks WHERE id = ?
          """, [.text(id)])
        try run(
          "INSERT OR REPLACE INTO main.items (id,notebook_id,z,kind,pen,color,size,payload,l,t,r,b) SELECT id,notebook_id,z,kind,pen,color,size,payload,l,t,r,b FROM bk.items WHERE notebook_id = ?",
          [.text(id)])
        result.changed.insert(id)
      }
      try exec("COMMIT")
    } catch {
      try? exec("ROLLBACK")
      throw error
    }
    try separateNames()
    return result
  }

  /// No two notebooks in one place share a name, nor two folders side by side (the older keeps the plain name).
  public func separateNames() throws {
    let notebooks = try query("SELECT id, title, IFNULL(folder_id, '') FROM notebooks WHERE deleted IS NULL AND draft = 0 ORDER BY created, id", []) {
      ($0.text(0) ?? "", $0.text(1) ?? "", $0.text(2) ?? "")
    }
    for (_, group) in Dictionary(grouping: notebooks, by: \.2) {
      var seen: [String] = []
      for (id, title, _) in group {
        let name = Names.numbered(title, taken: seen)
        if name != title { try run("UPDATE notebooks SET title=? WHERE id=?", [.text(name), .text(id)]) }
        seen.append(name)
      }
    }
    let folders = try query("SELECT id, name, IFNULL(parent_id, '') FROM folders ORDER BY created, id", []) {
      ($0.text(0) ?? "", $0.text(1) ?? "", $0.text(2) ?? "")
    }
    for (_, group) in Dictionary(grouping: folders, by: \.2) {
      var seen: [String] = []
      for (id, name0, _) in group {
        let name = Names.numbered(name0, taken: seen)
        if name != name0 { try run("UPDATE folders SET name=? WHERE id=?", [.text(name), .text(id)]) }
        seen.append(name)
      }
    }
  }

  /// A consistent copy of the whole database at [path] (for a backup).
  public func snapshot(to path: String) throws {
    try? FileManager.default.removeItem(atPath: path)
    try run("VACUUM INTO ?", [.text(path)])
  }
}

/// The backup .zip, the same as Android's `BackupArchive`: manifest.json, notes.db, settings.json,
/// and images/, thumbs/, audio/ folders.
public enum BackupArchive {
  public static let format = 1

  public enum Failure: Error, Equatable {
    /// Not a backup (no manifest or database).
    case notABackup
    /// Made by a newer version of the app.
    case tooNew
  }

  /// Where the app keeps its files.
  public struct Folders: Sendable {
    public var images: URL
    public var thumbs: URL
    public var audio: URL
    public var work: URL
    public init(images: URL, thumbs: URL, audio: URL, work: URL) {
      self.images = images
      self.thumbs = thumbs
      self.audio = audio
      self.work = work
    }
  }

  public static func fileName(_ now: Date = Date()) -> String {
    let f = DateFormatter()
    f.locale = Locale(identifier: "en_US_POSIX")
    f.dateFormat = "yyyy-MM-dd"
    return "Tali's Notes backup \(f.string(from: now)).zip"
  }

  static func manifest(notebooks: Int, now: Int64) -> Data {
    Data(#"{"format":\#(format),"created":\#(now),"notebooks":\#(notebooks),"app":"Tali's Notes"}"#.utf8)
  }

  /// A complete backup: every notebook, picture, preview and recording, and [settingsJSON].
  public static func write(db: NotesDb, settingsJSON: String?, folders: Folders, now: Int64) throws -> Data {
    let fm = FileManager.default
    try fm.createDirectory(at: folders.work, withIntermediateDirectories: true)
    let snap = folders.work.appendingPathComponent("backup-snapshot.db")
    try db.snapshot(to: snap.path)
    defer { try? fm.removeItem(at: snap) }
    let count = try db.scalarInt("SELECT COUNT(*) FROM notebooks WHERE deleted IS NULL AND draft = 0") ?? 0
    var z = Zip.Writer()
    z.add("manifest.json", manifest(notebooks: Int(count), now: now))
    z.add("notes.db", try Data(contentsOf: snap))
    if let s = settingsJSON { z.add("settings.json", Data(s.utf8)) }
    for (prefix, dir) in [("images/", folders.images), ("thumbs/", folders.thumbs), ("audio/", folders.audio)] {
      let names = (try? fm.contentsOfDirectory(atPath: dir.path)) ?? []
      for n in names.sorted() where !n.hasPrefix(".") {
        let url = dir.appendingPathComponent(n)
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: url.path, isDirectory: &isDir), !isDir.boolValue, let d = try? Data(contentsOf: url) else { continue }
        // Pictures and recordings are already compressed.
        z.add(prefix + n, d, deflate: prefix == "thumbs/" ? false : !(n.hasSuffix(".jpg") || n.hasSuffix(".m4a")))
      }
    }
    return z.finished()
  }

  /// Restores [zip] by merging into [db]. Returns the merge and the backup's settings.json, if any.
  public static func restore(_ zip: Data, into db: NotesDb, folders: Folders) throws -> (MergeResult, String?) {
    let fm = FileManager.default
    let z: Zip.Reader
    do { z = try Zip.Reader(zip) } catch { throw Failure.notABackup }
    guard let m = try? z.read("manifest.json"), let obj = try? JSONSerialization.jsonObject(with: m) as? [String: Any] else { throw Failure.notABackup }
    if let f = obj["format"] as? Int, f > format { throw Failure.tooNew }
    guard let dbData = try? z.read("notes.db") else { throw Failure.notABackup }
    let work = folders.work.appendingPathComponent("restore-\(UUID().uuidString)")
    try fm.createDirectory(at: work, withIntermediateDirectories: true)
    defer { try? fm.removeItem(at: work) }
    for dir in [folders.images, folders.thumbs, folders.audio] { try fm.createDirectory(at: dir, withIntermediateDirectories: true) }
    let dbURL = work.appendingPathComponent("notes.db")
    try dbData.write(to: dbURL)
    // Bring an older backup's tables up to date first (a newer schema can't be read).
    do {
      let old = try NotesDb(path: dbURL.path)
      if (try old.scalarInt("PRAGMA user_version") ?? 0) > Int64(NotesDb.version) { throw Failure.tooNew }
    } catch let e as Failure {
      throw e
    } catch {
      throw Failure.notABackup
    }
    var thumbs: [String: Zip.Entry] = [:]
    for e in z.entries where !e.isDirectory {
      // Only ever write plain file names into our own folders.
      let base = (e.name as NSString).lastPathComponent
      if base.isEmpty || base.hasPrefix(".") || e.name.contains("..") { continue }
      if e.name.hasPrefix("images/") || e.name.hasPrefix("audio/") {
        let target = (e.name.hasPrefix("images/") ? folders.images : folders.audio).appendingPathComponent(base)
        if !fm.fileExists(atPath: target.path) { try z.read(e).write(to: target) }
      } else if e.name.hasPrefix("thumbs/") {
        thumbs[base] = e
      }
    }
    let result = try db.merge(from: dbURL.path)
    for (name, e) in thumbs where result.changed.contains((name as NSString).deletingPathExtension) {
      try? z.read(e).write(to: folders.thumbs.appendingPathComponent(name))
    }
    let settings = (try? z.read("settings.json")).map { String(decoding: $0, as: UTF8.self) }
    return (result, settings)
  }
}
