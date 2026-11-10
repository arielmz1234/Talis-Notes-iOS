import Foundation

private let tau = Float.pi * 2
private let tick: Float = 8

extension Geo {
  public static func interiorAngle(_ a: Pt, _ b: Pt, _ c: Pt) -> Float {
    let u = (a - b).normalized(), v = (c - b).normalized()
    return acosf(min(max(u.dot(v), -1), 1))
  }

  /// A Catmull-Rom curve through [points], keeping corners sharper than [cornerDeg] (Android's `Geo.smooth`).
  public static func smooth(_ points: [Pt], step: Float = 1.5, cornerDeg: Float = 55) -> [Pt] {
    if points.count < 3 { return points }
    let corner = cornerDeg * .pi / 180
    var out: [Pt] = [points[0]]
    var start = 0
    for i in 1..<points.count {
      let isCorner = i < points.count - 1 && Float.pi - interiorAngle(points[i - 1], points[i], points[i + 1]) > corner
      if isCorner || i == points.count - 1 {
        let run = Array(points[start...i])
        for j in 0..<(run.count - 1) {
          let p0 = run[max(j - 1, 0)], p1 = run[j], p2 = run[j + 1], p3 = run[min(j + 2, run.count - 1)]
          let n = min(max(Int(ceilf(p1.dist(p2) / step)), 1), 32)
          for k in 1...n {
            let t = Float(k) / Float(n), t2 = t * t, t3 = t2 * t
            func f(_ a: Float, _ b: Float, _ c: Float, _ d: Float) -> Float {
              0.5 * (2 * b + (-a + c) * t + (2 * a - 5 * b + 4 * c - d) * t2 + (-a + 3 * b - 3 * c + d) * t3)
            }
            out.append(Pt(f(p0.x, p1.x, p2.x, p3.x), f(p0.y, p1.y, p2.y, p3.y)))
          }
        }
        start = i
      }
    }
    return out
  }
}

public enum Arrow {
  public static func headLength(_ penSize: Float, _ room: Float) -> Float { min(max(20, penSize * 7), room * 0.4) }

  /// Two short barbs at [tip], pointing back toward [from].
  public static func head(_ from: Pt, _ tip: Pt, _ penSize: Float, room: Float? = nil) -> [[Pt]] {
    let dir = (tip - from).normalized()
    if dir == .zero { return [] }
    let len = headLength(penSize, room ?? from.dist(tip))
    let back = dir * -len
    return [[tip + back.rotated(0.52), tip, tip + back.rotated(-0.52)]]
  }
}

