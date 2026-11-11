import Foundation

// A port of the Android app's `geometry/Snap.kt` and `snapFeatures()` in `model/Shapes.kt`. Keep them in step.

/// What something offers to snap to, in world units: its key [points] (corners, ends, middles,
/// centres), its [segments] (straight edges, and short pieces of curves) and its [box] (the drawn
/// outline's extent, without the pen's thickness). [middleOnly]: only the middle of its box lines
/// up (handwriting picked up with the lasso), and nothing of it touches.
public struct SnapFeatures: Sendable {
  public var points: [Pt]
  public var segments: [(a: Pt, b: Pt)]
  public var box: Rect?
  public var middleOnly: Bool

  public init(points: [Pt], segments: [(a: Pt, b: Pt)], box: Rect?, middleOnly: Bool = false) {
    self.points = points
    self.segments = segments
    self.box = box
    self.middleOnly = middleOnly
  }

  public func moved(_ dx: Float, _ dy: Float) -> SnapFeatures {
    if dx == 0 && dy == 0 { return self }
    let d = Pt(dx, dy)
    return SnapFeatures(
      points: points.map { $0 + d }, segments: segments.map { ($0.a + d, $0.b + d) },
      box: box.map { Rect($0.left + dx, $0.top + dy, $0.right + dx, $0.bottom + dy) }, middleOnly: middleOnly)
  }

  public static func of(_ parts: [SnapFeatures]) -> SnapFeatures {
    let boxes = parts.compactMap(\.box)
    return SnapFeatures(points: parts.flatMap(\.points), segments: parts.flatMap(\.segments), box: boxes.dropFirst().reduce(boxes.first) { $0?.union($1) })
  }

  /// Just the middle of [box], for handwriting: it lines up its middle with shapes, and nothing lines up with it.
  public static func middleOf(_ box: Rect) -> SnapFeatures { SnapFeatures(points: [], segments: [], box: box, middleOnly: true) }

  /// A picture or a text box: its corners and middle, its four sides.
  public static func ofBox(_ r: Rect) -> SnapFeatures {
    let c = [Pt(r.left, r.top), Pt(r.right, r.top), Pt(r.right, r.bottom), Pt(r.left, r.bottom)]
    return SnapFeatures(points: c + [r.center], segments: c.indices.map { (c[$0], c[($0 + 1) % 4]) }, box: r)
  }
}

/// A guide shown while something is held snapped.
public enum SnapGuide: Equatable, Sendable {
  /// Two things lined up: a line along x = [at] ([vertical]) or y = [at], reaching [from]..[to] the other way.
  case align(vertical: Bool, at: Float, from: Float, to: Float)
  /// Touching: a point resting on another shape's point or edge.
  case touch(Pt)

  public var isTouch: Bool {
    if case .touch = self { return true }
    return false
  }
}

/// How far to nudge what's being moved, and the guides that show why.
public struct SnapResult: Sendable {
  public var offset: Pt
  public var guides: [SnapGuide]

  public static let none = SnapResult(offset: .zero, guides: [])
}

/// A lock's name: its kind, and the indices naming what meets what.
struct SnapKey: Hashable {
  enum Kind { case alignX, alignY, point, edge, edgeBack, scaleX, scaleY, dotX, dotY }
  var kind: Kind
  var a = 0
  var b = 0
  var c = 0
}

/// One drag's snapping: how far things catch, and what she has pulled free of.
///
/// Touching (an end or corner onto another shape's end, corner or edge) and middles lining up catch
/// from [contact] away and hold firmly; sides lining up with something at a distance are softer,
/// catching only from [align]. When she pulls something out of a lock, that lock lets go for the
/// rest of the drag, until she moves well away from it ([rearm] times [contact]); after that it
/// catches again, so coming back to it on purpose still works.
///
/// Each frame: [begin], then any of [Snap]'s functions, then [end].
public final class SnapSession {
  /// A lock she pulled free of catches again once she's this many [contact]s from it.
  public static let rearm: Float = 3

