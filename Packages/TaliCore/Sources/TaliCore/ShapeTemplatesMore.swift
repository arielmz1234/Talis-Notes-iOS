import Foundation

// The rest of the Android app's `model/ShapeTemplates.kt`: mechanical, civil, electrical,
// psychology, economics, design and art. See ShapeTemplates.swift.

extension ShapeTemplates {
  // MARK: Mechanical engineering

  static let gear = sized("gear", 100, 100, 30, 30, round: true, joints: { f in [diameterJoint(f, 30)] }) { draw, f in
    let d = min(f.w, f.h)
    let r = d / 2
    let c = Pt(r, r)
    let n = count(2 * Float.pi * r / 17, 6, 48)
    let step = 360 / Float(n)
    var p: [Float] = []
    let tooth: [(Float, Float)] = [(0.76, -0.31), (1, -0.18), (1, 0.18), (0.76, 0.31)]
    for t in 0..<n {
      let base = Float(t) * step
      for (rr, dd) in tooth {
        let a = deg(base + dd * step)
        p += [c.x + r * rr * cosf(a), c.y + r * rr * sinf(a)]
      }
    }
    draw.poly(p)
    draw.circle(c.x, c.y, r * 0.27)
  }

  private static func springCoils(_ f: Frame) -> (lead: Float, n: Int, pitch: Float) {
    let lead = f.w * 0.15
    let n = count((f.w - 2 * lead) / 9, 2, 60)
    return (lead, n, (f.w - 2 * lead) / Float(n))
  }

  static let spring = line(
    "spring", 150, 40, [10],
    joints: { f in
      let (lead, _, pitch) = springCoils(f)
      return [Joint(Pt(lead + pitch * 0.5, -f.v(0, 10))) { g, p in g.set(0, clampF(-p.y, 3, 80)) }]
    }
  ) { draw, f in
    let a = f.v(0, 10)
    let (lead, n, pitch) = springCoils(f)
    var pts: [Float] = [0, 0, lead, 0]
    for i in 0..<n { pts += [lead + pitch * (Float(i) + 0.5), i % 2 == 0 ? -a : a] }
    pts += [f.w - lead, 0, f.w, 0]
    draw.open(pts)
  }

  static let damper = line(
    "damper", 140, 50, [0.5],
    joints: { f in
      [Joint(Pt(f.w * 0.35 + f.v(0, 0.5) * f.w * 0.33, -10)) { g, p in g.set(0, clampF((p.x - g.w * 0.35) / (g.w * 0.33), 0.1, 0.95)) }]
    }
  ) { draw, f in
    let c0 = f.w * 0.35
    let c1 = f.w * 0.68
    let px = c0 + f.v(0, 0.5) * (c1 - c0)
    draw.line(0, 0, c0, 0)
    draw.open(c1, -14, c0, -14, c0, 14, c1, 14)
    draw.line(px, -10, px, 10)
    draw.line(px, 0, f.w, 0)
  }

  static let bearing = sized("bearing", 100, 100, 30, 30, round: true, joints: { f in [diameterJoint(f, 30)] }) { draw, f in
    let r = min(f.w, f.h) / 2
    draw.circle(r, r, r)
    draw.circle(r, r, r * 0.67)
    draw.circle(r, r, r * 0.29)
    let n = count(2 * Float.pi * r * 0.83 / (r * 0.3), 6, 16)
    for i in 0..<n {
      let a = 2 * Double.pi * Double(i) / Double(n)
      draw.circle(r + r * 0.83 * Float(cos(a)), r + r * 0.83 * Float(sin(a)), r * 0.12)
    }
  }

  static let pulley = natural(
    "pulley", [76],
    joints: { f in [Joint(Pt(72, f.v(0, 76) + 16)) { g, p in g.set(0, clampF(p.y - 16, 60, 140)) }] }
  ) { draw, f in
    let y = f.v(0, 76)
    draw.line(32, 2, 68, 2)
    draw.line(50, 2, 50, 14)
    draw.circle(50, 36, 22)
    draw.circle(50, 36, 4)
    draw.line(28, 36, 28, 96)
    draw.line(72, 36, 72, y)
    draw.rect(62, y, 82, y + 16)
  }

