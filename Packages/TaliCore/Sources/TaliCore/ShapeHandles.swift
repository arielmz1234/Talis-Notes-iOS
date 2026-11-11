import Foundation

// A shape's dots and what dragging one does, ported from Android's `model/Shapes.kt`
// (`handles()` and `withHandle()` of each shape class). Dots only change a shape's form; resizing
// the whole shape is the resize chip's job.

private let tau = Float.pi * 2
private let minScale: Float = 0.05
/// How close to square (as a share of the side) a rectangle being stretched snaps to a square.
private let squareSnap: Float = 0.04
/// The smallest arc or part circle an end dot can make: one degree.
private let minTurn = Float.pi / 180

/// Kotlin's `Math.round` for floats (half rounds up, also below zero).
func kround(_ x: Float) -> Float { (x + 0.5).rounded(.down) }

/// An angle in (0, 2π]: how far round from one end to the other, going the positive way.
func positiveTurn(_ a: Float) -> Float {
  var s = a.truncatingRemainder(dividingBy: tau)
  if s <= 0 { s += tau }
  return s
}

extension ShapeGeometry {
  /// The same polygon or star keeping [form] (the shape tools' pentagon, hexagon, star).
  public func withForm(_ form: PolyForm) -> ShapeGeometry {
    if case let .poly(points, closed, smooth, rotation, _) = self {
      return .poly(points: points, closed: closed, smooth: smooth, rotation: rotation, form: form)
    }
    return self
  }

  /// A closed four-cornered shape whose corners sit on the corners of its box in its own frame.
  public var isRect: Bool {
    guard case let .poly(points, closed, _, rotation, _) = self, closed, points.count == 4 else { return false }
    let c = Geo.centroid(points)
    let local = points.map { ($0 - c).rotated(-rotation) }
    let w = local.map(\.x).max()! - local.map(\.x).min()!
    let h = local.map(\.y).max()! - local.map(\.y).min()!
    if w < 1e-3 || h < 1e-3 { return false }
    return local.allSatisfy { q in abs(abs(q.x) - w / 2) < w * 0.02 && abs(abs(q.y) - h / 2) < h * 0.02 }
  }

  /// A rectangle with equal sides (a square).
  public var isSquare: Bool {
    guard isRect, case let .poly(points, _, _, _, _) = self else { return false }
    let a = points[0].dist(points[1]), b = points[1].dist(points[2])
    return abs(a - b) < max(a, b) * 0.005
  }

  /// An ellipse that's perfectly round.
  public var isRound: Bool {
    guard case let .ellipse(_, rx, ry, _, _) = self else { return false }
    return abs(rx - ry) < max(rx, ry) * 0.01
  }

  /// A circle from the Circle tool: one dot, on its edge, that sets the radius.
  public var isCircle: Bool {
    guard case let .ellipse(_, _, _, _, stretchable) = self else { return false }
    return isRound && !stretchable
  }

  /// Where its dots sit (none for shapes that only resize with the chip).
  public func handles() -> [Pt] {
    switch self {
    case let .line(a, b, _, _, _): return [a, b]
    case let .poly(points, _, smooth, _, form):
      if smooth || form == .REGULAR { return [] }
      if form == .DIAMOND && points.count == 4 { return [points[1], points[2]] }
      if (form == .PARALLELOGRAM || form == .TRAPEZOID) && points.count == 4 { return [points[0]] }
      if isRect { return points.indices.map { (points[$0] + points[($0 + 1) % 4]) * 0.5 } }
      return points
    case let .ellipse(center, rx, ry, rotation, _):
      func point(_ t: Float) -> Pt { center + Pt(rx * cosf(t), ry * sinf(t)).rotated(rotation) }
      return isCircle ? [point(0)] : [point(0), point(.pi / 2), point(.pi), point(1.5 * .pi)]
    case let .arc(center, radius, start, sweep, arrowEnd):
      // A moment (the arc with an arrow) keeps its form: no dots, only the resize chip.
      if arrowEnd { return [] }
      return [center + Pt.polar(radius, start), center + Pt.polar(radius, start + sweep), center + Pt.polar(radius, start + sweep / 2)]
    case let .curve(points): return points
    case let .sector(center, radius, start, sweep):
      return [center + Pt.polar(radius, start), center + Pt.polar(radius, start + sweep), center + Pt.polar(radius, start + sweep / 2)]
    case let .triangle(a, b, c, _): return [a, b, c]
    case let .load(a, b, depth, _):
      let d = (b - a).normalized()
      return [a, b, a + (b - a) * 0.5 + Pt(-d.y, d.x) * depth]
    case .group: return []
    case .param: return []  // its joints come with the templates, not ported yet
    }
  }

