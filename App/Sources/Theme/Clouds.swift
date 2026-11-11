import SwiftUI

/// One cloud's puffs (x, y, r as shares of its width), how many of the first make the crown, and the
/// flat base joining them (ported from `ui/components/Clouds.kt`).
private struct CloudRecipe {
  let crown: Int
  let puffs: [(CGFloat, CGFloat, CGFloat)]
  let base: CGRect
}

private let recipes: [CloudRecipe] = [
  // Big cumulus.
  CloudRecipe(
    crown: 5,
    puffs: [
      (0.31, 0.25, 0.12), (0.49, 0.17, 0.165), (0.68, 0.235, 0.135), (0.83, 0.32, 0.09), (0.17, 0.33, 0.085),
      (0.12, 0.405, 0.06), (0.25, 0.40, 0.075), (0.38, 0.405, 0.08), (0.51, 0.40, 0.085), (0.64, 0.405, 0.08), (0.77, 0.40, 0.075), (0.88, 0.41, 0.055),
    ],
    base: CGRect(x: 0.12, y: 0.28, width: 0.76, height: 0.19)),
  // Long, low cloud.
  CloudRecipe(
    crown: 5,
    puffs: [
      (0.25, 0.30, 0.10), (0.42, 0.235, 0.14), (0.61, 0.27, 0.12), (0.78, 0.33, 0.085), (0.11, 0.36, 0.07),
      (0.08, 0.415, 0.045), (0.18, 0.41, 0.06), (0.30, 0.41, 0.065), (0.43, 0.41, 0.07), (0.56, 0.41, 0.07), (0.69, 0.41, 0.065), (0.81, 0.41, 0.06), (0.90, 0.415, 0.045),
    ],
    base: CGRect(x: 0.08, y: 0.30, width: 0.82, height: 0.17)),
  // Small, round puff.
  CloudRecipe(
    crown: 4,
    puffs: [
      (0.36, 0.22, 0.17), (0.62, 0.24, 0.16), (0.20, 0.34, 0.11), (0.82, 0.35, 0.10),
      (0.14, 0.41, 0.06), (0.27, 0.405, 0.08), (0.42, 0.405, 0.085), (0.58, 0.405, 0.085), (0.73, 0.405, 0.08), (0.87, 0.41, 0.06),
    ],
    base: CGRect(x: 0.14, y: 0.28, width: 0.73, height: 0.19)),
]

/// The box is a little taller than the cloud so its floating shadow has room.
private let cloudAspect: CGFloat = 0.56

/// One fluffy cartoon cloud: sunlit puffs on top, a soft blue-lilac underside and a gentle shadow
/// floating beneath. Drawn into one layer (`drawingGroup`), so drifting it costs nothing.
struct Cloud: View {
  var width: CGFloat = 160
  var variant = 0
  @Environment(\.tali) private var c

  var body: some View {
    let recipe = recipes[variant % recipes.count]
    Canvas { ctx, size in
      let w = size.width
      func circle(_ x: CGFloat, _ y: CGFloat, _ r: CGFloat) -> CGRect { CGRect(x: (x - r) * w, y: (y - r) * w, width: r * 2 * w, height: r * 2 * w) }
      // The shadow.
      var shadowCtx = ctx
      shadowCtx.addFilter(.blur(radius: w * 0.03))
      shadowCtx.fill(Path(ellipseIn: CGRect(x: w * 0.12, y: w * 0.47, width: w * 0.76, height: w * 0.06)), with: .color(c.skyCloudShadow))

      var body = Path()
      for (x, y, r) in recipe.puffs { body.addEllipse(in: circle(x, y, r)) }
      let b = recipe.base
      body.addRoundedRect(
        in: CGRect(x: b.minX * w, y: b.minY * w, width: b.width * w, height: b.height * w), cornerSize: CGSize(width: b.height * w / 2, height: b.height * w / 2))
      let top = recipe.puffs.map { $0.1 - $0.2 }.min()! * w
      let bottom = recipe.puffs.map { $0.1 + $0.2 }.max()! * w
      ctx.fill(
        body,
        with: .linearGradient(
          Gradient(stops: [
            .init(color: c.skyCloudTop, location: 0), .init(color: c.skyCloudTop, location: 0.42), .init(color: c.skyCloudMid, location: 0.78),
            .init(color: c.skyCloudLow, location: 1),
          ]), startPoint: CGPoint(x: 0, y: top), endPoint: CGPoint(x: 0, y: bottom)))

      var inside = ctx
      inside.clip(to: body)
      // The glow: crown puffs lifted a touch and blurred so far that no circle edge survives.
      var glow = Path()
      for i in 0..<recipe.crown {
        let (x, y, r) = recipe.puffs[i]
        glow.addEllipse(in: circle(x - r * 0.05, y - r * 0.12, r * 0.92))
      }
      var glowCtx = inside
      glowCtx.addFilter(.blur(radius: w * 0.045))
      glowCtx.fill(glow, with: .color(c.skyCloudTop.opacity(0.95)))
      // Creases: a soft shade along the lower rim of each crown puff.
      var crease = inside
      crease.addFilter(.blur(radius: w * 0.014))
      for i in 1..<recipe.crown {
        let (x, y, r) = recipe.puffs[i]
        let start = x < 0.5 ? 63.0 : 27.0
        var arc = Path()
        arc.addArc(center: CGPoint(x: x * w, y: y * w), radius: r * w * 0.97, startAngle: .degrees(start), endAngle: .degrees(start + 90), clockwise: false)
        crease.stroke(arc, with: .color(c.skyCloudMid.opacity(0.55)), style: StrokeStyle(lineWidth: w * 0.022, lineCap: .round))
      }
    }
    .frame(width: width, height: width * cloudAspect)
    .drawingGroup()
  }
}

