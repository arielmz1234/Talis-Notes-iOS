import Foundation

// Magnetic snapping for shapes, ported from Android's `geometry/Snap.kt` (and `snapFeatures()` in
// `model/Shapes.kt`). Kept line for line so a drag snaps the same on both.

/// What something offers to snap to, in world units: its key points (corners, ends, middles,
/// centres), its segments (straight edges, and short pieces of curves) and its box. `middleOnly`:
/// only the middle of its box lines up (handwriting picked up with the lasso), and nothing of it touches.
public struct SnapFeatures: Sendable {
  public var points: [Pt]
  public var segments: [(Pt, Pt)]
  public var box: Rect?
  public var middleOnly: Bool

  public init(_ points: [Pt], _ segments: [(Pt, Pt)], _ box: Rect?, middleOnly: Bool = false) {
    self.points = points
    self.segments = segments
    self.box = box
    self.middleOnly = middleOnly
  }

  public func moved(_ dx: Float, _ dy: Float) -> SnapFeatures {
    if dx == 0 && dy == 0 { return self }
    let d = Pt(dx, dy)
    return SnapFeatures(points.map { $0 + d }, segments.map { ($0.0 + d, $0.1 + d) }, box.map { Rect($0.left + dx, $0.top + dy, $0.right + dx, $0.bottom + dy) }, middleOnly: middleOnly)
  }

  public static func of(_ parts: [SnapFeatures]) -> SnapFeatures {
    let boxes = parts.compactMap(\.box)
    return SnapFeatures(parts.flatMap(\.points), parts.flatMap(\.segments), boxes.dropFirst().reduce(boxes.first) { $0?.union($1) })
  }

  /// Just the middle of [box], for handwriting.
  public static func middleOf(_ box: Rect) -> SnapFeatures { SnapFeatures([], [], box, middleOnly: true) }
}

/// A guide shown while something is held snapped.
public enum SnapGuide: Sendable, Equatable {
  /// Two things lined up: a line along x = at (vertical) or y = at, reaching from..to the other way.
  case align(vertical: Bool, at: Float, from: Float, to: Float)
  /// Touching: a point resting on another shape's point or edge.
  case touch(Pt)

  public var isTouch: Bool { if case .touch = self { true } else { false } }
}

public struct SnapResult: Sendable {
  public var offset: Pt
  public var guides: [SnapGuide]
  public static let none = SnapResult(offset: Pt(0, 0), guides: [])
}

/// One drag's snapping: how far things catch, and what she has pulled free of (Android's `SnapSession`).
public final class SnapSession {
  public private(set) var contact: Float
  public private(set) var align: Float
  private var engaged: Set<Int64> = []
  private var escaped: Set<Int64> = []
  private var seen: [Int64: Float] = [:]
  private var catchOf: [Int64: Float] = [:]
  private var used: Set<Int64> = []

  /// A lock she pulled free of catches again once she's this many `contact`s from it.
  public static let rearm: Float = 3

  public init(contact: Float, align: Float? = nil) {
    self.contact = contact
    self.align = align ?? contact
  }

  public var reach: Float { contact * Self.rearm }

  /// Starts a frame; contact and align follow the zoom.
  public func begin(contact: Float? = nil, align: Float? = nil) {
    if let contact { self.contact = contact }
    if let align { self.align = align }
    seen.removeAll(keepingCapacity: true)
    catchOf.removeAll(keepingCapacity: true)
    used.removeAll(keepingCapacity: true)
  }

  func catches(_ key: Int64, _ dist: Float, _ firm: Bool) -> Bool {
    let tol = firm ? contact : align
    if let before = seen[key], dist >= before {
    } else {
      seen[key] = dist
      catchOf[key] = tol
    }
    return dist < tol && !escaped.contains(key)
  }

  func use(_ key: Int64) { used.insert(key) }

  /// Ends a frame: a lock held last frame that's now further than it catches from was pulled free of.
  public func end() {
    for k in engaged where !used.contains(k) {
      let d = seen[k]
      if d == nil || d! >= (catchOf[k] ?? 0) { escaped.insert(k) }
    }
    escaped = escaped.filter { (seen[$0] ?? .greatestFiniteMagnitude) <= reach }
    engaged = used
  }