  static let lever = sized(
    "lever", 160, 70, 60, 30, [0.5],
    joints: { f in
      [
        Joint(Pt(f.v(0, 0.5) * f.w, f.h * 0.55 + f.h * 0.3)) { g, p in g.set(0, clampF(p.x / g.w, 0.08, 0.92)) },
        widthJoint(f, 60),
        topJoint(f, 30, x: f.w * 0.04),
      ]
    }
  ) { draw, f in
    let by = f.h * 0.55
    let s = f.h * 0.3
    let fx = f.v(0, 0.5) * f.w
    draw.line(0, by, f.w, by)
    draw.poly(fx, by, fx - s * 0.6, by + s, fx + s * 0.6, by + s)
    draw.line(f.w * 0.04, 0, f.w * 0.04, by - 2, arrow: true)
    draw.line(f.w * 0.96, 0, f.w * 0.96, by - 2, arrow: true)
  }

  static let piston = natural(
    "piston", [42],
    joints: { f in [Joint(Pt(78, f.v(0, 42) + 8)) { g, p in g.set(0, clampF(p.y - 8, 16, 74)) }] }
  ) { draw, f in
    let y = f.v(0, 42)
    draw.open(20, 12, 20, 92, 80, 92, 80, 12)
    draw.rect(22, y, 78, y + 16)
    draw.line(50, y, 50, 0)
  }

  static let mass = sized(
    "mass", 110, 80, 40, 40, [0.45, 0.65],
    joints: { f in
      let gy = f.h * 0.82
      let bw = f.v(0, 0.45) * f.w
      let bh = f.v(1, 0.65) * gy
      return [
        Joint(Pt(f.w / 2 + bw / 2, gy - bh)) { g, p in
          g.set(0, clampF(2 * (p.x - g.w / 2) / g.w, 0.1, 1)).set(1, clampF((g.h * 0.82 - p.y) / (g.h * 0.82), 0.1, 1))
        }
      ] + sizeJoints(f, 40, 40)
    }
  ) { draw, f in
    let gy = f.h * 0.82
    let bw = f.v(0, 0.45) * f.w
    let bh = f.v(1, 0.65) * gy
    draw.rect(f.w / 2 - bw / 2, gy - bh, f.w / 2 + bw / 2, gy)
    draw.line(0, gy, f.w, gy)
    let d = f.h - gy
    let n = count((f.w - d) / 12, 5, 40)
    for i in 0..<n {
      let x = d + (f.w - d) * (Float(i) + 0.5) / Float(n)
      draw.line(x, gy, x - d, f.h)
    }
  }

  static let shaft = line(
    "shaft", 150, 40, [0.4, 12],
    joints: { f in
      let r = f.v(1, 12)
      return [
        Joint(Pt(f.v(0, 0.4) * f.w, -r)) { g, p in g.set(0, clampF(p.x / g.w, 0.12, 0.88)) },
        Joint(Pt(f.w * 0.88, -r)) { g, p in g.set(1, clampF(-p.y, 3, 60)) },
      ]
    }
  ) { draw, f in
    let r = f.v(1, 12)
    let k = f.v(0, 0.4) * f.w
    draw.rect(0, -r, f.w, r)
    draw.rect(k - f.w * 0.1, -r, k + f.w * 0.1, -r * 0.5)
    draw.line(0, 0, f.w, 0)
  }

  static let bolt = sized("bolt", 40, 100, 16, 40, joints: { f in sizeJoints(f, 16, 40) }) { draw, f in
    let hh = min(f.h * 0.24, f.w * 0.6)
    draw.poly(f.w * 0.15, 0, f.w * 0.85, 0, f.w, hh / 2, f.w * 0.85, hh, f.w * 0.15, hh, 0, hh / 2)
    draw.rect(f.w * 0.25, hh, f.w * 0.75, f.h)
    let start = hh + (f.h - hh) * 0.3
    let n = whole((f.h - start) / 9, 1, 40)
    for k in 0..<n {
      let y = start + Float(k + 1) * (f.h - start) / (Float(n) + 0.5)
      draw.line(f.w * 0.25, y, f.w * 0.75, y - f.w * 0.12)
    }
  }

  // MARK: Civil engineering

  static let truss = sized("truss", 200, 60, 60, 20, joints: { f in sizeJoints(f, 60, 20) }) { draw, f in
    let n = count(f.w / (f.h * 0.9), 2, 24)
    let pw = f.w / Float(n)
    draw.line(0, f.h, f.w, f.h)
    draw.line(pw, 0, f.w - pw, 0)
    draw.line(0, f.h, pw, 0)
    draw.line(f.w, f.h, f.w - pw, 0)
    for k in 1..<n { draw.line(Float(k) * pw, 0, Float(k) * pw, f.h) }
    for k in 1..<(n - 1) {
      if Float(k) < Float(n) / 2 { draw.line(Float(k) * pw, 0, Float(k + 1) * pw, f.h) } else { draw.line(Float(k + 1) * pw, 0, Float(k) * pw, f.h) }
    }
  }

