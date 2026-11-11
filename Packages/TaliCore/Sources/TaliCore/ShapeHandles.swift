import Foundation

private let tau = Float.pi * 2
private let minScale: Float = 0.05
private let minTurn = Float.pi / 180

/// Java's `Math.round`: halves go up (Swift's `rounded()` sends -2.5 to -3, Java to -2).
func javaRound(_ x: Float) -> Float { (x + 0.5).rounded(.down) }


func positiveTurn(_ a: Float) -> Float {
  var s = a.truncatingRemainder(dividingBy: tau)
  if s <= 0 { s += tau }
  return s
}

private func snapArc(_ s: Float) -> Float {
  let step = Float.pi / 12
  let snapped = javaRound(s / step) * step
  return snapped > 0 && abs(s - snapped) < 0.03 ? snapped : max(s, minTurn)
}

public enum TriangleShape {
  private static let pull: Float = 3

  public static func lockAngle(_ x: Float) -> Float {
    let fifteen = javaRound(x / 15) * 15
    if abs(x - fifteen) < 2.5 { return fifteen }
    let five = javaRound(x / 5) * 5
    if abs(x - five) < 1 { return five }
    return javaRound(x)
  }

  public static func snapCorner(_ fa: Pt, _ fb: Pt, _ p: Pt) -> Pt {
    let base = fb - fa
    let len = base.length()
    let side = base.cross(p - fa)
    if len < 1 || abs(side) < 1e-3 { return p }
    let ra = degrees(Geo.interiorAngle(fb, fa, p))
    let rb = degrees(Geo.interiorAngle(fa, fb, p))
    let rp = 180 - ra - rb
    if ra < 1 || rb < 1 || rp < 1 { return p }
    var sa: Float, sb: Float
    if abs(ra - 90) < pull {
      sa = 90
      sb = lockAngle(rb)
    } else if abs(rb - 90) < pull {
      sb = 90
      sa = lockAngle(ra)
    } else if abs(rp - 90) < pull {
      sa = lockAngle(ra)
      sb = 90 - sa
    } else if abs(ra - rb) < pull {
      sa = lockAngle((ra + rb) / 2)
      sb = sa
    } else if abs(rb - rp) < pull {
      sb = lockAngle((rb + rp) / 2)
      sa = 180 - 2 * sb
    } else if abs(ra - rp) < pull {
      sa = lockAngle((ra + rp) / 2)
      sb = 180 - 2 * sa
    } else {
      sa = lockAngle(ra)
      sb = lockAngle(rb)
    }
    if sa < 1 || sb < 1 || sa + sb > 179 { return p }
    let toA = Float(Double(sa) * .pi / 180), toB = Float(Double(sb) * .pi / 180)
    let reach = len * sinf(toB) / sinf(toA + toB)
    let dir = base.normalized().rotated(side > 0 ? toA : -toA)
    return fa + dir * reach
  }
}

public enum SectorShape {
  public static func of(_ center: Pt, _ toward: Pt, _ fraction: Float) -> ShapeGeometry {
    let sweep = tau * min(max(fraction, 0.01), 1)
    let dir = toward.dist(center) < 0.5 ? -Float.pi / 2 : (toward - center).angle()
    return .sector(center: center, radius: max(4, toward.dist(center)), start: dir - sweep / 2, sweep: sweep)
  }

  /// A whole circle only when really close: a wide catch there made it stick shut.
  public static func snapSweep(_ s: Float) -> Float {
    let f = s / tau
    if f > 0.995 { return tau }
    let quarter = javaRound(f * 4) / 4
    if abs(f - quarter) < 0.025 && quarter > 0 && quarter < 1 { return quarter * tau }
    let five = javaRound(f * 20) / 20
    if abs(f - five) < 0.01 && five > 0 && five < 1 { return five * tau }
    return min(max(s, minTurn), tau)
  }
}

