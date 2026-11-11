import Foundation

// A port of the Android app's `model/ShapeTemplates.kt` (the subject shapes with joints), template
// for template with the same ids, numbers and order of joints, so a shape made on either app draws
// and reshapes the same on the other. This file has the helpers and the first five subjects;
// ShapeTemplatesMore.swift has the rest. Keep both in step with Android.

// MARK: Joint helpers

/// Pulls the right edge: wider (more cells, more bars…).
func widthJoint(_ f: Frame, _ least: Float, y: Float? = nil) -> Joint {
  Joint(Pt(f.w, y ?? f.h / 2)) { g, p in g.sized(w: max(p.x, least)) }
}

/// Pulls the bottom edge: taller (more levels, more rows…).
func heightJoint(_ f: Frame, _ least: Float, x: Float? = nil) -> Joint {
  Joint(Pt(x ?? f.w / 2, f.h)) { g, p in g.sized(h: max(p.y, least)) }
}

/// Pulls the top edge, keeping the bottom where it is (a chart's axis).
func topJoint(_ f: Frame, _ least: Float, x: Float = 0) -> Joint {
  Joint(Pt(x, 0)) { g, p in
    let top = min(p.y, g.h - least)
    var out = g
    out.h = g.h - top
    out.shift = Pt(0, top)
    return out
  }
}

/// The width and height joints together, for shapes that stretch both ways.
func sizeJoints(_ f: Frame, _ minW: Float, _ minH: Float) -> [Joint] { [widthJoint(f, minW), heightJoint(f, minH)] }

/// A circle's size: one dot on its right that sets its diameter.
func diameterJoint(_ f: Frame, _ least: Float) -> Joint {
  Joint(Pt(min(f.w, f.h), min(f.w, f.h) / 2)) { g, p in
    let d = max(p.x, least)
    return g.sized(w: d, h: d)
  }
}

/// A round shape's size from its box's bottom-right corner: off the circle, clear of dots on it.
func cornerSizeJoint(_ f: Frame, _ least: Float) -> Joint {
  let d = min(f.w, f.h)
  return Joint(Pt(d, d)) { g, p in
    let s = max(max(p.x, p.y), least)
    return g.sized(w: s, h: s)
  }
}

func clampF(_ x: Float, _ lo: Float, _ hi: Float) -> Float { min(max(x, lo), hi) }

/// [x] rounded to the nearest whole number (halves up, as Kotlin's `roundToInt`), kept within [lo]...[hi].
func count(_ x: Float, _ lo: Int, _ hi: Int) -> Int {
  let r = (x + 0.5).rounded(.down)
  return r.isNaN ? lo : Int(min(max(r, Float(lo)), Float(hi)))
}

/// [x] with its fraction dropped (as Kotlin's `toInt`), kept within [lo]...[hi].
func whole(_ x: Float, _ lo: Int, _ hi: Int) -> Int {
  x.isNaN ? lo : Int(min(max(x.rounded(.towardZero), Float(lo)), Float(hi)))
}

/// Degrees to radians.
func deg(_ d: Float) -> Float { Float(Double(d) * .pi / 180) }

/// Radians to degrees.
func degrees(_ r: Float) -> Float { Float(Double(r) * 180 / .pi) }

public enum ShapeTemplates {
  /// Frames (width, height) the panel's tiles draw these in; the rest use their usual size.
  static let tileFrames: [String: (Float, Float)] = [
    // Line-like symbols: shorter leads so the symbol fills the tile.
    "timeline": (100, 0),
    "heartbeat": (110, 0),
    "syringe": (74, 0),
    "spring": (96, 0),
    "damper": (100, 0),
    "shaft": (100, 0),
    "resistor": (76, 0),
    "capacitor": (66, 0),
    "inductor": (80, 0),
    "diode": (70, 0),
    "battery": (76, 0),
    "ac-source": (76, 0),
    "switch": (80, 0),
    "lamp": (76, 0),
    "pencil": (96, 0),
    "linked-list": (138, 0),
    // Long or busy ones: fewer cells, nodes or rows.
    "array": (112, 28),
    "neuron": (100, 70),
    "binary-tree": (110, 80),
    "graph": (100, 90),
    "gantt": (130, 76),
    "org-chart": (130, 90),
    "coins": (90, 56),
    "database": (90, 84),
    "indifference": (100, 72),
  ]

