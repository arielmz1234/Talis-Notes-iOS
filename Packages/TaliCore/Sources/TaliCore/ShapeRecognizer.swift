import Foundation

// A port of the Android app's `geometry/ShapeRecognizer.kt` (hold-to-shape), with the `Geo` helpers it
// needs from `geometry/Pt.kt`. Same thresholds, same order of tries; keep the two in step.

extension Geo {
  /// [n] points evenly spaced along the path (Android's `Geo.resample`).
  public static func resample(_ points: [Pt], _ n: Int) -> [Pt] {
    if points.count < 2 || n < 2 { return points }
    let total = pathLength(points)
    if total < 1e-6 { return Array(repeating: points[0], count: n) }
    let step = total / Float(n - 1)
    var out: [Pt] = [points[0]]
    out.reserveCapacity(n)
    var acc: Float = 0
    var prev = points[0]
    var i = 1
    while i < points.count && out.count < n - 1 {
      let cur = points[i]
      let d = prev.dist(cur)
      if acc + d >= step && d > 0 {
        let t = (step - acc) / d
        let q = prev + (cur - prev) * t
        out.append(q)
        prev = q
        acc = 0
      } else {
        acc += d
        prev = cur
        i += 1
      }
    }
    while out.count < n { out.append(points[points.count - 1]) }
    return out
  }

  /// Ramer-Douglas-Peucker simplification of an open polyline.
  public static func simplify(_ points: [Pt], _ epsilon: Float) -> [Pt] {
    if points.count < 3 { return points }
    var keep = [Bool](repeating: false, count: points.count)
    keep[0] = true
    keep[points.count - 1] = true
    var stack = [(0, points.count - 1)]
    while let (s, e) = stack.popLast() {
      var maxD: Float = 0
      var idx = -1
      if e > s + 1 {
        for i in (s + 1)..<e {
          let d = distToSegment(points[i], points[s], points[e])
          if d > maxD {
            maxD = d
            idx = i
          }
        }
      }
      if idx != -1 && maxD > epsilon {
        keep[idx] = true
        stack.append((s, idx))
        stack.append((idx, e))
      }
    }
    return points.indices.filter { keep[$0] }.map { points[$0] }
  }

  public static func meanDistToPolyline(_ points: [Pt], _ poly: [Pt], closed: Bool) -> Float {
    if poly.count < 2 || points.isEmpty { return .greatestFiniteMagnitude }
    let edges = closed ? poly.count : poly.count - 1
    var sum: Float = 0
    for p in points {
      var best = Float.greatestFiniteMagnitude
      for i in 0..<edges {
        let d = distToSegment(p, poly[i], poly[(i + 1) % poly.count])
        if d < best { best = d }
      }
      sum += best
    }
    return sum / Float(points.count)
  }

  public static func centroid(_ points: [Pt]) -> Pt {
    var sx: Float = 0, sy: Float = 0
    for p in points {
      sx += p.x
      sy += p.y
    }
    return Pt(sx / Float(points.count), sy / Float(points.count))
  }
}

public enum ShapeMaker {
  public static func regularPolygon(_ center: Pt, _ radius: Float, _ n: Int, rotation: Float = -.pi / 2) -> ShapeGeometry {
    .poly(points: (0..<n).map { center + Pt.polar(radius, rotation + 2 * .pi * Float($0) / Float(n)) }, closed: true)
  }

  public static func star(_ center: Pt, _ radius: Float, rotation: Float = -.pi / 2) -> ShapeGeometry {
    .poly(points: (0..<10).map { center + Pt.polar($0 % 2 == 0 ? radius : radius * 0.42, rotation + 2 * .pi * Float($0) / 10) }, closed: true)
  }
}

/// How many dots a curve has (Android's `CURVE_DOTS`).
public let curveDots = 5

/// Turns a hand-drawn stroke into clean geometry: lines, arrows, arcs, curves, an L or Z, circles,
/// ellipses, triangles, rectangles, squares, diamonds and other polygons, and stars. Returns nil when
/// the stroke doesn't clearly look like any of them, so the ink stays as drawn.
public enum ShapeRecognizer {
  private static let deg = Float.pi / 180
  private static let gentleBend: Float = 0.14
  private static let cornerTurn: Float = 40 * deg
  private static let sharpCorner: Float = 35 * deg
  private static let hookTurn: Float = 50 * deg
  private static let hook: Float = 0.08
  private static let arcMin: Float = 40 * deg
  private static let arcMax: Float = 300 * deg
  private static let halfSnap: Float = 15 * deg
  private static let levelSnap: Float = 10 * deg
  public static let lineSnapDeg: Float = 6