  static let iBeam = sized(
    "i-beam", 80, 100, 24, 30, [0.15, 0.16],
    joints: { f in
      [
        Joint(Pt(f.w * 0.85, f.v(0, 0.15) * f.h)) { g, p in g.set(0, clampF(p.y / g.h, 0.03, 0.45)) },
        Joint(Pt(f.w / 2 + f.v(1, 0.16) * f.w / 2, f.h / 2)) { g, p in g.set(1, clampF(2 * (p.x - g.w / 2) / g.w, 0.03, 0.9)) },
        // The width dot sits up on the flange, clear of the web's dot.
        Joint(Pt(f.w, f.h * 0.07)) { g, p in g.sized(w: max(p.x, 24)) },
        heightJoint(f, 30),
      ]
    }
  ) { draw, f in
    let tf = f.v(0, 0.15) * f.h
    let tw = f.v(1, 0.16) * f.w
    let l = f.w / 2 - tw / 2
    let r = f.w / 2 + tw / 2
    draw.poly(0, 0, f.w, 0, f.w, tf, r, tf, r, f.h - tf, f.w, f.h - tf, f.w, f.h, 0, f.h, 0, f.h - tf, l, f.h - tf, l, tf, 0, tf)
  }

  // MARK: Electrical engineering (drawn from terminal to terminal)

  static let resistor = line("resistor", 120, 40) { draw, f in
    let bl = min(48, f.w * 0.6)
    let s = (f.w - bl) / 2
    var pts: [Float] = [0, 0, s, 0]
    for i in 0..<6 { pts += [s + bl * (Float(i) + 0.5) / 6, i % 2 == 0 ? -8 : 8] }
    pts += [s + bl, 0, f.w, 0]
    draw.open(pts)
  }

  static let capacitor = line("capacitor", 120, 30) { draw, f in
    let c = f.w / 2
    draw.line(0, 0, c - 4, 0)
    draw.line(c - 4, -15, c - 4, 15)
    draw.line(c + 4, -15, c + 4, 15)
    draw.line(c + 4, 0, f.w, 0)
  }

  static let inductor = line("inductor", 120, 40) { draw, f in
    let n = count(f.w * 0.6 / 14, 2, 16)
    let s = (f.w - Float(n) * 14) / 2
    draw.line(0, 0, s, 0)
    for i in 0..<n { draw.arc(s + 7 + 14 * Float(i), 0, 7, 180, 180) }
    draw.line(f.w - s, 0, f.w, 0)
  }

  static let diode = line("diode", 120, 40) { draw, f in
    let c = f.w / 2
    draw.line(0, 0, c - 11, 0)
    draw.poly(c - 11, -12, c - 11, 12, c + 11, 0)
    draw.line(c + 11, -12, c + 11, 12)
    draw.line(c + 11, 0, f.w, 0)
  }

  static let battery = line("battery", 120, 30) { draw, f in
    let n = count(f.w * 0.45 / 18, 1, 8)
    let len = Float(n) * 18 - 11
    let s = (f.w - len) / 2
    draw.line(0, 0, s, 0)
    for i in 0..<n {
      let x = s + Float(i) * 18
      draw.line(x, -14, x, 14)
      draw.line(x + 7, -7, x + 7, 7)
      if i + 1 < n { draw.line(x + 7, 0, x + 18, 0) }
    }
    draw.line(s + len, 0, f.w, 0)
  }

  static let acSource = line("ac-source", 120, 40) { draw, f in
    let c = f.w / 2
    draw.line(0, 0, c - 16, 0)
    draw.circle(c, 0, 16)
    draw.curve(c - 11, 0, c - 5.5, -7, c, 0, c + 5.5, 7, c + 11, 0)
    draw.line(c + 16, 0, f.w, 0)
  }

  static let switchSymbol = line(
    "switch", 120, 40, [28],
    joints: { f in
      let c = f.w / 2
      let t = deg(f.v(0, 28))
      return [Joint(Pt(c - 14 + 30 * cosf(t), -30 * sinf(t))) { g, p in g.set(0, clampF(degrees(atan2f(-p.y, p.x - (g.w / 2 - 14))), 0, 80)) }]
    }
  ) { draw, f in
    let c = f.w / 2
    let t = deg(f.v(0, 28))
    draw.line(0, 0, c - 16, 0)
    draw.circle(c - 14, 0, 2)
    draw.line(c - 14, 0, c - 14 + 30 * cosf(t), -30 * sinf(t))
    draw.circle(c + 16, 0, 2)
    draw.line(c + 18, 0, f.w, 0)
  }

