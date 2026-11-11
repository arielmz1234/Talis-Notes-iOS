import Foundation

// A port of the fill tool's decisions in the Android app's canvas (`fillAt`, `runsThrough`,
// `fillPicture`) and of how a fill picture is stored (`ImageItem`, `ItemCodec`). Keep them in step.

extension ShapeRow {
  /// The outline enclosing its area, for filling and for telling whether a point is inside.
  public var outline: [Pt] { geometry.paths(size).first ?? [] }

  public func filled(_ color: Int32?) -> ShapeRow {
    var out = self
    out.fill = color
    return out
  }
}

/// What a tap of the fill tool lands on.
public enum FillTap {
  /// The topmost closed shape [p] is inside (locked ones are left alone).
  public static func shape(at p: Pt, in shapes: [ShapeRow]) -> ShapeRow? {
    shapes.filter { s in
      !s.locked && s.geometry.closed && (s.geometry.bounds(s.size)?.contains(p) ?? false) && Geo.pointInPolygon(p, s.outline)
    }.max { $0.z < $1.z }
  }

  /// Whether writing ([ink]: each stroke's points) or another shape runs through the inside of
  /// [shape] (a line across a box), so a tap there means the part it splits off, not the whole shape.
  public static func runsThrough(_ shape: ShapeRow, ink: [[Pt]], shapes: [ShapeRow]) -> Bool {
    guard let box = shape.geometry.bounds(shape.size) else { return false }
    let outline = shape.outline
    func inside(_ q: Pt) -> Bool { box.contains(q) && Geo.pointInPolygon(q, outline) }
    if ink.contains(where: { $0.contains(where: inside) }) { return true }
    return shapes.contains { other in
      other.id != shape.id && other.geometry.paths(other.size).contains { $0.contains(where: inside) }
    }
  }
}

extension AreaFill {
  /// The writing looked at round a tap at [p]: [reach] each way, kept to the tap's [page].
  public static func window(around p: Pt, page: Rect?) -> Rect {
    let w = Rect(p.x - reach, p.y - reach, p.x + reach, p.y + reach)
    guard let page else { return w }
    return Rect(max(w.left, page.left), max(w.top, page.top), min(w.right, page.right), min(w.bottom, page.bottom))
  }

  /// A filled area: where it sits on the page, its cells ([width] by [height], row by row) and the
  /// ids of the lines outlining it.
  public struct Area: Sendable, Equatable {
    public let rect: Rect
    public let width: Int
    public let height: Int
    public let cells: [Bool]
    public let outline: Set<String>
  }

  public enum Found: Sendable, Equatable {
    /// The tap is on a line, or what's round it isn't closed.
    case open
    /// The area is nearly all of the shape the tap is in: that shape takes a fill of its own.
    case wholeShape
    case area(Area)
  }

  /// The area round [p] that [mask] closes in. [mask] is the writing in [window] drawn on
  /// `grid(for: window)`, true where there's a line; [walls] are the same lines by id. [whole] is
  /// the area (world units) from which the fill counts as the whole shape the tap is in.
  public static func find(mask: [Bool], window: Rect, at p: Pt, walls: [Wall], whole: Float? = nil) -> Found {
    let (k, w, h) = grid(for: window)
    guard let filled = fill(mask, w, h, Int((p.x - window.left) * k), Int((p.y - window.top) * k), bridge: bridgeCells(k)),
      let e = extent(filled, w, h)
    else { return .open }
    if let whole, Float(e.cells) / (k * k) >= whole { return .wholeShape }
    let bw = e.x1 - e.x0 + 1, bh = e.y1 - e.y0 + 1
    var cells = [Bool](repeating: false, count: bw * bh)
    for y in 0..<bh {
      for x in 0..<bw where filled[(y + e.y0) * w + (x + e.x0)] { cells[y * bw + x] = true }
    }
    let rect = Rect(window.left + Float(e.x0) / k, window.top + Float(e.y0) / k, window.left + Float(e.x1 + 1) / k, window.top + Float(e.y1 + 1) / k)
    return .area(Area(rect: rect, width: bw, height: bh, cells: cells, outline: outline(of: walls, filled, w, h, window: window, k: k)))
  }
}

/// A filled area on the page: a picture behind the writing (an Android `ImageItem` whose file
/// begins "fill-"), with the strokes and shapes outlining it ([walls]), which move with it.
public struct FillRow: Sendable, Equatable {
  /// The stored row, kept as it is so nothing Android wrote is lost when it's put back.
  public let row: ItemRow
  public let file: String
  public let rect: Rect
  public let walls: [String]
  public let flipX: Bool
  public let flipY: Bool

  public var id: String { row.id }

  public static let prefix = "fill-"

  public init?(_ row: ItemRow) {
    guard row.kind == 2, let o = try? JSONSerialization.jsonObject(with: row.payload) as? [String: Any], let file = o["file"] as? String,
      file.hasPrefix(Self.prefix), let r = o["rect"] as? [String: Any]
    else { return nil }
    func f(_ k: String) -> Float { (r[k] as? NSNumber)?.floatValue ?? 0 }
    self.row = row
    self.file = file
    rect = Rect(f("left"), f("top"), f("right"), f("bottom"))
    walls = o["walls"] as? [String] ?? []
    flipX = o["flipX"] as? Bool ?? false
    flipY = o["flipY"] as? Bool ?? false
  }

  /// A new fill: the picture [file] at [rect], outlined by [walls].
  public init(id: String, z: Int64, file: String, rect: Rect, walls: Set<String>) {
    func num(_ f: Float) -> Double { Double("\(f)") ?? Double(f) }
    var o: [String: Any] = ["file": file, "rect": ["left": num(rect.left), "top": num(rect.top), "right": num(rect.right), "bottom": num(rect.bottom)]]
    if !walls.isEmpty { o["walls"] = walls.sorted() }
    let data = (try? JSONSerialization.data(withJSONObject: o)) ?? Data("{}".utf8)
    row = ItemRow(id: id, z: z, kind: 2, pen: nil, color: 0, size: 0, payload: data, l: rect.left, t: rect.top, r: rect.right, b: rect.bottom)
    self.file = file
    self.rect = rect
    self.walls = walls.sorted()
    flipX = false
    flipY = false
  }

  /// The picture's name: the colour goes in it, then [unique] (Android: the first 12 characters of a UUID).
  public static func fileName(colour: Int32, unique: String) -> String {
    prefix + String(format: "%08x-", UInt32(bitPattern: colour)) + unique.prefix(12) + ".png"
  }

  /// Which cell of a [width] by [height] picture covers [p] on the page, mirrored as the picture is.
  public func cell(at p: Pt, width: Int, height: Int) -> (x: Int, y: Int) {
    var x = min(max(Int((p.x - rect.left) / rect.width * Float(width)), 0), width - 1)
    var y = min(max(Int((p.y - rect.top) / rect.height * Float(height)), 0), height - 1)
    if flipX { x = width - 1 - x }
    if flipY { y = height - 1 - y }
    return (x, y)
  }
}
