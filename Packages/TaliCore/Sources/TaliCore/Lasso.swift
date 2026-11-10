import Foundation

extension Geo {
  public static func pointInPolygon(_ p: Pt, _ poly: [Pt]) -> Bool {
    var inside = false
    var j = poly.count - 1
    for i in poly.indices {
      let pi = poly[i], pj = poly[j]
      if (pi.y > p.y) != (pj.y > p.y) && p.x < (pj.x - pi.x) * (p.y - pi.y) / (pj.y - pi.y) + pi.x { inside.toggle() }
      j = i
    }
    return inside
  }
}

/// What a lasso loop picks up (Android's `geometry/Lasso.kt`). It takes whatever it touches: a
/// stroke counts if any of it is inside the loop or it crosses the loop's edge. Pictures count when
/// the loop crosses or encloses them, but not when the loop is drawn wholly inside a picture.
public enum Lasso {
  /// Whether the path (points in drawing order) touches the closed loop [poly].
  public static func touchesPath(_ path: [Pt], _ poly: [Pt]) -> Bool {
    if path.isEmpty || poly.count < 3 { return false }
    if path.contains(where: { Geo.pointInPolygon($0, poly) }) { return true }
    for i in path.indices.dropFirst() where crossesLoop(path[i - 1], path[i], poly) { return true }
    return false
  }

  /// Whether [r] is touched: part of it is inside the loop or the loop crosses its edge.
  public static func touchesRect(_ r: Rect, _ poly: [Pt]) -> Bool {
    if poly.count < 3 { return false }
    let corners = [Pt(r.left, r.top), Pt(r.right, r.top), Pt(r.right, r.bottom), Pt(r.left, r.bottom)]
    if corners.contains(where: { Geo.pointInPolygon($0, poly) }) || Geo.pointInPolygon(r.center, poly) { return true }
    for i in corners.indices where crossesLoop(corners[i], corners[(i + 1) % 4], poly) { return true }
    return false
  }

  private static func crossesLoop(_ a: Pt, _ b: Pt, _ poly: [Pt]) -> Bool {
    var j = poly.count - 1
    for i in poly.indices {
      if segmentsCross(a, b, poly[j], poly[i]) { return true }
      j = i
    }
    return false
  }

  /// Whether segments a-b and c-d cross (touching counts).
  public static func segmentsCross(_ a: Pt, _ b: Pt, _ c: Pt, _ d: Pt) -> Bool {
    func side(_ p: Pt, _ q: Pt, _ r: Pt) -> Float { (q.x - p.x) * (r.y - p.y) - (q.y - p.y) * (r.x - p.x) }
    let d1 = side(c, d, a), d2 = side(c, d, b), d3 = side(a, b, c), d4 = side(a, b, d)
    if ((d1 > 0 && d2 < 0) || (d1 < 0 && d2 > 0)) && ((d3 > 0 && d4 < 0) || (d3 < 0 && d4 > 0)) { return true }
    func on(_ p: Pt, _ q: Pt, _ r: Pt) -> Bool { min(p.x, q.x) <= r.x && r.x <= max(p.x, q.x) && min(p.y, q.y) <= r.y && r.y <= max(p.y, q.y) }
    return (d1 == 0 && on(c, d, a)) || (d2 == 0 && on(c, d, b)) || (d3 == 0 && on(a, b, c)) || (d4 == 0 && on(a, b, d))
  }

  /// Free-form selecting: whether a pen [path] passes within [r] of the drawing [points].
  public static func nearPath(_ points: [Pt], _ path: [Pt], _ r: Float) -> Bool {
    if points.isEmpty || path.isEmpty { return false }
    let a = points.count == 1 ? [points[0], points[0]] : points
    let b = path.count == 1 ? [path[0], path[0]] : path
    for i in 0..<(a.count - 1) {
      for j in 0..<(b.count - 1) where segmentDistance(a[i], a[i + 1], b[j], b[j + 1]) <= r { return true }
    }
    return false
  }

  /// Free-form selecting: whether a pen [path] passes within [r] of [rect] (a picture or text).
  public static func nearRect(_ rect: Rect, _ path: [Pt], _ r: Float) -> Bool {
    let grown = rect.outset(r)
    if path.contains(where: { grown.contains($0) }) { return true }
    let corners = [Pt(grown.left, grown.top), Pt(grown.right, grown.top), Pt(grown.right, grown.bottom), Pt(grown.left, grown.bottom)]
    for j in 0..<max(path.count - 1, 0) {
      for k in 0..<4 where segmentsCross(path[j], path[j + 1], corners[k], corners[(k + 1) % 4]) { return true }
    }
    return false
  }

  private static func segmentDistance(_ a: Pt, _ b: Pt, _ c: Pt, _ d: Pt) -> Float {
    if segmentsCross(a, b, c, d) { return 0 }
    return min(min(Geo.distToSegment(a, c, d), Geo.distToSegment(b, c, d)), min(Geo.distToSegment(c, a, b), Geo.distToSegment(d, a, b)))
  }
}