  static let lamp = line("lamp", 120, 40) { draw, f in
    let c = f.w / 2
    draw.line(0, 0, c - 16, 0)
    draw.circle(c, 0, 16)
    draw.line(c - 11.3, -11.3, c + 11.3, 11.3)
    draw.line(c - 11.3, 11.3, c + 11.3, -11.3)
    draw.line(c + 16, 0, f.w, 0)
  }

  static let andGate = sized("and-gate", 90, 80, 40, 30, joints: { f in sizeJoints(f, 40, 30) }) { draw, f in
    let rr = f.h / 2
    let xa = max(f.w * 0.85 - rr, f.w * 0.25)
    draw.open(xa, 0, f.w * 0.2, 0, f.w * 0.2, f.h, xa, f.h)
    draw.arc(xa, rr, rr, -90, 180)
    draw.line(xa + rr, rr, max(f.w, xa + rr + 6), rr)
    let n = count(f.h / 22, 2, 8)
    for k in 0..<n {
      let y = (Float(k) + 0.5) * f.h / Float(n)
      draw.line(0, y, f.w * 0.2, y)
    }
  }

  // MARK: Psychology

  static let neuron = sized("neuron", 170, 70, 70, 30, joints: { f in sizeJoints(f, 70, 30) }) { draw, f in
    let r = f.h * 0.17
    let c = Pt(f.h * 0.35, f.h / 2)
    draw.circle(c.x, c.y, r)
    for a: Float in [200, 235, 125, 160] {
      let e = c + Pt.polar(r, deg(a))
      let o = c + Pt.polar(f.h * 0.45, deg(a))
      draw.line(e.x, e.y, o.x, o.y)
    }
    let end = f.w - f.h * 0.15
    draw.line(c.x + r, c.y, end, c.y)
    let axon = end - c.x - r
    let n = whole(axon / 32, 1, 20)
    for k in 0..<n { draw.ellipse(c.x + r + (Float(k) + 0.5) * axon / Float(n), c.y, min(8, axon / Float(n) * 0.32), f.h * 0.07) }
    for dy: Float in [-0.15, 0, 0.15] { draw.line(end, c.y, f.w, c.y + dy * f.h) }
  }

  static let bellCurve = sized(
    "bell-curve", 140, 90, 50, 30, [0.5, 0.14],
    joints: { f in
      let mu = f.v(0, 0.5) * f.w
      let sd = f.v(1, 0.14) * f.w
      return [
        Joint(Pt(mu, f.h * 0.1)) { g, p in g.set(0, clampF(p.x / g.w, 0.1, 0.9)) },
        Joint(Pt(mu + sd, f.h - 0.9 * f.h * expf(-0.5))) { g, p in g.set(1, clampF((p.x - g.v(0, 0.5) * g.w) / g.w, 0.03, 0.45)) },
      ] + sizeJoints(f, 50, 30)
    }
  ) { draw, f in
    let mu = f.v(0, 0.5) * f.w
    let sd = f.v(1, 0.14) * f.w
    draw.line(0, f.h, f.w, f.h)
    draw.curve((0...30).map { i in
      let x = f.w * Float(i) / 30
      let z = (x - mu) / sd
      return Pt(x, f.h - 0.9 * f.h * expf(-(z * z) / 2))
    })
    draw.line(mu, f.h * 0.1, mu, f.h)
  }

  static let maslow = sized("maslow", 110, 100, 40, 40, joints: { f in sizeJoints(f, 40, 40) }) { draw, f in
    draw.poly(f.w / 2, 0, f.w, f.h, 0, f.h)
    let n = count(f.h / 24, 2, 9)
    for k in 1..<n {
      let y = f.h * Float(k) / Float(n)
      let half = f.w / 2 * y / f.h
      draw.line(f.w / 2 - half, y, f.w / 2 + half, y)
    }
  }

  static let thought = natural(
    "thought", [12, 92],
    joints: { f in [Joint(Pt(f.v(0, 12), f.v(1, 92))) { g, p in g.set(0, clampF(p.x, -40, 140)).set(1, clampF(p.y, 66, 160)) }] }
  ) { draw, f in
    draw.cloud(18, 4, 98, 62)
    let from = Pt(34, 66)
    let to = Pt(f.v(0, 12), f.v(1, 92))
    let m = from + (to - from) * 0.45
    draw.circle(m.x, m.y, 5.5)
    draw.circle(to.x, to.y, 3.5)
  }