  /// Dot [index] dragged to [p].
  public func withHandle(_ index: Int, _ p: Pt) -> ShapeGeometry {
    switch self {
    case let .line(a, b, arrowStart, arrowEnd, ticks):
      // Moving an end lengthens or shortens the line. Within 2° of its direction the drag is
      // projected onto it, so it keeps its exact angle; beyond that it turns freely.
      let fixed = index == 0 ? b : a
      let moving = index == 0 ? a : b
      let dir = (moving - fixed).normalized()
      let v = p - fixed
      let cosAngle: Float = v.length() < 1e-3 ? 1 : dir.dot(v.normalized())
      let target = cosAngle > cosf(2 * .pi / 180) ? fixed + dir * max(1, v.dot(dir)) : p
      return index == 0
        ? .line(a: target, b: b, arrowStart: arrowStart, arrowEnd: arrowEnd, ticks: ticks)
        : .line(a: a, b: target, arrowStart: arrowStart, arrowEnd: arrowEnd, ticks: ticks)

    case let .poly(points, closed, smooth, rotation, form):
      if smooth || form == .REGULAR { return self }
      if form != nil && points.count == 4, let out = polyWithForm(index, p) { return out }
      if isRect { return polyWithSide(index, p) }
      // Any other polygon: each dot moves its own corner.
      var q = points
      q[index] = p
      return .poly(points: q, closed: closed, smooth: smooth, rotation: rotation, form: form)

    case let .ellipse(center, rx, ry, rotation, stretchable):
      if isCircle {
        // The dot sets the radius round the fixed centre and goes round with the pen, settling
        // level, upright or diagonal when close.
        let r = max(2, p.dist(center))
        var a = (p - center).angle()
        let step = Float.pi / 4
        let tidy = kround(a / step) * step
        if abs(a - tidy) < 0.1 { a = tidy }
        return .ellipse(center: center, rx: r, ry: r, rotation: a, stretchable: stretchable)
      }
      // An ellipse's dot stretches it one way, snapping round into a circle when close.
      let local = (p - center).rotated(-rotation)
      if index % 2 == 0 {
        var r = max(2, abs(local.x))
        if abs(r - ry) < ry * squareSnap { r = ry }
        return .ellipse(center: center, rx: r, ry: ry, rotation: rotation, stretchable: stretchable)
      }
      var r = max(2, abs(local.y))
      if abs(r - rx) < rx * squareSnap { r = rx }
      return .ellipse(center: center, rx: rx, ry: r, rotation: rotation, stretchable: stretchable)

    case let .arc(center, radius, start, sweep, arrowEnd):
      // An end slides round the same circle; the turn wraps (361° is 1°).
      let ang = (p - center).angle()
      let dir: Float = sweep < 0 ? -1 : 1
      switch index {
      case 0:
        let end = start + sweep
        let s = Self.snapArc(positiveTurn(dir * (end - ang))) * dir
        return .arc(center: center, radius: radius, start: end - s, sweep: s, arrowEnd: arrowEnd)
      case 1:
        return .arc(center: center, radius: radius, start: start, sweep: Self.snapArc(positiveTurn(dir * (ang - start))) * dir, arrowEnd: arrowEnd)
      default:
        // The middle: size and direction, keeping the same turn.
        return .arc(center: center, radius: max(4, p.dist(center)), start: ang - sweep / 2, sweep: sweep, arrowEnd: arrowEnd)
      }

    case let .curve(points):
      var q = points
      if q.indices.contains(index) { q[index] = p }
      return .curve(points: q)

    case let .sector(center, radius, start, sweep):
      let ang = (p - center).angle()
      switch index {
      case 0:
        let end = start + sweep
        let s = Self.snapSweep(positiveTurn(end - ang))
        return .sector(center: center, radius: radius, start: end - s, sweep: s)
      case 1:
        return .sector(center: center, radius: radius, start: start, sweep: Self.snapSweep(positiveTurn(ang - start)))
      default:
        return .sector(center: center, radius: max(4, p.dist(center)), start: ang - sweep / 2, sweep: sweep)
      }

    case let .triangle(a, b, c, turn):
      let pts = [a, b, c]
      let q = Self.snapCorner(pts[(index + 1) % 3], pts[(index + 2) % 3], p)
      switch index {
      case 0: return .triangle(a: q, b: b, c: c, turn: turn)
      case 1: return .triangle(a: a, b: q, c: c, turn: turn)
      default: return .triangle(a: a, b: b, c: q, turn: turn)
      }

    case let .load(a, b, depth, count):
      let d = (b - a).normalized()
      let across = Pt(-d.y, d.x)
      if index == 2 {
        // The arrows' length (dragged across the line, they hang the other way).
        let dd = (p - (a + (b - a) * 0.5)).dot(across)
        return .load(a: a, b: b, depth: abs(dd) < 6 ? (dd < 0 ? -6 : 6) : dd, count: count)
      }
      let na = index == 0 ? p : a, nb = index == 0 ? b : p
      if na.dist(nb) < 8 { return self }
      // The arrows keep hanging on the same side as the line turns, and keep their spacing.
      let nd = (nb - na).normalized()
      let keepSide: Float = Pt(-nd.y, nd.x).dot(across) < 0 ? -1 : 1
      return .load(a: na, b: nb, depth: depth * keepSide, count: ShapeKind.loadArrows(na.dist(nb)))

    case let .group(parts, _):
      // Scales the group evenly round the corner opposite corner [index] (no dots offer it now).
      guard let r = Rect.around(parts.flatMap { $0.paths(1).joined() }) else { return self }
      let h = [Pt(r.left, r.top), Pt(r.right, r.top), Pt(r.right, r.bottom), Pt(r.left, r.bottom)]
      let anchor = h[(index + 2) % 4]
      let oldDiag = h[index].dist(anchor)
      if oldDiag < 1 { return self }
      let s = min(max(p.dist(anchor) / oldDiag, 0.05), 20)
      return transformed(Affine.scaleAround(anchor, s))

    case .param:
      return self
    }
  }