  public private(set) var contact: Float
  public private(set) var align: Float
  private var engaged: Set<SnapKey> = []
  private var escaped: Set<SnapKey> = []
  private var seen: [SnapKey: Float] = [:]
  private var catchOf: [SnapKey: Float] = [:]
  private var used: Set<SnapKey> = []

  public init(_ contact: Float, align: Float? = nil) {
    self.contact = contact
    self.align = align ?? contact
  }

  /// How far away locks are still watched (to notice pulling out of them, and moving away).
  public var reach: Float { contact * Self.rearm }

  /// Starts a frame; [contact] and [align] follow the zoom.
  public func begin(contact: Float? = nil, align: Float? = nil) {
    if let contact { self.contact = contact }
    if let align { self.align = align }
    seen.removeAll(keepingCapacity: true)
    catchOf.removeAll(keepingCapacity: true)
    used.removeAll(keepingCapacity: true)
  }

  /// Whether lock [key], [dist] away, catches: from [contact] when [firm] (a touch, or middles lining up), else from [align].
  func catches(_ key: SnapKey, _ dist: Float, firm: Bool) -> Bool {
    let tol = firm ? contact : align
    if seen[key].map({ dist < $0 }) ?? true {
      seen[key] = dist
      catchOf[key] = tol
    }
    return dist < tol && !escaped.contains(key)
  }

  func use(_ key: SnapKey) { used.insert(key) }

  /// Ends a frame: a lock held last frame that's now further than it catches from was pulled free
  /// of, and lets go; a lock let go of is back once she's moved away from it.
  public func end() {
    for k in engaged where !used.contains(k) {
      if seen[k].map({ $0 >= (catchOf[k] ?? 0) }) ?? true { escaped.insert(k) }
    }
    escaped = escaped.filter { (seen[$0] ?? .greatestFiniteMagnitude) <= reach }
    engaged = used
  }

  /// Whether anything is holding this frame.
  public var holding: Bool { !used.isEmpty }
}

/// Magnetic snapping for shapes, like a drawing app's smart guides. Moving something, it locks on
/// when it comes within reach of another shape: an end or corner onto another's corner or edge, and
/// its edges or middle lining up with another's top, bottom, sides or middle. Each direction snaps
/// on its own, so a box can sit on a line and line up with a neighbour at the same time.
public enum Snap {
  /// Edges this close to level or upright (as a share of their length) count as straight across or up.
  private static let axis: Float = 0.02
  /// A touch beats a lining-up at the same distance; an end on an end beats an end on an edge.
  private static let touchBias: Float = 0.75
  private static let pointBias: Float = 0.5
  /// Middles lining up hold firmly and win over a side at the same distance.
  private static let middleBias: Float = 0.8
  /// Two snaps this close (world units) land on the same place.
  private static let same: Float = 0.05

  /// By where the point is, so an edge whose nearest place is its own end counts as that corner:
  /// pulled free of a corner, the edges meeting there don't catch it back.
  private static func pointKey(_ q: Pt, moving: Int = 0) -> SnapKey {
    SnapKey(kind: .point, a: Int(javaRound(q.x * 8)), b: Int(javaRound(q.y * 8)), c: moving)
  }

  private static func edgeKey(_ q: Pt, _ a: Pt, _ b: Pt, target: Int, segment: Int) -> SnapKey {
    q == a || q == b ? pointKey(q) : SnapKey(kind: .edge, a: target, b: segment)
  }

  /// The ways one direction could lock on. The nearest wins; every other one that lands on the same
  /// place shows too (a box beside one the same size lines up at the top, middle and bottom at once).
  private struct Best {
    struct Option {
      var score: Float
      var delta: Float
      var guide: SnapGuide
      var key: SnapKey
    }

    var options: [Option] = []
    var best: Option?

    mutating func offer(_ score: Float, _ delta: Float, _ guide: SnapGuide, _ key: SnapKey) {
      let o = Option(score: score, delta: delta, guide: guide, key: key)
      options.append(o)
      if score < self.score { best = o }
    }

    var score: Float { best?.score ?? .greatestFiniteMagnitude }
    var delta: Float { best?.delta ?? 0 }