  public static func recognize(_ raw: [Pt]) -> ShapeGeometry? {
    let points = dedupe(raw)
    if points.count < 2 { return nil }
    guard let box = Rect.around(points) else { return nil }
    let diag = (box.width * box.width + box.height * box.height).squareRoot()
    if diag < 10 { return nil }
    let length = Geo.pathLength(points)
    let closedAt = closingIndex(points, diag, length)
    let shape = closedAt >= 0 ? recognizeClosed(Array(points[0...closedAt]), diag) : recognizeOpen(points, diag, length)
    return asTriangle(shape)
  }

  /// A three-cornered closed shape becomes a triangle, whose corners move one at a time.
  public static func asTriangle(_ g: ShapeGeometry?) -> ShapeGeometry? {
    if case let .poly(p, true, _, _)? = g, p.count == 3 { return .triangle(a: p[0], b: p[1], c: p[2]) }
    return g
  }

  static func dedupe(_ points: [Pt]) -> [Pt] {
    var out: [Pt] = []
    out.reserveCapacity(points.count)
    for p in points where out.isEmpty || out[out.count - 1].dist(p) > 0.5 { out.append(p) }
    return out
  }

  /// Index where the stroke meets its start again, or -1 when it's open.
  private static func closingIndex(_ points: [Pt], _ diag: Float, _ length: Float) -> Int {
    if length < 1.6 * diag { return -1 }
    let start = points[0]
    var best = -1
    var bestD = Float.greatestFiniteMagnitude
    var travelled: Float = 0
    for i in 1..<points.count {
      travelled += points[i].dist(points[i - 1])
      if travelled < length * 0.6 { continue }
      let d = points[i].dist(start)
      if d < bestD {
        bestD = d
        best = i
      }
    }
    return best >= 0 && bestD < 0.22 * diag ? best : -1
  }

  // MARK: Open strokes

  private static func recognizeOpen(_ points: [Pt], _ diag: Float, _ length: Float) -> ShapeGeometry? {
    let a = points[0], b = points[points.count - 1]
    let chord = a.dist(b)
    if chord > 0 {
      let maxDev = points.map { Geo.distToLine($0, a, b) }.max() ?? 0
      if maxDev < max(0.07 * chord, 3) && length < 1.3 * chord { return snappedLine(a, b) }
    }
    let simplified = Geo.simplify(points, max(0.08 * diag, 5))
    if let arrow = arrow(simplified) { return arrow }
    let body = withoutHooks(points)
    if let arc = fitArc(body, diag) { return arc }
    if !hasCorner(body), let curve = fitCurve(body, diag) { return curve }
    if (3...4).contains(simplified.count) {
      let fit = Geo.meanDistToPolyline(points, simplified, closed: false)
      let sides = (0..<(simplified.count - 1)).map { simplified[$0].dist(simplified[$0 + 1]) }
      let sharp = (1..<(simplified.count - 1)).allSatisfy { i in turnAt(simplified[i - 1], simplified[i], simplified[i + 1]) > sharpCorner }
      if fit < 0.03 * diag && sharp && sides.allSatisfy({ $0 > 0.15 * length }) { return .poly(points: simplified, closed: false) }
    }
    return nil
  }

  /// How much the path turns at [b] coming from [a] and going on to [c] (radians, 0 = straight on).
  private static func turnAt(_ a: Pt, _ b: Pt, _ c: Pt) -> Float {
    var t = abs((c - b).angle() - (b - a).angle())
    if t > .pi { t = 2 * .pi - t }
    return t
  }

  /// The stroke without a hook (the pen landing or lifting) at either end.
  private static func withoutHooks(_ points: [Pt]) -> [Pt] {
    let r = Geo.resample(points, 100)
    if r.count < 100 { return points }
    let reach = Int(hook * 100)
    var from = 0
    var to = r.count - 1
    for i in 1...reach where turnAt(r[i - 1], r[i], r[i + 1]) > hookTurn { from = i }
    for i in stride(from: r.count - 2, through: r.count - 1 - reach, by: -1) where turnAt(r[i - 1], r[i], r[i + 1]) > hookTurn { to = i }
    return Array(r[from...to])
  }