extension ShapeGeometry {
  public func handles() -> [Pt] {
    switch self {
    case let .line(a, b, _, _, _): return [a, b]
    case let .poly(points, _, smooth, _, form):
      if smooth || form == .REGULAR { return [] }
      if form == .DIAMOND, points.count == 4 { return [points[1], points[2]] }
      if form == .PARALLELOGRAM || form == .TRAPEZOID, points.count == 4 { return [points[0]] }
      if isRect { return (0..<4).map { (points[$0] + points[($0 + 1) % 4]) * 0.5 } }
      return points
    case .ellipse:
      return isCircle ? [ellipsePoint(0)] : [ellipsePoint(0), ellipsePoint(.pi / 2), ellipsePoint(.pi), ellipsePoint(1.5 * .pi)]
    case let .arc(center, radius, start, sweep, arrowEnd):
      // A moment (the arc with an arrow) keeps its form: no end dots.
      if arrowEnd { return [] }
      return [center + .polar(radius, start), center + .polar(radius, start + sweep), center + .polar(radius, start + sweep / 2)]
    case let .curve(points): return points
    case let .sector(center, radius, start, sweep):
      return [center + .polar(radius, start), center + .polar(radius, start + sweep), center + .polar(radius, start + sweep / 2)]
    case let .triangle(a, b, c, _): return [a, b, c]
    case let .load(a, b, depth, _): return [a, b, a + (b - a) * 0.5 + Self.across(a, b) * depth]
    case .group, .param: return []
    }
  }

  public func withHandle(_ index: Int, _ p: Pt) -> ShapeGeometry {
    switch self {
    case let .line(a, b, arrowStart, arrowEnd, ticks):
      // Within 2° of its direction the drag is projected onto it, so the line keeps its exact angle
      // while its length changes; beyond that it turns freely.
      let fixed = index == 0 ? b : a, moving = index == 0 ? a : b
      let dir = (moving - fixed).normalized()
      let v = p - fixed
      let cosAngle: Float = v.length() < 1e-3 ? 1 : dir.dot(v.normalized())
      let target = cosAngle > Float(cos(2.0 * Double.pi / 180)) ? fixed + dir * max(1, v.dot(dir)) : p
      return .line(a: index == 0 ? target : a, b: index == 0 ? b : target, arrowStart: arrowStart, arrowEnd: arrowEnd, ticks: ticks)
    case let .poly(points, closed, smooth, rotation, form):
      if smooth || form == .REGULAR { return self }
      if form != nil, points.count == 4, let shaped = withForm(index, p) { return shaped }
      if isRect { return withSide(index, p) }
      guard points.indices.contains(index) else { return self }
      var moved = points
      moved[index] = p
      return .poly(points: moved, closed: closed, smooth: smooth, rotation: rotation, form: form)
    case let .ellipse(center, rx, ry, rotation, stretchable):
      if isCircle {
        // Level, upright or diagonal when close, so its radius line reads tidily.
        let r = max(2, p.dist(center))
        var a = (p - center).angle()
        let step = Float.pi / 4
        let tidy = javaRound(a / step) * step
        if abs(a - tidy) < 0.1 { a = tidy }
        return .ellipse(center: center, rx: r, ry: r, rotation: a, stretchable: stretchable)
      }
      let local = (p - center).rotated(-rotation)
      if index % 2 == 0 {
        var r = max(2, abs(local.x))
        if abs(r - ry) < ry * ShapeKind.squareSnap { r = ry }
        return .ellipse(center: center, rx: r, ry: ry, rotation: rotation, stretchable: stretchable)
      }
      var r = max(2, abs(local.y))
      if abs(r - rx) < rx * ShapeKind.squareSnap { r = rx }
      return .ellipse(center: center, rx: rx, ry: r, rotation: rotation, stretchable: stretchable)
    case let .arc(center, radius, start, sweep, arrowEnd):
      // An end slides round the same circle; the turn wraps (361° is 1°), so an end can be dragged
      // round either way. The arc keeps its direction.
      let ang = (p - center).angle()
      let dir: Float = sweep < 0 ? -1 : 1
      switch index {
      case 0:
        let end = start + sweep
        let s = snapArc(positiveTurn(dir * (end - ang))) * dir
        return .arc(center: center, radius: radius, start: end - s, sweep: s, arrowEnd: arrowEnd)
      case 1:
        return .arc(center: center, radius: radius, start: start, sweep: snapArc(positiveTurn(dir * (ang - start))) * dir, arrowEnd: arrowEnd)
      default:
        return .arc(center: center, radius: max(4, p.dist(center)), start: ang - sweep / 2, sweep: sweep, arrowEnd: arrowEnd)
      }
    case let .curve(points):
      guard points.indices.contains(index) else { return self }
      var moved = points
      moved[index] = p
      return .curve(points: moved)
    case let .sector(center, radius, start, sweep):
      let ang = (p - center).angle()
      switch index {
      case 0:
        let end = start + sweep
        let s = SectorShape.snapSweep(positiveTurn(end - ang))
        return .sector(center: center, radius: radius, start: end - s, sweep: s)
      case 1:
        return .sector(center: center, radius: radius, start: start, sweep: SectorShape.snapSweep(positiveTurn(ang - start)))
      default:
        return .sector(center: center, radius: max(4, p.dist(center)), start: ang - sweep / 2, sweep: sweep)
      }
    case let .triangle(a, b, c, turn):
      guard index >= 0 else { return self }
      let corners = [a, b, c]
      let q = TriangleShape.snapCorner(corners[(index + 1) % 3], corners[(index + 2) % 3], p)
      switch index {
      case 0: return .triangle(a: q, b: b, c: c, turn: turn)
      case 1: return .triangle(a: a, b: q, c: c, turn: turn)
      default: return .triangle(a: a, b: b, c: q, turn: turn)
      }
    case let .load(a, b, depth, count):
      let across = Self.across(a, b)
      if index == 2 {
        let d = (p - (a + (b - a) * 0.5)).dot(across)
        return .load(a: a, b: b, depth: abs(d) < 6 ? (d < 0 ? -6 : 6) : d, count: count)
      }
      let na = index == 0 ? p : a, nb = index == 0 ? b : p
      if na.dist(nb) < 8 { return self }
      // The arrows keep hanging on the same side as the line turns, and keep their spacing.
      let keepSide: Float = Self.across(na, nb).dot(across) < 0 ? -1 : 1
      return .load(a: na, b: nb, depth: depth * keepSide, count: ShapeKind.loadArrows(na.dist(nb)))
    case .group, .param: return self
    }
  }