    /// The winner when it's a touch (one cross, where they meet), else every lining-up at the same place.
    var winners: [Option] {
      guard let win = best else { return [] }
      if win.guide.isTouch { return [win] }
      return options.filter { abs($0.delta - win.delta) < Snap.same && !$0.guide.isTouch }
    }
  }

  private struct Both {
    var score = Float.greatestFiniteMagnitude
    var offset = Pt.zero
    var guide: SnapGuide?
    var key = SnapKey(kind: .point)
  }

  /// Lining-up guides along the same line become one, reaching across everything lined up on it.
  private static func mergeAligns(_ all: [SnapGuide]) -> [SnapGuide] {
    func parts(_ g: SnapGuide) -> (vertical: Bool, at: Float, from: Float, to: Float)? {
      if case let .align(v, at, from, to) = g { return (v, at, from, to) }
      return nil
    }
    var out: [(vertical: Bool, at: Float, from: Float, to: Float)] = []
    for g in all.compactMap(parts).sorted(by: { $0.at < $1.at }) {
      if let last = out.last, last.vertical == g.vertical, abs(last.at - g.at) < same {
        out[out.count - 1] = (last.vertical, last.at, min(last.from, g.from), max(last.to, g.to))
      } else {
        out.append(g)
      }
    }
    return out.map { .align(vertical: $0.vertical, at: $0.at, from: $0.from, to: $0.to) }
  }

  /// Shows [picked] (using their locks) and returns their guides: lining-ups merged, at most one cross.
  private static func show(_ picked: [Best.Option], _ s: SnapSession) -> [SnapGuide] {
    for p in picked { s.use(p.key) }
    let touch = picked.filter(\.guide.isTouch).min { $0.score < $1.score }
    return mergeAligns(picked.map(\.guide).filter { !$0.isTouch }) + (touch.map { [$0.guide] } ?? [])
  }

  private static func vertical(_ a: Pt, _ b: Pt) -> Bool { abs(a.x - b.x) <= abs(a.y - b.y) * axis }
  private static func horizontal(_ a: Pt, _ b: Pt) -> Bool { abs(a.y - b.y) <= abs(a.x - b.x) * axis }
  private static func clamp(_ v: Float, _ lo: Float, _ hi: Float) -> Float { min(max(v, lo), hi) }

  /// The nearest point to [p] on the segment [a]–[b].
  public static func nearestOn(_ p: Pt, _ a: Pt, _ b: Pt) -> Pt {
    let ab = b - a
    let len = ab.dot(ab)
    if len < 1e-6 { return a }
    return a + ab * clamp((p - a).dot(ab) / len, 0, 1)
  }

  public static func move(_ moving: SnapFeatures, _ targets: [SnapFeatures], tol: Float) -> SnapResult { move(moving, targets, SnapSession(tol)) }

