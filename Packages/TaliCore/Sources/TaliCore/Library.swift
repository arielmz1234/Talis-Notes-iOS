import Foundation

/// Where the camera was looking: world point at the screen's top-left, and zoom (1 = 100%).
public struct Viewport: Hashable, Codable, Sendable {
  public var x: Float = 0
  public var y: Float = 0
  public var zoom: Float = 1
  public init(x: Float = 0, y: Float = 0, zoom: Float = 1) {
    self.x = x
    self.y = y
    self.zoom = zoom
  }
}

/// What an item in the library is: a notebook, or a PDF, picture or scan added on its own.
public enum DocKind: String, CaseIterable, Sendable {
  case notebook, pdf, picture, scan

  /// As stored in `notebooks.kind` (NULL for a notebook).
  public var stored: String? { self == .notebook ? nil : rawValue }
  public static func of(_ stored: String?) -> DocKind { allCases.first { $0.stored == stored } ?? .notebook }
}

/// Paper backgrounds, stored by their Android enum names.
public enum PaperStyle: String, CaseIterable, Codable, Sendable {
  case BLANK, DOTS, GRID, LINES, ENGINEERING, ISOMETRIC, CORNELL, RULED
}

public struct NotebookMeta: Hashable, Identifiable, Sendable {
  public var id: String
  public var title: String
  /// Milliseconds since 1970, as on Android.
  public var created: Int64
  public var updated: Int64
  /// ARGB, as on Android.
  public var cover: UInt32
  public var paper: PaperStyle
  /// Her own paper's id, stored after "custom:" in the paper column on Android.
  public var customPaper: String?
  public var viewport: Viewport?
  public var thumbVersion: Int64 = 0
  public var folderId: String?
  /// When it went into Recently deleted.
  public var deleted: Int64?
  /// How many pages, or nil for an endless canvas.
  public var pages: Int?
  public var dark = false
  public var landscape = false
  public var draft = false
  public var kind: DocKind = .notebook
  public var pageAspect: Float?

  public init(
    id: String, title: String, created: Int64, updated: Int64, cover: UInt32, paper: PaperStyle, customPaper: String? = nil,
    viewport: Viewport? = nil, thumbVersion: Int64 = 0, folderId: String? = nil, deleted: Int64? = nil, pages: Int? = 1,
    dark: Bool = false, landscape: Bool = false, draft: Bool = false, kind: DocKind = .notebook, pageAspect: Float? = nil
  ) {
    self.id = id
    self.title = title
    self.created = created
    self.updated = updated
    self.cover = cover
    self.paper = paper
    self.customPaper = customPaper
    self.viewport = viewport
    self.thumbVersion = thumbVersion
    self.folderId = folderId
    self.deleted = deleted
    self.pages = pages
    self.dark = dark
    self.landscape = landscape
    self.draft = draft
    self.kind = kind
    self.pageAspect = pageAspect
  }

  public var pageLayout: Pages { Pages.of(landscape: landscape, aspect: pageAspect) }
}

/// A folder; [parentId] is the folder it sits in, or nil at the top level.
public struct Folder: Hashable, Identifiable, Sendable {
  public var id: String
  public var name: String
  public var color: UInt32
  public var position: Int
  public var parentId: String?
  public var created: Int64 = 0

  public init(id: String, name: String, color: UInt32, position: Int, parentId: String? = nil, created: Int64 = 0) {
    self.id = id
    self.name = name
    self.color = color
    self.position = position
    self.parentId = parentId
    self.created = created
  }
}

