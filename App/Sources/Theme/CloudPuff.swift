import SwiftUI

/// Strong ease-out (0.23, 1, 0.32, 1): moves straight away, then settles (Android's `EaseOutStrong`).
enum Ease {
  static func cubic(_ x1: Double, _ y1: Double, _ x2: Double, _ y2: Double, _ t: Double) -> Double {
    if t <= 0 { return 0 }
    if t >= 1 { return 1 }
    // Solve x(s) = t for s by Newton's method, then return y(s).
    func bx(_ s: Double) -> Double { 3 * (1 - s) * (1 - s) * s * x1 + 3 * (1 - s) * s * s * x2 + s * s * s }
    func by(_ s: Double) -> Double { 3 * (1 - s) * (1 - s) * s * y1 + 3 * (1 - s) * s * s * y2 + s * s * s }
    func dx(_ s: Double) -> Double { 3 * (1 - s) * (1 - s) * x1 + 6 * (1 - s) * s * (x2 - x1) + 3 * s * s * (1 - x2) }
    var s = t
    for _ in 0..<8 {
      let d = dx(s)
      if abs(d) < 1e-6 { break }
      s = min(max(s - (bx(s) - t) / d, 0), 1)
    }
    return by(s)
  }
  static func outStrong(_ t: Double) -> Double { cubic(0.23, 1, 0.32, 1, t) }
  static func inOutSoft(_ t: Double) -> Double { cubic(0.45, 0, 0.55, 1, t) }
  static let outStrongAnimation = Animation.timingCurve(0.23, 1, 0.32, 1, duration: 0.2)
  static func outStrong(duration: Double) -> Animation { .timingCurve(0.23, 1, 0.32, 1, duration: duration) }
}

/// How long things take to go, and how long the quiet mist lasts (Android's `CloudPuff.kt`).
enum PuffTiming {
  static let elementLeave = 0.200
  static let subtlePuff = 0.520
  static let burstMist = 0.640
  static let reformAfter = 4.0
  static let leave = 0.600
}

/// One wisp: where it starts (from the centre), where it drifts to, its size, timing and tint.
private struct Wisp {
  let x: CGFloat, y: CGFloat, dx: CGFloat, dy: CGFloat, r: CGFloat, delay: Double, weight: Double, tone: Int
}

private let tones = 4

private func hash(_ i: Int, _ salt: Int) -> CGFloat {
  let x = sin(Double(i) * 127.1 + Double(salt) * 311.7) * 43758.5453
  return CGFloat(x - floor(x))
}

/// Wisps covering a [w] by [h] area on a jittered grid with rounded-off corners, each drifting
/// outwards from the middle and upwards (Android's `mist`).
private func mist(_ w: CGFloat, _ h: CGFloat, smooth: Bool) -> [Wisp] {
  var r = min(max(min(w, h) * 0.42, 24), 58) * (smooth ? 1.35 : 1)
  var step = r * 0.72
  while ceil(w / step) * ceil(h / step) > 56 {
    r *= 1.12
    step = r * 0.72
  }
  let cols = max(Int(ceil(w / step)), 1)
  let rows = h < r * 1.6 ? 1 : max(Int(ceil(h / step)), 1)
  var out: [Wisp] = []
  let reach = hypot(w / 2, h / 2)
  var i = 0
  for row in 0..<rows {
    for col in 0..<cols {
      i += 1
      let u = (CGFloat(col) + 0.5) / CGFloat(cols) - 0.5
      let v = (CGFloat(row) + 0.5) / CGFloat(rows) - 0.5
      if cols > 2 && rows > 2 && u * u + v * v > 0.42 && hash(i, 9) < 0.7 { continue }
      let x = u * w * 0.9 + (hash(i, 1) - 0.5) * step * 0.6
      let y = v * h * 0.9 + (hash(i, 2) - 0.5) * step * 0.6
      let len = max(hypot(x, y), 1)
      let spread = r * (0.25 + 0.45 * hash(i, 3)) * (len / reach)
      let dx = x / len * spread + (hash(i, 4) - 0.5) * r * 0.3
      let dy = y / len * spread * 0.5 - r * 0.35 * hash(i, 10)
      let size = r * (0.8 + 0.45 * hash(i, 5)) * (row == 0 && rows > 1 ? 1.15 : 1)
      let tone = min(max(Int((((v + 0.5) * CGFloat(tones - 1)) + (hash(i, 6) - 0.5)).rounded()), 0), tones - 1)
      out.append(
        Wisp(
          x: x, y: y, dx: smooth ? dx * 0.5 : dx, dy: smooth ? dy * 0.5 : dy, r: size,
          delay: Double(hash(i, 7)) * (smooth ? 0.04 : 0.12), weight: smooth ? 1 : 0.75 + 0.25 * Double(hash(i, 8)), tone: tone))
    }
  }
  return out
}

