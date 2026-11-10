import SwiftUI
import TaliCore

/// Draws the built-in papers the way Android's `canvas/PaperRenderer.kt` does: patterns in world
/// units anchored at the canvas origin, lines in world widths (never thinner than 0.75 px on screen),
/// faded out as they get too close together.
enum PaperPainter {
  static let mm: CGFloat = 160 / 25.4
  static let darkPaper = Color(argb: 0xFF1C_1A23)

  struct Tones {
    var paper: Color
    var line: Color
    var blueLine: Color
    var minor: Color
    var major: Color
    var margin: Color

    static func of(dark: Bool) -> Tones {
      dark
        ? Tones(
          paper: darkPaper, line: Color(argb: 0xFF5E_5C66), blueLine: Color(argb: 0xFF40_3E48), minor: Color(argb: 0xFF2A_2931),
          major: Color(argb: 0xFF4A_4852), margin: Color(argb: 0x99E0_7A90))
        : Tones(
          paper: .white, line: Color(argb: 0xFFC4_C4C4), blueLine: Color(argb: 0xFFDA_DADA), minor: Color(argb: 0xFFED_EDED),
          major: Color(argb: 0xFFCF_CFCF), margin: Color(argb: 0xFFF0_A0B4))
    }
  }

  /// Paints [page] (world units) onto [ctx], where world → screen is `(p - origin) * scale`.
  static func draw(
    _ style: PaperStyle, page: CGRect, in ctx: GraphicsContext, origin: CGPoint, scale: CGFloat, dark: Bool, weight: CGFloat = 1
  ) {
    let t = Tones.of(dark: dark)
    func sx(_ x: CGFloat) -> CGFloat { (x - origin.x) * scale }
    func sy(_ y: CGFloat) -> CGFloat { (y - origin.y) * scale }
    let screen = CGRect(x: sx(page.minX), y: sy(page.minY), width: page.width * scale, height: page.height * scale)
    ctx.fill(Path(screen), with: .color(t.paper))
    var c = ctx
    c.clip(to: Path(screen))
    func px(_ w: CGFloat) -> CGFloat { max(w * scale, 0.75) }
    func fade(_ step: CGFloat, from: CGFloat) -> Double { Double(min(max((step - from) / 10, 0), 1)) }

    func grid(_ spacing: CGFloat, _ color: Color, _ width: CGFloat, horizontalOnly: Bool) {
      let step = spacing * scale
      let a = fade(step, from: 5)
      guard a > 0 else { return }
      var p = Path()
      var y = (page.minY / spacing).rounded(.up) * spacing
      while y <= page.maxY {
        p.move(to: CGPoint(x: screen.minX, y: sy(y)))
        p.addLine(to: CGPoint(x: screen.maxX, y: sy(y)))
        y += spacing
      }
      if !horizontalOnly {
        var x = (page.minX / spacing).rounded(.up) * spacing
        while x <= page.maxX {
          p.move(to: CGPoint(x: sx(x), y: screen.minY))
          p.addLine(to: CGPoint(x: sx(x), y: screen.maxY))
          x += spacing
        }
      }
      c.stroke(p, with: .color(color.opacity(a)), lineWidth: px(width * weight))
    }

    func dots(_ spacing: CGFloat, _ color: Color) {
      let step = spacing * scale
      let a = fade(step, from: 5)
      guard a > 0 else { return }
      let r = max(1.3 / 0.45 * scale, 0.75) / 2 * weight
      var p = Path()
      var y = (page.minY / spacing).rounded(.up) * spacing
      while y <= page.maxY {
        var x = (page.minX / spacing).rounded(.up) * spacing
        while x <= page.maxX {
          p.addEllipse(in: CGRect(x: sx(x) - r, y: sy(y) - r, width: r * 2, height: r * 2))
          x += spacing
        }
        y += spacing
      }
      c.fill(p, with: .color(color.opacity(a)))
    }

    func isometric(_ spacing: CGFloat, _ color: Color, _ width: CGFloat) {
      let step = spacing * scale
      let a = fade(step, from: 7)
      guard a > 0 else { return }
      var p = Path()
      // Upright lines every `spacing`, and lines at 30° either way through the same lattice.
      let dx = spacing
      var x = (page.minX / dx).rounded(.down) * dx
      while x <= page.maxX {
        p.move(to: CGPoint(x: sx(x), y: screen.minY))
        p.addLine(to: CGPoint(x: sx(x), y: screen.maxY))
        x += dx
      }
      let rise = tan(CGFloat.pi / 6) * page.width
      let dy = spacing * tan(CGFloat.pi / 6) * 2
      var y0 = ((page.minY - rise) / dy).rounded(.down) * dy
      while y0 <= page.maxY + rise {
        p.move(to: CGPoint(x: sx(page.minX), y: sy(y0)))
        p.addLine(to: CGPoint(x: sx(page.maxX), y: sy(y0 + rise)))
        p.move(to: CGPoint(x: sx(page.minX), y: sy(y0)))
        p.addLine(to: CGPoint(x: sx(page.maxX), y: sy(y0 - rise)))
        y0 += dy
      }
      c.stroke(p, with: .color(color.opacity(a)), lineWidth: px(width * weight))
    }

    func laidOut(cornell: Bool) {
      let spacing = 8 * mm
      let a = fade(spacing * scale, from: 5)
      let header = page.minY + 28 * mm
      let linesEnd = cornell ? page.maxY - 50 * mm : page.maxY - 12 * mm
      if a > 0 {
        var p = Path()
        var y = header + spacing
        while y <= linesEnd - spacing * 0.5 {
          p.move(to: CGPoint(x: screen.minX, y: sy(y)))
          p.addLine(to: CGPoint(x: screen.maxX, y: sy(y)))
          y += spacing
        }
        c.stroke(p, with: .color(t.blueLine.opacity(a)), lineWidth: px(1.2 * weight))
      }
      var s = Path()
      s.move(to: CGPoint(x: screen.minX, y: sy(header)))
      s.addLine(to: CGPoint(x: screen.maxX, y: sy(header)))
      if cornell {
        s.move(to: CGPoint(x: sx(page.minX + 60 * mm), y: sy(header)))
        s.addLine(to: CGPoint(x: sx(page.minX + 60 * mm), y: sy(linesEnd)))
        s.move(to: CGPoint(x: screen.minX, y: sy(linesEnd)))
        s.addLine(to: CGPoint(x: screen.maxX, y: sy(linesEnd)))
        c.stroke(s, with: .color(t.major), lineWidth: px(1.6 * weight))
      } else {
        c.stroke(s, with: .color(t.major), lineWidth: px(1.6 * weight))
        var m = Path()
        m.move(to: CGPoint(x: sx(page.minX + 25 * mm), y: screen.minY))
        m.addLine(to: CGPoint(x: sx(page.minX + 25 * mm), y: screen.maxY))
        c.stroke(m, with: .color(t.margin), lineWidth: px(1.6 * weight))
      }
    }

    switch style {
    case .BLANK: break
    case .DOTS: dots(5 * mm, t.line)
    case .GRID: grid(5 * mm, t.blueLine, 1, horizontalOnly: false)
    case .LINES: grid(8 * mm, t.blueLine, 1.2, horizontalOnly: true)
    case .ENGINEERING:
      grid(2 * mm, t.minor, 0.8, horizontalOnly: false)
      grid(10 * mm, t.major, 1.3, horizontalOnly: false)
    case .ISOMETRIC: isometric(6 * mm, t.blueLine, 1)
    case .CORNELL: laidOut(cornell: true)
    case .RULED: laidOut(cornell: false)
    }
  }
}

/// The top of a notebook's first page, for library cards and paper tiles.
struct PaperPreview: View {
  var style: PaperStyle
  var landscape = false
  var dark = false
  /// How much of the page's width shows (1 = the whole width).
  var zoom: CGFloat = 1

  var body: some View {
    Canvas { ctx, size in
      let page = Pages.of(landscape: landscape)
      let scale = size.width / CGFloat(page.width) * zoom
      PaperPainter.draw(
        style, page: CGRect(x: 0, y: 0, width: CGFloat(page.width), height: CGFloat(page.height)), in: ctx, origin: .zero, scale: scale, dark: dark)
    }
  }
}
