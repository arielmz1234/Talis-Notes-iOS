import SwiftUI

/// Settings › Tips and tricks (Android's `FeaturesCard`): the smaller things the app can do, each
/// with how to use it or turn it on, in the same card as the first-run tour. Android's Circle to
/// select tip is left out (the app has no Circle to select), and its S Pen tip is Apple Pencil's.
struct FeaturesCard: View {
  var onDone: () -> Void
  var body: some View {
    StepsCard(
      steps: [
        TourStep(title: L("feat_paste_title"), body: L("feat_paste_body_ios"), picture: AnyView(PastePicture())),
        TourStep(title: L("feat_box_title"), body: L("feat_box_body"), picture: AnyView(BoxPicture())),
        TourStep(title: L("feat_pencil_title"), body: L("feat_pencil_body"), picture: AnyView(DoubleTapPicture())),
        TourStep(title: L("feat_fingers_title"), body: L("feat_fingers_body"), picture: AnyView(FingersPicture())),
        TourStep(title: L("feat_tidy_title"), body: L("feat_tidy_body"), picture: AnyView(AnglePicture())),
        TourStep(title: L("feat_dots_title"), body: L("feat_dots_body"), picture: AnyView(RadiusPicture())),
        TourStep(title: L("feat_fill_title"), body: L("feat_fill_body"), picture: AnyView(FillShapePicture())),
        TourStep(title: L("feat_shot_title"), body: L("feat_shot_body"), picture: AnyView(ShotPicture())),
        TourStep(title: L("feat_lock_title"), body: L("feat_lock_body"), picture: AnyView(LockPicture())),
        TourStep(title: L("feat_laser_title"), body: L("feat_laser_body"), picture: AnyView(LaserPicture())),
        TourStep(title: L("feat_pages_title"), body: L("feat_pages_body"), picture: AnyView(PagesPicture())),
        TourStep(title: L("feat_quick_title"), body: L("feat_quick_body"), picture: AnyView(QuickOpenPicture())),
        TourStep(title: L("feat_room_title"), body: L("feat_room_body"), picture: AnyView(RoomPicture())),
        TourStep(title: L("feat_star_title"), body: L("feat_star_body"), picture: AnyView(StarNotebookPicture())),
        TourStep(title: L("feat_colours_title"), body: L("feat_colours_body"), picture: AnyView(ColoursPicture())),
      ], finish: L("done"), heading: L("tips_and_tricks"), onDone: onDone)
  }
}

private let blue = Color(argb: 0xFF2F_6FE0)
private let red = Color(argb: 0xFFE5_484D)

/// A short word in a pill, as the app's badges and bubbles look.
private func pill(_ ctx: GraphicsContext, _ text: String, at: CGPoint, _ bg: Color, alpha: Double = 1) {
  let word = ctx.resolve(Text(text).font(.system(size: 12, weight: .bold)).foregroundStyle(Color.white.opacity(alpha)))
  let size = word.measure(in: CGSize(width: 400, height: 40))
  let w = size.width + 18, h: CGFloat = 24
  ctx.fill(Path(roundedRect: CGRect(x: at.x - w / 2, y: at.y - h / 2, width: w, height: h), cornerRadius: h / 2), with: .color(bg.opacity(alpha)))
  ctx.draw(word, at: at)
}

/// A fingertip: a soft round touch.
private func finger(_ ctx: GraphicsContext, _ at: CGPoint, _ c: TaliColors) {
  ctx.fill(circle(at, 17), with: .color(c.accent.opacity(0.18)))
  ctx.stroke(circle(at, 17), with: .color(c.accent.opacity(0.55)), lineWidth: 1.5)
}

