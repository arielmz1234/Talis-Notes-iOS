import Foundation

// The rules of picking things up, ported from the Android app's canvas (`lockSelection`, `withFills`,
// `loopCloses`, `arrangeSelection`, `mirrorSelection`, `takeScreenshot`) and its item classes
// (`CanvasItem.kt`). Keep them in step.

/// A stroke's lock, kept in the pen column as Android's `ItemCodec` keeps it: "PEN/STYLE/SQUARE/LOCKED".
public enum InkTags {
  public static let locked = "LOCKED"

  public static func isLocked(_ tags: [String]) -> Bool { tags.contains(locked) }

  /// [tags] with the lock on or off; it goes last, after the line style and the square tip.
  public static func with(_ tags: [String], locked on: Bool) -> [String] {
    tags.filter { $0 != locked } + (on ? [locked] : [])
  }
}

extension Lasso {
  /// Free form picks up what the pen passes within this far of, on screen (Android's `FREE_SELECT_DP`).
  public static let freeReach: Float = 10
  /// A free-form path that ends this near its start, on screen, is a loop (Android's `LOOP_CLOSE_DP`).
  public static let loopClose: Float = 40
  /// A lasso shorter than this on screen is a tap.
  public static let tapLength: Float = 12

  /// Whether a free-form path comes back round near where it started (it then picks up what's inside too).
  public static func loopCloses(_ path: [Pt], zoom: Float) -> Bool {
    guard path.count >= 8, let first = path.first, let last = path.last else { return false }
    return first.dist(last) * zoom < loopClose && Geo.pathLength(path) * zoom > 3 * loopClose
  }
}

extension ShapeRow {
  /// Moved, scaled, turned or mirrored by [m]: its line scales with it, and it comes out unlocked
  /// (Android's `ShapeItem.transformed`).
  public func transformed(_ m: Affine) -> ShapeRow {
    var s = self
    s.geometry = geometry.transformed(m)
    s.size = max(size * m.scaleFactor, 0.5)
    s.locked = false
    return s
  }

  /// Another colour; a see-through shape stays as see-through. It comes out unlocked, as on Android.
  public func recolored(_ argb: Int32) -> ShapeRow {
    var s = self
    let alpha = UInt32(bitPattern: color) >> 24
    s.color = (1...0xFE).contains(alpha) ? Int32(bitPattern: (UInt32(bitPattern: argb) & 0x00FF_FFFF) | (UInt32(bitPattern: color) & 0xFF00_0000)) : argb
    s.locked = false
    return s
  }
}

extension PictureRow {
  /// An area fill: a picture of the filled area, kept with the lines outlining it ([walls]).
  public var isFill: Bool { file.hasPrefix(FillRow.prefix) }

  /// Moved or resized by [m]: the corners of its box carried over (it never turns). It keeps its lock.
  public func transformed(_ m: Affine) -> PictureRow {
    let a = m.apply(Pt(rect.left, rect.top)), b = m.apply(Pt(rect.right, rect.bottom))
    var p = self
    p.rect = Rect(min(a.x, b.x), min(a.y, b.y), max(a.x, b.x), max(a.y, b.y))
    return p
  }

  /// Drawn mirrored in place (an area fill flipping with its outline).
  public func flipped(horizontal: Bool) -> PictureRow {
    var p = self
    if horizontal { p.flipX.toggle() } else { p.flipY.toggle() }
    return p
  }

  /// Mirrored with a selection by [m]: it moves to its mirrored place and keeps facing the right
  /// way, unless it's an area fill, which flips with its outline.
  public func mirrored(_ m: Affine, horizontal: Bool) -> PictureRow {
    let c = rect.center, to = m.apply(c)
    let moved = transformed(.translate(to.x - c.x, to.y - c.y))
    return isFill ? moved.flipped(horizontal: horizontal) : moved
  }

  /// Among the writing by its place in the stack ([on]), or behind all of it like paper.
  public func inFront(_ on: Bool, z: Int64) -> PictureRow {
    var p = self
    p.front = on
    p.z = z
    return p
  }

  /// A copy under [id] at [z]: unlocked, outlining [walls] (the copies of what the original outlined).
  public func copy(id: String, z: Int64, walls: [String]) -> PictureRow {
    var p = self
    p.id = id
    p.z = z
    p.locked = false
    p.walls = walls
    return p
  }
}

/// A fill and the drawing around it move as one (Android's `withFills`).
public enum FillGroup {
  public struct Fill: Sendable, Equatable {
    public var id: String
    public var walls: [String]
    public var locked: Bool

    public init(id: String, walls: [String], locked: Bool = false) {
      self.id = id
      self.walls = walls
      self.locked = locked
    }
  }