  /// A side's middle dot moves that side only; dragged past the opposite side, the rectangle turns
  /// over and keeps growing. Within `squareSnap` of square it snaps to an exact square.
  private func polyWithSide(_ side: Int, _ p: Pt) -> ShapeGeometry {
    guard case let .poly(points, closed, smooth, theta, form) = self else { return self }
    let c = Geo.centroid(points)
    let local = points.map { ($0 - c).rotated(-theta) }
    let target = (p - c).rotated(-theta)
    let mid = (local[side] + local[(side + 1) % 4]) * 0.5
    let l = local.map(\.x).min()!, r = local.map(\.x).max()!
    let t = local.map(\.y).min()!, b = local.map(\.y).max()!
    let w = r - l, h = b - t
    let horizontal = abs(mid.x) / w > abs(mid.y) / h
    func signedSize(_ reach: Float, _ was: Float, _ other: Float) -> Float {
      let sign: Float = reach < 0 ? -1 : 1
      var size = max(abs(reach), was * minScale)
      if abs(size - other) < other * squareSnap { size = other }
      return sign * size
    }
    let out: [Pt]
    if horizontal {
      let anchor = mid.x > 0 ? l : r
      let toward: Float = mid.x > 0 ? 1 : -1
      let sx = signedSize((target.x - anchor) * toward, w, h) / w
      out = local.map { Pt(anchor + ($0.x - anchor) * sx, $0.y) }
    } else {
      let anchor = mid.y > 0 ? t : b
      let toward: Float = mid.y > 0 ? 1 : -1
      let sy = signedSize((target.y - anchor) * toward, h, w) / h
      out = local.map { Pt($0.x, anchor + ($0.y - anchor) * sy) }
    }
    return .poly(points: out.map { c + $0.rotated(theta) }, closed: closed, smooth: smooth, rotation: theta, form: form)
  }

  /// A basic shape's own dot, in its own frame: a diamond's right and bottom points stretch it evenly
  /// (snapping square), a parallelogram's top-left corner sets its slant, a trapezoid's how narrow its top is.
  private func polyWithForm(_ index: Int, _ p: Pt) -> ShapeGeometry? {
    guard case let .poly(points, closed, smooth, rotation, form) = self else { return nil }
    let c = Geo.centroid(points)
    let local = points.map { ($0 - c).rotated(-rotation) }
    let target = (p - c).rotated(-rotation)
    let out: [Pt]
    switch form {
    case .DIAMOND:
      // Points: top, right, bottom, left, each on its own axis about the middle.
      var hw = abs(local[1].x), hh = abs(local[2].y)
      if index == 0 { hw = max(abs(target.x), hh * minScale) } else { hh = max(abs(target.y), hw * minScale) }
      if abs(hw - hh) < max(hw, hh) * squareSnap { if index == 0 { hw = hh } else { hh = hw } }
      let sx: Float = local[1].x < 0 ? -1 : 1, sy: Float = local[2].y < 0 ? -1 : 1
      out = [Pt(0, -hh * sy), Pt(hw * sx, 0), Pt(0, hh * sy), Pt(-hw * sx, 0)]
    case .PARALLELOGRAM:
      // Points: top-left, top-right, bottom-right, bottom-left; the bottom side stays.
      let x0 = local[3].x
      let a = local[2].x - local[3].x
      var slant = min(max(target.x - x0, -2 * abs(a)), 2 * abs(a))
      if abs(slant) < abs(a) * 0.03 { slant = 0 }
      let t = local[0].y
      out = [Pt(x0 + slant, t), Pt(x0 + slant + a, t), local[2], local[3]]
    case .TRAPEZOID:
      let xl = local[3].x, xr = local[2].x
      let w = xr - xl
      let sgn: Float = w < 0 ? -1 : 1
      var inset = min(max((target.x - xl) * sgn, -abs(w) * 0.45), abs(w) * 0.48)
      if abs(inset) < abs(w) * 0.02 { inset = 0 }
      let t = local[0].y
      out = [Pt(xl + inset * sgn, t), Pt(xr - inset * sgn, t), local[2], local[3]]
    default:
      return nil
    }
    return .poly(points: out.map { c + $0.rotated(rotation) }, closed: closed, smooth: smooth, rotation: rotation, form: form)
  }