/// A cloud drifting gently from side to side. Tapped, it bursts: it swells a touch and melts into
/// mist, then quietly forms again a few seconds later (Android's burstable `Cloud`).
struct DriftingCloud: View {
  var width: CGFloat
  var variant = 0
  var drift: CGFloat = 10
  var period: Double = 9
  var alpha: Double = 1
  @State private var out = false
  @State private var gone: Double = 0
  @State private var puffStart: Date?
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @AppStorage("minimal") private var minimal = false

  var body: some View {
    if !minimal {
      Cloud(width: width, variant: variant)
        .scaleEffect(1 + 0.08 * gone)
        .blur(radius: 8 * gone)
        .opacity(alpha * (1 - gone))
        .overlay {
          if let start = puffStart {
            PuffPlayer(start: start, duration: PuffTiming.burstMist)
          }
        }
        .contentShape(Ellipse())
        .onTapGesture(perform: burst)
        .offset(x: out ? drift : -drift)
        .onAppear {
          guard !reduceMotion, !ProcessInfo.processInfo.arguments.contains("-uitest") else { return }
          withAnimation(.easeInOut(duration: period / 2).repeatForever(autoreverses: true)) { out = true }
        }
    }
  }

  private func burst() {
    guard gone < 0.3 else { return }
    UIImpactFeedbackGenerator(style: .soft).impactOccurred(intensity: 0.6)
    puffStart = Date()
    withAnimation(Ease.outStrong(duration: PuffTiming.elementLeave)) { gone = 1 }
    Task { @MainActor in
      try? await Task.sleep(for: .seconds(PuffTiming.burstMist))
      puffStart = nil
      try? await Task.sleep(for: .seconds(PuffTiming.reformAfter - PuffTiming.burstMist))
      withAnimation(Ease.outStrong(duration: 1.1)) { gone = 0 }
    }
  }
}

/// The sky behind the library's heading: two soft blues meeting, fading into the background.
struct SkyBand: View {
  var height: CGFloat = 320
  @Environment(\.tali) private var c

  var body: some View {
    ZStack {
      LinearGradient(colors: [c.skyFrom, c.skyTo], startPoint: .topLeading, endPoint: .bottomTrailing)
      LinearGradient(stops: [.init(color: .clear, location: 0.35), .init(color: c.background, location: 1)], startPoint: .top, endPoint: .bottom)
    }
    .frame(height: height)
  }
}

/// Clouds scattered across the sky band, arranged by the screen's width.
struct SkyClouds: View {
  var width: CGFloat

  var body: some View {
    ZStack(alignment: .topLeading) {
      if width >= 1100 {
        DriftingCloud(width: 96, variant: 1, drift: 5, period: 23, alpha: 0.55).offset(x: 196, y: 104)
        DriftingCloud(width: 84, variant: 2, drift: 4, period: 26, alpha: 0.5).offset(x: width - 196 - 84, y: 118)
        DriftingCloud(width: 190, variant: 2, drift: 8, period: 14).offset(x: -24, y: 18)
        DriftingCloud(width: 230, variant: 1, drift: 12, period: 17).offset(x: 300, y: 8)
        DriftingCloud(width: 260, variant: 0, drift: 14, period: 20).offset(x: width / 2 - 130 + 170, y: 12)
        DriftingCloud(width: 170, variant: 2, drift: 8, period: 12).offset(x: width - 20 - 170, y: 26)
        Sparkle(size: 11).offset(x: 230, y: 40)
        Sparkle(size: 13).offset(x: width / 2 - 60, y: 26)
        Sparkle(size: 9, opacity: 0.85).offset(x: width - 230, y: 76)
      } else {
        DriftingCloud(width: 90, variant: 1, drift: 5, period: 23, alpha: 0.55).offset(x: 170, y: 110)
        DriftingCloud(width: 180, variant: 2, drift: 8, period: 14).offset(x: -24, y: 18)
        DriftingCloud(width: 230, variant: 0, drift: 12, period: 19).offset(x: width * 0.36, y: 10)
        DriftingCloud(width: 160, variant: 2, drift: 8, period: 12).offset(x: width - 16 - 160, y: 30)
        Sparkle(size: 11).offset(x: 214, y: 42)
        Sparkle(size: 9, opacity: 0.85).offset(x: width - 190, y: 96)
      }
    }
    .frame(width: width, alignment: .topLeading)
  }
}

/// A four-point sparkle.
struct Sparkle: View {
  var size: CGFloat = 10
  var opacity: Double = 1
  var color: Color = .white

  var body: some View {
    Canvas { ctx, s in
      let w = s.width, h = s.height
      var p = Path()
      p.move(to: CGPoint(x: w / 2, y: 0))
      p.addQuadCurve(to: CGPoint(x: w, y: h / 2), control: CGPoint(x: w * 0.56, y: h * 0.44))
      p.addQuadCurve(to: CGPoint(x: w / 2, y: h), control: CGPoint(x: w * 0.56, y: h * 0.56))
      p.addQuadCurve(to: CGPoint(x: 0, y: h / 2), control: CGPoint(x: w * 0.44, y: h * 0.56))
      p.addQuadCurve(to: CGPoint(x: w / 2, y: 0), control: CGPoint(x: w * 0.44, y: h * 0.44))
      ctx.fill(p, with: .color(color.opacity(opacity)))
    }
    .frame(width: size, height: size)
  }
}