  public var holding: Bool { !used.isEmpty }
}

public enum Snap {
  private static let axis: Float = 0.02
  private static let touchBias: Float = 0.75
  private static let pointBias: Float = 0.5
  private static let middleBias: Float = 0.8
  private static let same: Float = 0.05

  private static let kAlignX = 1, kAlignY = 2, kPoint = 3, kEdge = 4, kEdgeBack = 5, kScaleX = 6, kScaleY = 7, kDotX = 8, kDotY = 9

  private static func key(_ kind: Int, _ a: Int, _ b: Int = 0, _ c: Int = 0, _ d: Int = 0) -> Int64 {
    var h = Int64(kind)
    for v in [a, b, c, d] { h = h &* 1_000_003 &+ Int64(v) }
    return h
  }

  private static func pointKey(_ q: Pt, _ moving: Int = 0) -> Int64 { key(kPoint, Int(kround(q.x * 8)), Int(kround(q.y * 8)), moving) }

  private static func edgeKey(_ q: Pt, _ a: Pt, _ b: Pt, _ kind: Int, _ ti: Int, _ si: Int, _ moving: Int = 0) -> Int64 {
    q == a || q == b ? pointKey(q, moving) : key(kind, ti, si, moving)
  }

  private struct Option {
    let score: Float, delta: Float, guide: SnapGuide, key: Int64
  }

  private final class Best {
    var options: [Option] = []
    var best: Option?
    func offer(_ score: Float, _ delta: Float, _ guide: SnapGuide, _ key: Int64) {
      let o = Option(score: score, delta: delta, guide: guide, key: key)
      options.append(o)
      if score < (best?.score ?? .greatestFiniteMagnitude) { best = o }
    }
    var score: Float { best?.score ?? .greatestFiniteMagnitude }
    var delta: Float { best?.delta ?? 0 }
    func winners() -> [Option] {
      guard let win = best else { return [] }
      if win.guide.isTouch { return [win] }
      return options.filter { abs($0.delta - win.delta) < Snap.same && !$0.guide.isTouch }
    }
  }

  private final class Both {
    var score: Float = .greatestFiniteMagnitude
    var offset = Pt(0, 0)
    var guide: SnapGuide?
    var key: Int64 = 0
  }

  /// Lining-up guides along the same line become one.
  private static func mergeAligns(_ all: [SnapGuide]) -> [SnapGuide] {
    var out: [(vertical: Bool, at: Float, from: Float, to: Float)] = []
    let aligns = all.compactMap { g -> (vertical: Bool, at: Float, from: Float, to: Float)? in
      if case let .align(v, at, f, t) = g { return (v, at, f, t) }
      return nil
    }
    for g in aligns.sorted(by: { $0.at < $1.at }) {
      if let last = out.last, last.vertical == g.vertical, abs(last.at - g.at) < same {
        out[out.count - 1] = (last.vertical, last.at, min(last.from, g.from), max(last.to, g.to))
      } else {
        out.append(g)
      }
    }
    return out.map { .align(vertical: $0.vertical, at: $0.at, from: $0.from, to: $0.to) }
  }

  private static func show(_ picked: [Option], _ s: SnapSession) -> [SnapGuide] {
    for p in picked { s.use(p.key) }
    let touch = picked.filter { $0.guide.isTouch }.min { $0.score < $1.score }
    return mergeAligns(picked.map(\.guide)) + (touch.map { [$0.guide] } ?? [])
  }

  private static func vertical(_ a: Pt, _ b: Pt) -> Bool { abs(a.x - b.x) <= abs(a.y - b.y) * axis }
  private static func horizontal(_ a: Pt, _ b: Pt) -> Bool { abs(a.y - b.y) <= abs(a.x - b.x) * axis }

  /// The nearest point to [p] on the segment [a]–[b].
  public static func nearestOn(_ p: Pt, _ a: Pt, _ b: Pt) -> Pt {
    let ab = b - a
    let len = ab.dot(ab)
    if len < 1e-6 { return a }
    let t = min(max((p - a).dot(ab) / len, 0), 1)
    return a + ab * t
  }