  /// Every template, in the order Android declares them.
  public static let all: [ShapeTemplate] = [
    group, network, familyTree, speech, timeline, venn,
    orgChart, barChart, pieChart, growth, funnel, swot, gantt, target, coins, document,
    database, terminal, subroutine, binaryTree, graph, array, linkedList, stack, computer,
    scales, courthouse, column, contract, courtLevels, parties,
    medCross, heartbeat, syringe, thermometer, ivBag,
    gear, spring, damper, bearing, pulley, lever, piston, mass, shaft, bolt,
    truss, iBeam,
    resistor, capacitor, inductor, diode, battery, acSource, switchSymbol, lamp, andGate,
    neuron, bellCurve, maslow, thought, eye, face, cycle, scatter,
    supplyDemand, axes, demand, indifference, ppf, costCurves, lorenz, businessCycle, laffer,
    colourWheel, thirds, perspective, frame, cube, pencil,
  ]

  private static let byId: [String: ShapeTemplate] = Dictionary(all.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })

  public static func get(_ id: String) -> ShapeTemplate? { byId[id] }

  typealias Joints = @Sendable (Frame) -> [Joint]
  typealias Drawing = @Sendable (inout Draw, Frame) -> Void

  static func sized(
    _ id: String, _ w: Float, _ h: Float, _ minW: Float, _ minH: Float, _ defaults: [Float] = [], round: Bool = false,
    joints: @escaping Joints = { _ in [] }, draw: @escaping Drawing
  ) -> ShapeTemplate {
    ShapeTemplate(id: id, mode: .sized, naturalW: w, naturalH: h, minW: minW, minH: minH, defaults: defaults, joints: joints, draw: draw, round: round)
  }

  static func natural(_ id: String, _ defaults: [Float] = [], joints: @escaping Joints = { _ in [] }, draw: @escaping Drawing) -> ShapeTemplate {
    ShapeTemplate(id: id, mode: .natural, naturalW: 100, naturalH: 100, minW: 8, minH: 8, defaults: defaults, joints: joints, draw: draw, round: false)
  }

  static func line(_ id: String, _ length: Float, _ minLength: Float, _ defaults: [Float] = [], joints: @escaping Joints = { _ in [] }, draw: @escaping Drawing) -> ShapeTemplate {
    ShapeTemplate(id: id, mode: .line, naturalW: length, naturalH: 0, minW: minLength, minH: 0, defaults: defaults, joints: joints, draw: draw, round: false)
  }

  // MARK: Social sciences

  static let group = sized("group", 160, 70, 40, 36, joints: { f in sizeJoints(f, 40, 36) }) { draw, f in
    let n = count(f.w / (f.h * 0.75), 1, 14)
    let slot = f.w / Float(n)
    let hh = min(f.h, slot * 1.25)
    for i in 0..<n { draw.person(slot * (Float(i) + 0.5), f.h, hh) }
  }

  private static let networkNodes: [Float] = [0.15, 0.2, 0.85, 0.12, 0.5, 0.55, 0.18, 0.88, 0.85, 0.85]

  private static func networkNode(_ f: Frame, _ i: Int) -> Pt {
    Pt(f.v(2 * i, networkNodes[2 * i]) * f.w, f.v(2 * i + 1, networkNodes[2 * i + 1]) * f.h)
  }

  static let network = sized(
    "network", 140, 120, 50, 50, networkNodes,
    joints: { f in
      (0..<5).map { i in
        Joint(networkNode(f, i)) { g, p in g.set(2 * i, clampF(p.x / g.w, 0, 1)).set(2 * i + 1, clampF(p.y / g.h, 0, 1)) }
      }
    }
  ) { draw, f in
    let r = max(5, min(f.w, f.h) * 0.07)
    let n = (0..<5).map { networkNode(f, $0) }
    for p in n { draw.circle(p.x, p.y, r) }
    for (a, b) in [(0, 2), (1, 2), (2, 3), (2, 4), (0, 1), (3, 4)] where n[a].dist(n[b]) > 2 * r {
      draw.link(n[a].x, n[a].y, n[b].x, n[b].y, r)
    }
  }

  static let familyTree = sized("genogram", 150, 110, 60, 60, joints: { f in sizeJoints(f, 60, 60) }) { draw, f in
    let s = min(f.h * 0.26, 26)
    let cx = f.w / 2
    draw.rect(cx - s * 1.8, 0, cx - s * 0.8, s)
    draw.circle(cx + s * 1.3, s / 2, s / 2)
    draw.line(cx - s * 0.8, s / 2, cx + s * 0.8, s / 2)
    let mid = f.h * 0.5
    draw.line(cx, s / 2, cx, mid)
    let n = count(f.w / (s * 2.2), 1, 10)
    let xs = (0..<n).map { (Float($0) + 0.5) * f.w / Float(n) }
    if n > 1 { draw.line(xs[0], mid, xs[n - 1], mid) }
    for (i, x) in xs.enumerated() {
      draw.line(x, mid, x, f.h - s)
      if i % 2 == 0 { draw.rect(x - s / 2, f.h - s, x + s / 2, f.h) } else { draw.circle(x, f.h - s / 2, s / 2) }
    }
  }

  static let speech = sized(
    "speech", 140, 80, 40, 30, [0.25, 1.35],
    joints: { f in
      [
        Joint(Pt(f.v(0, 0.25) * f.w, f.v(1, 1.35) * f.h)) { g, p in g.set(0, clampF(p.x / g.w, -0.5, 1.5)).set(1, clampF(p.y / g.h, 1.02, 3)) },
        widthJoint(f, 40),
        heightJoint(f, 30, x: f.w * 0.75),
      ]
    }
  ) { draw, f in
    let tip = Pt(f.v(0, 0.25) * f.w, f.v(1, 1.35) * f.h)
    let base = clampF(tip.x, f.w * 0.12, f.w * 0.88)
    let half = min(f.w * 0.08, 12)
    draw.poly(0, 0, f.w, 0, f.w, f.h, base + half, f.h, tip.x, tip.y, base - half, f.h, 0, f.h)
  }

  static let timeline = line("timeline", 160, 40) { draw, f in
    draw.line(0, 0, f.w, 0, arrow: true)
    var x: Float = 36
    while x < f.w - 22 {
      draw.line(x, -7, x, 7)
      x += 36
    }
  }

  static let venn = sized("venn", 130, 80, 30, 30, joints: { f in [widthJoint(f, 30), heightJoint(f, 30)] }) { draw, f in
    let r = f.h / 2
    draw.circle(r, r, r)
    draw.circle(max(f.w - r, r + 2), r, r)
  }

  // MARK: Business

  static let orgChart = sized("org-chart", 180, 90, 60, 50, joints: { f in sizeJoints(f, 60, 50) }) { draw, f in
    let b = min(f.h * 0.28, 26)
    let n = count(f.w / 62, 1, 10)
    let tw = min(f.w * 0.36, 80)
    draw.rect(f.w / 2 - tw / 2, 0, f.w / 2 + tw / 2, b)
    let mid = (b + f.h - b) / 2
    draw.line(f.w / 2, b, f.w / 2, mid)
    let xs = (0..<n).map { (Float($0) + 0.5) * f.w / Float(n) }
    if n > 1 { draw.line(xs[0], mid, xs[n - 1], mid) }
    let cw = f.w / Float(n) * 0.82
    for x in xs {
      draw.line(x, mid, x, f.h - b)
      draw.rect(x - cw / 2, f.h - b, x + cw / 2, f.h)
    }
  }

  private static func barDefault(_ i: Int) -> Float { [0.45, 0.7, 0.55, 0.85, 0.6, 0.75, 0.5, 0.9][i % 8] }

  private static func bars(_ f: Frame) -> Int { count(((f.w - 8) / 40) - 0.49, 1, 24) }

  static let barChart = sized(
    "bar-chart", 160, 110, 40, 40,
    joints: { f in
      let n = bars(f)
      let slot = (f.w - 8) / Float(n)
      let each = (0..<n).map { i in
        let x = 8 + slot * (Float(i) + 0.5)
        return Joint(Pt(x, f.h - f.v(i, barDefault(i)) * (f.h - 6))) { g, p in g.set(i, clampF((g.h - p.y) / (g.h - 6), 0.02, 1), fill: barDefault) }
      }
      return each + [Joint(Pt(f.w, f.h)) { g, p in g.sized(w: max(p.x, 40)) }, topJoint(f, 40)]
    }
  ) { draw, f in
    draw.open(0, 0, 0, f.h, f.w, f.h)
    let n = bars(f)
    let slot = (f.w - 8) / Float(n)
    for i in 0..<n {
      let x = 8 + slot * Float(i) + slot * 0.2
      draw.rect(x, f.h - f.v(i, barDefault(i)) * (f.h - 6), x + slot * 0.6, f.h)
    }
  }

  static let pieChart = sized(
    "pie-chart", 110, 110, 30, 30, [-90, 0, 110, 200], round: true,
    joints: { f in
      let r = min(f.w, f.h) / 2
      let c = Pt(f.w / 2, f.h / 2)
      let slices = f.v.indices.map { i in
        Joint(c + Pt.polar(r, deg(f.v[i]))) { g, p in g.set(i, degrees(atan2f(p.y - c.y, p.x - c.x))) }
      }
      // The size dot sits off the circle, so a slice's edge never lands on it.
      return slices + [cornerSizeJoint(f, 30)]
    }
  ) { draw, f in
    let r = min(f.w, f.h) / 2
    let c = Pt(f.w / 2, f.h / 2)
    draw.circle(c.x, c.y, r)
    for a in f.v {
      let e = c + Pt.polar(r, deg(a))
      draw.line(c.x, c.y, e.x, e.y)
    }
  }

  private static func growthPoints(_ f: Frame) -> Int { count(f.w / 34, 3, 12) }

  private static func growthDefault(_ i: Int, _ k: Int) -> Float { 0.15 + 0.7 * Float(i) / Float(k - 1) + (i % 2 == 1 ? -0.1 : 0) }

  private static func growthPoint(_ f: Frame, _ i: Int, _ k: Int) -> Pt {
    Pt(10 + Float(i) * (f.w - 20) / Float(k - 1), f.h - f.v(i, growthDefault(i, k)) * f.h)
  }

  static let growth = sized(
    "growth", 150, 110, 60, 40,
    joints: { f in
      let k = growthPoints(f)
      let each = (0..<k).map { i in
        Joint(growthPoint(f, i, k)) { g, p in g.set(i, clampF((g.h - p.y) / g.h, 0, 1)) { j in growthDefault(j, k) } }
      }
      return each + [Joint(Pt(f.w, f.h)) { g, p in g.sized(w: max(p.x, 60)) }, topJoint(f, 40)]
    }
  ) { draw, f in
    draw.open(0, 0, 0, f.h, f.w, f.h)
    let k = growthPoints(f)
    let pts = (0..<k).map { growthPoint(f, $0, k) }
    draw.open(pts.dropLast().flatMap { [$0.x, $0.y] })
    draw.line(pts[k - 2].x, pts[k - 2].y, pts[k - 1].x, pts[k - 1].y, arrow: true)
  }

  static let funnel = sized(
    "funnel", 120, 130, 50, 50, [0.22],
    joints: { f in
      let nw = f.v(0, 0.22) * f.w
      return [
        Joint(Pt(f.w / 2 + nw / 2, f.h * 0.8)) { g, p in g.set(0, clampF(2 * (p.x - g.w / 2) / g.w, 0.05, 0.9)) },
        Joint(Pt(f.w, 0)) { g, p in g.sized(w: max(p.x, 50)) },
        heightJoint(f, 50),
      ]
    }
  ) { draw, f in
    let cx = f.w / 2
    let nw = f.v(0, 0.22) * f.w
    let ny = f.h * 0.6
    draw.poly(0, 0, f.w, 0, cx + nw / 2, ny, cx + nw / 2, f.h, cx - nw / 2, f.h, cx - nw / 2, ny)
    let stages = count(f.h / 32, 2, 8)
    for k in 1..<stages {
      let y = Float(k) * ny / Float(stages)
      let t = y / ny
      draw.line((cx - nw / 2) * t, y, f.w - (cx - nw / 2) * t, y)
    }
  }

  static let swot = sized(
    "swot", 120, 120, 30, 30, [0.5, 0.5],
    joints: { f in
      [Joint(Pt(f.v(0, 0.5) * f.w, f.v(1, 0.5) * f.h)) { g, p in g.set(0, clampF(p.x / g.w, 0.1, 0.9)).set(1, clampF(p.y / g.h, 0.1, 0.9)) }]
        + sizeJoints(f, 30, 30)
    }
  ) { draw, f in
    draw.rect(0, 0, f.w, f.h)
    draw.line(f.v(0, 0.5) * f.w, 0, f.v(0, 0.5) * f.w, f.h)
    draw.line(0, f.v(1, 0.5) * f.h, f.w, f.v(1, 0.5) * f.h)
  }

  private static func ganttRows(_ f: Frame) -> Int { count(f.h / 24 - 0.49, 1, 16) }

  private static func ganttDefault(_ j: Int) -> Float {
    let row = j / 2
    let start = (0.05 + 0.2 * Float(row)).truncatingRemainder(dividingBy: 0.65)
    return j % 2 == 0 ? start : start + 0.35
  }

  static let gantt = sized(
    "gantt", 180, 100, 60, 24,
    joints: { f in
      let n = ganttRows(f)
      let rh = f.h / Float(n)
      let ends = (0..<n).flatMap { i -> [Joint] in
        let y = rh * (Float(i) + 0.5)
        return [0, 1].map { e in
          let j = 2 * i + e
          return Joint(Pt(6 + f.v(j, ganttDefault(j)) * (f.w - 6), y)) { g, p in
            let x = clampF((p.x - 6) / (g.w - 6), 0, 1)
            let other = g.v(2 * i + 1 - e, ganttDefault(2 * i + 1 - e))
            return g.set(j, e == 0 ? min(x, other - 0.03) : max(x, other + 0.03), fill: ganttDefault)
          }
        }
      }
      return ends + [Joint(Pt(f.w, f.h)) { g, p in g.sized(w: max(p.x, 60)) }, heightJoint(f, 24, x: 0)]
    }
  ) { draw, f in
    draw.open(0, 0, 0, f.h, f.w, f.h)
    let n = ganttRows(f)
    let rh = f.h / Float(n)
    for i in 0..<n {
      let s = 6 + f.v(2 * i, ganttDefault(2 * i)) * (f.w - 6)
      let e = 6 + f.v(2 * i + 1, ganttDefault(2 * i + 1)) * (f.w - 6)
      draw.rect(s, rh * Float(i) + rh * 0.2, e, rh * (Float(i) + 0.8))
    }
  }

  static let target = sized(
    "target", 110, 110, 30, 30, [0.97, 0.03], round: true,
    joints: { f in
      [
        Joint(Pt(f.v(0, 0.97) * f.w, f.v(1, 0.03) * f.h)) { g, p in g.set(0, p.x / g.w).set(1, p.y / g.h) },
        Joint(Pt(f.w / 2, f.h)) { g, p in
          let d = max(p.y, 30)
          return g.sized(w: d, h: d)
        },
      ]
    }
  ) { draw, f in
    let r = min(f.w, f.h) / 2
    let c = Pt(f.w / 2, f.h / 2)
    let rings = count(r / 13, 2, 8)
    for k in 1...rings { draw.circle(c.x, c.y, r * Float(k) / Float(rings)) }
    let tail = Pt(f.v(0, 0.97) * f.w, f.v(1, 0.03) * f.h)
    if tail.dist(c) > 6 { draw.line(tail.x, tail.y, c.x, c.y, arrow: true) }
  }

  static let coins = sized("coins", 90, 80, 30, 24, joints: { f in sizeJoints(f, 30, 24) }) { draw, f in
    let rx = f.w / 2
    let ry = min(f.w * 0.15, f.h * 0.2)
    draw.ellipse(rx, ry, rx, ry)
    draw.line(0, ry, 0, f.h - ry)
    draw.line(f.w, ry, f.w, f.h - ry)
    let n = count((f.h - 2 * ry) / 12, 1, 20)
    for k in 1...n { draw.ellipseArc(rx, ry + Float(k) * (f.h - 2 * ry) / Float(n), rx, ry, 0, 180) }
  }

  static let document = sized(
    "document", 100, 120, 40, 40, [0.07],
    joints: { f in
      [Joint(Pt(f.w * 0.3, f.h * (0.86 + f.v(0, 0.07)))) { g, p in g.set(0, clampF(p.y / g.h - 0.86, 0, 0.13)) }] + sizeJoints(f, 40, 40)
    }
  ) { draw, f in
    let b = f.h * 0.86
    let a = f.v(0, 0.07) * f.h
    draw.open(0, b, 0, 0, f.w, 0, f.w, b)
    draw.curve(f.w, b, f.w * 0.7, b - a, f.w * 0.5, b, f.w * 0.3, b + a, 0, b)
  }

  // MARK: Computer science

  static let database = sized("database", 90, 110, 30, 40, joints: { f in sizeJoints(f, 30, 40) }) { draw, f in
    let ry = min(f.w * 0.15, f.h * 0.15)
    draw.ellipse(f.w / 2, ry, f.w / 2, ry)
    draw.line(0, ry, 0, f.h - ry)
    draw.line(f.w, ry, f.w, f.h - ry)
    let bands = count((f.h - 2 * ry) / 36, 1, 8)
    for k in 1...bands { draw.ellipseArc(f.w / 2, ry + Float(k) * (f.h - 2 * ry) / Float(bands), f.w / 2, ry, 0, 180) }
  }

  static let terminal = sized("terminal", 140, 60, 40, 20, joints: { f in sizeJoints(f, 40, 20) }) { draw, f in
    let r = min(f.h, f.w) / 2
    draw.line(r, 0, f.w - r, 0)
    draw.line(r, f.h, f.w - r, f.h)
    draw.ellipseArc(r, f.h / 2, r, f.h / 2, 90, 270)
    draw.ellipseArc(f.w - r, f.h / 2, r, f.h / 2, -90, 90)
  }

  static let subroutine = sized(
    "subroutine", 140, 70, 40, 24, [0.1],
    joints: { f in [Joint(Pt(f.v(0, 0.1) * f.w, f.h / 2)) { g, p in g.set(0, clampF(p.x / g.w, 0.02, 0.4)) }] + sizeJoints(f, 40, 24) }
  ) { draw, f in
    let i = f.v(0, 0.1) * f.w
    draw.rect(0, 0, f.w, f.h)
    draw.line(i, 0, i, f.h)
    draw.line(f.w - i, 0, f.w - i, f.h)
  }

  private static func treeLevels(_ f: Frame) -> Int { count(f.h / 45 + 1, 2, 6) }

  static let binaryTree = sized("binary-tree", 150, 120, 40, 40, joints: { f in sizeJoints(f, 40, 40) }) { draw, f in
    let levels = treeLevels(f)
    let r = clampF(min(f.h / (Float(levels) * 3.2), f.w / powf(2, Float(levels - 1)) / 2.6), 3, 14)
    func at(_ l: Int, _ j: Int) -> Pt {
      Pt((Float(j) + 0.5) * f.w / powf(2, Float(l)), r + Float(l) * (f.h - 2 * r) / Float(levels - 1))
    }
    for l in 0..<levels {
      for j in 0..<(1 << l) {
        let p = at(l, j)
        draw.circle(p.x, p.y, r)
        if l + 1 < levels {
          for c in [2 * j, 2 * j + 1] {
            let q = at(l + 1, c)
            draw.link(p.x, p.y, q.x, q.y, r)
          }
        }
      }
    }
  }

  static let graph = sized("graph", 140, 120, 50, 50, joints: { f in sizeJoints(f, 50, 50) }) { draw, f in
    let n = count(Float.pi * (f.w + f.h) / 2 / 55, 3, 12)
    let r = clampF(min(f.w, f.h) * 0.07, 5, 12)
    let pts = (0..<n).map { i in
      let a = -Double.pi / 2 + 2 * Double.pi * Double(i) / Double(n)
      return Pt(f.w / 2 + (f.w / 2 - r) * Float(cos(a)), f.h / 2 + (f.h / 2 - r) * Float(sin(a)))
    }
    for p in pts { draw.circle(p.x, p.y, r) }
    for i in 0..<n {
      let a = pts[i], b = pts[(i + 1) % n]
      draw.link(a.x, a.y, b.x, b.y, r, arrow: true)
      if i % 2 == 0 && n > 4 && i + 2 < n { draw.link(a.x, a.y, pts[i + 2].x, pts[i + 2].y, r, arrow: true) }
    }
  }

  static let array = sized("array", 160, 32, 20, 14, joints: { f in sizeJoints(f, 20, 14) }) { draw, f in
    draw.rect(0, 0, f.w, f.h)
    let n = count(f.w / f.h, 1, 60)
    for k in 1..<n { draw.line(Float(k) * f.w / Float(n), 0, Float(k) * f.w / Float(n), f.h) }
  }

  static let linkedList = line("linked-list", 190, 34) { draw, f in
    let box: Float = 34
    let n = whole((f.w + 18) / (box + 18), 1, 14)
    let pitch = n > 1 ? (f.w - box) / Float(n - 1) : 0
    for i in 0..<n {
      let x = Float(i) * pitch
      draw.rect(x, -11, x + box, 11)
      draw.line(x + 24, -11, x + 24, 11)
      if i + 1 < n { draw.line(x + 29, 0, Float(i + 1) * pitch, 0, arrow: true) } else { draw.line(x + 24, 11, x + box, -11) }
    }
  }

  static let stack = sized("stack", 70, 120, 30, 40, joints: { f in sizeJoints(f, 30, 40) }) { draw, f in
    let a = min(28, f.h * 0.25)
    let n = count((f.h - a) / 26, 1, 30)
    let c = (f.h - a) / Float(n)
    for k in 0..<n { draw.rect(0, a + Float(k) * c, f.w, a + Float(k + 1) * c) }
    draw.line(f.w / 2, 0, f.w / 2, a - 4, arrow: true)
  }

  static let computer = sized("computer", 120, 100, 40, 40, joints: { f in sizeJoints(f, 40, 40) }) { draw, f in
    let sh = f.h * 0.76
    draw.rect(0, 0, f.w, sh)
    draw.rect(f.w * 0.06, sh * 0.08, f.w * 0.94, sh * 0.92)
    draw.line(f.w / 2, sh, f.w / 2, f.h * 0.94)
    draw.line(f.w * 0.28, f.h, f.w * 0.72, f.h)
  }

  // MARK: Law

  static let scales = natural(
    "scales", [0],
    joints: { f in
      let t = deg(f.v(0, 0))
      let lx = 50 - 36 * cosf(t)
      let ly = 22 + 36 * sinf(t)
      return [Joint(Pt(lx, ly + 38)) { g, p in g.set(0, degrees(asinf(clampF((p.y - 38 - 22) / 36, -0.6, 0.6)))) }]
    }
  ) { draw, f in
    let t = deg(f.v(0, 0))
    draw.line(50, 12, 50, 88)
    draw.line(32, 92, 68, 92)
    draw.circle(50, 10, 3)
    let ends = [Pt(50 - 36 * cosf(t), 22 + 36 * sinf(t)), Pt(50 + 36 * cosf(t), 22 - 36 * sinf(t))]
    draw.line(ends[0].x, ends[0].y, ends[1].x, ends[1].y)
    for e in ends {
      draw.line(e.x, e.y, e.x - 11.3, e.y + 30)
      draw.line(e.x, e.y, e.x + 11.3, e.y + 30)
      draw.arc(e.x, e.y + 26, 12, 20, 140)
    }
  }

  static let courthouse = sized("courthouse", 130, 100, 50, 50, joints: { f in sizeJoints(f, 50, 50) }) { draw, f in
    draw.poly(0, f.h * 0.3, f.w / 2, 0, f.w, f.h * 0.3)
    draw.rect(f.w * 0.02, f.h * 0.3, f.w * 0.98, f.h * 0.37)
    let n = count(f.w / 22, 2, 16)
    for k in 0..<n {
      let x = f.w * 0.1 + Float(k) * f.w * 0.8 / Float(n - 1)
      draw.line(x, f.h * 0.37, x, f.h * 0.82)
    }
    draw.rect(0, f.h * 0.82, f.w, f.h * 0.9)
    draw.line(0, f.h, f.w, f.h)
  }

  static let column = sized("column", 50, 110, 24, 50, joints: { f in sizeJoints(f, 24, 50) }) { draw, f in
    draw.rect(0, 0, f.w, f.h * 0.08)
    draw.rect(0, f.h * 0.92, f.w, f.h)
    draw.line(f.w * 0.14, f.h * 0.08, f.w * 0.14, f.h * 0.92)
    draw.line(f.w * 0.86, f.h * 0.08, f.w * 0.86, f.h * 0.92)
    let flutes = count(f.w / 16, 1, 6)
    for k in 1...flutes {
      let x = f.w * 0.14 + Float(k) * f.w * 0.72 / Float(flutes + 1)
      draw.line(x, f.h * 0.12, x, f.h * 0.88)
    }
  }

  static let contract = sized("contract", 80, 105, 40, 50, joints: { f in sizeJoints(f, 40, 50) }) { draw, f in
    draw.rect(0, 0, f.w, f.h)
    let n = whole((f.h * 0.5) / 12, 1, 20)
    for k in 0..<n {
      let y = f.h * 0.12 + Float(k) * 12
      draw.line(f.w * 0.12, y, f.w * (k % 3 == 2 ? 0.6 : 0.88), y)
    }
    draw.curve(f.w * 0.12, f.h * 0.82, f.w * 0.25, f.h * 0.74, f.w * 0.36, f.h * 0.84, f.w * 0.48, f.h * 0.76, f.w * 0.6, f.h * 0.82)
    draw.line(f.w * 0.12, f.h * 0.88, f.w * 0.88, f.h * 0.88)
  }

  static let courtLevels = sized("court-levels", 120, 90, 40, 40, joints: { f in sizeJoints(f, 40, 40) }) { draw, f in
    let n = count(f.h / 26, 2, 7)
    let lh = f.h / Float(n)
    for k in 0..<n {
      let half = f.w * Float(k + 1) / Float(n) / 2
      draw.rect(f.w / 2 - half, Float(k) * lh, f.w / 2 + half, Float(k + 1) * lh)
    }
  }

  static let parties = sized("parties", 150, 70, 70, 30, joints: { f in sizeJoints(f, 70, 30) }) { draw, f in
    draw.person(f.h * 0.42, f.h, f.h)
    draw.person(f.w - f.h * 0.42, f.h, f.h)
    if f.w - 1.7 * f.h > 10 { draw.line(f.h * 0.85, f.h * 0.55, f.w - f.h * 0.85, f.h * 0.55, both: true) }
  }

  // MARK: Nursing and health

  static let medCross = natural(
    "med-cross", [15],
    joints: { f in [Joint(Pt(50 + f.v(0, 15), 5)) { g, p in g.set(0, clampF(p.x - 50, 5, 40)) }] }
  ) { draw, f in
    let t = f.v(0, 15)
    let near = 50 - t, far = 50 + t
    draw.poly(near, 5, far, 5, far, near, 95, near, 95, far, far, far, far, 95, near, 95, near, far, 5, far, 5, near, near, near)
  }

  private static func heartbeats(_ f: Frame) -> Int { count(f.w / 70 - 0.49, 1, 14) }

  static let heartbeat = line(
    "heartbeat", 160, 40, [36],
    joints: { f in
      let slot = f.w / Float(heartbeats(f))
      return [Joint(Pt(slot * 0.5 + 7, -f.v(0, 36))) { g, p in g.set(0, clampF(-p.y, 6, 150)) }]
    }
  ) { draw, f in
    let a = f.v(0, 36)
    let n = heartbeats(f)
    let slot = f.w / Float(n)
    var pts: [Float] = [0, 0]
    let beat: [(Float, Float)] = [(-22, 0), (-15, -0.22), (-9, 0), (-3, 0), (1, 0.6), (7, -1), (13, 0.3), (17, 0)]
    for i in 0..<n {
      let cx = slot * (Float(i) + 0.5)
      for (dx, dy) in beat { pts += [cx + dx, dy * a] }
    }
    pts += [f.w, 0]
    draw.open(pts)
  }

  static let syringe = line(
    "syringe", 130, 60, [0.35],
    joints: { f in
      let b0 = f.w * 0.2
      let b1 = f.w * 0.72
      return [Joint(Pt(b0 + f.v(0, 0.35) * (b1 - b0), -10)) { g, p in g.set(0, clampF((p.x - g.w * 0.2) / (g.w * 0.52), 0.02, 0.95)) }]
    }
  ) { draw, f in
    let b0 = f.w * 0.2
    let b1 = f.w * 0.72
    let px = b0 + f.v(0, 0.35) * (b1 - b0)
    draw.rect(b0, -10, b1, 10)
    draw.line(px, -9, px, 9)
    draw.line(0, 0, px, 0)
    draw.line(0, -9, 0, 9)
    draw.rect(b1, -4, b1 + f.w * 0.05, 4)
    draw.line(b1 + f.w * 0.05, 0, f.w, 0)
  }

  static let thermometer = natural(
    "thermometer", [40],
    joints: { f in [Joint(Pt(50, f.v(0, 40))) { g, p in g.set(0, clampF(p.y, 14, 68)) }] }
  ) { draw, f in
    draw.line(42, 12, 42, 68)
    draw.line(58, 12, 58, 68)
    draw.arc(50, 12, 8, 180, 180)
    draw.circle(50, 80, 14)
    draw.line(50, f.v(0, 40), 50, 66)
    for y: Float in [25, 38, 51] { draw.line(58, y, 66, y) }
  }

  static let ivBag = natural(
    "iv-bag", [20],
    joints: { f in [Joint(Pt(70, f.v(0, 20))) { g, p in g.set(0, clampF(p.y, 8, 52)) }] }
  ) { draw, f in
    draw.rect(30, 5, 70, 55)
    draw.line(30, f.v(0, 20), 70, f.v(0, 20))
    draw.line(45, 55, 45, 62)
    draw.line(55, 55, 55, 62)
    draw.rect(43, 62, 57, 76)
    draw.curve(50, 76, 50, 86, 60, 95)
  }
}
