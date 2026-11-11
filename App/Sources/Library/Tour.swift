import SwiftUI

/// A tour step: a title, a few lines, and the little moving picture that shows it.
struct TourStep {
  var title: String
  var body: String
  var picture: AnyView
}

/// A short walk through the app for someone new (Android's `TourCard`). Android's steps about
/// subject shapes, voice memos, the S Pen and Google Drive are left out until the app has them.
struct TourCard: View {
  var onDone: () -> Void
  var body: some View {
    StepsCard(
      steps: [
        TourStep(title: L("tour_write_title"), body: L("tour_write_body"), picture: AnyView(WritingPicture())),
        TourStep(title: L("tour_pens_title"), body: L("tour_pens_body"), picture: AnyView(PensPicture())),
        TourStep(title: L("tour_hold_title"), body: L("tour_hold_body"), picture: AnyView(HoldPicture())),
        TourStep(title: L("tour_lasso_title"), body: L("tour_lasso_body"), picture: AnyView(LassoPicture())),
      ], finish: L("tour_start_writing"), onDone: onDone)
  }
}

/// A card that walks through [steps] one at a time (Android's `StepsCard`): a counter and Skip
/// along the top, the step's picture beside its words, then dots, Back and Next; the last step's
/// button says [finish].
struct StepsCard: View {
  var steps: [TourStep]
  var finish: String
  var onDone: () -> Void
  @Environment(\.tali) private var c
  @Environment(\.layoutDirection) private var direction
  @State private var at = 0
  @State private var forward = true
  @State private var width: CGFloat = 0

  private var last: Bool { at == steps.count - 1 }

  var body: some View {
    DialogCard(width: 760) {
      HStack(spacing: 0) {
        Text(L("tour_step_n_of_n", at + 1, steps.count)).font(TaliType.labelMedium).foregroundStyle(c.inkFaint)
        Spacer(minLength: 0)
        if !last {
          Button(action: onDone) {
            Text(L("tour_skip")).font(TaliType.labelLarge).foregroundStyle(c.accent)
              .padding(.horizontal, 10).padding(.vertical, 6).contentShape(RoundedRectangle(cornerRadius: 10))
          }
          .buttonStyle(.plain)
          .accessibilityIdentifier("tour-skip")
        }
      }
      Spacer().frame(height: 6)
      ZStack(alignment: .topLeading) {
        page(steps[at]).id(at).transition(slide)
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(GeometryReader { g in Color.clear.onAppear { width = g.size.width }.onChange(of: g.size.width) { _, w in width = w } })
      Spacer().frame(height: 18)
      HStack(spacing: 0) {
        dots.frame(maxWidth: .infinity, alignment: .leading)
        if at > 0 {
          Button(L("back")) { go(at - 1) }.buttonStyle(QuietButtonStyle())
          Spacer().frame(width: 8)
        }
        Button(last ? finish : L("tour_next")) { if last { onDone() } else { go(at + 1) } }
          .buttonStyle(PrimaryButtonStyle())
          .accessibilityIdentifier("tour-next")
      }
    }
  }

  /// Forward slides in from the reading side's end: from the right in English, the left in Hebrew.
  private var slide: AnyTransition {
    let sign: CGFloat = (forward ? 1 : -1) * (direction == .rightToLeft ? -1 : 1)
    return .asymmetric(
      insertion: .offset(x: width / 6 * sign).combined(with: .opacity).animation(Ease.outStrong(duration: 0.26)),
      removal: .offset(x: -width / 8 * sign).combined(with: .opacity).animation(.easeOut(duration: 0.16)))
  }

  private func go(_ i: Int) {
    forward = i > at
    withAnimation(Ease.outStrong(duration: 0.26)) { at = i }
  }

  @ViewBuilder private func page(_ step: TourStep) -> some View {
    if width > 560 {
      HStack(spacing: 26) {
        frame(step.picture)
        words(step).frame(maxWidth: .infinity, alignment: .leading)
      }
    } else {
      VStack(spacing: 16) {
        frame(step.picture)
        words(step).frame(maxWidth: .infinity, alignment: .leading)
      }
      .frame(maxWidth: .infinity)
    }
  }

  private func words(_ step: TourStep) -> some View {
    VStack(alignment: .leading, spacing: 10) {
      Text(step.title).font(TaliType.headlineSmall).foregroundStyle(c.ink)
      Text(step.body).font(TaliType.bodyLarge).foregroundStyle(c.inkMuted).fixedSize(horizontal: false, vertical: true)
    }
  }

  /// A soft page the picture sits on.
  private func frame(_ picture: AnyView) -> some View {
    picture.frame(width: 240, height: 200)
      .frame(width: 280, height: 230)
      .background(RoundedRectangle(cornerRadius: 22).fill(c.surface))
      .overlay(RoundedRectangle(cornerRadius: 22).stroke(c.line, lineWidth: 1))
      .environment(\.layoutDirection, .leftToRight)
  }

  /// One dot per step; the current one is a wider pill. Tapping a dot goes there.
  private var dots: some View {
    HStack(spacing: 6) {
      ForEach(steps.indices, id: \.self) { i in
        Capsule().fill(i == at ? c.accent : c.line)
          .frame(width: i == at ? 22 : 8, height: 8)
          .animation(Ease.outStrong(duration: 0.24), value: at)
          .contentShape(Rectangle().inset(by: -6))
          .onTapGesture { go(i) }
      }
    }
  }
}

// MARK: The pictures: small drawings that loop, in the app's colours

/// 0..1 over [seconds], round and round; with Reduce Motion, held at [still].
private struct Loop<Content: View>: View {
  var seconds: Double
  var still: Double
  @ViewBuilder var content: (Double) -> Content
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  var body: some View {
    if reduceMotion {
      content(still)
    } else {
      TimelineView(.animation) { tl in
        content(tl.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: seconds) / seconds)
      }
    }
  }
}

