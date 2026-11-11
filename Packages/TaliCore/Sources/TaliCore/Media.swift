import Foundation

/// A Float as the shortest decimal that reads back as the same Float (as Kotlin prints it).
private func num(_ f: Float) -> Double { Double("\(f)") ?? Double(f) }

private func rectJSON(_ r: Rect) -> [String: Any] { ["left": num(r.left), "top": num(r.top), "right": num(r.right), "bottom": num(r.bottom)] }

private func rectOf(_ any: Any?) -> Rect? {
  guard let o = any as? [String: Any] else { return nil }
  func f(_ k: String) -> Float { (o[k] as? NSNumber)?.floatValue ?? 0 }
  return Rect(f("left"), f("top"), f("right"), f("bottom"))
}

/// A picture on the page (Android's `ImageItem`, item kind 2): its file in the images folder, where it
/// sits, and the part of the whole picture shown ([crop], fractions 0..1; nil shows it all).
public struct PictureRow: Sendable, Equatable {
  public static let kind = 2

  public var id: String
  public var z: Int64
  public var file: String
  public var rect: Rect
  /// A page of an imported PDF (export gives it back its own page; the lasso never takes it).
  public var pdfPage = false
  /// Drawn among the writing by z instead of behind all of it.
  public var front = false
  public var locked = false
  /// An area fill's outline (the strokes and shapes it was made in).
  public var walls: [String] = []
  public var flipX = false
  public var flipY = false
  public var crop: Rect?

  public init(id: String, z: Int64, file: String, rect: Rect, pdfPage: Bool = false, front: Bool = false, crop: Rect? = nil) {
    self.id = id
    self.z = z
    self.file = file
    self.rect = rect
    self.pdfPage = pdfPage
    self.front = front
    self.crop = crop
  }

  public init?(_ row: ItemRow) {
    guard row.kind == Self.kind, let o = try? JSONSerialization.jsonObject(with: row.payload) as? [String: Any], let file = o["file"] as? String,
      let rect = rectOf(o["rect"])
    else { return nil }
    self.init(id: row.id, z: row.z, file: file, rect: rect)
    func b(_ k: String) -> Bool { (o[k] as? Bool) ?? false }
    pdfPage = b("pdfPage")
    front = b("front")
    locked = b("locked")
    walls = (o["walls"] as? [String]) ?? []
    flipX = b("flipX")
    flipY = b("flipY")
    crop = rectOf(o["crop"])
  }

  /// The row Android's `ItemCodec` writes (values left at their defaults are left out, as kotlinx does).
  public var itemRow: ItemRow {
    var o: [String: Any] = ["file": file, "rect": rectJSON(rect)]
    if pdfPage { o["pdfPage"] = true }
    if front { o["front"] = true }
    if locked { o["locked"] = true }
    if !walls.isEmpty { o["walls"] = walls }
    if flipX { o["flipX"] = true }
    if flipY { o["flipY"] = true }
    if let crop { o["crop"] = rectJSON(crop) }
    let data = (try? JSONSerialization.data(withJSONObject: o)) ?? Data()
    return ItemRow(id: id, z: z, kind: Self.kind, pen: nil, color: 0, size: 0, payload: data, l: rect.left, t: rect.top, r: rect.right, b: rect.bottom)
  }

  /// Where the whole picture would sit on the page, uncropped.
  public var whole: Rect {
    guard let c = crop else { return rect }
    let w = rect.width / max(c.width, 0.001)
    let h = rect.height / max(c.height, 0.001)
    let left = rect.left - c.left * w
    let top = rect.top - c.top * h
    return Rect(left, top, left + w, top + h)
  }

  /// Cropped to [part] of the whole picture, shown in [shown] on the page.
  public func cropped(_ part: Rect?, shown: Rect) -> PictureRow {
    var p = self
    p.crop = part
    p.rect = shown
    return p
  }

  /// The imported PDF and page this picture shows (`pdf-<pdf id>-p<page>-<uuid>.jpg`), if it is one.
  public var pdfSource: (pdf: String, page: Int)? { Self.pdfSource(of: file) }