  /// Without snapping onto other shapes, which Android's `HANDLE_DRAG` does first (not ported).
  public func dragging(_ index: Int, to p: Pt) -> ShapeGeometry {
    func tidy(_ fixed: Pt, _ end: Pt) -> Pt {
      if case let .line(_, b, _, _, _) = ShapeRecognizer.snappedLine(fixed, end) { return b }
      return end
    }
    if case let .load(a, b, _, _) = self, index < 2 { return withHandle(index, tidy(index == 0 ? b : a, p)) }
    let g = withHandle(index, p)
    guard case let .line(a, b, arrowStart, arrowEnd, ticks) = g else { return g }
    return .line(a: index == 1 ? a : tidy(b, a), b: index == 1 ? tidy(a, b) : b, arrowStart: arrowStart, arrowEnd: arrowEnd, ticks: ticks)
  }

  private static func across(_ a: Pt, _ b: Pt) -> Pt {
    let d = (b - a).normalized()
    return Pt(-d.y, d.x)
  }

  public var isRect: Bool {
    guard case let .poly(points, true, _, rotation, _) = self, points.count == 4 else { return false }
    let c = Geo.centroid(points)
    let local = points.map { ($0 - c).rotated(-rotation) }
    guard let box = Rect.around(local) else { return false }
    let w = box.width, h = box.height
    if w < 1e-3 || h < 1e-3 { return false }
    return local.allSatisfy { abs(abs($0.x) - w / 2) < w * 0.02 && abs(abs($0.y) - h / 2) < h * 0.02 }
  }

  public var isSquare: Bool {
    guard isRect, case let .poly(points, _, _, _, _) = self else { return false }
    let a = points[0].dist(points[1]), b = points[1].dist(points[2])
    return abs(a - b) < max(a, b) * 0.005
  }

  public var round: Bool {
    guard case let .ellipse(_, rx, ry, _, _) = self else { return false }
    return abs(rx - ry) < max(rx, ry) * 0.01
  }

  public var isCircle: Bool {
    guard case let .ellipse(_, _, _, _, stretchable) = self else { return false }
    return round && !stretchable
  }