  /// An arc of a circle through the stroke (Kåsa least-squares fit), or nil.
  private static func fitArc(_ points: [Pt], _ diag: Float) -> ShapeGeometry? {
    let r = Geo.resample(points, 64)
    if r.count < 8 { return nil }
    let n = Double(r.count)
    let mx = r.reduce(0.0) { $0 + Double($1.x) } / n
    let my = r.reduce(0.0) { $0 + Double($1.y) } / n
    var suu = 0.0, suv = 0.0, svv = 0.0, suuu = 0.0, svvv = 0.0, suvv = 0.0, svuu = 0.0
    for p in r {
      // Android computes these in Float - Double = Double; the same here.
      let u = Double(p.x) - mx, v = Double(p.y) - my
      suu += u * u
      suv += u * v
      svv += v * v
      suuu += u * u * u
      svvv += v * v * v
      suvv += u * v * v
      svuu += v * u * u
    }
    let det = suu * svv - suv * suv
    if abs(det) < 1e-9 { return nil }
    let bu = (suuu + suvv) / 2, bv = (svvv + svuu) / 2
    let uc = (bu * svv - bv * suv) / det
    let vc = (bv * suu - bu * suv) / det
    let center = Pt(Float(uc + mx), Float(vc + my))
    let radius = Float((uc * uc + vc * vc + (suu + svv) / n).squareRoot())
    if radius > 1.5 * diag || radius < 4 { return nil }
    let off = r.map { abs($0.dist(center) - radius) }
    if (off.max() ?? 0) > 0.06 * diag || off.reduce(0, +) / Float(off.count) > 0.02 * diag { return nil }
    var sweep: Float = 0, travel: Float = 0
    for i in 1..<r.count {
      var d = (r[i] - center).angle() - (r[i - 1] - center).angle()
      if d > .pi { d -= 2 * .pi }
      if d < -.pi { d += 2 * .pi }
      sweep += d
      travel += abs(d)
    }
    if travel > abs(sweep) * 1.15 { return nil }
    if abs(sweep) < arcMin || abs(sweep) > arcMax { return nil }
    var start = (r[0] - center).angle()
    if abs(abs(sweep) - .pi) < halfSnap {
      sweep = sweep > 0 ? .pi : -.pi
      let quarter = Float.pi / 2
      let snapped = (start / quarter).rounded() * quarter
      if abs(start - snapped) < levelSnap { start = snapped }
    }
    return .arc(center: center, radius: radius, start: start, sweep: sweep, arrowEnd: false)
  }

  /// Whether the stroke turns sharply somewhere rather than bending smoothly.
  private static func hasCorner(_ points: [Pt]) -> Bool {
    let r = Geo.resample(points, 96)
    guard r.count >= 3 else { return false }
    for i in 1..<(r.count - 1) {
      let before = r[i] - r[i - 1], after = r[i + 1] - r[i]
      if before.length() < 1e-3 || after.length() < 1e-3 { continue }
      var turn = abs(after.angle() - before.angle())
      if turn > .pi { turn = 2 * .pi - turn }
      if turn > cornerTurn { return true }
    }
    return false
  }

  /// A smooth curve through the stroke, or nil when none follows it closely.
  private static func fitCurve(_ points: [Pt], _ diag: Float) -> ShapeGeometry? {
    let stroke = Geo.resample(points, 120)
    func close(_ c: ShapeGeometry) -> Bool {
      guard let path = c.paths(1).first, path.count > 1 else { return false }
      var worst: Float = 0
      for p in stroke {
        var nearest = Float.greatestFiniteMagnitude
        for i in 0..<(path.count - 1) { nearest = min(nearest, Geo.distToSegment(p, path[i], path[i + 1])) }
        worst = max(worst, nearest)
      }
      return worst < 0.05 * diag && Geo.meanDistToPolyline(stroke, path, closed: false) < 0.02 * diag
    }
    for tolerance: Float in [0.05, 0.035, 0.02] {
      let turns = Geo.simplify(stroke, tolerance * diag)
      if turns.count > 12 { break }
      var at = turns.map { t in stroke.firstIndex(of: t)! }
      while at.count < curveDots {
        // The widest gap (the first of equal ones, as Kotlin's maxBy).
        var gap = 0
        for i in 1..<(at.count - 1) where at[i + 1] - at[i] > at[gap + 1] - at[gap] { gap = i }
        if at[gap + 1] - at[gap] < 2 { break }
        at.insert((at[gap] + at[gap + 1]) / 2, at: gap + 1)
      }
      let curve = ShapeGeometry.curve(points: at.map { stroke[$0] })
      if close(curve) { return curve }
    }
    return nil
  }