  /// How far to move [moving] (already at its unsnapped place) to lock onto [targets].
  public static func move(_ moving: SnapFeatures, _ targets: [SnapFeatures], _ s: SnapSession) -> SnapResult {
    if targets.isEmpty { return .none }
    var bx = Best(), by = Best(), two = Both()
    let mb = moving.box
    let reach = s.reach
    let near = mb?.outset(reach)
    for (ti, t) in targets.enumerated() {
      let tb = t.box
      // Lining up: sides and middles, each way. Handwriting lines up only its own middle, with
      // the other shape's sides and middle alike.
      if let mb, let tb {
        let mx = moving.middleOnly ? [mb.center.x] : [mb.left, mb.center.x, mb.right]
        let tx = [tb.left, tb.center.x, tb.right]
        for mi in mx.indices {
          for vi in tx.indices {
            let d = tx[vi] - mx[mi]
            let middle = vi == 1 && (mx.count == 1 || mi == 1)
            let k = SnapKey(kind: .alignX, a: ti, b: mi, c: vi)
            if abs(d) < reach, s.catches(k, abs(d), firm: middle) {
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
            let k = SnapKey(kind: .alignY, a: ti, b: mi, c: vi)
            if abs(d) < reach, s.catches(k, abs(d), firm: middle) {
              by.offer(abs(d) * (middle ? middleBias : 1), d, .align(vertical: false, at: ty[vi], from: min(mb.left, tb.left), to: max(mb.right, tb.right)), k)
            }
          }
        }
      }
      // Touching only matters for things within reach.
      if let near, let tb, !near.intersects(tb.outset(reach)) { continue }
      // An end or corner onto an end or corner.
      for (pi, p) in moving.points.enumerated() {
        for q in t.points {
          let d = p.dist(q)
          let k = pointKey(q, moving: pi + 1)
          if d < reach, s.catches(k, d, firm: true), d * pointBias < two.score {
            two = Both(score: d * pointBias, offset: q - p, guide: .touch(q), key: k)
          }
        }
      }
      // Moving points onto the target's edges, and the target's points onto moving edges.
      for (si, seg) in t.segments.enumerated() {
        for (pi, p) in moving.points.enumerated() { touch(p, seg.a, seg.b, s, SnapKey(kind: .edge, a: ti, b: si, c: pi), pi, &bx, &by, &two, sign: 1) }
      }
      for (si, seg) in moving.segments.enumerated() {
        for (qi, q) in t.points.enumerated() { touch(q, seg.a, seg.b, s, SnapKey(kind: .edgeBack, a: ti, b: qi, c: si), -1, &bx, &by, &two, sign: -1) }
      }
    }
    // One snap that fixes both ways (an end on an end, or on a slanted edge) wins if it's the nearest.
    if let guide = two.guide, two.score <= min(bx.score, by.score) {
      s.use(two.key)
      return SnapResult(offset: two.offset, guides: [guide])
    }
    let wx = bx.winners, wy = by.winners
    if wx.isEmpty && wy.isEmpty { return .none }
    return SnapResult(offset: Pt(wx.isEmpty ? 0 : bx.delta, wy.isEmpty ? 0 : by.delta), guides: show(wx + wy, s))
  }

  public static func scale(_ box: Rect, anchor: Pt, _ k: Float, _ targets: [SnapFeatures], tol: Float) -> (scale: Float, guides: [SnapGuide]) {
    scale(box, anchor: anchor, k, targets, SnapSession(tol))
  }

  /// Resizing from the corner opposite [anchor]: the scale [k] of [box] (as it was) nudged so its far
  /// side or middle lines up with something in [targets] (only its middle when [middleOnly], for
  /// handwriting). Only a way the box really reaches counts: a level line's height is next to
  /// nothing, and lining that up would throw its length wildly.
  public static func scale(_ box: Rect, anchor: Pt, _ k: Float, _ targets: [SnapFeatures], _ s: SnapSession, middleOnly: Bool = false) -> (scale: Float, guides: [SnapGuide]) {
    func at(_ v: Float, _ a: Float, _ f: Float) -> Float { a + (v - a) * f }
    func scaled(_ f: Float) -> Rect { Rect(at(box.left, anchor.x, f), at(box.top, anchor.y, f), at(box.right, anchor.x, f), at(box.bottom, anchor.y, f)) }
    let now = scaled(k)
    let extent = max(box.right - anchor.x, box.bottom - anchor.y)
    let lever = max(extent * 0.2, s.contact)
    var bestErr = Float.greatestFiniteMagnitude
    var bestS = k
    var bestKey: SnapKey?
    for (ti, t) in targets.enumerated() {
      guard let tb = t.box else { continue }
      // The far side and the middle move with the size; the near side stays at the anchor.
      let xs = [tb.left, tb.center.x, tb.right], ys = [tb.top, tb.center.y, tb.bottom]
      for vi in 0...2 {
        for (ei, pair) in [(now.right, box.right), (now.center.x, box.center.x)].enumerated() {
          let (edge, base) = pair
          if middleOnly && ei == 0 { continue }
          if abs(base - anchor.x) < lever { continue }
          let err = abs(xs[vi] - edge)
          let kk = SnapKey(kind: .scaleX, a: ti, b: vi, c: ei)
          if err < s.reach, s.catches(kk, err, firm: vi == 1 && ei == 1), err < bestErr {
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
          let kk = SnapKey(kind: .scaleY, a: ti, b: vi, c: ei)
          if err < s.reach, s.catches(kk, err, firm: vi == 1 && ei == 1), err < bestErr {
            bestErr = err
            bestS = (ys[vi] - anchor.y) / (base - anchor.y)
            bestKey = kk
          }
        }
      }
    }
    guard let bestKey, bestS > 0 else { return (k, []) }
    s.use(bestKey)
    // Everything that lines up at that size.
    let moved = SnapFeatures(points: [], segments: [], box: scaled(bestS), middleOnly: middleOnly)
    let lined = move(moved, targets.map { SnapFeatures(points: [], segments: [], box: $0.box) }, tol: same * 4)
    return (bestS, lined.guides)
  }

  /// Point [p] against segment [a]–[b] (sign 1: [p] moves; -1: the segment moves). Level and
  /// upright edges snap one way only (so the other way can still line up); slanted ones both ways.
  /// [pi] is which of the moving points [p] is (when it's the one moving).
  private static func touch(_ p: Pt, _ a: Pt, _ b: Pt, _ s: SnapSession, _ k: SnapKey, _ pi: Int, _ bx: inout Best, _ by: inout Best, _ two: inout Both, sign: Float) {
    let reach = s.reach
    if vertical(a, b) {
      if p.y < min(a.y, b.y) - s.contact || p.y > max(a.y, b.y) + s.contact { return }
      let x = (a.x + b.x) / 2
      let d = x - p.x
      if abs(d) < reach, s.catches(k, abs(d), firm: true) {
        bx.offer(abs(d) * touchBias, d * sign, .touch(Pt(sign > 0 ? x : p.x, clamp(p.y, min(a.y, b.y), max(a.y, b.y)))), k)
      }
    } else if horizontal(a, b) {
      if p.x < min(a.x, b.x) - s.contact || p.x > max(a.x, b.x) + s.contact { return }
      let y = (a.y + b.y) / 2
      let d = y - p.y
      if abs(d) < reach, s.catches(k, abs(d), firm: true) {
        by.offer(abs(d) * touchBias, d * sign, .touch(Pt(clamp(p.x, min(a.x, b.x), max(a.x, b.x)), sign > 0 ? y : p.y)), k)
      }
    } else {
      let q = nearestOn(p, a, b)
      let d = p.dist(q)
      // Onto the edge's end: the same lock as onto that corner.
      let kk = sign > 0 && (q == a || q == b) ? pointKey(q, moving: pi + 1) : k
      if d < reach, s.catches(kk, d, firm: true), d * touchBias < two.score {
        two = Both(score: d * touchBias, offset: (q - p) * sign, guide: .touch(sign > 0 ? q : p), key: kk)
      }
    }
  }

  public static func alignPoint(_ p: Pt, _ targets: [SnapFeatures], tol: Float) -> (at: Pt, guides: [SnapGuide]) { alignPoint(p, targets, SnapSession(tol)) }

  /// A dot being dragged to [p] (a shape's corner or side, a new shape's corner) lines up with the
  /// sides, middles and corners of [targets], each way on its own. Returns where it goes and the
  /// guides of everything it lines up with (none when it doesn't).
  public static func alignPoint(_ p: Pt, _ targets: [SnapFeatures], _ s: SnapSession) -> (at: Pt, guides: [SnapGuide]) {
    var bx = Best(), by = Best()
    let reach = s.reach
    for (ti, t) in targets.enumerated() {
      if let tb = t.box {
        for (vi, v) in [tb.left, tb.center.x, tb.right].enumerated() {
          let d = v - p.x
          let k = SnapKey(kind: .alignX, a: ti, b: vi)
          if abs(d) < reach, s.catches(k, abs(d), firm: vi == 1) {
            bx.offer(abs(d) * (vi == 1 ? middleBias : 1), d, .align(vertical: true, at: v, from: min(p.y, tb.top), to: max(p.y, tb.bottom)), k)
          }
        }
        for (vi, v) in [tb.top, tb.center.y, tb.bottom].enumerated() {
          let d = v - p.y
          let k = SnapKey(kind: .alignY, a: ti, b: vi)
          if abs(d) < reach, s.catches(k, abs(d), firm: vi == 1) {
            by.offer(abs(d) * (vi == 1 ? middleBias : 1), d, .align(vertical: false, at: v, from: min(p.x, tb.left), to: max(p.x, tb.right)), k)
          }
        }
      }
      for (qi, q) in t.points.enumerated() {
        let dx = q.x - p.x
        let kx = SnapKey(kind: .dotX, a: ti, b: qi)
        if abs(dx) < reach, s.catches(kx, abs(dx), firm: false) { bx.offer(abs(dx), dx, .align(vertical: true, at: q.x, from: min(p.y, q.y), to: max(p.y, q.y)), kx) }
        let dy = q.y - p.y
        let ky = SnapKey(kind: .dotY, a: ti, b: qi)
        if abs(dy) < reach, s.catches(ky, abs(dy), firm: false) { by.offer(abs(dy), dy, .align(vertical: false, at: q.y, from: min(p.x, q.x), to: max(p.x, q.x)), ky) }
      }
    }
    let wx = bx.winners, wy = by.winners
    return (Pt(p.x + (wx.isEmpty ? 0 : bx.delta), p.y + (wy.isEmpty ? 0 : by.delta)), show(wx + wy, s))
  }

  public static func alongAngle(_ from: Pt, _ to: Pt, _ targets: [SnapFeatures], tol: Float) -> (at: Pt, guides: [SnapGuide]) {
    alongAngle(from, to, targets, SnapSession(tol))
  }

  /// A line's end at [to], on a tidy angle from [from], slides along the line (keeping its angle) to
  /// line up with the sides, middles and corners of [targets]: a level line's end stops right above
  /// a box's side or middle, an upright one level with it. Returns where it goes and the guides
  /// (none when nothing lines up).
  public static func alongAngle(_ from: Pt, _ to: Pt, _ targets: [SnapFeatures], _ s: SnapSession) -> (at: Pt, guides: [SnapGuide]) {
    let len = to.dist(from)
    if len < 1e-3 { return (to, []) }
    let dir = (to - from) * (1 / len)
    var best = Best()
    let reach = s.reach
    // The end moved along the line to x = v (a vertical guide) or y = v (a level one).
    func offer(_ vertical: Bool, _ v: Float, _ k: SnapKey, _ middle: Bool, _ spanFrom: Float, _ spanTo: Float) {
      let d = vertical ? dir.x : dir.y
      if abs(d) < 0.2 { return }
      let t = (v - (vertical ? from.x : from.y)) / d
      if t <= 0 { return }
      let shift = t - len
      if abs(shift) >= reach || !s.catches(k, abs(shift), firm: middle) { return }
      let q = from + dir * t
      let guide: SnapGuide =
        vertical ? .align(vertical: true, at: v, from: min(q.y, spanFrom), to: max(q.y, spanTo)) : .align(vertical: false, at: v, from: min(q.x, spanFrom), to: max(q.x, spanTo))
      best.offer(abs(shift) * (middle ? middleBias : 1), shift, guide, k)
    }
    for (ti, t) in targets.enumerated() {
      if let tb = t.box {
        for (vi, v) in [tb.left, tb.center.x, tb.right].enumerated() { offer(true, v, SnapKey(kind: .alignX, a: ti, b: vi), vi == 1, tb.top, tb.bottom) }
        for (vi, v) in [tb.top, tb.center.y, tb.bottom].enumerated() { offer(false, v, SnapKey(kind: .alignY, a: ti, b: vi), vi == 1, tb.left, tb.right) }
      }
      for (qi, q) in t.points.enumerated() {
        offer(true, q.x, SnapKey(kind: .dotX, a: ti, b: qi), false, q.y, q.y)
        offer(false, q.y, SnapKey(kind: .dotY, a: ti, b: qi), false, q.x, q.x)
      }
    }
    let win = best.winners
    if win.isEmpty { return (to, []) }
    return (from + dir * (len + best.delta), show(win, s))
  }

  public static func corner(_ p: Pt, _ targets: [SnapFeatures], tol: Float) -> Pt? { corner(p, targets, SnapSession(tol)) }

  /// The nearest end or corner of [targets] that catches [p].
  public static func corner(_ p: Pt, _ targets: [SnapFeatures], _ s: SnapSession) -> Pt? {
    var best: (at: Pt, key: SnapKey)?
    var dist = Float.greatestFiniteMagnitude
    for t in targets {
      for q in t.points {
        let d = p.dist(q)
        let k = pointKey(q)
        if d < s.reach, s.catches(k, d, firm: true), d < dist {
          dist = d
          best = (q, k)
        }
      }
    }
    if let best { s.use(best.key) }
    return best?.at
  }

  public static func alongLine(_ from: Pt, _ to: Pt, _ targets: [SnapFeatures], tol: Float) -> Pt? { alongLine(from, to, targets, SnapSession(tol)) }

  /// Where the line from [from] through [to] meets an edge of [targets] near [to]: a line being drawn
  /// keeps its direction (its tidy angle) and just stops on the edge it reaches.
  public static func alongLine(_ from: Pt, _ to: Pt, _ targets: [SnapFeatures], _ s: SnapSession) -> Pt? {
    let dir = to - from
    if dir.length() < 1e-3 { return nil }
    var best: (at: Pt, key: SnapKey)?
    var dist = Float.greatestFiniteMagnitude
    for (ti, t) in targets.enumerated() {
      if let tb = t.box, !tb.outset(s.reach).contains(to) { continue }
      for (si, seg) in t.segments.enumerated() {
        let e = seg.b - seg.a
        let den = dir.cross(e)
        if abs(den) < 1e-6 { continue }
        // from + dir·s = a + e·u, with the meeting point on the edge (0..1 along it).
        let u = (seg.a - from).cross(dir) / den
        if u < -1e-4 || u > 1 + 1e-4 { continue }
        let q = u <= 0 ? seg.a : (u >= 1 ? seg.b : seg.a + e * u)
        let d = q.dist(to)
        let k = edgeKey(q, seg.a, seg.b, target: ti, segment: si)
        if d < s.reach, s.catches(k, d, firm: true), d < dist {
          dist = d
          best = (q, k)
        }
      }
    }
    if let best { s.use(best.key) }
    return best?.at
  }

  public static func point(_ p: Pt, _ targets: [SnapFeatures], tol: Float) -> Pt? { point(p, targets, SnapSession(tol)) }

  /// Where a single point being dragged (a line's end, a shape's dot, where a new shape starts)
  /// locks on: another shape's end or corner first, else the nearest place on an edge.
  public static func point(_ p: Pt, _ targets: [SnapFeatures], _ s: SnapSession) -> Pt? {
    var best: (at: Pt, key: SnapKey)?
    var score = Float.greatestFiniteMagnitude
    for (ti, t) in targets.enumerated() {
      if let tb = t.box, !tb.outset(s.reach).contains(p) { continue }
      for q in t.points {
        let d = p.dist(q)
        let k = pointKey(q)
        if d < s.reach, s.catches(k, d, firm: true), d * pointBias < score {
          score = d * pointBias
          best = (q, k)
        }
      }
      for (si, seg) in t.segments.enumerated() {
        let q = nearestOn(p, seg.a, seg.b)
        let d = p.dist(q)
        let k = edgeKey(q, seg.a, seg.b, target: ti, segment: si)
        if d < s.reach, s.catches(k, d, firm: true), d < score {
          score = d
          best = (q, k)
        }
      }
    }
    if let best { s.use(best.key) }
    return best?.at
  }

  /// Where a line's end goes, dragged to [raw] with its other end at [fixed]: onto another shape's
  /// end or corner; else, keeping its tidy angle, onto the edge it reaches; else onto the nearest
  /// edge; else free at its tidy angle. [on] says whether it locked onto something.
  public static func lineEnd(fixed: Pt, raw: Pt, _ targets: [SnapFeatures], _ s: SnapSession) -> (at: Pt, on: Bool) {
    if let c = corner(raw, targets, s) { return (c, true) }
    var angled = raw
    if case let .line(_, b, _, _, _) = ShapeRecognizer.snappedLine(fixed, raw) { angled = b }
    if let q = alongLine(fixed, angled, targets, s) { return (q, true) }
    if let q = point(raw, targets, s) { return (q, true) }
    return (angled, false)
  }
}

extension ShapeGeometry {
  /// What this shape offers for snapping: its ends, corners, side middles and centre, its edges (a
  /// curve as short pieces), and the box of its outline. Arrow barbs and dimension marks aren't
  /// edges to snap to; the line itself is.
  public func snapFeatures() -> SnapFeatures {
    func segs(_ path: [Pt], closed: Bool = false) -> [(a: Pt, b: Pt)] {
      var out: [(a: Pt, b: Pt)] = path.indices.dropLast().map { (path[$0], path[$0 + 1]) }
      if closed, path.count > 2 { out.append((path[path.count - 1], path[0])) }
      return out
    }
    func mid(_ a: Pt, _ b: Pt) -> Pt { Pt((a.x + b.x) / 2, (a.y + b.y) / 2) }
    func outline() -> [(a: Pt, b: Pt)] { segs(paths(1).first ?? []) }
    let points: [Pt]
    let segments: [(a: Pt, b: Pt)]
    switch self {
    case let .line(a, b, _, _, _):
      points = [a, b, mid(a, b)]
      segments = [(a, b)]
    case let .poly(pts, closed, smooth, _, _):
      guard let first = pts.first, let last = pts.last else { return SnapFeatures(points: [], segments: [], box: nil) }
      if smooth {
        points = [first, last]
        segments = segs(Geo.smooth(pts))
      } else {
        let sides = segs(pts, closed: closed)
        points = pts + sides.map { mid($0.a, $0.b) } + (closed ? [Geo.centroid(pts)] : [])
        segments = sides
      }
    case let .triangle(a, b, c, _):
      let sides = segs([a, b, c], closed: true)
      points = [a, b, c] + sides.map { mid($0.a, $0.b) }
      segments = sides
    case let .ellipse(center, _, _, _, _):
      points = [center, ellipsePoint(0), ellipsePoint(.pi / 2), ellipsePoint(.pi), ellipsePoint(1.5 * .pi)]
      segments = outline()
    case let .arc(center, radius, start, sweep, _), let .sector(center, radius, start, sweep):
      points = [center, center + .polar(radius, start), center + .polar(radius, start + sweep)]
      segments = outline()
    case let .curve(pts):
      // A curve: its two ends, and the curve itself.
      guard let first = pts.first, let last = pts.last else { return SnapFeatures(points: [], segments: [], box: nil) }
      points = [first, last]
      segments = outline()
    case let .load(a, b, _, _):
      // A distributed load: its line, and the line along its arrow tips (which rest on the beam).
      let tips = handles()[2]
      let ta = a + (tips - mid(a, b)), tb = b + (tips - mid(a, b))
      points = [a, b, mid(a, b), ta, tb, tips]
      segments = [(a, b), (ta, tb), (a, ta), (b, tb)]
    case let .param(p):
      // A shape with joints snaps like the drawing it shows.
      return p.drawn().snapFeatures()
    case let .group(parts, _):
      // Engineering symbols: their outlines, ground lines and arrows snap; the hatching under a
      // support (five or more short plain lines) doesn't, or its ends would catch on everything.
      let box = Rect.around(parts.flatMap { $0.paths(1).joined() })
      let reach = box.map { Pt($0.width, $0.height).length() } ?? 0
      func short(_ g: ShapeGeometry) -> Bool {
        if case let .line(a, b, false, false, false) = g { return a.dist(b) < reach * 0.3 }
        return false
      }
      let hatching = parts.filter(short).count >= 5
      return .of(parts.filter { !(hatching && short($0)) }.map { $0.snapFeatures() })
    }
    return SnapFeatures(points: points, segments: segments, box: Rect.around(points + segments.flatMap { [$0.a, $0.b] }))
  }
}
