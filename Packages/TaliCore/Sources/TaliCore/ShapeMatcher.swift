import Foundation

// A port of the Android app's `geometry/ShapeMatcher.kt` (the $P recogniser) and the parts of
// `ShapeRecognizer.kt` that use it. Same numbers; keep the two in step.

/// Compares drawings by their point clouds (the $P recogniser): both are resampled to the same
/// number of points, centred and scaled to a unit size, then each point is greedily paired with the
/// nearest unpaired point of the other cloud. Stroke order, direction and how many strokes a
/// template was drawn with don't matter, so one continuous pen stroke can match a template built
/// from several parts. Orientation does matter: a shape drawn upside down is a different shape.
public enum ShapeMatcher {
  private static let n = 48

  /// Distances below this (in units of the drawing's size) count as a match.
  public static let match: Float = 0.055

  public struct Cloud: Sendable {
    let points: [Pt]
    public let aspect: Float
  }

  /// Builds a cloud from one or more polylines, spreading the points along them by length.
  public static func cloud(_ paths: [[Pt]]) -> Cloud? {
    let usable = paths.filter { $0.count >= 2 }
    let total = Float(usable.reduce(0.0) { $0 + Double(Geo.pathLength($1)) })
    if total < 1e-3 { return nil }
    guard let box = Rect.around(usable.joined()) else { return nil }
    let step = total / Float(n)
    var out: [Pt] = []
    out.reserveCapacity(n + usable.count)
    // Walk every path at the same spacing; each path contributes at least its start point.
    for path in usable {
      out.append(path[0])
      var carry: Float = 0
      for i in 1..<path.count {
        var a = path[i - 1]
        let b = path[i]
        var d = a.dist(b)
        while carry + d >= step && d > 0 {
          let t = (step - carry) / d
          let q = a + (b - a) * t
          out.append(q)
          a = q
          d = a.dist(b)
          carry = 0
        }
        carry += d
      }
    }
    // Evenly drops or repeats points so every cloud has exactly n.
    let points = (0..<n).map { out[$0 * out.count / n] }
    let c = Geo.centroid(points)
    let size = max(max(box.width, box.height), 1e-3)
    return Cloud(points: points.map { ($0 - c) / size }, aspect: (box.width + 1e-3) / (box.height + 1e-3))
  }

  /// How different two clouds are, as a weighted mean distance between paired points in units of the
  /// drawing's size: about 0.015–0.045 for the same shape drawn by hand, 0.06 and up for different ones.
  public static func distance(_ a: Cloud, _ b: Cloud) -> Float { min(greedy(a.points, b.points), greedy(b.points, a.points)) }

  /// Whether two clouds have a similar width-to-height ratio (within a factor of [factor]).
  public static func similarAspect(_ a: Cloud, _ b: Cloud, factor: Float = 1.7) -> Bool {
    // Very thin drawings (lines, arrows) have unstable ratios; compare how thin they are instead.
    let ra = min(max(a.aspect, 0.08), 12)
    let rb = min(max(b.aspect, 0.08), 12)
    return abs(logf(ra / rb)) < logf(factor)
  }

  private static func greedy(_ a: [Pt], _ b: [Pt]) -> Float {
    let step = max(1, Int(Float(a.count).squareRoot()))
    var best = Float.greatestFiniteMagnitude
    for start in stride(from: 0, to: a.count, by: step) { best = min(best, cloudDistance(a, b, start)) }
    return best
  }

  private static func cloudDistance(_ a: [Pt], _ b: [Pt], _ start: Int) -> Float {
    let n = a.count
    var matched = [Bool](repeating: false, count: n)
    var sum: Float = 0
    var weights: Float = 0
    var i = start
    repeat {
      var bestJ = -1
      var bestD = Float.greatestFiniteMagnitude
      for j in 0..<n where !matched[j] {
        let d = a[i].dist(b[j])
        if d < bestD {
          bestD = d
          bestJ = j
        }
      }
      matched[bestJ] = true
      let w = 1 - Float((i - start + n) % n) / Float(n)
      sum += w * bestD
      weights += w
      i = (i + 1) % n
    } while i != start
    return sum / weights
  }
}

/// A shape she saved herself from something she drew (Android's `CustomShape`). Its geometry is
/// kept normalised: the top-left corner at the origin and the longer side `size` units long.
/// Holding the pen at the end of a stroke that looks like it snaps the stroke into this clean version.
public struct CustomShape: Sendable, Equatable, Identifiable {
  public var id: String
  public var name: String
  public var geometry: ShapeGeometry

  public init(id: String, name: String, geometry: ShapeGeometry) {
    self.id = id
    self.name = name
    self.geometry = geometry
  }

  public static let size: Float = 100

  /// Arrowheads and hatching are sized for this pen when shapes are compared and previewed.
  public static let referencePen: Float = 2.4

  public var cloud: ShapeMatcher.Cloud? { ShapeMatcher.cloud(geometry.paths(Self.referencePen)) }

  private var box: Rect { Rect.around(geometry.paths(Self.referencePen).joined()) ?? Rect(0, 0, Self.size, Self.size) }

  /// Scales the shape to cover the area of [target] (keeping its proportions), centred on it.
  public func placeOver(_ target: Rect) -> ShapeGeometry {
    let b = box
    let sx = b.width > 1 ? target.width / b.width : 0
    let sy = b.height > 1 ? target.height / b.height : 0
    let s = max(sx > 0 && sy > 0 ? (sx * sy).squareRoot() : max(sx, sy), 0.05)
    return placed(b, s, target.center)
  }