private func phase(_ t: Double, _ from: Double, _ to: Double) -> Double { min(max((t - from) / (to - from), 0), 1) }

private func ease(_ x: Double) -> Double { 1 - (1 - x) * (1 - x) * (1 - x) }

/// Joined-up "handwriting" from [x0] to [x1] on [baseline]: loops like cursive letters (a prolate
/// trochoid), smaller and taller by turns, with gaps between words.
private func cursive(_ x0: CGFloat, _ x1: CGFloat, _ baseline: CGFloat, _ height: CGFloat, seed: Int = 0) -> [CGPoint] {
  let step = height * 0.42
  let loops = max(Int((x1 - x0) / (step * 2 * .pi)), 2)
  var out: [CGPoint] = []
  for i in 0...(loops * 24) {
    let t = CGFloat(i) / 24 * 2 * .pi
    let letter = i / 24 + seed
    let word = letter % 5 == 4
    let tall: CGFloat = letter % 3 == 1 ? 1.35 : 1
    let amp = (word ? 0.12 : 0.5) * height * tall
    let x = x0 + step * t + amp * 1.3 * sin(t)
    let y = baseline - amp * (1 - cos(t))
    if x > x1 { break }
    out.append(CGPoint(x: x, y: y))
  }
  return out
}

/// The first [part] of a polyline, as a path.
private func partial(_ points: [CGPoint], _ part: Double) -> Path {
  var path = Path()
  guard let first = points.first, part > 0 else { return path }
  var total: CGFloat = 0
  for i in 1..<points.count { total += hypot(points[i].x - points[i - 1].x, points[i].y - points[i - 1].y) }
  var left = total * part
  path.move(to: first)
  for i in 1..<points.count {
    let a = points[i - 1], b = points[i]
    let seg = hypot(b.x - a.x, b.y - a.y)
    if left >= seg {
      path.addLine(to: b)
      left -= seg
    } else {
      let f = seg > 0 ? left / seg : 0
      path.addLine(to: CGPoint(x: a.x + (b.x - a.x) * f, y: a.y + (b.y - a.y) * f))
      break
    }
  }
  return path
}