  /// A line snapped to every 45° when within `lineSnapDeg`, keeping its start and length.
  public static func snappedLine(_ a: Pt, _ b: Pt, arrowEnd: Bool = false) -> ShapeGeometry {
    let v = b - a
    let angle = v.angle()
    let wide = (angle / (45 * deg)).rounded() * (45 * deg)
    let end = abs(angle - wide) < lineSnapDeg * deg ? a + Pt.polar(v.length(), wide) : b
    return .line(a: a, b: end, arrowStart: false, arrowEnd: arrowEnd, ticks: false)
  }

  /// One-stroke arrows: a shaft and one barb, or a barb, back to the tip and a second barb.
  private static func arrow(_ v: [Pt]) -> ShapeGeometry? {
    guard (3...5).contains(v.count) else { return nil }
    let start = v[0], tip = v[1]
    let shaft = start.dist(tip)
    if shaft < 20 { return nil }
    let back = (start - tip).normalized()
    func isBarb(_ p: Pt) -> Bool {
      let d = p.dist(tip)
      if d < shaft * 0.06 || d > shaft * 0.45 { return false }
      let cosA = back.dot((p - tip).normalized())
      return cosA > cosf(75 * deg) && cosA < cosf(10 * deg)
    }
    let ok: Bool
    switch v.count {
    case 3: ok = isBarb(v[2])
    case 4: ok = isBarb(v[2]) && (v[3].dist(tip) < shaft * 0.12 || isBarb(v[3]))
    default: ok = isBarb(v[2]) && v[3].dist(tip) < shaft * 0.15 && isBarb(v[4])
    }
    return ok ? snappedLine(start, tip, arrowEnd: true) : nil
  }

  // MARK: Closed strokes

  private struct Ellipse {
    var center: Pt, rx: Float, ry: Float, rotation: Float
  }

  private static func recognizeClosed(_ points: [Pt], _ diag: Float) -> ShapeGeometry? {
    let samples = Geo.resample(points, 72)
    let centroid = Geo.centroid(samples)
    let meanRadius = samples.reduce(Float(0)) { $0 + $1.dist(centroid) } / Float(samples.count)
    if meanRadius < 4 { return nil }
    let ellipse = fitEllipse(samples)
    let polygon = fitPolygon(samples, centroid, diag)
    let polyErr = polygon.map { Geo.meanDistToPolyline(samples, $0, closed: true) / meanRadius } ?? .greatestFiniteMagnitude
    if let e = ellipse, e.1 < 0.12, polygon == nil || polygon!.count > 6 || e.1 < polyErr { return beautifyEllipse(e.0) }
    if let polygon, polyErr < 0.09, let p = beautifyPolygon(polygon) { return p }
    if let e = ellipse, e.1 < 0.16 { return beautifyEllipse(e.0) }
    return nil
  }

  /// Principal-axis ellipse fit, with its mean relative radial error.
  private static func fitEllipse(_ samples: [Pt]) -> (Ellipse, Float)? {
    let c0 = Geo.centroid(samples)
    var sxx: Float = 0, syy: Float = 0, sxy: Float = 0
    for p in samples {
      let d = p - c0
      sxx += d.x * d.x
      syy += d.y * d.y
      sxy += d.x * d.y
    }
    let theta = 0.5 * atan2f(2 * sxy, sxx - syy)
    let local = samples.map { ($0 - c0).rotated(-theta) }
    guard let box = Rect.around(local) else { return nil }
    let rx = box.width / 2, ry = box.height / 2
    if rx < 2 || ry < 2 { return nil }
    let center = c0 + box.center.rotated(theta)
    var err: Float = 0
    for p in samples {
      let q = (p - center).rotated(-theta)
      err += abs(((q.x / rx) * (q.x / rx) + (q.y / ry) * (q.y / ry)).squareRoot() - 1)
    }
    return (Ellipse(center: center, rx: rx, ry: ry, rotation: theta), err / Float(samples.count))
  }

  private static func beautifyEllipse(_ e: Ellipse) -> ShapeGeometry {
    let ratio = min(e.rx, e.ry) / max(e.rx, e.ry)
    if ratio > 0.8 {
      let r = (e.rx + e.ry) / 2
      return .ellipse(center: e.center, rx: r, ry: r, rotation: 0)
    }
    let quarter = 90 * deg
    let snapped = (e.rotation / quarter).rounded() * quarter
    return .ellipse(center: e.center, rx: e.rx, ry: e.ry, rotation: abs(e.rotation - snapped) < 15 * deg ? snapped : e.rotation)
  }

