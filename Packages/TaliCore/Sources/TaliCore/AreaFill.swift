import Foundation

// A port of the Android app's `canvas/AreaFill.kt`, with the grid arithmetic of `fillPicture` and
// `outlineOf` from its canvas. Same numbers; keep the two in step.

extension Geo {
  /// The polygon's signed area.
  public static func polygonArea(_ poly: [Pt]) -> Float {
    var a: Float = 0
    for i in poly.indices {
      let p = poly[i], q = poly[(i + 1) % poly.count]
      a += p.x * q.y - q.x * p.y
    }
    return a / 2
  }
}

/// Finds the area around a tapped point that her writing encloses, on a grid of "wall" cells (the
/// ink drawn into a mask). Small gaps in hand-drawn outlines are bridged by thickening the walls a
/// little first; if the area still runs out to the edge of the search window, it isn't closed and
/// nothing is filled (rather than flooding the page). The result is grown back by a few cells so
/// the fill tucks under the lines instead of leaving a thin gap beside them.
public enum AreaFill {
  /// How far round the tap the writing is looked at, in world units each way.
  public static let reach: Float = 1100
  /// The longest side of the mask, in cells.
  public static let pixels: Float = 1400
  /// Gaps this wide in world units (about 1 mm) are closed.
  public static let bridge: Float = 3

  /// The mask for [window]: cells per world unit and its size in cells.
  public static func grid(for window: Rect) -> (k: Float, w: Int, h: Int) {
    let k = min(1, pixels / max(window.width, window.height))
    return (k, max(Int(window.width * k), 8), max(Int(window.height * k), 8))
  }

  /// How many cells of gap to close on a mask of [k] cells per world unit.
  public static func bridgeCells(_ k: Float) -> Int { max(Int(bridge * k), 1) }

  /// [walls] is a [w] by [h] grid (row by row). Returns the filled grid, or nil when the tap is on a
  /// line or the area isn't closed. [bridge] is how many cells of gap to close.
  public static func fill(_ walls: [Bool], _ w: Int, _ h: Int, _ x: Int, _ y: Int, bridge: Int) -> [Bool]? {
    guard (0..<w).contains(x), (0..<h).contains(y) else { return nil }
    let thick = dilate(walls, w, h, bridge)
    if thick[y * w + x] { return nil }
    var filled = [Bool](repeating: false, count: w * h)
    // Scanline flood fill: each stack entry seeds one run of open cells in a row.
    var stack = [y * w + x]
    while let i = stack.popLast() {
      if filled[i] || thick[i] { continue }
      let row = i / w
      var l = i % w
      while l > 0 && !thick[row * w + l - 1] && !filled[row * w + l - 1] { l -= 1 }
      var r = i % w
      while r < w - 1 && !thick[row * w + r + 1] && !filled[row * w + r + 1] { r += 1 }
      // It ran out to the window's edge: not closed.
      if l == 0 || r == w - 1 || row == 0 || row == h - 1 { return nil }
      for cx in l...r { filled[row * w + cx] = true }
      for ny in [row - 1, row + 1] {
        var open = false
        for cx in l...r {
          let j = ny * w + cx
          let free = !filled[j] && !thick[j]
          if free && !open { stack.append(j) }
          open = free
        }
      }
    }
    return dilate(filled, w, h, bridge + 2)
  }

  /// Grows the true cells of [grid] by [r] cells in every direction (a square brush, two passes).
  public static func dilate(_ grid: [Bool], _ w: Int, _ h: Int, _ r: Int) -> [Bool] {
    if r <= 0 { return grid }
    var horizontal = [Bool](repeating: false, count: w * h)
    for y in 0..<h {
      var last = -r - 1
      for x in 0..<w {
        if grid[y * w + x] { last = x }
        if x - last <= r { horizontal[y * w + x] = true }
      }
      last = w + r + 1
      for x in stride(from: w - 1, through: 0, by: -1) {
        if grid[y * w + x] { last = x }
        if last - x <= r { horizontal[y * w + x] = true }
      }
    }
    var out = [Bool](repeating: false, count: w * h)
    for x in 0..<w {
      var last = -r - 1
      for y in 0..<h {
        if horizontal[y * w + x] { last = y }
        if y - last <= r { out[y * w + x] = true }
      }
      last = h + r + 1
      for y in stride(from: h - 1, through: 0, by: -1) {
        if horizontal[y * w + x] { last = y }
        if last - y <= r { out[y * w + x] = true }
      }
    }
    return out
  }

  /// The filled cells' box (x0, y0 to x1, y1, inclusive) and how many there are; nil when none.
  public static func extent(_ filled: [Bool], _ w: Int, _ h: Int) -> (x0: Int, y0: Int, x1: Int, y1: Int, cells: Int)? {
    var x0 = w, y0 = h, x1 = -1, y1 = -1, cells = 0
    for y in 0..<h {
      for x in 0..<w where filled[y * w + x] {
        cells += 1
        x0 = min(x0, x)
        x1 = max(x1, x)
        y0 = min(y0, y)
        y1 = max(y1, y)
      }
    }
    return x1 < x0 ? nil : (x0, y0, x1, y1, cells)
  }

  /// Something that may border a filled area: a stroke or a shape, by its id, lines and thickness.
  public struct Wall: Sendable {
    public let id: String
    public let paths: [[Pt]]
    public let size: Float

    public init(id: String, paths: [[Pt]], size: Float) {
      self.id = id
      self.paths = paths
      self.size = size
    }
  }

  /// Which of [walls] outline the filled area: along much of its length (a quarter or more), there
  /// is fill just to one side of it and not the other. Writing inside the area has fill on both
  /// sides, and a stroke or shape that only touches or crosses the edge borders it just briefly;
  /// neither is part of the outline, so neither moves with the fill.
  public static func outline(of walls: [Wall], _ filled: [Bool], _ w: Int, _ h: Int, window: Rect, k: Float) -> Set<String> {
    func on(_ x: Float, _ y: Float) -> Bool {
      let px = Int((x - window.left) * k), py = Int((y - window.top) * k)
      return (0..<w).contains(px) && (0..<h).contains(py) && filled[py * w + px]
    }
    let step = 3 / k
    var out = Set<String>()
    for wall in walls {
      // Probe just past the line's own width and the gap bridging, on either side.
      let reach = wall.size / 2 + bridge + 2.5 / k
      var samples = 0, oneSided = 0
      for path in wall.paths where path.count > 1 {
        for i in 0..<(path.count - 1) {
          let a = path[i], b = path[i + 1]
          let len = a.dist(b)
          if len < 1e-3 { continue }
          let n = Pt(-(b.y - a.y) / len, (b.x - a.x) / len)
          var t: Float = 0
          while t < len {
            let q = a + (b - a) * (t / len)
            let left = on(q.x + n.x * reach, q.y + n.y * reach)
            let right = on(q.x - n.x * reach, q.y - n.y * reach)
            samples += 1
            if left != right { oneSided += 1 }
            t += step
          }
        }
      }
      if samples > 0 && oneSided >= 4 && oneSided >= samples / 4 { out.insert(wall.id) }
    }
    return out
  }
}