  public static func move(_ moving: SnapFeatures, _ targets: [SnapFeatures], tol: Float) -> SnapResult {
    move(moving, targets, SnapSession(contact: tol))
  }

  /// How far to move [moving] (already at its unsnapped place) to lock onto [targets].
  public static func move(_ moving: SnapFeatures, _ targets: [SnapFeatures], _ s: SnapSession) -> SnapResult {
    if targets.isEmpty { return .none }
    let bx = Best(), by = Best(), two = Both()
    let mb = moving.box
    let reach = s.reach
    let near = mb?.outset(reach)
    for (ti, t) in targets.enumerated() {
      let tb = t.box
      if let mb, let tb {
        let mx = moving.middleOnly ? [mb.center.x] : [mb.left, mb.center.x, mb.right]
        let tx = [tb.left, tb.center.x, tb.right]
        for mi in mx.indices {
          for vi in tx.indices {
            let d = tx[vi] - mx[mi]
            let middle = vi == 1 && (mx.count == 1 || mi == 1)
            let k = key(kAlignX, ti, mi, vi)
            if abs(d) < reach && s.catches(k, abs(d), middle) {
              bx.offer(abs(d) * (middle ? middleBias : 1), d, .align(vertical: true, at: tx[vi], from: min(mb.top, tb.top), to: max(mb.bottom, tb.bottom)), k)
            }
          }
        }
        let my = moving.middleOnly ? [mb.center.y] : [mb.top, mb.center.y, mb.bottom]
        let ty = [tb.top, tb.center.y, tb.bottom]
        for mi in my.indices {
          for vi in ty.indices {
            let d = ty[vi] - my[mi]
            let middle = vi == 1 && (my.count == 1 || mi == 1)
            let k = key(kAlignY, ti, mi, vi)
            if abs(d) < reach && s.catches(k, abs(d), middle) {
              by.offer(abs(d) * (middle ? middleBias : 1), d, .align(vertical: false, at: ty[vi], from: min(mb.left, tb.left), to: max(mb.right, tb.right)), k)
            }
          }
        }
      }
      // Touching only matters for things within reach.
      if let near, let tb, !near.intersects(tb.outset(reach)) { continue }
      for (pi, p) in moving.points.enumerated() {
        for q in t.points {
          let d = p.dist(q)
          let k = pointKey(q, pi + 1)
          if d < reach && s.catches(k, d, true) && d * pointBias < two.score {
            two.score = d * pointBias
            two.offset = q - p
            two.guide = .touch(q)
            two.key = k
          }
        }
      }
      for (si, seg) in t.segments.enumerated() {
        for (pi, p) in moving.points.enumerated() {
          touch(p, seg.0, seg.1, s, key(kEdge, ti, si, pi), pi, bx, by, two, sign: 1)
        }
      }
      for (si, seg) in moving.segments.enumerated() {
        for (qi, q) in t.points.enumerated() {
          touch(q, seg.0, seg.1, s, key(kEdgeBack, ti, qi, si), -1, bx, by, two, sign: -1)
        }
      }
    }
    if let g = two.guide, two.score <= min(bx.score, by.score) {
      s.use(two.key)
      return SnapResult(offset: two.offset, guides: [g])
    }
    let wx = bx.winners(), wy = by.winners()
    if wx.isEmpty && wy.isEmpty { return .none }
    return SnapResult(offset: Pt(wx.isEmpty ? 0 : bx.delta, wy.isEmpty ? 0 : by.delta), guides: show(wx + wy, s))
  }

  public static func scale(_ box: Rect, _ anchor: Pt, _ k: Float, _ targets: [SnapFeatures], tol: Float) -> (Float, [SnapGuide]) {
    scale(box, anchor, k, targets, SnapSession(contact: tol))
  }