  /// Corners of a closed stroke: simplified from the point farthest from the centre, flat corners merged.
  private static func fitPolygon(_ samples: [Pt], _ centroid: Pt, _ diag: Float) -> [Pt]? {
    let loop = Array(samples.dropLast())
    guard let far = loop.indices.max(by: { loop[$0].dist(centroid) < loop[$1].dist(centroid) }) else { return nil }
    let rotated = Array(loop[far...]) + Array(loop[..<far]) + [loop[far]]
    var poly = Array(Geo.simplify(rotated, 0.06 * diag).dropLast())
    poly = mergeFlatCorners(poly, 0.1 * diag)
    return (3...12).contains(poly.count) ? poly : nil
  }

  /// Takes away corners that aren't really corners, weakest first.
  private static func mergeFlatCorners(_ input: [Pt], _ minEdge: Float) -> [Pt] {
    let diag = minEdge * 10
    var poly = input
    while poly.count > 3 {
      var weakest = -1
      var weakestHeight = Float.greatestFiniteMagnitude
      for i in poly.indices {
        let prev = poly[(i - 1 + poly.count) % poly.count], cur = poly[i], next = poly[(i + 1) % poly.count]
        let angle = Geo.interiorAngle(prev, cur, next)
        let height = Geo.distToSegment(cur, prev, next)
        let flat = angle > 155 * deg
        let tiny = cur.dist(next) < minEdge * 0.5
        let gentle = angle > 130 * deg && height < gentleBend * diag
        if (flat || tiny || gentle) && height < weakestHeight {
          weakest = i
          weakestHeight = height
        }
      }
      if weakest < 0 { break }
      poly.remove(at: weakest)
    }
    return poly
  }

  /// Only triangles, four-sided shapes, even pentagons and hexagons, and stars are made.
  private static func beautifyPolygon(_ poly: [Pt]) -> ShapeGeometry? {
    let c = Geo.centroid(poly)
    switch poly.count {
    case 3: return beautifyTriangle(poly)
    case 4: return beautifyQuad(poly)
    case 5, 6: return isNearlyRegular(poly, c) ? regularFrom(poly, c) : nil
    case 10: return starFrom(poly, c)
    default: return nil
    }
  }

  private static func beautifyTriangle(_ t: [Pt]) -> ShapeGeometry {
    let sides = [t[0].dist(t[1]), t[1].dist(t[2]), t[2].dist(t[0])]
    let mean = sides.reduce(0, +) / 3
    if sides.allSatisfy({ abs($0 - mean) / mean < 0.15 }) { return regularFrom(t, Geo.centroid(t)) }
    for i in 0..<3 {
      let a = t[(i + 2) % 3], b = t[i], cc = t[(i + 1) % 3]
      if abs(Geo.interiorAngle(a, b, cc) - 90 * deg) < 15 * deg {
        let mid = (a + cc) / 2
        let r = a.dist(cc) / 2
        var out = t
        out[i] = mid + (b - mid).normalized() * r
        return .poly(points: axisSnapRightTriangle(out, i), closed: true)
      }
    }
    return .poly(points: levelBase(isoscelesFrom(t) ?? t), closed: true)
  }

  private static func isoscelesFrom(_ t: [Pt]) -> [Pt]? {
    for apex in 0..<3 {
      let a = t[(apex + 1) % 3], b = t[(apex + 2) % 3]
      let s1 = t[apex].dist(a), s2 = t[apex].dist(b)
      if abs(s1 - s2) / max(s1, s2) >= 0.15 { continue }
      let mid = (a + b) / 2
      let base = (b - a).normalized()
      let normal = Pt(-base.y, base.x)
      let height = (t[apex] - mid).dot(normal)
      var out = t
      out[apex] = mid + normal * height
      return out
    }
    return nil
  }

  private static func levelBase(_ t: [Pt]) -> [Pt] {
    let quarter = 90 * deg
    var best: Float = 0
    var bestAbs = Float.greatestFiniteMagnitude
    for i in 0..<3 {
      let angle = (t[(i + 1) % 3] - t[i]).angle()
      let delta = (angle / quarter).rounded() * quarter - angle
      if abs(delta) < bestAbs {
        bestAbs = abs(delta)
        best = delta
      }
    }
    if bestAbs >= 15 * deg { return t }
    let c = Geo.centroid(t)
    return t.map { $0.rotated(around: c, by: best) }
  }