/// A ring filling round [at] while something is held, [part] (0..1) of the way.
private func holdRing(_ ctx: GraphicsContext, _ at: CGPoint, _ part: Double, _ c: TaliColors) {
  var arc = Path()
  arc.addArc(center: at, radius: 21, startAngle: .degrees(-90), endAngle: .degrees(-90 + 360 * part), clockwise: false)
  ctx.stroke(arc, with: .color(c.accent), style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
}

private func dashedRect(_ ctx: GraphicsContext, _ r: CGRect, _ c: TaliColors) {
  ctx.stroke(Path(r), with: .color(c.accent), style: StrokeStyle(lineWidth: 1.6, dash: [5, 4]))
}

private func triangle(_ ctx: GraphicsContext, _ cx: CGFloat, _ cy: CGFloat, _ s: CGFloat, _ color: Color, _ width: CGFloat = 2.6) {
  var p = Path()
  p.move(to: CGPoint(x: cx - s, y: cy + s * 0.75))
  p.addLine(to: CGPoint(x: cx, y: cy - s * 0.85))
  p.addLine(to: CGPoint(x: cx + s, y: cy + s * 0.75))
  p.closeSubpath()
  ink(ctx, p, color, width)
}

/// A padlock, closed or with its shackle lifted by [open] (0..1).
private func padlock(_ ctx: GraphicsContext, _ at: CGPoint, _ c: TaliColors, open: Double) {
  ctx.fill(Path(roundedRect: CGRect(x: at.x - 16, y: at.y - 16, width: 32, height: 32), cornerRadius: 10), with: .color(.white))
  ctx.fill(Path(roundedRect: CGRect(x: at.x - 8, y: at.y - 2, width: 16, height: 12), cornerRadius: 2.5), with: .color(c.accent))
  let lift = 4 * open
  var shackle = Path()
  shackle.move(to: CGPoint(x: at.x - 5, y: at.y - 2 - lift))
  shackle.addLine(to: CGPoint(x: at.x - 5, y: at.y - 6 - lift))
  shackle.addCurve(
    to: CGPoint(x: at.x + 5, y: at.y - 6 - lift), control1: CGPoint(x: at.x - 5, y: at.y - 12 - lift), control2: CGPoint(x: at.x + 5, y: at.y - 12 - lift))
  shackle.addLine(to: CGPoint(x: at.x + 5, y: at.y - 2 - (open > 0.5 ? 4 + lift : 0)))
  ctx.stroke(shackle, with: .color(c.accent), style: StrokeStyle(lineWidth: 2.4, lineCap: .round))
}

private func card(_ ctx: GraphicsContext, _ r: CGRect, _ corner: CGFloat, _ edge: Color) {
  ctx.fill(Path(roundedRect: r, cornerRadius: corner), with: .color(.white))
  ctx.stroke(Path(roundedRect: r, cornerRadius: corner), with: .color(edge), lineWidth: 1)
}

private struct PastePicture: View {
  @Environment(\.tali) private var c
  var body: some View {
    Loop(seconds: 3.8, still: 0.75) { t in
      Canvas { ctx, size in
        let w = size.width, h = size.height
        triangle(ctx, w * 0.25, h * 0.38, 22, c.ink)
        let spot = CGPoint(x: w * 0.68, y: h * 0.62)
        let bubble = ease(phase(t, 0.4, 0.48))
        let landed = ease(phase(t, 0.58, 0.7))
        if t > 0.08 && t < 0.58 {
          finger(ctx, spot, c)
          holdRing(ctx, spot, phase(t, 0.1, 0.4), c)
        }
        if bubble > 0 && t < 0.6 { pill(ctx, L("paste"), at: CGPoint(x: spot.x, y: spot.y - 46 + 6 * bubble), c.accent, alpha: bubble) }
        if landed > 0 { triangle(ctx, spot.x, spot.y, 22 * (0.9 + 0.1 * landed), c.ink.opacity(landed)) }
      }
    }
  }
}

private struct BoxPicture: View {
  @Environment(\.tali) private var c
  var body: some View {
    Loop(seconds: 3.6, still: 0.9) { t in
      Canvas { ctx, size in
        let w = size.width, h = size.height
        ink(ctx, partial(cursive(w * 0.3, w * 0.7, h * 0.62, 12, seed: 1), 1), c.ink, 2.4)
        let l = w * 0.24, r = w * 0.76, top = h * 0.42, b = h * 0.74
        dashedRect(ctx, CGRect(x: l, y: top, width: r - l, height: b - top), c)
        let menuY = h * 0.22
        let menu = Path(roundedRect: CGRect(x: w * 0.3, y: menuY - 16, width: w * 0.4, height: 32), cornerRadius: 14)
        ctx.fill(menu, with: .color(c.surface))
        ctx.stroke(menu, with: .color(c.line), lineWidth: 1)
        let btn = CGPoint(x: w * 0.56, y: menuY)
        if t >= 0.25 && t <= 0.38 { ctx.fill(circle(btn, 14), with: .color(c.accentSoft)) }
        ctx.stroke(Path(CGRect(x: btn.x - 6, y: btn.y - 6, width: 12, height: 12)), with: .color(c.ink), lineWidth: 1.8)
        for x in [w * 0.38, w * 0.47, w * 0.65] { ctx.fill(circle(CGPoint(x: x, y: menuY), 2.5), with: .color(c.inkFaint)) }
        let box = ease(phase(t, 0.4, 0.65))
        let g: CGFloat = 5
        let outline = [CGPoint(x: l + g, y: top + g), CGPoint(x: r - g, y: top + g), CGPoint(x: r - g, y: b - g), CGPoint(x: l + g, y: b - g), CGPoint(x: l + g, y: top + g)]
        if box > 0 { ink(ctx, partial(outline, box), blue, 2.6) }
      }
    }
  }
}

/// Android's starred pens and S Pen button, as Apple Pencil's double-tap: each one hops between
/// the pen and the eraser.
private struct DoubleTapPicture: View {
  @Environment(\.tali) private var c
  var body: some View {
    Loop(seconds: 3.6, still: 0.7) { t in
      Canvas { ctx, size in
        let w = size.width, h = size.height
        let erasing = t >= 0.5
        let top = h * 0.14
        for (i, x) in [w * 0.32, w * 0.68].enumerated() {
          if (i == 1) == erasing {
            ctx.fill(Path(roundedRect: CGRect(x: x - 18, y: top - 8, width: 36, height: 92), cornerRadius: 12), with: .color(c.accentSoft))
          }
          if i == 0 {
            card(ctx, CGRect(x: x - 8, y: top + 12, width: 16, height: 64), 4, c.line)
            ctx.fill(Path(CGRect(x: x - 8, y: top + 40, width: 16, height: 6)), with: .color(c.ink))
            var tip = Path()
            tip.move(to: CGPoint(x: x - 6, y: top + 12))
            tip.addLine(to: CGPoint(x: x, y: top))
            tip.addLine(to: CGPoint(x: x + 6, y: top + 12))
            tip.closeSubpath()
            ctx.fill(tip, with: .color(c.ink))
          } else {
            card(ctx, CGRect(x: x - 9, y: top + 18, width: 18, height: 58), 4, c.line)
            ctx.fill(Path(roundedRect: CGRect(x: x - 9, y: top + 4, width: 18, height: 18), cornerRadius: 5), with: .color(Color(argb: 0xFFF4_A7B9)))
          }
        }
        let tapped = t < 0.5 ? phase(t, 0.36, 0.48) : phase(t, 0.86, 0.98)
        pencil(ctx, c, y: h * 0.86, l: w * 0.16, r: w * 0.74, tapped: tapped)
      }
    }
  }
}

private struct FingersPicture: View {
  @Environment(\.tali) private var c
  var body: some View {
    Loop(seconds: 4.4, still: 0.9) { t in
      Canvas { ctx, size in
        let w = size.width, h = size.height
        ruledPage(ctx, size, c)
        let pts = cursive(w * 0.12, w * 0.88, h * 0.4, 13, seed: 3)
        if !(t >= 0.35 && t <= 0.72) { ink(ctx, partial(pts, t > 0.72 ? 1 : ease(phase(t, 0, 0.25))), c.ink, 2.4) }
        let y = h * 0.74
        if t >= 0.28 && t <= 0.4 { for x in [w * 0.42, w * 0.58] { finger(ctx, CGPoint(x: x, y: y), c) } }
        if t >= 0.66 && t <= 0.78 { for x in [w * 0.34, w * 0.5, w * 0.66] { finger(ctx, CGPoint(x: x, y: y), c) } }
      }
    }
  }
}

private struct AnglePicture: View {
  @Environment(\.tali) private var c
  var body: some View {
    Loop(seconds: 4, still: 0.8) { t in
      Canvas { ctx, size in
        let w = size.width, h = size.height
        let o = CGPoint(x: w * 0.3, y: h * 0.7)
        let len = w * 0.5
        let raw = ease(phase(t, 0.05, 0.5)) * 60
        let deg = (raw >= 38 && raw <= 52) || t > 0.5 ? 45 : raw
        let a = -deg * .pi / 180
        let end = CGPoint(x: o.x + cos(a) * len, y: o.y + sin(a) * len)
        var level = Path()
        level.move(to: o)
        level.addLine(to: CGPoint(x: o.x + len, y: o.y))
        ctx.stroke(level, with: .color(c.line), style: StrokeStyle(lineWidth: 1.5, dash: [4, 4]))
        line(ctx, o, end, c.ink, 3, round: true)
        handle(ctx, o, c)
        handle(ctx, end, c)
        pill(ctx, "\(Int(deg.rounded()))°", at: CGPoint(x: w * 0.5, y: h * 0.2), deg == 45 ? c.accent : c.inkMuted)
      }
    }
  }
}

private struct RadiusPicture: View {
  @Environment(\.tali) private var c
  var body: some View {
    Loop(seconds: 3.6, still: 0.5) { t in
      Canvas { ctx, size in
        let w = size.width, h = size.height
        let o = CGPoint(x: w * 0.42, y: h * 0.55)
        let grow = t < 0.5 ? ease(phase(t, 0.1, 0.45)) : 1 - ease(phase(t, 0.6, 0.95))
        let r = h * (0.2 + 0.14 * grow)
        ctx.stroke(circle(o, r), with: .color(c.ink), lineWidth: 2.6)
        let end = CGPoint(x: o.x + r, y: o.y)
        var radius = Path()
        radius.move(to: o)
        radius.addLine(to: end)
        ctx.stroke(radius, with: .color(c.accent), style: StrokeStyle(lineWidth: 2, lineCap: .round, dash: [0.1, 5]))
        ctx.fill(circle(o, 3), with: .color(c.accent))
        handle(ctx, end, c)
        pill(ctx, "r " + String(format: "%.1f", 2 + 1.4 * grow) + " cm", at: CGPoint(x: o.x + r / 2, y: o.y - 20), c.accent)
      }
    }
  }
}

private struct FillShapePicture: View {
  @Environment(\.tali) private var c
  var body: some View {
    Loop(seconds: 3.4, still: 0.9) { t in
      Canvas { ctx, size in
        let w = size.width, h = size.height
        var blob = Path()
        for k in 0...48 {
          let a = CGFloat(k) / 48 * 2 * .pi
          let rr = 1 + 0.12 * sin(a * 3) + 0.06 * cos(a * 5)
          let p = CGPoint(x: w * 0.5 + cos(a) * w * 0.3 * rr, y: h * 0.5 + sin(a) * h * 0.3 * rr)
          if k == 0 { blob.move(to: p) } else { blob.addLine(to: p) }
        }
        blob.closeSubpath()
        let tap = CGPoint(x: w * 0.45, y: h * 0.52)
        let spread = ease(phase(t, 0.25, 0.6))
        if spread > 0 {
          var inside = ctx
          inside.clip(to: blob)
          inside.fill(circle(tap, w * 0.6 * spread), with: .color(Color(argb: 0xFF8B_C4F0)))
        }
        ink(ctx, blob, c.ink, 2.6)
        if t >= 0.15 && t <= 0.3 { finger(ctx, tap, c) }
      }
    }
  }
}

private struct ShotPicture: View {
  @Environment(\.tali) private var c
  var body: some View {
    Loop(seconds: 4, still: 0.8) { t in
      Canvas { ctx, size in
        let w = size.width, h = size.height
        ruledPage(ctx, size, c)
        triangle(ctx, w * 0.3, h * 0.42, 18, c.ink)
        ink(ctx, partial(cursive(w * 0.48, w * 0.85, h * 0.48, 10, seed: 4), 1), blue, 2.2)
        let drawn = ease(phase(t, 0.05, 0.35))
        let l = w * 0.14, r = w * 0.9, top = h * 0.24, b = h * 0.62
        if t < 0.45 { dashedRect(ctx, CGRect(x: l, y: top, width: (r - l) * drawn, height: (b - top) * drawn), c) }
        if t >= 0.45 && t <= 0.55 {
          ctx.fill(Path(CGRect(x: l, y: top, width: r - l, height: b - top)), with: .color(.white.opacity((1 - phase(t, 0.45, 0.55)) * 0.9)))
        }
        let slide = ease(phase(t, 0.55, 0.7))
        if slide > 0 {
          let y = h - h * 0.42 * slide
          card(ctx, CGRect(x: w * 0.22, y: y, width: w * 0.56, height: h * 0.36), 10, c.line)
          triangle(ctx, w * 0.36, y + h * 0.16, 10, c.ink, 1.8)
          ink(ctx, partial(cursive(w * 0.46, w * 0.72, y + h * 0.2, 6, seed: 4), 1), blue, 1.6)
        }
      }
    }
  }
}

private struct LockPicture: View {
  @Environment(\.tali) private var c
  var body: some View {
    Loop(seconds: 4.2, still: 0.5) { t in
      Canvas { ctx, size in
        let w = size.width, h = size.height
        ctx.stroke(Path(roundedRect: CGRect(x: w * 0.25, y: h * 0.35, width: w * 0.5, height: h * 0.4), cornerRadius: 4), with: .color(c.ink), lineWidth: 2.6)
        let lock = CGPoint(x: w * 0.5, y: h * 0.2)
        padlock(ctx, lock, c, open: ease(phase(t, 0.65, 0.75)))
        if t >= 0.25 && t <= 0.68 {
          finger(ctx, CGPoint(x: w * 0.5, y: h * 0.6), c)
          holdRing(ctx, lock, phase(t, 0.3, 0.65), c)
        }
      }
    }
  }
}

private struct LaserPicture: View {
  @Environment(\.tali) private var c
  var body: some View {
    Loop(seconds: 3.6, still: 0.5) { t in
      Canvas { ctx, size in
        let w = size.width, h = size.height
        ruledPage(ctx, size, c)
        let pts = (0..<60).map { k -> CGPoint in
          let a = CGFloat(k) / 59 * 2.2 * .pi
          return CGPoint(x: w * 0.5 + cos(a) * w * 0.28 * (1 - CGFloat(k) / 200), y: h * 0.5 + sin(a) * h * 0.22)
        }
        let fade = 1 - phase(t, 0.62, 0.85)
        if fade > 0 {
          let p = partial(pts, ease(phase(t, 0, 0.4)))
          ctx.stroke(p, with: .color(red.opacity(0.25 * fade)), style: StrokeStyle(lineWidth: 12 * fade, lineCap: .round))
          ctx.stroke(p, with: .color(Color(argb: 0xFFFF_B3B5).opacity(fade)), style: StrokeStyle(lineWidth: 2.5 * fade + 0.5, lineCap: .round))
        }
      }
    }
  }
}

private struct PagesPicture: View {
  @Environment(\.tali) private var c
  var body: some View {
    Loop(seconds: 4, still: 0.65) { t in
      Canvas { ctx, size in
        let w = size.width, h = size.height
        let pw = w * 0.2, ph = h * 0.36
        func slot(_ i: Int) -> CGPoint { CGPoint(x: w * 0.12 + CGFloat(i % 3) * w * 0.28, y: h * 0.08 + CGFloat(i / 3) * h * 0.48) }
        func page(_ at: CGPoint, _ edge: Color, _ width: CGFloat) {
          let r = CGRect(origin: at, size: CGSize(width: pw, height: ph))
          ctx.fill(Path(roundedRect: r, cornerRadius: 5), with: .color(.white))
          ctx.stroke(Path(roundedRect: r, cornerRadius: 5), with: .color(edge), lineWidth: width)
        }
        let move = ease(phase(t, 0.2, 0.6))
        for p in 1...4 {
          let from = slot(p), to = slot(p - 1)
          let at = CGPoint(x: from.x + (to.x - from.x) * move, y: from.y + (to.y - from.y) * move)
          page(at, c.line, 1)
          for k in 1...3 {
            let y = at.y + ph * CGFloat(k) / 4
            line(ctx, CGPoint(x: at.x + 6, y: y), CGPoint(x: at.x + pw - 6, y: y), c.line, 1)
          }
        }
        let a = slot(0), z = slot(4)
        let lifted = t >= 0.1 && t <= 0.7
        let held = CGPoint(x: a.x + (z.x - a.x) * move, y: a.y + (z.y - a.y) * move - (lifted ? 6 : 0))
        page(held, c.accent, 2)
        ink(ctx, partial(cursive(held.x + 6, held.x + pw - 6, held.y + ph * 0.4, 5), 1), c.ink, 1.4)
        if lifted { finger(ctx, CGPoint(x: held.x + pw / 2, y: held.y + ph / 2), c) }
      }
    }
  }
}

private struct QuickOpenPicture: View {
  @Environment(\.tali) private var c
  var body: some View {
    Loop(seconds: 3.6, still: 0.7) { t in
      Canvas { ctx, size in
        let w = size.width, h = size.height
        let b = CGPoint(x: w * 0.18, y: h * 0.14)
        ctx.fill(circle(b, 16), with: .color(c.accentSoft))
        ctx.stroke(circle(b, 7), with: .color(c.accent), lineWidth: 1.8)
        line(ctx, b, CGPoint(x: b.x, y: b.y - 4), c.accent, 1.8, round: true)
        line(ctx, b, CGPoint(x: b.x + 3, y: b.y + 1), c.accent, 1.8, round: true)
        let spines = [Color(argb: 0xFF7C_5CE0), Color(argb: 0xFF2F_A37A), red, blue]
        for (i, col) in spines.enumerated() {
          let k = ease(phase(t, 0.08 + Double(i) * 0.07, 0.28 + Double(i) * 0.07)) * (1 - phase(t, 0.85, 0.95))
          guard k > 0 else { continue }
          let y = h * (0.3 + CGFloat(i) * 0.17) + 8 * (1 - k)
          ctx.fill(Path(roundedRect: CGRect(x: w * 0.12, y: y, width: w * 0.76, height: h * 0.14), cornerRadius: 8), with: .color(.white.opacity(k)))
          ctx.fill(Path(roundedRect: CGRect(x: w * 0.14, y: y + 4, width: 20, height: h * 0.14 - 8), cornerRadius: 3), with: .color(col.opacity(k)))
          line(ctx, CGPoint(x: w * 0.3, y: y + h * 0.07), CGPoint(x: w * (0.6 + 0.06 * CGFloat(i % 2)), y: y + h * 0.07), c.inkMuted.opacity(k), 3, round: true)
        }
        if t >= 0.5 && t <= 0.62 { finger(ctx, CGPoint(x: w * 0.5, y: h * 0.54), c) }
      }
    }
  }
}

private struct RoomPicture: View {
  @Environment(\.tali) private var c
  var body: some View {
    Loop(seconds: 3.8, still: 0.5) { t in
      Canvas { ctx, size in
        let w = size.width, h = size.height
        let hide = t < 0.5 ? ease(phase(t, 0.15, 0.35)) : 1 - ease(phase(t, 0.7, 0.9))
        ctx.fill(Path(roundedRect: CGRect(origin: .zero, size: size), cornerRadius: 12), with: .color(c.desk))
        let page = CGSize(width: w * (0.62 + 0.16 * hide), height: h * (0.7 + 0.22 * hide))
        let po = CGPoint(x: (w - page.width) / 2, y: h * (0.22 - 0.18 * hide))
        ctx.fill(Path(roundedRect: CGRect(origin: po, size: page), cornerRadius: 4), with: .color(.white))
        var y = po.y + 14
        while y < po.y + page.height {
          line(ctx, CGPoint(x: po.x + 6, y: y), CGPoint(x: po.x + page.width - 6, y: y), c.line, 1)
          y += 14
        }
        let barY = h * 0.08 - h * 0.2 * hide
        ctx.fill(Path(roundedRect: CGRect(x: w * 0.2, y: barY - 10, width: w * 0.6, height: 20), cornerRadius: 10), with: .color(c.surface))
        ctx.fill(Path(roundedRect: CGRect(x: w * 0.84, y: barY - 10, width: w * 0.12, height: 20), cornerRadius: 10), with: .color(c.surface))
        ctx.fill(Path(CGRect(x: 0, y: h - 6, width: w, height: 6)), with: .color(c.inkMuted.opacity(0.5 * (1 - hide))))
      }
    }
  }
}

private struct StarNotebookPicture: View {
  @Environment(\.tali) private var c
  var body: some View {
    Loop(seconds: 3.6, still: 0.8) { t in
      Canvas { ctx, size in
        let w = size.width, h = size.height
        let spines = [Color(argb: 0xFF7C_5CE0), Color(argb: 0xFF2F_A37A), blue]
        for (i, col) in spines.enumerated() {
          let x = w * (0.06 + CGFloat(i) * 0.32), y = h * 0.28
          card(ctx, CGRect(x: x, y: y, width: w * 0.26, height: h * 0.46), 8, c.line)
          ctx.fill(Path(roundedRect: CGRect(x: x, y: y, width: 8, height: h * 0.46), cornerRadius: 3), with: .color(col))
          for k in 1...3 {
            let ly = y + h * 0.46 * CGFloat(k) / 4
            line(ctx, CGPoint(x: x + 14, y: ly), CGPoint(x: x + w * 0.26 - 6, y: ly), c.line, 1)
          }
        }
        if t >= 0.1 && t <= 0.35 { finger(ctx, CGPoint(x: w * 0.51, y: h * 0.51), c) }
        let pop = ease(phase(t, 0.38, 0.5))
        if pop > 0 {
          let s = pop < 1 ? pop * 1.25 : 1
          star(ctx, CGPoint(x: w * 0.62, y: h * 0.7), 9 * s, 9 * s * 0.42, starGold)
        }
      }
    }
  }
}

private struct ColoursPicture: View {
  @Environment(\.tali) private var c
  var body: some View {
    Loop(seconds: 4.8, still: 0.3) { t in
      Canvas { ctx, size in
        let w = size.width, h = size.height
        let skies: [(Color, Color)] = [
          (Color(argb: 0xFFD9_CCF7), Color(argb: 0xFF8E_6CF0)), (Color(argb: 0xFFCF_E2F7), Color(argb: 0xFF3B_82D6)),
          (Color(argb: 0xFFD5_EADB), Color(argb: 0xFF2F_9E73)), (Color(argb: 0xFFFB_DCCB), Color(argb: 0xFFE0_7A5F)),
        ]
        let i = min(max(Int(t * 4), 0), 3)
        ctx.fill(Path(roundedRect: CGRect(x: w * 0.06, y: h * 0.06, width: w * 0.88, height: h * 0.48), cornerRadius: 14), with: .color(skies[i].0))
        let r = min(w, h) * 0.07
        for (o, rr) in [(CGPoint(x: w * 0.32, y: h * 0.3), r), (CGPoint(x: w * 0.42, y: h * 0.24), r * 1.3), (CGPoint(x: w * 0.53, y: h * 0.3), r)] {
          ctx.fill(circle(o, rr), with: .color(.white))
        }
        for (k, sky) in skies.enumerated() {
          let o = CGPoint(x: w * (0.2 + CGFloat(k) * 0.2), y: h * 0.76)
          ctx.fill(circle(o, 13), with: .color(sky.1))
          if k == i { ctx.stroke(circle(o, 18), with: .color(c.accent), lineWidth: 2.2) }
        }
      }
    }
  }
}
