import Foundation

/// A point in a picture, in parts of its width and height (0..1).
public struct UnitPt: Hashable, Sendable {
  public var x: Float
  public var y: Float
  public init(_ x: Float, _ y: Float) {
    self.x = x
    self.y = y
  }
}

/// A crop's four corners in parts of the picture: top-left, top-right, bottom-right, bottom-left
/// (Android's `camera/Quad.kt`).
public struct Quad: Hashable, Sendable {
  public var tl: UnitPt, tr: UnitPt, br: UnitPt, bl: UnitPt

  public init(_ tl: UnitPt, _ tr: UnitPt, _ br: UnitPt, _ bl: UnitPt) {
    self.tl = tl
    self.tr = tr
    self.br = br
    self.bl = bl
  }

  public var points: [UnitPt] { [tl, tr, br, bl] }

  public func with(_ i: Int, _ p: UnitPt) -> Quad {
    var q = self
    switch i {
    case 0: q.tl = p
    case 1: q.tr = p
    case 2: q.br = p
    default: q.bl = p
    }
    return q
  }

  /// The same corners in the picture turned a quarter clockwise [quarters] times.
  public func turned(_ quarters: Int) -> Quad {
    var q = self
    for _ in 0..<(((quarters % 4) + 4) % 4) {
      func r(_ p: UnitPt) -> UnitPt { UnitPt(1 - p.y, p.x) }
      // Turned clockwise, the old bottom-left becomes the top-left.
      q = Quad(r(q.bl), r(q.tl), r(q.tr), r(q.br))
    }
    return q
  }

  /// No corner crossing over: the four make a shape that bulges outward everywhere.
  public var convex: Bool {
    let ps = points
    var sign = 0
    for i in 0..<4 {
      let a = ps[i], b = ps[(i + 1) % 4], c = ps[(i + 2) % 4]
      let z = (b.x - a.x) * (c.y - b.y) - (b.y - a.y) * (c.x - b.x)
      let s = z > 0 ? 1 : (z < 0 ? -1 : 0)
      if s == 0 { return false }
      if sign == 0 { sign = s } else if s != sign { return false }
    }
    return true
  }

  /// The whole picture, a little in from its edges.
  public static func whole(inset: Float = 0) -> Quad {
    Quad(UnitPt(inset, inset), UnitPt(1 - inset, inset), UnitPt(1 - inset, 1 - inset), UnitPt(inset, 1 - inset))
  }

  /// The size the page inside comes out at when straightened from a [w] by [h] picture: each side as
  /// long as the longer of its pair, at most [maxSide] (Android's `straightened`).
  public func straightenedSize(_ w: Float, _ h: Float, maxSide: Float) -> (width: Float, height: Float) {
    let c = points.map { Pt($0.x * w, $0.y * h) }
    var outW = max(c[0].dist(c[1]), c[3].dist(c[2]))
    var outH = max(c[0].dist(c[3]), c[1].dist(c[2]))
    let s = min(1, maxSide / max(outW, outH))
    outW = max(8, outW * s)
    outH = max(8, outH * s)
    return (outW, outH)
  }
}

/// How a page looks once taken (Android's `Look`).
public enum Look: String, CaseIterable, Sendable {
  case original = "ORIGINAL", document = "DOCUMENT", grey = "GREY", blackWhite = "BLACK_WHITE"
}

/// The camera's looks on RGBA pixels (Android's `PageImage.looked`): [Look.document] whitens the paper
/// and its shadows while keeping the ink's colour, [Look.grey] the same in grey, [Look.blackWhite] crisp
/// black on white. The paper's own brightness behind each pixel is divided out, so shadows and a
/// yellow lamp go.
public enum PageLooks {
  public static func looked(_ rgba: [UInt8], width w: Int, height h: Int, _ look: Look) -> [UInt8] {
    if look == .original || w <= 0 || h <= 0 { return rgba }
    let bg = paper(rgba, w, h)
    var out = rgba
    for i in 0..<(w * h) {
      let o = i * 4
      let r = Float(rgba[o]), g = Float(rgba[o + 1]), b = Float(rgba[o + 2])
      let k = 255 / Float(max(bg[i], 24))
      let l = Float(lum(rgba, o))
      let px: (Float, Float, Float)
      switch look {
      case .document: px = (curve(r * k / 255), curve(g * k / 255), curve(b * k / 255))
      case .grey:
        let v = curve(l * k / 255)
        px = (v, v, v)
      default:
        let v = min(max((l * k / 255 - 0.6) / 0.16, 0), 1)
        px = (v, v, v)
      }
      out[o] = byte(px.0)
      out[o + 1] = byte(px.1)
      out[o + 2] = byte(px.2)
      out[o + 3] = 255
    }
    return out
  }

  /// The brightest of each small cell (the writing is darker than the paper, so that's paper),
  /// smoothed, then spread back over the page.
  static func paper(_ px: [UInt8], _ w: Int, _ h: Int) -> [Int] {
    let cell = max(4, max(w, h) / 48)
    let gw = (w + cell - 1) / cell, gh = (h + cell - 1) / cell
    var grid = [Int](repeating: 0, count: gw * gh)
    for y in 0..<h {
      let gy = y / cell
      for x in 0..<w {
        let i = gy * gw + x / cell
        let v = lum(px, (y * w + x) * 4)
        if v > grid[i] { grid[i] = v }
      }
    }
    for _ in 0..<2 { grid = blur(grid, gw, gh) }
    var out = [Int](repeating: 0, count: w * h)
    for y in 0..<h {
      let fy = min(max((Float(y) + 0.5) / Float(cell) - 0.5, 0), Float(gh - 1))
      let y0 = Int(fy), y1 = min(y0 + 1, gh - 1)
      let ty = fy - Float(y0)
      for x in 0..<w {
        let fx = min(max((Float(x) + 0.5) / Float(cell) - 0.5, 0), Float(gw - 1))
        let x0 = Int(fx), x1 = min(x0 + 1, gw - 1)
        let tx = fx - Float(x0)
        let top = Float(grid[y0 * gw + x0]) * (1 - tx) + Float(grid[y0 * gw + x1]) * tx
        let bottom = Float(grid[y1 * gw + x0]) * (1 - tx) + Float(grid[y1 * gw + x1]) * tx
        out[y * w + x] = Int(top * (1 - ty) + bottom * ty)
      }
    }
    return out
  }

  /// Paper to white, ink a little deeper.
  static func curve(_ v: Float) -> Float { powf(min(max((v - 0.18) / 0.72, 0), 1), 1.25) }

  static func lum(_ px: [UInt8], _ o: Int) -> Int { (Int(px[o]) * 77 + Int(px[o + 1]) * 150 + Int(px[o + 2]) * 29) >> 8 }

  private static func byte(_ v: Float) -> UInt8 { UInt8(min(max(v, 0), 1) * 255) }

  /// A 3×3 box blur.
  static func blur(_ src: [Int], _ w: Int, _ h: Int) -> [Int] {
    var tmp = [Int](repeating: 0, count: w * h)
    for y in 0..<h {
      let r = y * w
      for x in 0..<w { tmp[r + x] = (src[r + max(x - 1, 0)] + src[r + x] + src[r + min(x + 1, w - 1)]) / 3 }
    }
    var out = [Int](repeating: 0, count: w * h)
    for y in 0..<h {
      for x in 0..<w { out[y * w + x] = (tmp[max(y - 1, 0) * w + x] + tmp[y * w + x] + tmp[min(y + 1, h - 1) * w + x]) / 3 }
    }
    return out
  }
}