  public static func pdfSource(of file: String) -> (pdf: String, page: Int)? {
    guard file.hasPrefix("pdf-") else { return nil }
    let rest = file.dropFirst(4)
    guard rest.count > 38 else { return nil }
    let id = rest.prefix(36)
    guard id.allSatisfy({ $0.isHexDigit || $0 == "-" }) else { return nil }
    let after = rest.dropFirst(36)
    guard after.hasPrefix("-p") else { return nil }
    let digits = after.dropFirst(2).prefix { $0.isNumber }
    guard !digits.isEmpty, after.dropFirst(2 + digits.count).hasPrefix("-"), let page = Int(digits) else { return nil }
    return (String(id), page)
  }

  public static func pdfPageFile(pdf: String, page: Int, unique: String) -> String { "pdf-\(pdf)-p\(page)-\(unique).jpg" }
}

/// A voice memo (Android's `AudioItem`, item kind 4): its recording in the audio folder, where it sits
/// in the world (beside a page: [side] and [edge], points out from the paper), how long it is, its
/// loudness bars and her name for it.
public struct MemoRow: Sendable, Equatable, Identifiable {
  public static let kind = 4
  public static let right = 0
  public static let left = 1
  /// How far a memo's centre sits out from the page's edge, in points on screen.
  public static let edge: Float = 36
  /// Its footprint in world units (to place it and tell which page it belongs to).
  public static let size: Float = 40
  public static let waveBars = 48

  public var id: String
  public var z: Int64
  public var file: String
  public var at: Pt
  public var durationMs: Int64
  public var wave: [Int]
  public var created: Int64
  public var locked = false
  public var side = MemoRow.right
  public var edge = MemoRow.edge
  public var title = ""

  public init(id: String, z: Int64, file: String, at: Pt, durationMs: Int64, wave: [Int], created: Int64, side: Int = MemoRow.right, title: String = "") {
    self.id = id
    self.z = z
    self.file = file
    self.at = at
    self.durationMs = durationMs
    self.wave = wave
    self.created = created
    self.side = side
    self.title = title
  }

  public init?(_ row: ItemRow) {
    guard row.kind == Self.kind, let o = try? JSONSerialization.jsonObject(with: row.payload) as? [String: Any], let file = o["file"] as? String else { return nil }
    func f(_ k: String) -> Float { (o[k] as? NSNumber)?.floatValue ?? 0 }
    func i(_ k: String) -> Int64 { (o[k] as? NSNumber)?.int64Value ?? 0 }
    self.init(
      id: row.id, z: row.z, file: file, at: Pt(f("x"), f("y")), durationMs: i("durationMs"), wave: (o["wave"] as? [NSNumber])?.map(\.intValue) ?? [],
      created: i("created"), side: (o["side"] as? NSNumber)?.intValue ?? Self.right, title: (o["title"] as? String) ?? "")
    locked = (o["locked"] as? Bool) ?? false
    edge = (o["edge"] as? NSNumber)?.floatValue ?? Self.edge
  }

  public var bounds: Rect { Rect(at.x - Self.size / 2, at.y - Self.size / 2, at.x + Self.size / 2, at.y + Self.size / 2) }

  public var itemRow: ItemRow {
    var o: [String: Any] = ["file": file, "x": num(at.x), "y": num(at.y), "durationMs": durationMs]
    if !wave.isEmpty { o["wave"] = wave }
    if created != 0 { o["created"] = created }
    if locked { o["locked"] = true }
    if side != Self.right { o["side"] = side }
    if edge != Self.edge { o["edge"] = num(edge) }
    if !title.isEmpty { o["title"] = title }
    let data = (try? JSONSerialization.data(withJSONObject: o)) ?? Data()
    let b = bounds
    return ItemRow(id: id, z: z, kind: Self.kind, pen: nil, color: 0, size: 0, payload: data, l: b.left, t: b.top, r: b.right, b: b.bottom)
  }

  /// [levels] (0..1, one per moment) as [waveBars] bars from 0 to 100, scaled to the loudest moment but
  /// never past a speaking voice, so a quiet room stays low (Android's `VoiceRecorder.waveOf`).
  public static func waveOf(_ levels: [Float]) -> [Int] {
    let n = waveBars
    if levels.isEmpty { return Array(repeating: 0, count: n) }
    let peak = max(levels.max() ?? 0, 0.45)
    return (0..<n).map { i in
      let from = i * levels.count / n
      let to = min(max(from + 1, (i + 1) * levels.count / n), levels.count)
      let v = levels[min(from, levels.count - 1)..<to].max() ?? 0
      return min(max(Int(v / peak * 100), 0), 100)
    }
  }