  public func ellipsePoint(_ t: Float) -> Pt {
    guard case let .ellipse(center, rx, ry, rotation, _) = self else { return .zero }
    return center + Pt(rx * cosf(t), ry * sinf(t)).rotated(rotation)
  }

  public var arcDegrees: Int {
    guard case let .arc(_, _, _, sweep, _) = self else { return 0 }
    return Int((Double(abs(sweep)) * 180 / .pi + 0.5).rounded(.down))
  }

  public var sectorFraction: Float {
    guard case let .sector(_, _, _, sweep) = self else { return 0 }
    return min(max(abs(sweep) / tau, 0), 1)
  }

  public var triangleAngles: [Float] {
    guard case let .triangle(a, b, c, _) = self else { return [] }
    return [degrees(Geo.interiorAngle(c, a, b)), degrees(Geo.interiorAngle(a, b, c)), degrees(Geo.interiorAngle(b, c, a))]
  }

  var keepingForm: ShapeGeometry {
    guard case let .poly(points, closed, smooth, rotation, _) = self else { return self }
    return .poly(points: points, closed: closed, smooth: smooth, rotation: rotation, form: .REGULAR)
  }

  private func withSide(_ side: Int, _ p: Pt) -> ShapeGeometry {
    guard case let .poly(points, closed, smooth, theta, form) = self, (0..<4).contains(side) else { return self }
    let c = Geo.centroid(points)
    let local = points.map { ($0 - c).rotated(-theta) }
    let target = (p - c).rotated(-theta)
    let mid = (local[side] + local[(side + 1) % 4]) * 0.5
    guard let box = Rect.around(local) else { return self }
    let w = box.width, h = box.height
    let horizontal = abs(mid.x) / w > abs(mid.y) / h
    // The scale is signed: past the opposite side it's negative, and the rectangle turns over.
    func signedSize(_ reach: Float, _ was: Float, _ other: Float) -> Float {
      let sign: Float = reach < 0 ? -1 : 1
      var size = max(abs(reach), was * minScale)
      if abs(size - other) < other * ShapeKind.squareSnap { size = other }
      return sign * size
    }
    let out: [Pt]
    if horizontal {
      let anchor = mid.x > 0 ? box.left : box.right
      let toward: Float = mid.x > 0 ? 1 : -1
      let sx = signedSize((target.x - anchor) * toward, w, h) / w
      out = local.map { Pt(anchor + ($0.x - anchor) * sx, $0.y) }
    } else {
      let anchor = mid.y > 0 ? box.top : box.bottom
      let toward: Float = mid.y > 0 ? 1 : -1
      let sy = signedSize((target.y - anchor) * toward, h, w) / h
      out = local.map { Pt($0.x, anchor + ($0.y - anchor) * sy) }
    }
    return .poly(points: out.map { c + $0.rotated(theta) }, closed: closed, smooth: smooth, rotation: theta, form: form)
  }

  private func withForm(_ index: Int, _ p: Pt) -> ShapeGeometry? {
    guard case let .poly(points, closed, smooth, rotation, form) = self, points.count == 4 else { return nil }
    let c = Geo.centroid(points)
    let local = points.map { ($0 - c).rotated(-rotation) }
    let target = (p - c).rotated(-rotation)
    let out: [Pt]
    switch form {
    case .DIAMOND:
      var hw = abs(local[1].x), hh = abs(local[2].y)
      if index == 0 { hw = max(abs(target.x), hh * minScale) } else { hh = max(abs(target.y), hw * minScale) }
      if abs(hw - hh) < max(hw, hh) * ShapeKind.squareSnap {
        if index == 0 { hw = hh } else { hh = hw }
      }
      let sx: Float = local[1].x < 0 ? -1 : 1, sy: Float = local[2].y < 0 ? -1 : 1
      out = [Pt(0, -hh * sy), Pt(hw * sx, 0), Pt(0, hh * sy), Pt(-hw * sx, 0)]
    case .PARALLELOGRAM:
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
    default: return nil
    }
    return .poly(points: out.map { c + $0.rotated(rotation) }, closed: closed, smooth: smooth, rotation: rotation, form: form)
  }
}
