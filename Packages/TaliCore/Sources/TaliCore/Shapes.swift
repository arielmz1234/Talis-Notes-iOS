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
/// The basic shapes that keep their form when their dots are dragged (Android's `PolyForm`).
public enum PolyForm: String, Sendable, Equatable { case DIAMOND, PARALLELOGRAM, TRAPEZOID, REGULAR }

/// A subject-pack design (Android's `ParamShape`): template id, its place on the page, frame size, settings.
public struct ParamShape: Sendable, Equatable {
  public var template: String
  public var place: Affine
  public var w: Float
  public var h: Float
  public var v: [Float]
  public init(template: String, place: Affine, w: Float, h: Float, v: [Float] = []) {
    self.template = template
    self.place = place
    self.w = w
    self.h = h
    self.v = v
  }
}

public indirect enum ShapeGeometry: Sendable, Equatable {
  case line(a: Pt, b: Pt, arrowStart: Bool, arrowEnd: Bool, ticks: Bool)
  case poly(points: [Pt], closed: Bool, smooth: Bool = false, rotation: Float = 0, form: PolyForm? = nil)
  case ellipse(center: Pt, rx: Float, ry: Float, rotation: Float, stretchable: Bool = false)
  case arc(center: Pt, radius: Float, start: Float, sweep: Float, arrowEnd: Bool)
  case curve(points: [Pt])
  case sector(center: Pt, radius: Float, start: Float, sweep: Float)
  case triangle(a: Pt, b: Pt, c: Pt, turn: Float = 0)
  case load(a: Pt, b: Pt, depth: Float, count: Int)
  case group(_ parts: [ShapeGeometry], turn: Float = 0)
  /// A subject-pack design (its template isn't ported yet, so it isn't drawn), kept whole so it
  /// goes back to Android unchanged.
  case param(ParamShape)

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
    case let .poly(points, closed, smooth, _, _):
      guard let first = points.first else { return [] }
      return [closed ? points + [first] : (smooth ? Geo.smooth(points) : points)]
    case let .ellipse(center, rx, ry, rotation, _):
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
    case let .triangle(a, b, c, _):
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
    case let .group(parts, _):
      return parts.flatMap { $0.paths(penSize) }
    case .param:
      return []
    }
  }

  /// Whether it encloses an area that takes a fill.
  public var closed: Bool {
    switch self {
    case .ellipse, .sector, .triangle: true
    case .poly(_, let closed, _, _, _): closed
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
    case "poly":
      return .poly(
        points: pts("points"), closed: b("closed"), smooth: b("smooth"), rotation: f("rotation"),
        form: (o["form"] as? String).flatMap(PolyForm.init(rawValue:)))
    case "ellipse":
      guard let c = pt("center") else { return nil }
      return .ellipse(center: c, rx: f("rx"), ry: f("ry"), rotation: f("rotation"), stretchable: b("stretchable"))
    case "arc":
      guard let c = pt("center") else { return nil }
      return .arc(center: c, radius: f("radius"), start: f("start"), sweep: f("sweep"), arrowEnd: b("arrowEnd"))
    case "curve": return .curve(points: pts("points"))
    case "sector":
      guard let c = pt("center") else { return nil }
      return .sector(center: c, radius: f("radius"), start: f("start"), sweep: f("sweep"))
    case "triangle":
      guard let a = pt("a"), let bb = pt("b"), let c = pt("c") else { return nil }
      return .triangle(a: a, b: bb, c: c, turn: f("turn"))
    case "load":
      guard let a = pt("a"), let bb = pt("b") else { return nil }
      return .load(a: a, b: bb, depth: f("depth"), count: Int(f("count", 2)))
    case "group": return .group(((o["parts"] as? [Any]) ?? []).compactMap(decode), turn: f("turn"))
    case "param":
      let pl = o["place"] as? [String: Any] ?? [:]
      func m(_ k: String, _ d: Float) -> Float { pl[k] == nil ? d : num(pl[k]) }
      let place = Affine(a: m("a", 1), b: m("b", 0), c: m("c", 0), d: m("d", 1), tx: m("tx", 0), ty: m("ty", 0))
      let v = ((o["v"] as? [Any]) ?? []).map { num($0) }
      return .param(ParamShape(template: (o["template"] as? String) ?? "", place: place, w: f("w"), h: f("h"), v: v))
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
public struct ShapeRow: Sendable, Equatable {
  /// The item's id ("" until it's stored) and its place in the drawing order.
  public var id: String = ""
  public var z: Int64 = 0
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
    id = row.id
    z = row.z
    geometry = g
    pen = row.pen ?? "FINELINER"
    color = row.color
    size = row.size
    fill = (obj["fill"] as? NSNumber).map { Int32(truncatingIfNeeded: $0.int64Value) }
    line = (obj["line"] as? String) ?? "SOLID"
    locked = (obj["locked"] as? Bool) ?? false
  }
}

// MARK: Writing shapes the Android way

extension ShapeGeometry {
  /// The JSON object Android's kotlinx.serialization writes for this geometry (class discriminator
  /// "type", default values left out), so a shape made here reads back the same on Android.
  public var json: [String: Any] {
    func pt(_ p: Pt) -> [String: Any] { ["x": num(p.x), "y": num(p.y)] }
    var o: [String: Any]
    switch self {
    case let .line(a, b, arrowStart, arrowEnd, ticks):
      o = ["type": "line", "a": pt(a), "b": pt(b)]
      if arrowStart { o["arrowStart"] = true }
      if arrowEnd { o["arrowEnd"] = true }
      if ticks { o["ticks"] = true }
    case let .poly(points, closed, smooth, rotation, form):
      o = ["type": "poly", "points": points.map(pt), "closed": closed]
      if rotation != 0 { o["rotation"] = num(rotation) }
      if smooth { o["smooth"] = true }
      if let form { o["form"] = form.rawValue }
    case let .ellipse(center, rx, ry, rotation, stretchable):
      o = ["type": "ellipse", "center": pt(center), "rx": num(rx), "ry": num(ry)]
      if rotation != 0 { o["rotation"] = num(rotation) }
      if stretchable { o["stretchable"] = true }
    case let .arc(center, radius, start, sweep, arrowEnd):
      o = ["type": "arc", "center": pt(center), "radius": num(radius), "start": num(start), "sweep": num(sweep)]
      if arrowEnd { o["arrowEnd"] = true }
    case let .curve(points):
      o = ["type": "curve", "points": points.map(pt)]
    case let .sector(center, radius, start, sweep):
      o = ["type": "sector", "center": pt(center), "radius": num(radius), "start": num(start), "sweep": num(sweep)]
    case let .triangle(a, b, c, turn):
      o = ["type": "triangle", "a": pt(a), "b": pt(b), "c": pt(c)]
      if turn != 0 { o["turn"] = num(turn) }
    case let .load(a, b, depth, count):
      o = ["type": "load", "a": pt(a), "b": pt(b), "depth": num(depth), "count": count]
    case let .group(parts, turn):
      o = ["type": "group", "parts": parts.map(\.json)]
      if turn != 0 { o["turn"] = num(turn) }
    case let .param(q):
      var place: [String: Any] = [:]
      let m = q.place
      if m.a != 1 { place["a"] = num(m.a) }
      if m.b != 0 { place["b"] = num(m.b) }
      if m.c != 0 { place["c"] = num(m.c) }
      if m.d != 1 { place["d"] = num(m.d) }
      if m.tx != 0 { place["tx"] = num(m.tx) }
      if m.ty != 0 { place["ty"] = num(m.ty) }
      o = ["type": "param", "template": q.template, "place": place, "w": num(q.w), "h": num(q.h)]
      if !q.v.isEmpty { o["v"] = q.v.map { num($0) } }
    }
    return o
  }

  /// A Float as the shortest decimal that reads back as the same Float (as Kotlin prints it).
  private func num(_ f: Float) -> Double { Double("\(f)") ?? Double(f) }

  /// The box its lines cover, widened by half the pen.
  public func bounds(_ penSize: Float) -> Rect? {
    guard let r = Rect.around(paths(penSize).joined()) else { return nil }
    return r.outset(max(penSize, 0.5) / 2)
  }

  /// Moved, scaled or turned by [m] (Android's `transformed`).
  public func transformed(_ m: Affine) -> ShapeGeometry {
    let s = m.scaleFactor
    switch self {
    case let .line(a, b, s1, e1, t): return .line(a: m.apply(a), b: m.apply(b), arrowStart: s1, arrowEnd: e1, ticks: t)
    case let .poly(points, closed, smooth, rotation, form):
      return .poly(points: points.map(m.apply), closed: closed, smooth: smooth, rotation: m.mapAngle(rotation), form: form)
    case let .ellipse(center, rx, ry, rotation, stretchable):
      // Uniform scale, moving, turning and mirroring keep an ellipse an ellipse; that's all selections do.
      return .ellipse(center: m.apply(center), rx: rx * s, ry: ry * s, rotation: m.mapAngle(rotation), stretchable: stretchable)
    case let .arc(center, radius, start, sweep, arrowEnd):
      return .arc(center: m.apply(center), radius: radius * s, start: m.mapAngle(start), sweep: m.mirrors ? -sweep : sweep, arrowEnd: arrowEnd)
    case let .curve(points): return .curve(points: points.map(m.apply))
    case let .sector(center, radius, start, sweep):
      return .sector(center: m.apply(center), radius: radius * s, start: m.mapAngle(start), sweep: m.mirrors ? -sweep : sweep)
    case let .triangle(a, b, c, turn): return .triangle(a: m.apply(a), b: m.apply(b), c: m.apply(c), turn: m.mapAngle(turn))
    // A mirror flips which side the arrows hang (their side is measured from a to b, which a mirror reverses).
    case let .load(a, b, depth, count): return .load(a: m.apply(a), b: m.apply(b), depth: depth * s * (m.mirrors ? -1 : 1), count: count)
    case let .group(parts, turn): return .group(parts.map { $0.transformed(m) }, turn: m.mapAngle(turn))
    // Affine.then applies the left-hand transform first: the shape's own place, then [m].
    case let .param(q):
      var out = q
      out.place = q.place.then(m)
      return .param(out)
    }
  }
}

extension ShapeRow {
  public init(id: String = "", geometry: ShapeGeometry, pen: String, color: Int32, size: Float, fill: Int32? = nil, line: String = "SOLID", locked: Bool = false) {
    self.id = id
    self.geometry = geometry
    self.pen = pen
    self.color = color
    self.size = size
    self.fill = fill
    self.line = line
    self.locked = locked
  }

  /// The item row Android's `ItemCodec.encode` writes for a shape (kind 1): the geometry's JSON plus
  /// "fill", "locked" and "line" when they aren't the defaults.
  public func row(id: String, z: Int64) -> ItemRow {
    var o = geometry.json
    if let fill { o["fill"] = Int(fill) }
    if locked { o["locked"] = true }
    if line != "SOLID" { o["line"] = line }
    let data = (try? JSONSerialization.data(withJSONObject: o)) ?? Data("{}".utf8)
    let b = geometry.bounds(size) ?? Rect(0, 0, 0, 0)
    return ItemRow(id: id, z: z, kind: 1, pen: pen, color: color, size: size, payload: data, l: b.left, t: b.top, r: b.right, b: b.bottom)
  }
}

extension ShapeRow {
  /// Its item row, with its own id and z.
  public var itemRow: ItemRow { row(id: id, z: z) }
}

/// A typed text box (Android's `TextItem`, item kind 3): its text, top-left, width it wraps in, its
/// own height (0 = the text's), font size (the row's size) and colour.
public struct TextRow: Sendable, Equatable {
  public var id: String = ""
  public var z: Int64 = 0
  public var text: String
  public var x: Float
  public var y: Float
  public var width: Float
  public var height: Float = 0
  public var fontSize: Float
  public var color: Int32
  public var locked = false

  /// Line height as a multiple of the font size (Android's `TextItem.LINE`).
  public static let line: Float = 1.3
  /// The size new text boxes start at (Android's `TEXT_SIZE`).
  public static let defaultSize: Float = 26

  public init(id: String = "", z: Int64 = 0, text: String, x: Float, y: Float, width: Float, height: Float = 0, fontSize: Float, color: Int32, locked: Bool = false) {
    self.id = id
    self.z = z
    self.text = text
    self.x = x
    self.y = y
    self.width = width
    self.height = height
    self.fontSize = fontSize
    self.color = color
    self.locked = locked
  }

  public init?(_ row: ItemRow) {
    guard row.kind == 3, let o = try? JSONSerialization.jsonObject(with: row.payload) as? [String: Any], let text = o["text"] as? String else { return nil }
    func f(_ k: String) -> Float { (o[k] as? NSNumber)?.floatValue ?? 0 }
    self.init(
      id: row.id, z: row.z, text: text, x: f("x"), y: f("y"), width: max(f("width"), 1), height: f("height"), fontSize: row.size > 0 ? row.size : TextRow.defaultSize,
      color: row.color, locked: (o["locked"] as? Bool) ?? false)
  }

  /// The row Android's `ItemCodec` writes ([textHeight]: how tall the laid-out text is, for its bounds).
  public func row(textHeight: Float) -> ItemRow {
    func n(_ v: Float) -> Double { Double("\(v)") ?? Double(v) }
    var o: [String: Any] = ["text": text, "x": n(x), "y": n(y), "width": n(width)]
    if locked { o["locked"] = true }
    if height != 0 { o["height"] = n(height) }
    let data = (try? JSONSerialization.data(withJSONObject: o)) ?? Data()
    let h = max(textHeight, fontSize * TextRow.line, height)
    return ItemRow(id: id, z: z, kind: 3, pen: nil, color: color, size: fontSize, payload: data, l: x, t: y, r: x + width, b: y + h)
  }
}
