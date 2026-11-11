import Foundation

// A port of the first part of the Android app's `model/ShapeTemplates.kt`: the shape with joints
// itself. The templates are in ShapeTemplates.swift; keep the two in step with Android.

/// A subject shape with joints (Android's `ParamShape`, stored as "param"): dots that change what it
/// is, not just its size. Kept as its [template], where it sits ([place]: its own frame to the
/// page), its frame size ([w] × [h]) and its settings [v]; the drawing is rebuilt from those.
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

  private var spec: ShapeTemplate? { ShapeTemplates.get(template) }

  private var frame: Frame { Frame(w: w, h: h, v: v) }

  /// Where a design drawn like a line starts and ends on the page; nil for any other.
  public var lineEnds: (Pt, Pt)? {
    spec?.mode == .line ? (place.apply(.zero), place.apply(Pt(w, 0))) : nil
  }

  /// The drawing on the page. A template this version doesn't know draws nothing and is kept as it is.
  public func drawn() -> ShapeGeometry { (spec?.render(frame) ?? .group([])).transformed(place) }

  public func paths(_ penSize: Float) -> [[Pt]] { drawn().paths(penSize) }

  public func transformed(_ m: Affine) -> ParamShape {
    var out = self
    out.place = place.then(m)
    return out
  }

  /// Its dots on the page: a line-like design's two ends first, then its joints.
  public func handles() -> [Pt] {
    guard let s = spec else { return [] }
    let ends = s.mode == .line ? [Pt.zero, Pt(w, 0)] : []
    return (ends + s.joints(frame).map(\.at)).map(place.apply)
  }

  /// Dot [index] dragged to [p] on the page.
  public func withHandle(_ index: Int, _ p: Pt) -> ParamShape {
    guard let s = spec, let local = place.inverse()?.apply(p) else { return self }
    var out = self
    if s.mode == .line && index < 2 {
      // An end: like a line's, it re-aims and lengthens the shape; the other end stays put.
      if index == 1 {
        out.place = Affine.rotation(atan2f(local.y, local.x)).then(place)
        out.w = max(local.dist(.zero), s.minW)
      } else {
        let d = Pt(w, 0) - local
        out.place = Affine.rotation(atan2f(d.y, d.x)).then(.translate(local.x, local.y)).then(place)
        out.w = max(d.length(), s.minW)
      }
      return out
    }
    let joints = s.joints(frame)
    let i = s.mode == .line ? index - 2 : index
    guard joints.indices.contains(i) else { return self }
    let f = joints[i].move(frame, local)
    if f.shift.x != 0 || f.shift.y != 0 { out.place = Affine.translate(f.shift.x, f.shift.y).then(place) }
    out.w = f.w
    out.h = f.h
    out.v = f.v
    return out
  }

  // MARK: JSON (kotlinx's form: defaults left out)

  init?(json o: [String: Any]) {
    guard let template = o["template"] as? String else { return nil }
    func f(_ v: Any?, _ d: Float) -> Float { (v as? NSNumber)?.floatValue ?? d }
    let p = o["place"] as? [String: Any] ?? [:]
    self.init(
      template: template,
      place: Affine(a: f(p["a"], 1), b: f(p["b"], 0), c: f(p["c"], 0), d: f(p["d"], 1), tx: f(p["tx"], 0), ty: f(p["ty"], 0)),
      w: f(o["w"], 0), h: f(o["h"], 0), v: ((o["v"] as? [Any]) ?? []).map { f($0, 0) })
  }

  var json: [String: Any] {
    func num(_ x: Float) -> Double { Double("\(x)") ?? Double(x) }
    var p: [String: Any] = [:]
    let unit = Affine.identity
    if place.a != unit.a { p["a"] = num(place.a) }
    if place.b != unit.b { p["b"] = num(place.b) }
    if place.c != unit.c { p["c"] = num(place.c) }
    if place.d != unit.d { p["d"] = num(place.d) }
    if place.tx != unit.tx { p["tx"] = num(place.tx) }
    if place.ty != unit.ty { p["ty"] = num(place.ty) }
    var o: [String: Any] = ["type": "param", "template": template, "place": p, "w": num(w), "h": num(h)]
    if !v.isEmpty { o["v"] = v.map(num) }
    return o
  }
}

extension Affine {
  static func rotation(_ angle: Float) -> Affine {
    let c = cosf(angle), s = sinf(angle)
    return Affine(a: c, b: s, c: -s, d: c)
  }