  /// Resizing from the corner opposite [anchor]: the scale [k] nudged so the far side or middle lines
  /// up with something. Only a way the box really reaches counts.
  public static func scale(_ box: Rect, _ anchor: Pt, _ k: Float, _ targets: [SnapFeatures], _ s: SnapSession, middleOnly: Bool = false) -> (Float, [SnapGuide]) {
    func at(_ v: Float, _ a: Float, _ f: Float) -> Float { a + (v - a) * f }
    let now = Rect(at(box.left, anchor.x, k), at(box.top, anchor.y, k), at(box.right, anchor.x, k), at(box.bottom, anchor.y, k))
    let extent = max(box.right - anchor.x, box.bottom - anchor.y)
    let lever = max(extent * 0.2, s.contact)
    var bestErr = Float.greatestFiniteMagnitude
    var bestS = k
    var bestKey: Int64 = 0
    for (ti, t) in targets.enumerated() {
      guard let tb = t.box else { continue }
      let xs = [tb.left, tb.center.x, tb.right]
      let ys = [tb.top, tb.center.y, tb.bottom]
      for vi in 0...2 {
        for (ei, pair) in [(now.right, box.right), (now.center.x, box.center.x)].enumerated() {
          let (edge, base) = pair
          if middleOnly && ei == 0 { continue }
          if abs(base - anchor.x) < lever { continue }
          let err = abs(xs[vi] - edge)
          let kk = key(kScaleX, ti, vi, ei)
          if err < s.reach && s.catches(kk, err, vi == 1 && ei == 1) && err < bestErr {
            bestErr = err
            bestS = (xs[vi] - anchor.x) / (base - anchor.x)
            bestKey = kk
          }
        }
        for (ei, pair) in [(now.bottom, box.bottom), (now.center.y, box.center.y)].enumerated() {
          let (edge, base) = pair
          if middleOnly && ei == 0 { continue }
          if abs(base - anchor.y) < lever { continue }
          let err = abs(ys[vi] - edge)
          let kk = key(kScaleY, ti, vi, ei)
          if err < s.reach && s.catches(kk, err, vi == 1 && ei == 1) && err < bestErr {
            bestErr = err
            bestS = (ys[vi] - anchor.y) / (base - anchor.y)
            bestKey = kk
          }
        }
      }
    }
    if bestErr == .greatestFiniteMagnitude || bestS <= 0 { return (k, []) }
    s.use(bestKey)
    let moved = SnapFeatures([], [], Rect(at(box.left, anchor.x, bestS), at(box.top, anchor.y, bestS), at(box.right, anchor.x, bestS), at(box.bottom, anchor.y, bestS)), middleOnly: middleOnly)
    let lined = move(moved, targets.map { SnapFeatures([], [], $0.box) }, tol: same * 4)
    return (bestS, lined.guides)
  }

  /// Point [p] against segment [a]–[b] (sign 1: [p] moves; -1: the segment moves).
  private static func touch(_ p: Pt, _ a: Pt, _ b: Pt, _ s: SnapSession, _ k: Int64, _ pi: Int, _ bx: Best, _ by: Best, _ two: Both, sign: Float) {
    let reach = s.reach
    if vertical(a, b) {
      if p.y < min(a.y, b.y) - s.contact || p.y > max(a.y, b.y) + s.contact { return }
      let x = (a.x + b.x) / 2
      let d = x - p.x
      if abs(d) < reach && s.catches(k, abs(d), true) {
        bx.offer(abs(d) * touchBias, d * sign, .touch(Pt(sign > 0 ? x : p.x, min(max(p.y, min(a.y, b.y)), max(a.y, b.y)))), k)
      }
    } else if horizontal(a, b) {
      if p.x < min(a.x, b.x) - s.contact || p.x > max(a.x, b.x) + s.contact { return }
      let y = (a.y + b.y) / 2
      let d = y - p.y
      if abs(d) < reach && s.catches(k, abs(d), true) {
        by.offer(abs(d) * touchBias, d * sign, .touch(Pt(min(max(p.x, min(a.x, b.x)), max(a.x, b.x)), sign > 0 ? y : p.y)), k)
      }
    } else {
      let q = nearestOn(p, a, b)
      let d = p.dist(q)
      let kk = sign > 0 && (q == a || q == b) ? pointKey(q, pi + 1) : k
      if d < reach && s.catches(kk, d, true) && d * touchBias < two.score {
        two.score = d * touchBias
        two.offset = (q - p) * sign
        two.guide = .touch(sign > 0 ? q : p)
        two.key = kk
      }
    }
  }