public enum Covers {
  /// Cover colours that sit with the lilac and sky theme: lavender, sky, orchid, blue, rose, mint, plum.
  public static let soft: [UInt32] = [0xFF9B_7BE0, 0xFF7F_B5F0, 0xFFC7_8FD9, 0xFF4F_7BE8, 0xFFE5_9BB8, 0xFF7D_C4B2, 0xFF5E_4B8B]
  /// Every colour offered for covers and folders: the soft ones, then bold ones.
  public static let all: [UInt32] =
    soft + [0xFFE5_3935, 0xFFFB_8C00, 0xFFFD_D835, 0xFF43_A047, 0xFF00_897B, 0xFF00_ACC1, 0xFF1E_3A8A, 0xFF79_5548, 0xFF75_7575, 0xFF21_2121]
}

public enum LibrarySort: String, CaseIterable, Codable, Sendable {
  case EDITED, OPENED, CREATED, NAME
}

/// Days a deleted notebook waits in Recently deleted.
public let trashDays = 30

public enum Names {
  /// [name], or "[name] (1)", "(2)"… whichever is first free among [taken] (ignoring case and spaces at
  /// the ends). A name already ending in a number in brackets counts on from its stem.
  public static func numbered(_ name: String, taken: some Collection<String>, untitled: String = "Untitled") -> String {
    let used = Set(taken.map { $0.trimmingCharacters(in: .whitespaces).lowercased() })
    var base = name.trimmingCharacters(in: .whitespaces)
    if base.isEmpty { base = untitled }
    if !used.contains(base.lowercased()) { return base }
    var stem = base
    if let m = base.range(of: #"^(.*\S)\s*\(\d+\)$"#, options: .regularExpression), m == base.startIndex..<base.endIndex,
      let open = base.lastIndex(of: "(")
    {
      stem = String(base[..<open]).trimmingCharacters(in: .whitespaces)
    }
    var n = 1
    while used.contains("\(stem.lowercased()) (\(n))") { n += 1 }
    return "\(stem) (\(n))"
  }

  /// Compares names the way people read them: ignoring case, and "Notebook 2" before "Notebook 10".
  public static func naturalCompare(_ a: String, _ b: String) -> Int {
    let x = chunks(a.trimmingCharacters(in: .whitespaces).lowercased())
    let y = chunks(b.trimmingCharacters(in: .whitespaces).lowercased())
    for i in 0..<min(x.count, y.count) {
      let p = x[i], q = y[i]
      let c: Int
      if p.first!.isASCIIDigit && q.first!.isASCIIDigit {
        let pp = String(p.drop { $0 == "0" }), qq = String(q.drop { $0 == "0" })
        c = pp.count != qq.count ? (pp.count < qq.count ? -1 : 1) : compare(pp, qq)
      } else {
        c = compare(p, q)
      }
      if c != 0 { return c }
    }
    return x.count == y.count ? 0 : (x.count < y.count ? -1 : 1)
  }

  // Kotlin's String.compareTo compares UTF-16 code units.
  private static func compare(_ a: String, _ b: String) -> Int {
    let x = Array(a.utf16), y = Array(b.utf16)
    for i in 0..<min(x.count, y.count) where x[i] != y[i] { return x[i] < y[i] ? -1 : 1 }
    return x.count == y.count ? 0 : (x.count < y.count ? -1 : 1)
  }

  private static func chunks(_ s: String) -> [String] {
    var out: [String] = []
    var cur = ""
    var digits = false
    for ch in s {
      let d = ch.isASCIIDigit
      if !cur.isEmpty && d != digits {
        out.append(cur)
        cur = ""
      }
      digits = d
      cur.append(ch)
    }
    if !cur.isEmpty { out.append(cur) }
    return out
  }
}

extension Character {
  var isASCIIDigit: Bool { ("0"..."9").contains(self) }
}

public enum LibraryOrder {
  /// Notebooks in [sort] order: newest first (A to Z for names), or the other way round when [reversed].
  public static func sorted(_ list: [NotebookMeta], by sort: LibrarySort, reversed: Bool, opened: [String]) -> [NotebookMeta] {
    var base: [NotebookMeta]
    switch sort {
    case .EDITED: base = stable(list) { $0.updated > $1.updated }
    case .CREATED: base = stable(list) { $0.created > $1.created }
    case .OPENED:
      let rank = Dictionary(opened.enumerated().map { ($1, $0) }, uniquingKeysWith: { a, _ in a })
      base = stable(list) { a, b in
        let ra = rank[a.id] ?? Int.max, rb = rank[b.id] ?? Int.max
        return ra != rb ? ra < rb : a.updated > b.updated
      }
    case .NAME: base = stable(list) { Names.naturalCompare($0.title, $1.title) < 0 }
    }
    return reversed ? base.reversed() : base
  }

