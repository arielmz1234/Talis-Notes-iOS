import Foundation

/// The Shapes tool's kinds (Android's `ShapeKind` in `model/Shapes.kt`): how each is drawn from where
/// the pen landed to where it is. Names match Android's (they're saved in settings as "lastShape").
public enum ShapeKind: String, CaseIterable, Sendable {
  case LINE, ARROW, DOUBLE_ARROW, CIRCLE, ELLIPSE, ARC, CURVE, PART_CIRCLE, TRIANGLE, SQUARE, RECTANGLE, DIAMOND,
    PARALLELOGRAM, TRAPEZOID, PENTAGON, HEXAGON, STAR
  case PIN_SUPPORT, ROLLER_SUPPORT, FIXED_SUPPORT, POINT_LOAD, DISTRIBUTED_LOAD, MOMENT, DIMENSION

  /// How close (as a share of the side) a rectangle or ellipse snaps to a square or circle.
  public static let squareSnap: Float = 0.04

  public var engineering: Bool {
    switch self {
    case .PIN_SUPPORT, .ROLLER_SUPPORT, .FIXED_SUPPORT, .POINT_LOAD, .DISTRIBUTED_LOAD, .MOMENT, .DIMENSION: true
    default: false
    }
  }

  /// The shapes in the panel (Square only loads older choices: the rectangle snaps to a square).
  public static let offered: [ShapeKind] = allCases.filter { $0 != .SQUARE }

  /// Drawn like a line from one end to the other: its end keeps to tidy angles.
  public var drawnAsLine: Bool {
    switch self {
    case .LINE, .ARROW, .DOUBLE_ARROW, .DIMENSION, .POINT_LOAD, .FIXED_SUPPORT, .CURVE: true
    default: false
    }
  }

  /// Drawn out from a point (a support's tip, a moment's centre, a circle's centre).
  public var drawnFromPoint: Bool {
    switch self {
    case .PIN_SUPPORT, .ROLLER_SUPPORT, .MOMENT, .CIRCLE, .PART_CIRCLE: true
    default: false
    }
  }

  /// The shape as the Shapes tool draws it from [p0] to [p1]. Line-like kinds have their end put on
  /// a tidy angle first, unless [keepEnd] (Android's `buildShape`).
  public func drawn(_ p0: Pt, _ p1: Pt, keepEnd: Bool = false) -> ShapeGeometry {
    let end: Pt
    if !keepEnd && drawnAsLine, case let .line(_, b, _, _, _) = ShapeRecognizer.snappedLine(p0, p1) { end = b } else { end = p1 }
    return create(p0, end)
  }

  /// Most shapes fill the box between the points; the engineering symbols start at the point they attach to.
  public func create(_ p0: Pt, _ p1: Pt) -> ShapeGeometry {
    switch self {
    case .PIN_SUPPORT: return ShapeKind.pinSupportAt(p0, max(p0.dist(p1), 12))
    case .ROLLER_SUPPORT: return ShapeKind.rollerSupportAt(p0, max(p0.dist(p1), 12))
    case .FIXED_SUPPORT: return ShapeKind.fixedSupport(p0, p0.dist(p1) < 4 ? p0 + Pt(0, 40) : p1)
    case .POINT_LOAD: return .line(a: p0, b: p1, arrowStart: false, arrowEnd: true, ticks: false)
    case .MOMENT: return .arc(center: p0, radius: max(p0.dist(p1), 6), start: 0.75 * .pi, sweep: 1.5 * .pi, arrowEnd: true)
    case .CURVE: return ShapeKind.curveBetween(p0, p1)
    default: return inBox(p0, p1)
    }
  }