  static let eye = natural(
    "eye", [0, 0],
    joints: { f in [Joint(Pt(50 + f.v(0, 0), 50 + f.v(1, 0))) { g, p in g.set(0, clampF(p.x - 50, -26, 26)).set(1, clampF(p.y - 50, -9, 9)) }] }
  ) { draw, f in
    draw.curve(5, 50, 50, 18, 95, 50)
    draw.curve(5, 50, 50, 82, 95, 50)
    let c = Pt(50 + f.v(0, 0), 50 + f.v(1, 0))
    draw.circle(c.x, c.y, 16)
    draw.circle(c.x, c.y, 6)
  }

  static let face = natural(
    "face", [12],
    joints: { f in [Joint(Pt(50, 62 + f.v(0, 12))) { g, p in g.set(0, clampF(p.y - 62, -16, 18)) }] }
  ) { draw, f in
    draw.circle(50, 50, 42)
    draw.circle(36, 40, 4)
    draw.circle(64, 40, 4)
    let smile = f.v(0, 12)
    draw.curve(30, 62, 40, 62 + smile * 0.85, 50, 62 + smile, 60, 62 + smile * 0.85, 70, 62)
  }

  private static func cycleArrows(_ f: Frame) -> Int { count(f.v(0, 4), 2, 8) }

  static let cycle = sized(
    "cycle", 100, 100, 40, 40, [4], round: true,
    joints: { f in
      let r = min(f.w, f.h) / 2 * 0.85
      let c = Pt(min(f.w, f.h) / 2, min(f.w, f.h) / 2)
      let span = 360 / Float(cycleArrows(f))
      return [
        Joint(c + Pt.polar(r, deg(-90 + span * 0.85))) { g, p in
          let a = (degrees(atan2f(p.y - c.y, p.x - c.x)) + 90 + 360).truncatingRemainder(dividingBy: 360)
          return g.set(0, Float(count(360 / max(a / 0.85, 30), 2, 8)))
        },
        cornerSizeJoint(f, 40),
      ]
    }
  ) { draw, f in
    let d = min(f.w, f.h)
    let c = Pt(d / 2, d / 2)
    let r = d / 2 * 0.85
    let n = cycleArrows(f)
    let span = 360 / Float(n)
    for i in 0..<n { draw.arc(c.x, c.y, r, -90 + span * Float(i) + span * 0.08, span * 0.77, arrow: true) }
  }

  private static let scatterDots: [(Float, Float)] = [(0.12, 0.83), (0.25, 0.75), (0.32, 0.62), (0.44, 0.65), (0.55, 0.48), (0.63, 0.52), (0.74, 0.35), (0.86, 0.28)]

  static let scatter = sized(
    "scatter", 130, 100, 50, 40, [0.06, 0.9, 0.94, 0.2],
    joints: { f in
      [0, 2].map { i in
        Joint(Pt(f.v(i, 0) * f.w, f.v(i + 1, 0) * f.h)) { g, p in g.set(i, clampF(p.x / g.w, 0, 1)).set(i + 1, clampF(p.y / g.h, 0, 1)) }
      } + sizeJoints(f, 50, 40)
    }
  ) { draw, f in
    draw.open(0, 0, 0, f.h, f.w, f.h)
    let r = clampF(min(f.w, f.h) * 0.025, 1.5, 4)
    for (x, y) in scatterDots { draw.circle(x * f.w, y * f.h, r) }
    draw.line(f.v(0, 0.06) * f.w, f.v(1, 0.9) * f.h, f.v(2, 0.94) * f.w, f.v(3, 0.2) * f.h)
  }

  // MARK: Economics (on axes from the bottom-left corner)

  private static func axesIn(_ draw: inout Draw, _ f: Frame) {
    draw.line(0, f.h, 0, 0, arrow: true)
    draw.line(0, f.h, f.w, f.h, arrow: true)
  }

  private static func pointJoint(_ f: Frame, _ i: Int, _ x: Float, _ y: Float) -> Joint {
    Joint(Pt(f.v(i, x) * f.w, f.v(i + 1, y) * f.h)) { g, p in g.set(i, clampF(p.x / g.w, 0.02, 0.98)).set(i + 1, clampF(p.y / g.h, 0.02, 0.98)) }
  }

  private static let sdDefaults: [Float] = [0.12, 0.15, 0.9, 0.85, 0.12, 0.85, 0.9, 0.15]