  /// Buttons in one column pushed apart so none overlap, top to bottom, at least [spacing] apart;
  /// columns closer than [size] count as one (Android's `spread`).
  public static func spread(_ centres: [(id: String, at: Pt)], spacing: Float, size: Float) -> [String: Pt] {
    var out: [String: Pt] = [:]
    var placed: [Pt] = []
    for (id, p) in centres.sorted(by: { $0.at.y < $1.at.y }) {
      var y = p.y
      if let above = placed.filter({ abs($0.x - p.x) < size }).max(by: { $0.y < $1.y }), y < above.y + spacing { y = above.y + spacing }
      let at = Pt(p.x, y)
      placed.append(at)
      out[id] = at
    }
    return out
  }
}

/// Where memos sit, given how the page is on screen: [zoom] screen points per world unit and
/// [origin] the screen point of the world's origin (Android's `memoCenter`, `memoDrop`, `newMemoSpot`).
public struct MemoPlacement: Sendable {
  public var zoom: Float
  public var origin: Pt
  /// The screen's size in points.
  public var screen: Pt
  /// The pages, or nil on an endless canvas.
  public var pages: Pages?
  public var pageCount: Int
  /// How far the toolbars reach down over the canvas.
  public var topClearance: Float

  public init(zoom: Float, origin: Pt, screen: Pt, pages: Pages?, pageCount: Int, topClearance: Float) {
    self.zoom = zoom
    self.origin = origin
    self.screen = screen
    self.pages = pages
    self.pageCount = pageCount
    self.topClearance = topClearance
  }

  public func toScreen(_ p: Pt) -> Pt { origin + p * zoom }
  public func toWorld(_ p: Pt) -> Pt { (p - origin) / zoom }

  /// A memo's button centre on screen: always [MemoRow.edge] out from the paper on its side, kept on screen.
  public func centre(_ m: MemoRow, radius: Float, gap: Float) -> Pt {
    let p = toScreen(m.at)
    guard let pages else { return p }
    let x = m.side == MemoRow.left ? toScreen(Pt(0, m.at.y)).x - MemoRow.edge : toScreen(Pt(pages.width, m.at.y)).x + MemoRow.edge
    return Pt(min(max(x, gap + radius), max(gap + radius, screen.x - gap - radius)), p.y)
  }

  /// Where a memo dropped at screen point [s] goes: beside the nearer side of the page at that height
  /// (kept within the pages); on an endless canvas, right there.
  public func drop(_ m: MemoRow, at s: Pt) -> MemoRow {
    let w = toWorld(s)
    var out = m
    out.edge = MemoRow.edge
    guard let pages else {
      out.at = w
      return out
    }
    let y = min(max(w.y, 0), Float(pageCount - 1) * pages.pitch + pages.height)
    let left = toScreen(Pt(0, y)).x, right = toScreen(Pt(pages.width, y)).x
    if s.x >= (left + right) / 2 {
      out.at = Pt(pages.width + MemoRow.size, y)
      out.side = MemoRow.right
    } else {
      out.at = Pt(-MemoRow.size, y)
      out.side = MemoRow.left
    }
    return out
  }

  /// Where a new memo goes: beside the page on screen, near the top of what shows of it (below the
  /// toolbars) and below any memos already there. [spacing] is the screen distance between two memos.
  public func newSpot(_ memos: [MemoRow], spacing: Float) -> Pt {
    let visibleTop = toWorld(.zero).y
    let visible = Rect(toWorld(.zero).x, visibleTop, toWorld(screen).x, toWorld(screen).y)
    let step = spacing / zoom
    let top = visible.top + (topClearance + 12) / zoom + step / 2
    guard let pages else {
      let x = visible.right - (spacing / 2 + 16) / zoom
      var y = top
      while memos.contains(where: { abs($0.at.y - y) < step * 0.9 && abs($0.at.x - x) < step }) { y += step }
      return Pt(x, y)
    }
    let page = pages.rect(min(max(pages.indexAt(visible.top + visible.height * 0.4), 0), pageCount - 1))
    let x = page.right + MemoRow.size
    var y = min(max(top, page.top + step / 2), max(page.top + step / 2, page.bottom - step / 2))
    while memos.contains(where: { abs($0.at.y - y) < step * 0.9 }) && y + step < page.bottom { y += step }
    return Pt(x, y)
  }
}