  public static func alignPoint(_ p: Pt, _ targets: [SnapFeatures], tol: Float) -> (Pt, [SnapGuide]) {
    alignPoint(p, targets, SnapSession(contact: tol))
  }

  /// A dot being dragged to [p] lines up with the sides, middles and corners of [targets], each way on its own.
  public static func alignPoint(_ p: Pt, _ targets: [SnapFeatures], _ s: SnapSession) -> (Pt, [SnapGuide]) {
    let bx = Best(), by = Best()
    let reach = s.reach
    for (ti, t) in targets.enumerated() {
      if let tb = t.box {
        for (vi, v) in [tb.left, tb.center.x, tb.right].enumerated() {
          let d = v - p.x
          let k = key(kAlignX, ti, vi)
          if abs(d) < reach && s.catches(k, abs(d), vi == 1) {
            bx.offer(abs(d) * (vi == 1 ? middleBias : 1), d, .align(vertical: true, at: v, from: min(p.y, tb.top), to: max(p.y, tb.bottom)), k)
          }
        }
        for (vi, v) in [tb.top, tb.center.y, tb.bottom].enumerated() {
          let d = v - p.y
          let k = key(kAlignY, ti, vi)
          if abs(d) < reach && s.catches(k, abs(d), vi == 1) {
            by.offer(abs(d) * (vi == 1 ? middleBias : 1), d, .align(vertical: false, at: v, from: min(p.x, tb.left), to: max(p.x, tb.right)), k)
          }
        }
      }
      for (qi, q) in t.points.enumerated() {
        let dx = q.x - p.x
        let kx = key(kDotX, ti, qi)
        if abs(dx) < reach && s.catches(kx, abs(dx), false) { bx.offer(abs(dx), dx, .align(vertical: true, at: q.x, from: min(p.y, q.y), to: max(p.y, q.y)), kx) }
        let dy = q.y - p.y
        let ky = key(kDotY, ti, qi)
        if abs(dy) < reach && s.catches(ky, abs(dy), false) { by.offer(abs(dy), dy, .align(vertical: false, at: q.y, from: min(p.x, q.x), to: max(p.x, q.x)), ky) }
      }
    }
    let wx = bx.winners(), wy = by.winners()
    return (Pt(p.x + (wx.isEmpty ? 0 : bx.delta), p.y + (wy.isEmpty ? 0 : by.delta)), show(wx + wy, s))
  }

  public static func alongAngle(_ from: Pt, _ to: Pt, _ targets: [SnapFeatures], tol: Float) -> (Pt, [SnapGuide]) {
    alongAngle(from, to, targets, SnapSession(contact: tol))
  }

  /// A line's end at [to], on a tidy angle from [from], slides along the line to line up with the
  /// sides, middles and corners of [targets].
  public static func alongAngle(_ from: Pt, _ to: Pt, _ targets: [SnapFeatures], _ s: SnapSession) -> (Pt, [SnapGuide]) {
    let len = to.dist(from)
    if len < 1e-3 { return (to, []) }
    let dir = (to - from) * (1 / len)
    let best = Best()
    let reach = s.reach
    func offer(_ vertical: Bool, _ v: Float, _ k: Int64, _ middle: Bool, _ spanFrom: Float, _ spanTo: Float) {
      let d = vertical ? dir.x : dir.y
      if abs(d) < 0.2 { return }
      let t = (v - (vertical ? from.x : from.y)) / d
      if t <= 0 { return }
      let shift = t - len
      if abs(shift) >= reach || !s.catches(k, abs(shift), middle) { return }
      let q = from + dir * t
      let guide: SnapGuide = vertical
        ? .align(vertical: true, at: v, from: min(q.y, spanFrom), to: max(q.y, spanTo))
        : .align(vertical: false, at: v, from: min(q.x, spanFrom), to: max(q.x, spanTo))
      best.offer(abs(shift) * (middle ? middleBias : 1), shift, guide, k)
    }
    for (ti, t) in targets.enumerated() {
      if let tb = t.box {
        for (vi, v) in [tb.left, tb.center.x, tb.right].enumerated() { offer(true, v, key(kAlignX, ti, vi), vi == 1, tb.top, tb.bottom) }
        for (vi, v) in [tb.top, tb.center.y, tb.bottom].enumerated() { offer(false, v, key(kAlignY, ti, vi), vi == 1, tb.left, tb.right) }
      }
      for (qi, q) in t.points.enumerated() {
        offer(true, q.x, key(kDotX, ti, qi), false, q.y, q.y)
        offer(false, q.y, key(kDotY, ti, qi), false, q.x, q.x)
      }
    }
    let win = best.winners()
    if win.isEmpty { return (to, []) }
    return (from + dir * (len + best.delta), show(win, s))
  }