  static let supplyDemand = sized(
    "supply-demand", 130, 110, 50, 50, sdDefaults,
    joints: { f in (0..<4).map { k in pointJoint(f, 2 * k, sdDefaults[2 * k], sdDefaults[2 * k + 1]) } }
  ) { draw, f in
    axesIn(&draw, f)
    for k in [0, 4] {
      draw.line(f.v(k, sdDefaults[k]) * f.w, f.v(k + 1, sdDefaults[k + 1]) * f.h, f.v(k + 2, sdDefaults[k + 2]) * f.w, f.v(k + 3, sdDefaults[k + 3]) * f.h)
    }
  }

  static let axes = sized(
    "axes", 120, 100, 30, 30,
    joints: { f in [Joint(Pt(f.w, f.h)) { g, p in g.sized(w: max(p.x, 30)) }, topJoint(f, 30)] }
  ) { draw, f in axesIn(&draw, f) }

  /// A smooth bend from [a] to [b], pulled towards [corner] by [bulge] (0: straight). It passes
  /// through the point its joint sits on, and is drawn through many points so it stays round.
  private static func bentCurve(_ draw: inout Draw, _ a: Pt, _ b: Pt, _ corner: Pt, _ bulge: Float) {
    let mid = Pt((a.x + b.x) / 2, (a.y + b.y) / 2)
    let m = mid + (corner - mid) * bulge
    // The quadratic curve through a, m (at its middle) and b.
    let c = m * 2 - mid
    draw.curve((0...16).map { i in
      let t = Float(i) / 16
      return a * ((1 - t) * (1 - t)) + c * (2 * t * (1 - t)) + b * (t * t)
    })
  }

  /// How far [p] is pulled from [mid] towards [corner], as a share of the way there.
  private static func pull(_ p: Pt, _ mid: Pt, _ corner: Pt) -> Float {
    let d = corner - mid
    return (p - mid).dot(d) / max(d.dot(d), 1)
  }

  static let demand = sized(
    "demand", 130, 110, 50, 50, [0.12, 0.92, 0.45],
    joints: { f in
      let a = Pt(0.1 * f.w, f.v(0, 0.12) * f.h)
      let b = Pt(f.v(1, 0.92) * f.w, 0.9 * f.h)
      let mid = Pt((a.x + b.x) / 2, (a.y + b.y) / 2)
      let corner = Pt(0.1 * f.w, 0.9 * f.h)
      return [
        Joint(a) { g, p in g.set(0, clampF(p.y / g.h, 0.05, 0.8)) },
        Joint(b) { g, p in g.set(1, clampF(p.x / g.w, 0.3, 0.98)) },
        Joint(mid + (corner - mid) * f.v(2, 0.45)) { g, p in g.set(2, clampF(pull(p, mid, corner), -0.2, 0.95)) },
      ]
    }
  ) { draw, f in
    axesIn(&draw, f)
    bentCurve(&draw, Pt(0.1 * f.w, f.v(0, 0.12) * f.h), Pt(f.v(1, 0.92) * f.w, 0.9 * f.h), Pt(0.1 * f.w, 0.9 * f.h), f.v(2, 0.45))
  }

  static let indifference = sized("indifference", 130, 110, 50, 50, joints: { f in sizeJoints(f, 50, 50) }) { draw, f in
    axesIn(&draw, f)
    let n = count(min(f.w, f.h) / 36, 1, 7)
    for k in 0..<n {
      let s = 0.3 + 0.6 * Float(k + 1) / Float(n)
      // Each curve further out than the last at its ends too, so they never bunch together.
      let a = Pt(0.04 * f.w + 0.24 * s * f.w, f.h - s * f.h * 0.95)
      let b = Pt(s * f.w * 0.95, f.h - 0.04 * f.h - 0.24 * s * f.h)
      bentCurve(&draw, a, b, Pt(a.x, b.y), 0.55)
    }
  }

  static let ppf = sized(
    "ppf", 130, 110, 50, 50, [0.85, 0.85, 0.55],
    joints: { f in
      let yi = Pt(0, f.h - f.v(1, 0.85) * f.h)
      let xi = Pt(f.v(0, 0.85) * f.w, f.h)
      let mid = Pt(xi.x / 2, (yi.y + f.h) / 2)
      let corner = Pt(xi.x, yi.y)
      return [
        Joint(xi) { g, p in g.set(0, clampF(p.x / g.w, 0.2, 0.98)) },
        Joint(yi) { g, p in g.set(1, clampF((g.h - p.y) / g.h, 0.2, 0.98)) },
        Joint(mid + (corner - mid) * f.v(2, 0.55)) { g, p in g.set(2, clampF(pull(p, mid, corner), -0.5, 0.95)) },
      ]
    }
  ) { draw, f in
    axesIn(&draw, f)
    let yi = Pt(0, f.h - f.v(1, 0.85) * f.h)
    let xi = Pt(f.v(0, 0.85) * f.w, f.h)
    bentCurve(&draw, yi, xi, Pt(xi.x, yi.y), f.v(2, 0.55))
  }