  /// [ids] with every area fill outlined by something in it, and every outline stroke of any fill in
  /// it (so a box drawn in four strokes comes along whole). Only fills that know their outline group
  /// with it; writing inside the filled area isn't part of it. [isLocked] says whether an item is
  /// locked, or nil when it's gone; locked fills and lines stay behind unless [pickLocked].
  public static func with(_ ids: [String], fills: [Fill], isLocked: (String) -> Bool?, pickLocked: Bool) -> [String] {
    let known = fills.filter { !$0.walls.isEmpty && (!$0.locked || pickLocked) }
    if known.isEmpty || ids.isEmpty { return ids }
    var group = ids
    var inGroup = Set(ids)
    func add(_ id: String) -> Bool {
      guard inGroup.insert(id).inserted else { return false }
      group.append(id)
      return true
    }
    var changed = true
    var rounds = 0
    while changed && rounds < 4 {
      rounds += 1
      changed = false
      for f in known where inGroup.contains(f.id) || f.walls.contains(where: inGroup.contains) {
        if add(f.id) { changed = true }
        for wall in f.walls {
          guard let locked = isLocked(wall), !locked || pickLocked else { continue }
          if add(wall) { changed = true }
        }
      }
    }
    return group
  }

  /// The outlines of copied fills: each copy outlines the copies of what the original outlined.
  public static func copiedWalls(_ walls: [String], ids: [String: String]) -> [String] { walls.compactMap { ids[$0] } }

  /// What a fill outlines once the eraser has passed (Android's `finishErase`): the lines of [walls]
  /// that are left, and every piece cut from one of them ([pieces]: a piece's id to the id of the
  /// line it was cut from), so a cut outline still travels with its fill. Nil when the eraser
  /// touched none of its lines.
  public static func wallsAfterErasing(_ walls: [String], gone: Set<String>, pieces: [String: String]) -> [String]? {
    guard walls.contains(where: gone.contains) else { return nil }
    let outline = Set(walls)
    return (walls.filter { !gone.contains($0) } + pieces.filter { outline.contains($0.value) }.keys).sorted()
  }
}

/// Bring to front and Send to back (Android's `arrangeSelection`).
public enum Arrange {
  public struct Item: Sendable, Equatable {
    public var id: String
    public var z: Int64
    /// A picture is behind all writing until it's brought forward ([front]).
    public var picture: Bool
    public var front: Bool

    public init(id: String, z: Int64, picture: Bool = false, front: Bool = false) {
      self.id = id
      self.z = z
      self.picture = picture
      self.front = front
    }

    var behind: Bool { picture && !front }
  }

  /// Where each of [picked] goes in the stack (keeping their own order), or nil when they're there
  /// already. [others] is everything else on the page; [top] the highest place in use.
  public static func plan(_ picked: [Item], others: [Item], toFront: Bool, top: Int64) -> [(id: String, z: Int64, front: Bool)]? {
    let sel = picked.sorted { $0.z < $1.z }
    guard let lowest = sel.first, let highest = sel.last else { return nil }
    let already =
      toFront
      ? !sel.contains(where: \.behind) && !others.contains { $0.z > lowest.z && !$0.behind }
      : !sel.contains { $0.picture && $0.front } && !others.contains { $0.z < highest.z }
    if already { return nil }
    let bottom = (picked + others).map(\.z).min() ?? 0
    return sel.enumerated().map { i, item in
      (item.id, toFront ? top + 1 + Int64(i) : bottom - Int64(sel.count) + Int64(i), toFront)
    }
  }
}

/// The screenshot lasso (Android's `takeScreenshot`).
public enum ScreenshotLasso {
  static let maxPixels: Float = 16_000_000

  /// Whether [area] is too small on screen to be worth a picture.
  public static func tooSmall(_ area: Rect, zoom: Float) -> Bool { area.width * zoom < 16 || area.height * zoom < 16 }

  /// Pixels per world unit: at least twice the screen's sharpness, up to about 16 million pixels.
  public static func pixelsPerUnit(_ area: Rect, zoom: Float, screenScale: Float) -> Float {
    min(max(zoom * screenScale, 2 * screenScale), (maxPixels / max(area.width * area.height, 1)).squareRoot())
  }
}

extension TextRow {
  /// How narrow and how wide a text box can be dragged, and how tall it can be set (Android's
  /// `MIN_TEXT_WIDTH`, `MAX_TEXT_WIDTH`, `MAX_TEXT_HEIGHT`).
  public static let minWidth: Float = 60
  public static let maxWidth: Float = 2400
  public static let maxHeight: Float = 4000

  /// One side of the box as a rectangle's: 0 left, 1 right (the width, the other side staying put),
  /// 2 top, 3 bottom (the height; never shorter than the text when dragged from the top). [content]
  /// is how tall the box is now and [text] how tall its text; [d] how far the dot has been dragged.
  public func withSide(_ side: Int, draggedBy d: Pt, content: Float, text: Float) -> TextRow {
    var t = self
    switch side {
    case 0:
      t.width = min(max(width - d.x, Self.minWidth), Self.maxWidth)
      t.x = x + (width - t.width)
    case 1:
      t.width = min(max(width + d.x, Self.minWidth), Self.maxWidth)
    case 2:
      t.height = min(max(content - d.y, text), Self.maxHeight)
      t.y = y + (content - t.height)
    default:
      t.height = min(max(content + d.y, 0), Self.maxHeight)
    }
    return t
  }

  /// The corner chip: the corner follows the finger, the text keeps its size.
  public func withCorner(draggedBy d: Pt, content: Float) -> TextRow {
    var t = self
    t.width = min(max(width + d.x, Self.minWidth), Self.maxWidth)
    t.height = min(max(content + d.y, 0), Self.maxHeight)
    return t
  }
}
