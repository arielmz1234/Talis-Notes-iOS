import Foundation

/// A point (or vector) in world coordinates. World units are the Android app's dp: points at 100% zoom.
public struct Pt: Hashable, Codable, Sendable {
  public var x: Float
  public var y: Float

  public init(_ x: Float, _ y: Float) {
    self.x = x
    self.y = y
  }

  public static let zero = Pt(0, 0)

  public static func + (a: Pt, b: Pt) -> Pt { Pt(a.x + b.x, a.y + b.y) }
  public static func - (a: Pt, b: Pt) -> Pt { Pt(a.x - b.x, a.y - b.y) }
  public static func * (a: Pt, s: Float) -> Pt { Pt(a.x * s, a.y * s) }
  public static func / (a: Pt, s: Float) -> Pt { Pt(a.x / s, a.y / s) }

  public func length() -> Float { (x * x + y * y).squareRoot() }
  public func dist(_ o: Pt) -> Float { (self - o).length() }
  public func dot(_ o: Pt) -> Float { x * o.x + y * o.y }
  public func cross(_ o: Pt) -> Float { x * o.y - y * o.x }
  public func angle() -> Float { atan2f(y, x) }

  public func normalized() -> Pt {
    let l = length()
    return l < 1e-6 ? .zero : Pt(x / l, y / l)
  }

  public func rotated(_ radians: Float) -> Pt {
    let c = cosf(radians), s = sinf(radians)
    return Pt(x * c - y * s, x * s + y * c)
  }

  public func rotated(around center: Pt, by radians: Float) -> Pt { (self - center).rotated(radians) + center }

  public static func polar(_ radius: Float, _ radians: Float) -> Pt { Pt(radius * cosf(radians), radius * sinf(radians)) }

  // Stored as {"x":…,"y":…} like the Android app's kotlinx.serialization.
  enum CodingKeys: String, CodingKey { case x, y }
}

/// An axis-aligned rectangle in world coordinates.
public struct Rect: Hashable, Codable, Sendable {
  public var left: Float
  public var top: Float
  public var right: Float
  public var bottom: Float

  public init(_ left: Float, _ top: Float, _ right: Float, _ bottom: Float) {
    self.left = left
    self.top = top
    self.right = right
    self.bottom = bottom
  }

  public var width: Float { right - left }
  public var height: Float { bottom - top }
  public var center: Pt { Pt((left + right) / 2, (top + bottom) / 2) }
  public var isEmpty: Bool { width <= 0 || height <= 0 }

  public func intersects(_ o: Rect) -> Bool { left < o.right && o.left < right && top < o.bottom && o.top < bottom }
  public func contains(_ p: Pt) -> Bool { p.x >= left && p.x <= right && p.y >= top && p.y <= bottom }
  public func union(_ o: Rect) -> Rect { Rect(min(left, o.left), min(top, o.top), max(right, o.right), max(bottom, o.bottom)) }
  public func inset(_ d: Float) -> Rect { Rect(left + d, top + d, right - d, bottom - d) }
  public func outset(_ d: Float) -> Rect { inset(-d) }

  public static func around(_ points: some Sequence<Pt>) -> Rect? {
    var r: Rect?
    for p in points {
      r = r.map { Rect(min($0.left, p.x), min($0.top, p.y), max($0.right, p.x), max($0.bottom, p.y)) } ?? Rect(p.x, p.y, p.x, p.y)
    }
    return r
  }
}

/// A 2D affine transform with the Android app's field names and meaning, so stored shapes read the
/// same: x' = a·x + c·y + tx, y' = b·x + d·y + ty.
public struct Affine: Hashable, Codable, Sendable {
  public var a: Float, b: Float, c: Float, d: Float, tx: Float, ty: Float

  public init(a: Float = 1, b: Float = 0, c: Float = 0, d: Float = 1, tx: Float = 0, ty: Float = 0) {
    self.a = a
    self.b = b
    self.c = c
    self.d = d
    self.tx = tx
    self.ty = ty
  }

  public static let identity = Affine()

  public static func translate(_ dx: Float, _ dy: Float) -> Affine { Affine(tx: dx, ty: dy) }
  public static func scaleAround(_ p: Pt, _ sx: Float, _ sy: Float? = nil) -> Affine {
    let sy = sy ?? sx
    return Affine(a: sx, d: sy, tx: p.x - sx * p.x, ty: p.y - sy * p.y)
  }
  public static func rotateAround(_ p: Pt, _ radians: Float) -> Affine {
    let cs = cosf(radians), sn = sinf(radians)
    return Affine(a: cs, b: sn, c: -sn, d: cs, tx: p.x - cs * p.x + sn * p.y, ty: p.y - sn * p.x - cs * p.y)
  }

  public func apply(_ p: Pt) -> Pt { Pt(a * p.x + c * p.y + tx, b * p.x + d * p.y + ty) }

  /// This transform first, then [other] (as Android's `a.then(b)`: a applies first).
  public func then(_ other: Affine) -> Affine {
    Affine(
      a: other.a * a + other.c * b,
      b: other.b * a + other.d * b,
      c: other.a * c + other.c * d,
      d: other.b * c + other.d * d,
      tx: other.a * tx + other.c * ty + other.tx,
      ty: other.b * tx + other.d * ty + other.ty)
  }

  /// Uniform scale factor, for scaling brush sizes along with geometry.
  public var scaleFactor: Float { abs(a * d - b * c).squareRoot() }

  /// Whether it mirrors (turns clockwise into anticlockwise).
  public var mirrors: Bool { a * d - b * c < 0 }

  /// Where a direction at angle [t] points after this transform.
  public func mapAngle(_ t: Float) -> Float { atan2f(b * cosf(t) + d * sinf(t), a * cosf(t) + c * sinf(t)) }
}

public enum Geo {
  public static func pathLength(_ points: [Pt]) -> Float {
    var len: Float = 0
    for i in points.indices.dropFirst() { len += points[i].dist(points[i - 1]) }
    return len
  }

  /// Distance from [p] to the segment [a]-[b].
  public static func distToSegment(_ p: Pt, _ a: Pt, _ b: Pt) -> Float {
    let ab = b - a
    let lenSq = ab.dot(ab)
    if lenSq < 1e-9 { return p.dist(a) }
    let t = min(max((p - a).dot(ab) / lenSq, 0), 1)
    return p.dist(a + ab * t)
  }

  /// Perpendicular distance from [p] to the infinite line through [a] and [b].
  public static func distToLine(_ p: Pt, _ a: Pt, _ b: Pt) -> Float {
    let ab = b - a
    let len = ab.length()
    if len < 1e-6 { return p.dist(a) }
    return abs(ab.cross(p - a)) / len
  }
}