/// A shape's geometry as the Android app stores it (JSON with a "type" key, `model/Shapes.kt`).
/// This port draws every kind; designs from the subject packs ("param") are kept but not drawn yet.
public indirect enum ShapeGeometry: Sendable, Equatable {
  case line(a: Pt, b: Pt, arrowStart: Bool, arrowEnd: Bool, ticks: Bool)
  case poly(points: [Pt], closed: Bool, smooth: Bool)
  case ellipse(center: Pt, rx: Float, ry: Float, rotation: Float)
  case arc(center: Pt, radius: Float, start: Float, sweep: Float, arrowEnd: Bool)
  case curve(points: [Pt])
  case sector(center: Pt, radius: Float, start: Float, sweep: Float)
  case triangle(a: Pt, b: Pt, c: Pt)
  case load(a: Pt, b: Pt, depth: Float, count: Int)
  case group([ShapeGeometry])
  /// A subject-pack design (its template isn't ported yet).
  case param

  /// Polylines to ink, each one continuous stroke. [penSize] sizes arrowheads.
  public func paths(_ penSize: Float) -> [[Pt]] {
    switch self {
    case let .line(a, b, arrowStart, arrowEnd, ticks):
      var out = [[a, b]]
      if arrowEnd { out += Arrow.head(a, b, penSize) }
      if arrowStart { out += Arrow.head(b, a, penSize) }
      if ticks {
        let dir = (b - a).normalized()
        if dir != .zero {
          let n = Pt(-dir.y, dir.x) * max(tick, penSize * 2.5)
          out += [[a - n, a + n], [b - n, b + n]]
        }
      }
      return out
    case let .poly(points, closed, smooth):
      guard let first = points.first else { return [] }
      return [closed ? points + [first] : (smooth ? Geo.smooth(points) : points)]
    case let .ellipse(center, rx, ry, rotation):
      let n = min(max(Int(max(rx, ry) / 3), 48), 180)
      return [(0...n).map { i in
        let t = tau * Float(i) / Float(n)
        return center + Pt(rx * cosf(t), ry * sinf(t)).rotated(rotation)
      }]
    case let .arc(center, radius, start, sweep, arrowEnd):
      let n = min(max(Int(abs(sweep) * radius / 3), 16), 160)
      let arc = (0...n).map { center + Pt.polar(radius, start + sweep * Float($0) / Float(n)) }
      if !arrowEnd { return [arc] }
      let room = min(abs(sweep), 1.5) * radius
      let back = Arrow.headLength(penSize, room) / radius
      let from = center + Pt.polar(radius, start + sweep - (sweep < 0 ? -back : back))
      return [arc] + Arrow.head(from, arc.last!, penSize, room: room)
    case let .curve(points):
      return [Geo.smooth(points, cornerDeg: 180)]
    case let .sector(center, radius, start, sweep):
      let n = min(max(Int(abs(sweep) * radius / 3), 12), 200)
      let arc = (0...n).map { center + Pt.polar(radius, start + sweep * Float($0) / Float(n)) }
      return min(max(abs(sweep) / tau, 0), 1) >= 0.999 ? [arc] : [[center] + arc + [center]]
    case let .triangle(a, b, c):
      return [[a, b, c, a]]
    case let .load(a, b, depth, count):
      let d = (b - a).normalized()
      let across = Pt(-d.y, d.x)
      var out = [[a, b]]
      for i in 0...max(count, 1) {
        let p = a + (b - a) * (Float(i) / Float(max(count, 1)))
        let t = p + across * depth
        out.append([p, t])
        out += Arrow.head(p, t, penSize)
      }
      return out
    case let .group(parts):
      return parts.flatMap { $0.paths(penSize) }
    case .param:
      return []
    }
  }

  /// Whether it encloses an area that takes a fill.
  public var closed: Bool {
    switch self {
    case .ellipse, .sector, .triangle: true
    case .poly(_, let closed, _): closed
    default: false
    }
  }

  // MARK: JSON

  public static func decode(_ json: Any) -> ShapeGeometry? {
    guard let o = json as? [String: Any], let type = o["type"] as? String else { return nil }
    func pt(_ k: String) -> Pt? {
      guard let p = o[k] as? [String: Any] else { return nil }
      return Pt(num(p["x"]), num(p["y"]))
    }
    func pts(_ k: String) -> [Pt] {
      ((o[k] as? [[String: Any]]) ?? []).map { Pt(num($0["x"]), num($0["y"])) }
    }
    func f(_ k: String, _ d: Float = 0) -> Float { o[k] == nil ? d : num(o[k]) }
    func b(_ k: String) -> Bool { (o[k] as? Bool) ?? false }
    switch type {
    case "line":
      guard let a = pt("a"), let bb = pt("b") else { return nil }
      return .line(a: a, b: bb, arrowStart: b("arrowStart"), arrowEnd: b("arrowEnd"), ticks: b("ticks"))
    case "poly": return .poly(points: pts("points"), closed: b("closed"), smooth: b("smooth"))
    case "ellipse":
      guard let c = pt("center") else { return nil }
      return .ellipse(center: c, rx: f("rx"), ry: f("ry"), rotation: f("rotation"))
    case "arc":
      guard let c = pt("center") else { return nil }
      return .arc(center: c, radius: f("radius"), start: f("start"), sweep: f("sweep"), arrowEnd: b("arrowEnd"))
    case "curve": return .curve(points: pts("points"))
    case "sector":
      guard let c = pt("center") else { return nil }
      return .sector(center: c, radius: f("radius"), start: f("start"), sweep: f("sweep"))
    case "triangle":
      guard let a = pt("a"), let bb = pt("b"), let c = pt("c") else { return nil }
      return .triangle(a: a, b: bb, c: c)
    case "load":
      guard let a = pt("a"), let bb = pt("b") else { return nil }
      return .load(a: a, b: bb, depth: f("depth"), count: Int(f("count", 2)))
    case "group": return .group(((o["parts"] as? [Any]) ?? []).compactMap(decode))
    case "param": return .param
    default: return nil
    }
  }

  private static func num(_ v: Any?) -> Float {
    if let n = v as? NSNumber { return n.floatValue }
    if let d = v as? Double { return Float(d) }
    return 0
  }
}

/// A shape item row (kind 1) read for drawing: its geometry, pen, colour, size, fill and line style.
public struct ShapeRow: Sendable {
  public var geometry: ShapeGeometry
  public var pen: String
  public var color: Int32
  public var size: Float
  public var fill: Int32?
  public var line: String
  public var locked: Bool

  public init?(_ row: ItemRow) {
    guard row.kind == 1, let obj = try? JSONSerialization.jsonObject(with: row.payload) as? [String: Any],
      let g = ShapeGeometry.decode(obj)
    else { return nil }
    geometry = g
    pen = row.pen ?? "FINELINER"
    color = row.color
    size = row.size
    fill = (obj["fill"] as? NSNumber).map { Int32(truncatingIfNeeded: $0.int64Value) }
    line = (obj["line"] as? String) ?? "SOLID"
    locked = (obj["locked"] as? Bool) ?? false
  }
}