  /// This shape filling the box from [p0] to [p1] (the icons, and most shapes when drawn).
  public func inBox(_ p0: Pt, _ p1: Pt) -> ShapeGeometry {
    let l = min(p0.x, p1.x), r = max(p0.x, p1.x), t = min(p0.y, p1.y), b = max(p0.y, p1.y)
    let w = max(r - l, 4), h = max(b - t, 4)
    let c = Pt(l + w / 2, t + h / 2)
    let side = max(w, h)
    switch self {
    case .LINE: return .line(a: p0, b: p1, arrowStart: false, arrowEnd: false, ticks: false)
    case .ARROW: return .line(a: p0, b: p1, arrowStart: false, arrowEnd: true, ticks: false)
    case .DOUBLE_ARROW: return .line(a: p0, b: p1, arrowStart: true, arrowEnd: true, ticks: false)
    case .DIMENSION: return .line(a: p0, b: p1, arrowStart: true, arrowEnd: true, ticks: true)
    case .CIRCLE:
      let rr = p0.dist(p1)
      return .ellipse(center: p0, rx: rr, ry: rr, rotation: 0)
    case .ELLIPSE:
      var rx = w / 2, ry = h / 2
      if abs(rx - ry) < max(rx, ry) * ShapeKind.squareSnap {
        rx = max(rx, ry)
        ry = rx
      }
      return .ellipse(center: c, rx: rx, ry: ry, rotation: 0, stretchable: true)
    case .ARC: return .arc(center: c, radius: side / 2, start: .pi, sweep: .pi, arrowEnd: false)
    case .CURVE: return ShapeKind.curveBetween(Pt(l, b - h * 0.15), Pt(r, t + h * 0.15))
    case .PART_CIRCLE: return SectorShape.of(p0, p1, 0.5)
    case .TRIANGLE: return .triangle(a: Pt(c.x, t), b: Pt(r, t + h), c: Pt(l, t + h))
    case .SQUARE: return .poly(points: [Pt(l, t), Pt(l + side, t), Pt(l + side, t + side), Pt(l, t + side)], closed: true)
    case .RECTANGLE:
      if abs(w - h) < max(w, h) * ShapeKind.squareSnap {
        let sx: Float = p1.x >= p0.x ? 1 : -1, sy: Float = p1.y >= p0.y ? 1 : -1
        let q = Pt(p0.x + sx * side, p0.y + sy * side)
        let x0 = min(p0.x, q.x), x1 = max(p0.x, q.x), y0 = min(p0.y, q.y), y1 = max(p0.y, q.y)
        return .poly(points: [Pt(x0, y0), Pt(x1, y0), Pt(x1, y1), Pt(x0, y1)], closed: true)
      }
      return .poly(points: [Pt(l, t), Pt(r, t), Pt(r, b), Pt(l, b)], closed: true)
    case .DIAMOND: return .poly(points: [Pt(c.x, t), Pt(r, c.y), Pt(c.x, b), Pt(l, c.y)], closed: true, form: .DIAMOND)
    case .PARALLELOGRAM: return .poly(points: [Pt(l + w * 0.25, t), Pt(r, t), Pt(r - w * 0.25, b), Pt(l, b)], closed: true, form: .PARALLELOGRAM)
    case .TRAPEZOID: return .poly(points: [Pt(l + w * 0.22, t), Pt(r - w * 0.22, t), Pt(r, b), Pt(l, b)], closed: true, form: .TRAPEZOID)
    case .PENTAGON: return ShapeMaker.regularPolygon(c, side / 2, 5).keepingForm
    case .HEXAGON: return ShapeMaker.regularPolygon(c, side / 2, 6).keepingForm
    case .STAR: return ShapeMaker.star(c, side / 2).keepingForm
    case .PIN_SUPPORT: return ShapeKind.pinSupport(c, side)
    case .ROLLER_SUPPORT: return ShapeKind.rollerSupport(c, side)
    case .FIXED_SUPPORT: return ShapeKind.fixedSupport(Pt(c.x, c.y - side / 2), Pt(c.x, c.y + side / 2))
    case .POINT_LOAD: return .line(a: Pt(c.x, t), b: Pt(c.x, b), arrowStart: false, arrowEnd: true, ticks: false)
    case .DISTRIBUTED_LOAD: return .load(a: Pt(l, t), b: Pt(r, t), depth: b - t, count: ShapeKind.loadArrows(r - l))
    case .MOMENT: return .arc(center: c, radius: side / 2, start: 0.75 * .pi, sweep: 1.5 * .pi, arrowEnd: true)
    }
  }