  public static func corner(_ p: Pt, _ targets: [SnapFeatures], tol: Float) -> Pt? { corner(p, targets, SnapSession(contact: tol)) }

  /// The nearest end or corner of [targets] that catches [p].
  public static func corner(_ p: Pt, _ targets: [SnapFeatures], _ s: SnapSession) -> Pt? {
    var best: Pt?
    var bestKey: Int64 = 0
    var dist = Float.greatestFiniteMagnitude
    for t in targets {
      for q in t.points {
        let d = p.dist(q)
        let k = pointKey(q)
        if d < s.reach && s.catches(k, d, true) && d < dist {
          dist = d
          best = q
          bestKey = k
        }
      }
    }
    if best != nil { s.use(bestKey) }
    return best
  }

  public static func alongLine(_ from: Pt, _ to: Pt, _ targets: [SnapFeatures], tol: Float) -> Pt? { alongLine(from, to, targets, SnapSession(contact: tol)) }

  /// Where the line from [from] through [to] meets an edge of [targets] near [to].
  public static func alongLine(_ from: Pt, _ to: Pt, _ targets: [SnapFeatures], _ s: SnapSession) -> Pt? {
    let dir = to - from
    if dir.length() < 1e-3 { return nil }
    var best: Pt?
    var bestKey: Int64 = 0
    var dist = Float.greatestFiniteMagnitude
    for (ti, t) in targets.enumerated() {
      if let tb = t.box, !tb.outset(s.reach).contains(to) { continue }
      for (si, seg) in t.segments.enumerated() {
        let (a, b) = seg
        let e = b - a
        let den = dir.cross(e)
        if abs(den) < 1e-6 { continue }
        let u = (a - from).cross(dir) / den
        if u < -1e-4 || u > 1 + 1e-4 { continue }
        let q = u <= 0 ? a : (u >= 1 ? b : a + e * u)
        let d = q.dist(to)
        let k = edgeKey(q, a, b, kEdge, ti, si)
        if d < s.reach && s.catches(k, d, true) && d < dist {
          dist = d
          best = q
          bestKey = k
        }
      }
    }
    if best != nil { s.use(bestKey) }
    return best
  }

  public static func point(_ p: Pt, _ targets: [SnapFeatures], tol: Float) -> Pt? { point(p, targets, SnapSession(contact: tol)) }

  /// Where a single point being dragged locks on: another shape's end or corner first, else the nearest place on an edge.
  public static func point(_ p: Pt, _ targets: [SnapFeatures], _ s: SnapSession) -> Pt? {
    var best: Pt?
    var bestKey: Int64 = 0
    var score = Float.greatestFiniteMagnitude
    for (ti, t) in targets.enumerated() {
      if let tb = t.box, !tb.outset(s.reach).contains(p) { continue }
      for q in t.points {
        let d = p.dist(q)
        let k = pointKey(q)
        if d < s.reach && s.catches(k, d, true) && d * pointBias < score {
          score = d * pointBias
          best = q
          bestKey = k
        }
      }
      for (si, seg) in t.segments.enumerated() {
        let q = nearestOn(p, seg.0, seg.1)
        let d = p.dist(q)
        let k = edgeKey(q, seg.0, seg.1, kEdge, ti, si)
        if d < s.reach && s.catches(k, d, true) && d < score {
          score = d
          best = q
          bestKey = k
        }
      }
    }
    if best != nil { s.use(bestKey) }
    return best
  }
}