private func ink(_ ctx: GraphicsContext, _ path: Path, _ color: Color, _ width: CGFloat = 3) {
  ctx.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round))
}

private func line(_ ctx: GraphicsContext, _ a: CGPoint, _ b: CGPoint, _ color: Color, _ width: CGFloat, round: Bool = false) {
  var p = Path()
  p.move(to: a)
  p.addLine(to: b)
  ctx.stroke(p, with: .color(color), style: StrokeStyle(lineWidth: width, lineCap: round ? .round : .butt))
}

private func ruledPage(_ ctx: GraphicsContext, _ size: CGSize, _ c: TaliColors) {
  var y: CGFloat = 26
  while y < size.height {
    line(ctx, CGPoint(x: 0, y: y), CGPoint(x: size.width, y: y), c.line, 1)
    y += 26
  }
}

private struct WritingPicture: View {
  @Environment(\.tali) private var c
  var body: some View {
    Loop(seconds: 3.6, still: 0.95) { t in
      Canvas { ctx, size in
        ruledPage(ctx, size, c)
        let w = size.width
        for l in 0...1 {
          let base = 26 * CGFloat(2 + l) - 3
          let pts = cursive(w * 0.08, w * (l == 0 ? 0.92 : 0.66), base, 13, seed: l * 2)
          let part = phase(t, Double(l) * 0.35, Double(l) * 0.35 + 0.4)
          ink(ctx, partial(pts, ease(part)), c.ink, 2.4)
        }
        let u = ease(phase(t, 0.8, 0.92))
        if u > 0 { line(ctx, CGPoint(x: w * 0.08, y: 104), CGPoint(x: w * 0.08 + w * 0.5 * u, y: 104), c.accent, 3, round: true) }
      }
    }
  }
}

private struct PensPicture: View {
  @Environment(\.tali) private var c
  var body: some View {
    Loop(seconds: 3, still: 0.99) { t in
      Canvas { ctx, size in
        let w = size.width, h = size.height
        let colours = [c.ink, Color(argb: 0xFF2F_6FE0), Color(argb: 0xFFE0_457B)]
        for (i, col) in colours.enumerated() {
          let y = h * (0.25 + CGFloat(i) * 0.22)
          let pts = (0..<40).map { k -> CGPoint in
            let f = CGFloat(k) / 39
            let x: CGFloat = w * 0.1 + w * 0.62 * f
            return CGPoint(x: x, y: y + sin(f * .pi * 2) * 8)
          }
          ink(ctx, partial(pts, ease(phase(t, Double(i) * 0.18, Double(i) * 0.18 + 0.45))), col, 2 + CGFloat(i) * 2.4)
          let dot = CGPoint(x: w * 0.86, y: y)
          ctx.fill(Path(ellipseIn: CGRect(x: dot.x - 9, y: dot.y - 9, width: 18, height: 18)), with: .color(col))
          if Int(t * 3) % 3 == i {
            ctx.stroke(Path(ellipseIn: CGRect(x: dot.x - 13, y: dot.y - 13, width: 26, height: 26)), with: .color(c.accent), lineWidth: 2)
          }
        }
      }
    }
  }
}