  /// How many gaps a distributed load of [length] has (arrows about 28 units apart).
  public static func loadArrows(_ length: Float) -> Int { min(max(Int(length / 28), 2), 40) }

  /// A gentle bow from [a] to [b] through `curveDots` dots (Android's `CurveShape.between`).
  public static func curveBetween(_ a: Pt, _ b: Pt) -> ShapeGeometry {
    let d = b - a
    let len = d.length()
    let normal = len < 1e-3 ? Pt(0, -1) : Pt(d.y / len, -d.x / len)
    let bulge = len * 0.2
    return .curve(points: (0..<curveDots).map { (i: Int) -> Pt in
      let t = Float(i) / Float(curveDots - 1)
      if i == 0 { return a }
      if i == curveDots - 1 { return b }
      return a + d * t + normal * (bulge * sinf(.pi * t))
    })
  }

  private static func hatch(_ from: Pt, _ to: Pt, _ count: Int, _ offset: Pt) -> [ShapeGeometry] {
    (0..<count).map { i in
      let p = from + (to - from) * ((Float(i) + 0.5) / Float(count))
      return .line(a: p, b: p + offset, arrowStart: false, arrowEnd: false, ticks: false)
    }
  }

  private static func plain(_ a: Pt, _ b: Pt) -> ShapeGeometry { .line(a: a, b: b, arrowStart: false, arrowEnd: false, ticks: false) }

  static func pinSupport(_ c: Pt, _ size: Float) -> ShapeGeometry {
    let h = size * 0.6
    let top = Pt(c.x, c.y - h / 2), bl = Pt(c.x - h * 0.6, c.y + h / 2), br = Pt(c.x + h * 0.6, c.y + h / 2)
    let gl = Pt(bl.x - h * 0.25, bl.y), gr = Pt(br.x + h * 0.25, br.y)
    return .group([.poly(points: [top, br, bl], closed: true), plain(gl, gr)] + hatch(gl, gr, 6, Pt(-h * 0.18, h * 0.22)))
  }

  static func rollerSupport(_ c: Pt, _ size: Float) -> ShapeGeometry {
    let h = size * 0.5
    let top = Pt(c.x, c.y - h / 2), bl = Pt(c.x - h * 0.6, c.y + h * 0.25), br = Pt(c.x + h * 0.6, c.y + h * 0.25)
    let r = h * 0.14
    let wheelY = bl.y + r, groundY = wheelY + r
    let gl = Pt(bl.x - h * 0.25, groundY), gr = Pt(br.x + h * 0.25, groundY)
    return .group(
      [
        .poly(points: [top, br, bl], closed: true),
        .ellipse(center: Pt(c.x - h * 0.3, wheelY), rx: r, ry: r, rotation: 0),
        .ellipse(center: Pt(c.x + h * 0.3, wheelY), rx: r, ry: r, rotation: 0),
        plain(gl, gr),
      ] + hatch(gl, gr, 6, Pt(-h * 0.18, h * 0.22)))
  }

  static func pinSupportAt(_ apex: Pt, _ height: Float) -> ShapeGeometry {
    let size = height / 0.732
    return pinSupport(Pt(apex.x, apex.y + 0.3 * size), size)
  }

  static func rollerSupportAt(_ apex: Pt, _ height: Float) -> ShapeGeometry {
    let size = height / 0.625
    return rollerSupport(Pt(apex.x, apex.y + 0.25 * size), size)
  }

  static func fixedSupport(_ a: Pt, _ b: Pt) -> ShapeGeometry {
    let size = a.dist(b)
    let d = (b - a).normalized()
    let across = Pt(d.y, -d.x)
    let offset = across * (-size * 0.16) + d * (size * 0.12)
    return .group([plain(a, b)] + hatch(a, b, 7, offset))
  }
}