extension ShapeGeometry {
  /// What this shape offers for snapping: its ends, corners, side middles and centre, its edges (a
  /// curve as short pieces), and the box of its outline. Arrow barbs and dimension marks aren't edges.
  public func snapFeatures() -> SnapFeatures {
    func segs(_ path: [Pt], closed: Bool = false) -> [(Pt, Pt)] {
      var out: [(Pt, Pt)] = []
      if path.count > 1 { for i in 0..<(path.count - 1) { out.append((path[i], path[i + 1])) } }
      if closed && path.count > 2 { out.append((path.last!, path.first!)) }
      return out
    }
    func mid(_ a: Pt, _ b: Pt) -> Pt { Pt((a.x + b.x) / 2, (a.y + b.y) / 2) }
    let points: [Pt]
    let segments: [(Pt, Pt)]
    switch self {
    case let .line(a, b, _, _, _):
      points = [a, b, mid(a, b)]
      segments = [(a, b)]
    case let .poly(p, closed, smooth, _, _):
      if smooth {
        points = [p.first!, p.last!]
        segments = segs(Geo.smooth(p))
      } else {
        let s = segs(p, closed: closed)
        points = p + s.map { mid($0.0, $0.1) } + (closed ? [Geo.centroid(p)] : [])
        segments = s
      }
    case let .triangle(a, b, c, _):
      let s = segs([a, b, c], closed: true)
      points = [a, b, c] + s.map { mid($0.0, $0.1) }
      segments = s
    case let .ellipse(center, _, _, _, _):
      points = [center] + ShapeGeometry.ellipseAxisPoints(self)
      segments = segs(paths(1)[0])
    case let .arc(center, radius, start, sweep, _):
      points = [center, center + Pt.polar(radius, start), center + Pt.polar(radius, start + sweep)]
      segments = segs(paths(1)[0])
    case let .sector(center, radius, start, sweep):
      points = [center, center + Pt.polar(radius, start), center + Pt.polar(radius, start + sweep)]
      segments = segs(paths(1)[0])
    case let .curve(p):
      points = [p.first!, p.last!]
      segments = segs(paths(1)[0])
    case let .load(a, b, _, _):
      let tip = handles()[2]
      let ta = a + (tip - mid(a, b)), tb = b + (tip - mid(a, b))
      points = [a, b, mid(a, b), ta, tb, tip]
      segments = [(a, b), (ta, tb), (a, ta), (b, tb)]
    case .param:
      // Its drawing comes with the templates, not ported yet.
      return SnapFeatures([], [], nil)
    case let .group(parts, _):
      // The hatching under a support (five or more short plain lines) doesn't snap.
      let box = Rect.around(parts.flatMap { $0.paths(1).joined() })
      let reach = box.map { Pt($0.width, $0.height).length() } ?? 0
      let shortIdx = parts.indices.filter { i in
        if case let .line(a, b, s, e, t) = parts[i], !s, !e, !t, a.dist(b) < reach * 0.3 { return true }
        return false
      }
      let hatching = shortIdx.count >= 5 ? Set(shortIdx) : []
      return SnapFeatures.of(parts.indices.filter { !hatching.contains($0) }.map { parts[$0].snapFeatures() })
    }
    let box = Rect.around(points + segments.flatMap { [$0.0, $0.1] })
    return SnapFeatures(points, segments, box)
  }

  /// An ellipse's four axis points (its dots when it isn't a circle).
  static func ellipseAxisPoints(_ g: ShapeGeometry) -> [Pt] {
    guard case let .ellipse(center, rx, ry, rotation, _) = g else { return [] }
    return [0, Float.pi / 2, Float.pi, 1.5 * Float.pi].map { center + Pt(rx * cosf($0), ry * sinf($0)).rotated(rotation) }
  }
}