  /// The transform that undoes this one, or nil if it flattens everything.
  func inverse() -> Affine? {
    let det = a * d - b * c
    if abs(det) < 1e-9 { return nil }
    let ia = d / det, ib = -b / det, ic = -c / det, id = a / det
    return Affine(a: ia, b: ib, c: ic, d: id, tx: -(ia * tx + ic * ty), ty: -(ib * tx + id * ty))
  }
}

/// A shape's frame size and settings; [shift] moves its origin (a joint on the top or left edge).
public struct Frame: Sendable, Equatable {
  public var w: Float
  public var h: Float
  public var v: [Float]
  public var shift = Pt.zero

  public init(w: Float, h: Float, v: [Float], shift: Pt = .zero) {
    self.w = w
    self.h = h
    self.v = v
    self.shift = shift
  }

  func v(_ i: Int, _ fallback: Float) -> Float { v.indices.contains(i) ? v[i] : fallback }

  /// Setting [i] as [value]; settings before it that were never set take [fill]'s.
  func set(_ i: Int, _ value: Float, fill: (Int) -> Float = { _ in 0 }) -> Frame {
    var out = self
    while out.v.count <= i { out.v.append(fill(out.v.count)) }
    out.v[i] = value
    return out
  }

  func sized(w: Float? = nil, h: Float? = nil) -> Frame {
    var out = self
    out.w = w ?? self.w
    out.h = h ?? self.h
    return out
  }
}

/// A dot on a shape (in its frame) and what dragging it to a point (in its frame) does.
public struct Joint: Sendable {
  public let at: Pt
  let move: @Sendable (Frame, Pt) -> Frame

  init(_ at: Pt, _ move: @escaping @Sendable (Frame, Pt) -> Frame) {
    self.at = at
    self.move = move
  }
}

/// How one shape with joints is drawn and what its joints do. `sized` fills the dragged box at its
/// real size (so a longer stack has more cells), `natural` keeps its proportions in its own
/// [naturalW] × [naturalH] frame, scaled to the box, and `line` runs along x from where the pen
/// landed to where it lifted, with end dots like a line's.
public struct ShapeTemplate: Sendable {
  public enum Mode: Sendable { case sized, natural, line }

  public let id: String
  public let mode: Mode
  public let naturalW: Float
  public let naturalH: Float
  public let minW: Float
  public let minH: Float
  public let defaults: [Float]
  let joints: @Sendable (Frame) -> [Joint]
  let draw: @Sendable (inout Draw, Frame) -> Void
  /// Drawn square (a circle's frame), whatever box is dragged.
  public let round: Bool

  public func render(_ f: Frame) -> ShapeGeometry {
    var d = Draw()
    draw(&d, f)
    return d.build()
  }

  /// As drawn from [p0] to [p1].
  public func create(_ p0: Pt, _ p1: Pt) -> ParamShape {
    switch mode {
    case .line:
      let len = max(p0.dist(p1), minW)
      let angle = p0.dist(p1) < 1 ? 0 : atan2f(p1.y - p0.y, p1.x - p0.x)
      return ParamShape(template: id, place: Affine.rotation(angle).then(.translate(p0.x, p0.y)), w: len, h: 0, v: defaults)
    case .sized:
      let l = min(p0.x, p1.x), t = min(p0.y, p1.y)
      let w = max(abs(p1.x - p0.x), minW), h = max(abs(p1.y - p0.y), minH)
      if round {
        // Round ones (a pie, a gear) are square, centred in the box.
        let d = min(w, h)
        return ParamShape(template: id, place: .translate(l + (w - d) / 2, t + (h - d) / 2), w: d, h: d, v: defaults)
      }
      return ParamShape(template: id, place: .translate(l, t), w: w, h: h, v: defaults)
    case .natural:
      let w = max(abs(p1.x - p0.x), 8), h = max(abs(p1.y - p0.y), 8)
      let s = min(w / naturalW, h / naturalH)
      let cx = (p0.x + p1.x) / 2 - naturalW * s / 2
      let cy = (p0.y + p1.y) / 2 - naturalH * s / 2
      return ParamShape(template: id, place: Affine(a: s, d: s, tx: cx, ty: cy), w: naturalW, h: naturalH, v: defaults)
    }
  }

  /// For hold-to-shape: drawn at its usual size.
  public var icon: ShapeGeometry { render(Frame(w: naturalW, h: mode == .line ? 0 : naturalH, v: defaults)) }

  /// For the panel's tile: drawn in a frame that suits a small square (`ShapeTemplates.tileFrames`):
  /// shorter leads, so a resistor is a resistor and not a line, and fewer cells, nodes or rows.
  public var tile: ShapeGeometry {
    guard let (w, h) = ShapeTemplates.tileFrames[id] else { return icon }
    return render(Frame(w: w, h: mode == .line ? 0 : h, v: defaults))
  }
}