/// A puff of mist over its area that dissipates as [progress] goes from 0 to 1, spilling a little
/// past the area (Android's `CloudPuff`). Subtle by default (white wisps with a hint of lilac);
/// [vivid] is the fuller, faintly lilac mist of deleting something.
struct CloudPuffCanvas: View {
  var progress: Double
  var strength: Double = 1
  var vivid = false
  @Environment(\.tali) private var c

  static let overflow: CGFloat = 56

  var body: some View {
    Canvas { ctx, size in
      let t = progress
      guard t > 0, t < 1 else { return }
      let m = CloudPuffCanvas.overflow
      let w = size.width - 2 * m, h = size.height - 2 * m
      guard w > 0, h > 0 else { return }
      let dark = c.isDark
      let wisps = mist(w, h, smooth: dark)
      let top: Color = dark ? mix(mix(c.cloudTop, c.dusk, 0.4), .white, 0.45) : (vivid ? mix(.white, c.cloudBelly, 0.28) : .white)
      let low: Color = dark ? top : mix(.white, c.cloudBelly, vivid ? 0.85 : 0.7)
      let belly = mix(c.cloudBelly, c.accent, vivid ? 0.38 : 0.22)
      let peak = (dark ? (vivid ? 0.38 : 0.26) : (vivid ? 1 : 0.95)) * strength
      let hold = vivid ? 0.18 : 0
      let underside = vivid ? 0.7 : 0.4
      let tints = (0..<tones).map { mix(top, low, CGFloat($0) / CGFloat(tones - 1)) }
      let cx = m + w / 2, cy = m + h / 2
      let lift = -min(h, w) * (vivid ? 0.22 : 0.28) * Ease.outStrong(t)
      let swell = 1 + (vivid ? 0.14 : 0.22) * Ease.outStrong(t)
      for pass in (dark ? 1 : 0)...1 {
        for p in wisps {
          if pass == 0 && p.tone < tones / 2 { continue }
          let local = min(max((t - p.delay) / (1 - p.delay), 0), 1)
          if local <= 0 { continue }
          let go = Ease.outStrong(local)
          let a = peak * p.weight * Ease.outStrong(min(local / 0.12, 1)) * (1 - Ease.inOutSoft(min(max((local - hold) / (1 - hold), 0), 1)))
          if a <= 0.004 { continue }
          let x = cx + p.x * swell + p.dx * go
          let y = cy + p.y * swell + p.dy * go + lift + (pass == 0 ? p.r * 0.3 : 0)
          let r = p.r * (vivid ? 0.82 + 0.36 * go : 0.9 + 0.45 * go)
          let color = pass == 0 ? belly : tints[p.tone]
          let alpha = min(pass == 0 ? a * underside : a, 1)
          // A soft Gaussian dot, like Android's SoftDot sprite.
          let stops = (0...8).map { k -> Gradient.Stop in
            let s = Double(k) / 8
            let g = exp(-(s * s) / (2 * 0.44 * 0.44)) * (1 - s * s * s)
            return .init(color: color.opacity(g * alpha), location: s)
          }
          ctx.fill(
            Path(ellipseIn: CGRect(x: x - r, y: y - r, width: 2 * r, height: 2 * r)),
            with: .radialGradient(Gradient(stops: stops), center: CGPoint(x: x, y: y), startRadius: 0, endRadius: r))
        }
      }
    }
    .padding(-CloudPuffCanvas.overflow)
    .allowsHitTesting(false)
  }
}

/// A mist that plays once from [start] over [duration] seconds.
struct PuffPlayer: View {
  var start: Date
  var duration: Double
  var strength: Double = 1
  var vivid = false

  var body: some View {
    TimelineView(.animation) { tl in
      CloudPuffCanvas(progress: tl.date.timeIntervalSince(start) / duration, strength: strength, vivid: vivid)
    }
  }
}