  /// Gently onto whole 15° steps (30°, 45°, 90°...), so the usual angles are easy to hit.
  static func snapArc(_ s: Float) -> Float {
    let step = Float.pi / 12
    let snapped = kround(s / step) * step
    return snapped > 0 && abs(s - snapped) < 0.03 ? snapped : max(s, minTurn)
  }

  /// Snaps to quarters (strongly) and to whole 5% steps, so 25%, 50% and 75% are easy to hit exactly.
  public static func snapSweep(_ s: Float) -> Float {
    let f = s / tau
    // A whole circle only when really close: a wide catch made it stick shut.
    if f > 0.995 { return tau }
    let quarter = kround(f * 4) / 4
    if abs(f - quarter) < 0.025 && quarter > 0 && quarter < 1 { return quarter * tau }
    let five = kround(f * 20) / 20
    if abs(f - five) < 0.01 && five > 0 && five < 1 { return five * tau }
    return min(max(s, minTurn), tau)
  }

  /// How close (in degrees) a right angle or two equal angles pull.
  private static let pull: Float = 3

  /// One angle locked to the nearest 15° within 2.5°, else the nearest 5° within 1°, else the whole degree.
  public static func lockAngle(_ x: Float) -> Float {
    let fifteen = kround(x / 15) * 15
    if abs(x - fifteen) < 2.5 { return fifteen }
    let five = kround(x / 5) * 5
    if abs(x - five) < 1 { return five }
    return kround(x)
  }

  /// Where the triangle corner dragged to [p] settles, with the other two at [fa] and [fb]: the
  /// angles at those corners are locked (a right angle, two equal, or `lockAngle`), and the corner
  /// goes where the two sides meet, on the side it was dragged.
  public static func snapCorner(_ fa: Pt, _ fb: Pt, _ p: Pt) -> Pt {
    func deg(_ r: Float) -> Float { r * 180 / .pi }
    let base = fb - fa
    let len = base.length()
    let side = base.cross(p - fa)
    if len < 1 || abs(side) < 1e-3 { return p }
    let ra = deg(Geo.interiorAngle(fb, fa, p))
    let rb = deg(Geo.interiorAngle(fa, fb, p))
    let rp = 180 - ra - rb
    if ra < 1 || rb < 1 || rp < 1 { return p }
    var sa: Float, sb: Float
    if abs(ra - 90) < pull { sa = 90; sb = lockAngle(rb) }
    else if abs(rb - 90) < pull { sb = 90; sa = lockAngle(ra) }
    else if abs(rp - 90) < pull { sa = lockAngle(ra); sb = 90 - sa }
    else if abs(ra - rb) < pull { sa = lockAngle((ra + rb) / 2); sb = sa }
    else if abs(rb - rp) < pull { sb = lockAngle((rb + rp) / 2); sa = 180 - 2 * sb }
    else if abs(ra - rp) < pull { sa = lockAngle((ra + rp) / 2); sb = 180 - 2 * sa }
    else { sa = lockAngle(ra); sb = lockAngle(rb) }
    if sa < 1 || sb < 1 || sa + sb > 179 { return p }
    let toA = sa * .pi / 180, toB = sb * .pi / 180
    let reach = len * sinf(toB) / sinf(toA + toB)
    let dir = base.normalized().rotated(side > 0 ? toA : -toA)
    return fa + dir * reach
  }

  /// A triangle's angles at a, b and c, in degrees.
  public var triangleAngles: [Float]? {
    guard case let .triangle(a, b, c, _) = self else { return nil }
    func deg(_ r: Float) -> Float { r * 180 / .pi }
    return [deg(Geo.interiorAngle(c, a, b)), deg(Geo.interiorAngle(a, b, c)), deg(Geo.interiorAngle(b, c, a))]
  }
}