  private static func axisSnapRightTriangle(_ t: [Pt], _ corner: Int) -> [Pt] {
    let b = t[corner]
    let angle = (t[(corner + 1) % 3] - b).angle()
    let quarter = 90 * deg
    let delta = (angle / quarter).rounded() * quarter - angle
    return abs(delta) < 15 * deg ? t.map { $0.rotated(around: b, by: delta) } : t
  }

  private static func beautifyQuad(_ q: [Pt]) -> ShapeGeometry {
    let angles = q.indices.map { i in Geo.interiorAngle(q[(i + 3) % 4], q[i], q[(i + 1) % 4]) }
    let c = Geo.centroid(q)
    if angles.allSatisfy({ abs($0 - 90 * deg) < 20 * deg }) {
      let edges = q.indices.map { q[($0 + 1) % 4] - q[$0] }
      let longest = edges.max { $0.length() < $1.length() }!
      var theta = longest.angle()
      let quarter = 90 * deg
      let snapped = (theta / quarter).rounded() * quarter
      if abs(theta - snapped) < 15 * deg { theta = snapped }
      let local = q.map { ($0 - c).rotated(-theta) }
      let box = Rect.around(local)!
      var hw = box.width / 2, hh = box.height / 2
      if min(hw, hh) / max(hw, hh) > 0.88 {
        let s = (hw + hh) / 2
        hw = s
        hh = s
      }
      let center = c + box.center.rotated(theta)
      let corners = [Pt(-hw, -hh), Pt(hw, -hh), Pt(hw, hh), Pt(-hw, hh)].map { center + $0.rotated(theta) }
      return .poly(points: corners, closed: true, rotation: theta)
    }
    let box = Rect.around(q)!
    let mids = [Pt(box.center.x, box.top), Pt(box.right, box.center.y), Pt(box.center.x, box.bottom), Pt(box.left, box.center.y)]
    let tol = 0.15 * max(box.width, box.height)
    if q.allSatisfy({ p in mids.contains { $0.dist(p) < tol } }) {
      func order(_ m: Pt) -> Int { q.indices.min { q[$0].dist(m) < q[$1].dist(m) }! }
      // Kotlin's sortedBy is stable; so is this (ties keep their order).
      let ordered = mids.enumerated().sorted { (order($0.element), $0.offset) < (order($1.element), $1.offset) }.map(\.element)
      return .poly(points: ordered, closed: true)
    }
    return .poly(points: q, closed: true)
  }

  private static func isNearlyRegular(_ poly: [Pt], _ c: Pt) -> Bool {
    let radii = poly.map { $0.dist(c) }
    let meanR = radii.reduce(0, +) / Float(radii.count)
    let sides = poly.indices.map { poly[$0].dist(poly[($0 + 1) % poly.count]) }
    let meanS = sides.reduce(0, +) / Float(sides.count)
    return radii.allSatisfy { abs($0 - meanR) / meanR < 0.18 } && sides.allSatisfy { abs($0 - meanS) / meanS < 0.25 }
  }

  private static func regularFrom(_ poly: [Pt], _ c: Pt) -> ShapeGeometry {
    let r = poly.reduce(Float(0)) { $0 + $1.dist(c) } / Float(poly.count)
    var rot = (poly[0] - c).angle()
    let step = 2 * Float.pi / Float(poly.count)
    let upright = -Float.pi / 2
    let k = ((rot - upright) / step).rounded()
    let candidate = upright + k * step
    if abs(rot - candidate) < 15 * deg { rot = candidate }
    return ShapeMaker.regularPolygon(c, r, poly.count, rotation: rot)
  }

  private static func starFrom(_ poly: [Pt], _ c: Pt) -> ShapeGeometry? {
    let radii = poly.map { $0.dist(c) }
    let even = stride(from: 0, to: radii.count, by: 2).map { radii[$0] }
    let odd = stride(from: 1, to: radii.count, by: 2).map { radii[$0] }
    let evenMean = even.reduce(0, +) / Float(even.count), oddMean = odd.reduce(0, +) / Float(odd.count)
    let outer = max(evenMean, oddMean), inner = min(evenMean, oddMean)
    if inner / outer > 0.75 { return nil }
    let firstOuter = evenMean > oddMean ? poly[0] : poly[1]
    return ShapeMaker.star(c, outer, rotation: (firstOuter - c).angle())
  }
}