  // Kotlin's sorts are stable; Swift's `sorted` isn't guaranteed to be.
  private static func stable(_ list: [NotebookMeta], _ less: (NotebookMeta, NotebookMeta) -> Bool) -> [NotebookMeta] {
    list.enumerated().sorted { l, r in less(l.element, r.element) || (!less(r.element, l.element) && l.offset < r.offset) }.map(\.element)
  }
}

public enum Greeting: String, Sendable {
  case good_morning, good_afternoon, good_evening, good_night

  /// Which part of the day [hour] (0-23) is.
  public static func forHour(_ hour: Int) -> Greeting {
    switch hour {
    case 5...11: return .good_morning
    case 12...16: return .good_afternoon
    case 17...20: return .good_evening
    default: return .good_night
    }
  }
}

/// Folders inside folders (Android's `folderTree`, `descendants` and `folderPath`).
public enum FolderTree {
  /// Folders in tree order, each followed by its own folders, with how deep each one sits. A folder
  /// whose parent is gone sits at the top level.
  public static func ordered(_ folders: [Folder]) -> [(folder: Folder, depth: Int)] {
    let ids = Set(folders.map(\.id))
    var children: [String?: [Folder]] = [:]
    for f in folders { children[f.parentId.flatMap { ids.contains($0) ? $0 : nil }, default: []].append(f) }
    var out: [(folder: Folder, depth: Int)] = []
    var seen = Set<String>()
    func walk(_ parent: String?, _ depth: Int) {
      for f in children[parent] ?? [] where seen.insert(f.id).inserted {
        out.append((f, depth))
        walk(f.id, depth + 1)
      }
    }
    walk(nil, 0)
    return out
  }

  /// Ids of every folder inside [id], at any depth.
  public static func descendants(of id: String, in folders: [Folder]) -> Set<String> {
    var out = Set<String>()
    var frontier: Set<String> = [id]
    while !frontier.isEmpty {
      frontier = Set(folders.filter { f in f.parentId.map(frontier.contains) == true && out.insert(f.id).inserted }.map(\.id))
    }
    return out
  }

  /// The folders from the top level down to [id], [id] included.
  public static func path(to id: String?, in folders: [Folder]) -> [Folder] {
    var out: [Folder] = []
    var cur = folders.first { $0.id == id }
    while let f = cur, !out.contains(where: { $0.id == f.id }) {
      out.insert(f, at: 0)
      cur = folders.first { $0.id == f.parentId }
    }
    return out
  }

  /// A folder can't go inside itself or one of its own folders.
  public static func canMove(_ id: String, into parent: String?, in folders: [Folder]) -> Bool {
    guard let parent else { return true }
    return parent != id && !descendants(of: id, in: folders).contains(parent)
  }
}

extension Names {
  /// Numbers names that clash with an older one in the same place (Android's `separateNames`):
  /// [items] oldest first, each with the place it sits in; the older keeps the plain name. Returns
  /// only the ones renamed, in order.
  public static func apart(_ items: [(id: String, name: String, place: String?)]) -> [(id: String, name: String)] {
    var seen: [String?: [String]] = [:]
    var out: [(id: String, name: String)] = []
    for item in items {
      let name = numbered(item.name, taken: seen[item.place] ?? [])
      if name != item.name { out.append((item.id, name)) }
      seen[item.place, default: []].append(name)
    }
    return out
  }
}