  static let costCurves = sized(
    "cost-curves", 130, 110, 50, 50, [0.45, 0.65],
    joints: { f in
      [Joint(Pt(f.v(0, 0.45) * f.w, f.v(1, 0.65) * f.h)) { g, p in g.set(0, clampF(p.x / g.w, 0.25, 0.75)).set(1, clampF(p.y / g.h, 0.25, 0.85)) }]
        + sizeJoints(f, 50, 50)
    }
  ) { draw, f in
    axesIn(&draw, f)
    let mx = f.v(0, 0.45) * f.w
    let my = f.v(1, 0.65) * f.h
    let w = f.w, h = f.h
    draw.curve(0.12 * w, my - 0.45 * my, (0.12 * w + mx) / 2, my - 0.05 * h, mx, my, (mx + 0.92 * w) / 2, my - 0.12 * h, 0.92 * w, 0.12 * h)
    draw.curve(0.15 * w, my - 0.55 * my, (0.15 * w + mx + 0.1 * w) / 2, my - 0.08 * h, mx + 0.1 * w, my - 0.04 * h, 0.94 * w, my - 0.3 * h)
  }

  static let lorenz = sized(
    "lorenz", 110, 110, 40, 40, [0.5],
    joints: { f in
      let mid = Pt(f.w / 2, f.h / 2)
      let corner = Pt(f.w, f.h)
      return [Joint(mid + (corner - mid) * f.v(0, 0.5)) { g, p in g.set(0, clampF(pull(p, Pt(g.w / 2, g.h / 2), Pt(g.w, g.h)), 0, 0.95)) }]
        + sizeJoints(f, 40, 40)
    }
  ) { draw, f in
    draw.rect(0, 0, f.w, f.h)
    draw.line(0, f.h, f.w, 0)
    bentCurve(&draw, Pt(0, f.h), Pt(f.w, 0), Pt(f.w, f.h), f.v(0, 0.5))
  }

  static let businessCycle = sized(
    "business-cycle", 160, 100, 60, 40, [0.16],
    joints: { f in
      let n = count(f.w / 80, 1, 10)
      let period = f.w * 0.85 / Float(n)
      let x = 0.08 * f.w + period / 4
      let trend = 0.78 * f.h - (x - 0.08 * f.w) / (0.85 * f.w) * 0.45 * f.h
      return [
        Joint(Pt(x, trend - f.v(0, 0.16) * f.h)) { g, p in
          let tr = 0.78 * g.h - (x - 0.08 * g.w) / (0.85 * g.w) * 0.45 * g.h
          return g.set(0, clampF((tr - p.y) / g.h, 0.02, 0.4))
        }
      ] + sizeJoints(f, 60, 40)
    }
  ) { draw, f in
    axesIn(&draw, f)
    let n = count(f.w / 80, 1, 10)
    let a = f.v(0, 0.16) * f.h
    let x0 = 0.08 * f.w
    let len = 0.85 * f.w
    draw.line(x0, 0.78 * f.h, x0 + len, 0.78 * f.h - 0.45 * f.h)
    draw.curve((0...(n * 12)).map { i in
      let t = Float(i) / (Float(n) * 12)
      let wave = Float(sin(Double(t * Float(n) * 2) * .pi))
      return Pt(x0 + t * len, 0.78 * f.h - t * 0.45 * f.h - a * wave)
    })
  }

  static let laffer = sized(
    "laffer", 130, 110, 50, 50, [0.5, 0.15],
    joints: { f in
      [Joint(Pt(f.v(0, 0.5) * f.w, f.v(1, 0.15) * f.h)) { g, p in g.set(0, clampF(p.x / g.w, 0.15, 0.85)).set(1, clampF(p.y / g.h, 0.05, 0.8)) }]
        + sizeJoints(f, 50, 50)
    }
  ) { draw, f in
    axesIn(&draw, f)
    let px = f.v(0, 0.5) * f.w
    let py = f.v(1, 0.15) * f.h
    let shoulder = py + (f.h - py) * 0.38
    draw.curve(0, f.h, px * 0.45, shoulder, px, py, px + (0.97 * f.w - px) * 0.55, shoulder, 0.97 * f.w, f.h)
  }