private struct HoldPicture: View {
  @Environment(\.tali) private var c
  var body: some View {
    Loop(seconds: 4.2, still: 0.9) { t in
      Canvas { ctx, size in
        let w = size.width, h = size.height
        let l = w * 0.18, r = w * 0.82, top = h * 0.22, b = h * 0.78
        let corners = [CGPoint(x: l, y: top), CGPoint(x: r, y: top), CGPoint(x: r, y: b), CGPoint(x: l, y: b), CGPoint(x: l, y: top)]
        var wobbly: [CGPoint] = []
        var clean: [CGPoint] = []
        for s in 0..<4 {
          let a = corners[s], z = corners[s + 1]
          let dx = z.x - a.x, dy = z.y - a.y
          let len = hypot(dx, dy)
          for k in 0..<24 {
            let f = CGFloat(k) / 24
            let wob = sin(f * .pi * 3 + CGFloat(s)) * 5 * sin(f * .pi)
            wobbly.append(CGPoint(x: a.x + dx * f - dy / len * wob, y: a.y + dy * f + dx / len * wob))
            clean.append(CGPoint(x: a.x + dx * f, y: a.y + dy * f))
          }
        }
        wobbly.append(CGPoint(x: l + 4, y: top + 3))
        clean.append(corners[0])
        let draw = ease(phase(t, 0, 0.4))
        let hold = phase(t, 0.42, 0.6)
        let snap = ease(phase(t, 0.6, 0.7))
        let pts = wobbly.indices.map { i in
          CGPoint(x: wobbly[i].x + (clean[i].x - wobbly[i].x) * snap, y: wobbly[i].y + (clean[i].y - wobbly[i].y) * snap)
        }
        ink(ctx, partial(pts, draw), c.ink, 3)
        if hold > 0 && snap < 1, let tip = wobbly.last {
          var arc = Path()
          arc.addArc(center: tip, radius: 14, startAngle: .degrees(-90), endAngle: .degrees(-90 + 360 * hold), clockwise: false)
          ctx.stroke(arc, with: .color(c.accent), style: StrokeStyle(lineWidth: 3, lineCap: .round))
        }
        if snap >= 1 {
          for p in [CGPoint(x: (l + r) / 2, y: top), CGPoint(x: r, y: (top + b) / 2), CGPoint(x: (l + r) / 2, y: b), CGPoint(x: l, y: (top + b) / 2)] {
            let dot = Path(ellipseIn: CGRect(x: p.x - 5, y: p.y - 5, width: 10, height: 10))
            ctx.fill(dot, with: .color(.white))
            ctx.stroke(dot, with: .color(c.accent), lineWidth: 1.6)
          }
        }
      }
    }
  }
}

private struct LassoPicture: View {
  @Environment(\.tali) private var c
  var body: some View {
    Loop(seconds: 4.2, still: 0.7) { t in
      Canvas { ctx, size in
        let w = size.width, h = size.height
        let cx = w * 0.36 + ease(phase(t, 0.55, 0.8)) * w * 0.22
        let cy = h * 0.5
        var tri = Path()
        tri.move(to: CGPoint(x: cx - 22, y: cy + 16))
        tri.addLine(to: CGPoint(x: cx, y: cy - 20))
        tri.addLine(to: CGPoint(x: cx + 22, y: cy + 16))
        tri.closeSubpath()
        ink(ctx, tri, c.ink, 2.6)
        line(ctx, CGPoint(x: cx - 34, y: cy + 16), CGPoint(x: cx + 34, y: cy + 16), c.ink, 2.6, round: true)
        let loop = (0..<60).map { k -> CGPoint in
          let a = -CGFloat.pi / 2 + CGFloat(k) / 59 * .pi * 2.1
          return CGPoint(x: cx + cos(a) * 58, y: cy + sin(a) * 46)
        }
        if t < 0.92 {
          ctx.stroke(
            partial(loop, ease(phase(t, 0.05, 0.45))), with: .color(c.accent), style: StrokeStyle(lineWidth: 2, lineCap: .round, dash: [6, 6]))
        }
        let paste = phase(t, 0.82, 0.88)
        if paste > 0 {
          let p = CGPoint(x: w * 0.2, y: h * 0.18)
          ctx.fill(Path(roundedRect: CGRect(x: p.x - 28, y: p.y - 12, width: 56, height: 24), cornerRadius: 12), with: .color(c.accent.opacity(paste)))
        }
      }
    }
  }
}