  /// Scales the shape to fit inside the box dragged from [p0] to [p1], for the Shapes tool.
  public func fitInto(_ p0: Pt, _ p1: Pt) -> ShapeGeometry {
    let b = box
    let w = max(abs(p1.x - p0.x), 8), h = max(abs(p1.y - p0.y), 8)
    let s = min(max(min(b.width > 1 ? w / b.width : .greatestFiniteMagnitude, b.height > 1 ? h / b.height : .greatestFiniteMagnitude), 0.05), 100)
    return placed(b, s, Pt((p0.x + p1.x) / 2, (p0.y + p1.y) / 2))
  }

  /// As it's drawn: lines that came from her ink are smooth curves.
  private func placed(_ b: Rect, _ s: Float, _ center: Pt) -> ShapeGeometry {
    Self.smoothInk(geometry).transformed(Affine(a: s, d: s, tx: center.x - b.center.x * s, ty: center.y - b.center.y * s))
  }

  /// One thing in a selection being saved as a shape: a shape, or a pen stroke's points.
  public enum Part: Sendable {
    case shape(ShapeGeometry)
    case ink([Pt])
  }

  /// Turns what's selected into one shape: clean shapes keep their exact geometry, hand-drawn ink is
  /// lightly simplified into smooth lines. [bounds] is the box round all of it. Nil if there's
  /// nothing usable.
  public static func geometryFrom(_ parts: [Part], bounds: Rect?) -> ShapeGeometry? {
    guard let bounds else { return nil }
    let diag = (bounds.width * bounds.width + bounds.height * bounds.height).squareRoot()
    if diag < 8 { return nil }
    var out: [ShapeGeometry] = []
    for part in parts {
      switch part {
      case .shape(let g): out.append(g)
      case .ink(let points):
        // Lightly simplified (fine enough to keep the curve), then drawn smooth through the points.
        let pts = Geo.simplify(points, max(0.25, diag * 0.0015))
        if pts.count >= 2 { out.append(.poly(points: pts, closed: false, smooth: true)) }
      }
    }
    if out.isEmpty { return nil }
    return normalized(out.count == 1 ? out[0] : .group(out))
  }

  /// Open lines (from ink) drawn as smooth curves, inside groups too.
  public static func smoothInk(_ g: ShapeGeometry) -> ShapeGeometry {
    switch g {
    case let .poly(points, false, false, rotation, form) where points.count > 2: .poly(points: points, closed: false, smooth: true, rotation: rotation, form: form)
    case let .group(parts, turn): .group(parts.map(smoothInk), turn: turn)
    default: g
    }
  }

  public static func normalized(_ g: ShapeGeometry) -> ShapeGeometry? {
    guard let box = Rect.around(g.paths(referencePen).joined()) else { return nil }
    let longest = max(box.width, box.height)
    if longest < 1e-3 { return nil }
    let s = size / longest
    return g.transformed(Affine(a: s, d: s, tx: -box.left * s, ty: -box.top * s))
  }

  // MARK: JSON (as Android's settings keep them: {"id", "name", "geometry"})

  public var json: [String: Any] { ["id": id, "name": name, "geometry": geometry.json] }

  public init?(json o: [String: Any]) {
    guard let id = o["id"] as? String, let name = o["name"] as? String, let g = o["geometry"].flatMap(ShapeGeometry.decode) else { return nil }
    self.init(id: id, name: name, geometry: g)
  }
}

extension ShapeRecognizer {
  /// The clean shape for a held stroke: one of the standard shapes, one of hers ([custom]), or one
  /// of the starred subjects' shapes ([packs]), whichever it looks most like, when it's close
  /// enough. A straight line always stays a line, so hold-to-straighten never surprises her.
  public static func recognize(_ raw: [Pt], custom: [CustomShape], packs: [PackShape] = []) -> ShapeGeometry? {
    let builtin = recognize(raw)
    if case .line = builtin { return builtin }
    let packClouds = packs.compactMap { shape in shape.cloud.map { (shape, $0) } }
    if custom.isEmpty && packClouds.isEmpty { return builtin }
    guard let box = Rect.around(raw), let first = raw.first, let last = raw.last, let drawn = ShapeMatcher.cloud([dedupe(raw)]) else { return builtin }
    var bestD = ShapeMatcher.match
    var best: ShapeGeometry?
    func consider(_ template: ShapeMatcher.Cloud?, _ place: () -> ShapeGeometry) {
      guard let template, ShapeMatcher.similarAspect(drawn, template) else { return }
      let d = ShapeMatcher.distance(drawn, template)
      if d < bestD {
        bestD = d
        best = place()
      }
    }
    for shape in custom { consider(shape.cloud) { shape.placeOver(box) } }
    for (shape, cloud) in packClouds { consider(cloud) { shape.placeOver(box, first, last) } }
    return best ?? builtin
  }

  /// The saved shape that the stroke looks most like, or nil when none is close enough.
  public static func bestCustom(_ raw: [Pt], _ custom: [CustomShape]) -> CustomShape? {
    guard let drawn = ShapeMatcher.cloud([dedupe(raw)]) else { return nil }
    var best: CustomShape?
    var bestD = ShapeMatcher.match
    for shape in custom {
      guard let template = shape.cloud, ShapeMatcher.similarAspect(drawn, template) else { continue }
      let d = ShapeMatcher.distance(drawn, template)
      if d < bestD {
        bestD = d
        best = shape
      }
    }
    return best
  }
}