  // MARK: Design and art

  static let colourWheel = sized(
    "colour-wheel", 100, 100, 30, 30, [0.38], round: true,
    joints: { f in
      let r = min(f.w, f.h) / 2
      return [
        Joint(Pt(r + f.v(0, 0.38) * r, r)) { g, p in g.set(0, clampF((p.x - min(g.w, g.h) / 2) / (min(g.w, g.h) / 2), 0.1, 0.85)) },
        Joint(Pt(r, 2 * r)) { g, p in
          let d = max(p.y, 30)
          return g.sized(w: d, h: d)
        },
      ]
    }
  ) { draw, f in
    let r = min(f.w, f.h) / 2
    let ri = f.v(0, 0.38) * r
    draw.circle(r, r, r)
    draw.circle(r, r, ri)
    let n = r < 55 ? 6 : 12
    for i in 0..<n {
      let a = 2 * Double.pi * Double(i) / Double(n) - Double.pi / 2
      let cs = Float(cos(a)), sn = Float(sin(a))
      draw.line(r + ri * cs, r + ri * sn, r + r * cs, r + r * sn)
    }
  }

  static let thirds = sized("thirds", 150, 100, 30, 30, joints: { f in sizeJoints(f, 30, 30) }) { draw, f in
    draw.rect(0, 0, f.w, f.h)
    for k: Float in [1, 2] {
      draw.line(f.w * k / 3, 0, f.w * k / 3, f.h)
      draw.line(0, f.h * k / 3, f.w, f.h * k / 3)
    }
  }

  static let perspective = sized(
    "perspective", 160, 110, 50, 40, [0.5, 0.4],
    joints: { f in
      [Joint(Pt(f.v(0, 0.5) * f.w, f.v(1, 0.4) * f.h)) { g, p in g.set(0, clampF(p.x / g.w, 0, 1)).set(1, clampF(p.y / g.h, 0.05, 0.95)) }]
        + sizeJoints(f, 50, 40)
    }
  ) { draw, f in
    let vp = Pt(f.v(0, 0.5) * f.w, f.v(1, 0.4) * f.h)
    draw.line(0, vp.y, f.w, vp.y)
    let to: [(Float, Float)] = [(0, f.h), (f.w * 0.3, f.h), (f.w * 0.7, f.h), (f.w, f.h), (0, 0), (f.w, 0)]
    for (x, y) in to { draw.line(vp.x, vp.y, x, y) }
  }

  static let frame = sized(
    "frame", 120, 100, 30, 30, [0.1],
    joints: { f in
      let b = f.v(0, 0.1) * min(f.w, f.h)
      return [Joint(Pt(b, b)) { g, p in g.set(0, clampF(min(p.x, p.y) / min(g.w, g.h), 0.02, 0.4)) }] + sizeJoints(f, 30, 30)
    }
  ) { draw, f in
    let b = f.v(0, 0.1) * min(f.w, f.h)
    draw.rect(0, 0, f.w, f.h)
    draw.rect(b, b, f.w - b, f.h - b)
    draw.line(0, 0, b, b)
    draw.line(f.w, 0, f.w - b, b)
    draw.line(f.w, f.h, f.w - b, f.h - b)
    draw.line(0, f.h, b, f.h - b)
  }

  static let cube = sized(
    "cube", 100, 100, 30, 30, [0.3],
    joints: { f in
      let d = f.v(0, 0.3) * min(f.w, f.h)
      return [Joint(Pt(d, 0)) { g, p in g.set(0, clampF(p.x / min(g.w, g.h), 0.05, 0.6)) }] + sizeJoints(f, 30, 30)
    }
  ) { draw, f in
    let d = f.v(0, 0.3) * min(f.w, f.h)
    draw.rect(0, d, f.w - d, f.h)
    draw.open(0, d, d, 0, f.w, 0, f.w, f.h - d, f.w - d, f.h)
    draw.line(f.w - d, d, f.w, 0)
  }

  static let pencil = line("pencil", 130, 40) { draw, f in
    let tip = min(25, f.w * 0.3)
    draw.rect(0, -8, f.w - tip, 8)
    draw.line(min(12, f.w * 0.1), -8, min(12, f.w * 0.1), 8)
    draw.open(f.w - tip, -8, f.w, 0, f.w - tip, 8)
    draw.line(f.w - tip * 0.36, -3, f.w - tip * 0.36, 3)
  }
}
