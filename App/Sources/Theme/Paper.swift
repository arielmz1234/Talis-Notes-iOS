import SwiftUI
import TaliCore
import UIKit

/// Draws the built-in papers the way Android's `canvas/PaperRenderer.kt` does: patterns in world
/// units anchored at the canvas origin, lines in world widths (never thinner than 0.75 px on screen),
/// faded out as they get too close together. The drawing is a list of operations so SwiftUI
/// (library previews) and Core Graphics (the notebook's pages) share it.
enum PaperPainter {
  static let mm: CGFloat = 160 / 25.4
  static let darkPaper = UIColor(argb: Int32(bitPattern: 0xFF1C_1A23))

  struct Tones {
    var paper: UIColor
    var line: UIColor
    var blueLine: UIColor
    var minor: UIColor
    var major: UIColor
    var margin: UIColor

    static func of(dark: Bool) -> Tones {
      func c(_ v: UInt32) -> UIColor { UIColor(argb: Int32(bitPattern: v)) }
      return dark
        ? Tones(paper: darkPaper, line: c(0xFF5E_5C66), blueLine: c(0xFF40_3E48), minor: c(0xFF2A_2931), major: c(0xFF4A_4852), margin: c(0x99E0_7A90))
        : Tones(paper: .white, line: c(0xFFC4_C4C4), blueLine: c(0xFFDA_DADA), minor: c(0xFFED_EDED), major: c(0xFFCF_CFCF), margin: c(0xFFF0_A0B4))
    }
  }

  enum Op {
    case fill(CGPath, UIColor)
    case stroke(CGPath, UIColor, CGFloat)
  }

  /// What to draw for [page] (world units), where world → screen is `(p - origin) * scale`.
  static func ops(_ style: PaperStyle, page: CGRect, origin: CGPoint, scale: CGFloat, dark: Bool, weight: CGFloat = 1, print: Bool = false) -> [Op] {
    let t = Tones.of(dark: dark)
    func sx(_ x: CGFloat) -> CGFloat { (x - origin.x) * scale }
    func sy(_ y: CGFloat) -> CGFloat { (y - origin.y) * scale }
    let screen = CGRect(x: sx(page.minX), y: sy(page.minY), width: page.width * scale, height: page.height * scale)
    var out: [Op] = [.fill(CGPath(rect: screen, transform: nil), t.paper)]
    // A small preview is like print: every line shows, however close together.
    func px(_ w: CGFloat) -> CGFloat { max(w * scale, print ? 0.5 : 0.75) }
    func fade(_ step: CGFloat, from: CGFloat) -> CGFloat { print ? 1 : min(max((step - from) / 10, 0), 1) }
    func faded(_ c: UIColor, _ a: CGFloat) -> UIColor { c.withAlphaComponent(c.cgColor.alpha * a) }

    func grid(_ spacing: CGFloat, _ color: UIColor, _ width: CGFloat, horizontalOnly: Bool) {
      let a = fade(spacing * scale, from: 5)
      guard a > 0 else { return }
      let p = CGMutablePath()
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
      out.append(.stroke(p, faded(color, a), px(width * weight)))
    }

    func dots(_ spacing: CGFloat, _ color: UIColor) {
      let a = fade(spacing * scale, from: 5)
      guard a > 0 else { return }
      let r = max(1.3 / 0.45 * scale, print ? 1.1 : 0.75) / 2 * weight
      let p = CGMutablePath()
      var y = (page.minY / spacing).rounded(.up) * spacing
      while y <= page.maxY {
        var x = (page.minX / spacing).rounded(.up) * spacing
        while x <= page.maxX {
          p.addEllipse(in: CGRect(x: sx(x) - r, y: sy(y) - r, width: r * 2, height: r * 2))
          x += spacing
        }
        y += spacing
      }
      out.append(.fill(p, faded(color, a)))
    }

    func isometric(_ spacing: CGFloat, _ color: UIColor, _ width: CGFloat) {
      let a = fade(spacing * scale, from: 7)
      guard a > 0 else { return }
      let p = CGMutablePath()
      var x = (page.minX / spacing).rounded(.down) * spacing
      while x <= page.maxX {
        p.move(to: CGPoint(x: sx(x), y: screen.minY))
        p.addLine(to: CGPoint(x: sx(x), y: screen.maxY))
        x += spacing
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
      out.append(.stroke(p, faded(color, a), px(width * weight)))
    }

    func laidOut(cornell: Bool) {
      let spacing = 8 * mm
      let a = fade(spacing * scale, from: 5)
      let header = page.minY + 28 * mm
      let linesEnd = cornell ? page.maxY - 50 * mm : page.maxY - 12 * mm
      if a > 0 {
        let p = CGMutablePath()
        var y = header + spacing
        while y <= linesEnd - spacing * 0.5 {
          p.move(to: CGPoint(x: screen.minX, y: sy(y)))
          p.addLine(to: CGPoint(x: screen.maxX, y: sy(y)))
          y += spacing
        }
        out.append(.stroke(p, faded(t.blueLine, a), px(1.2 * weight)))
      }
      let s = CGMutablePath()
      s.move(to: CGPoint(x: screen.minX, y: sy(header)))
      s.addLine(to: CGPoint(x: screen.maxX, y: sy(header)))
      if cornell {
        s.move(to: CGPoint(x: sx(page.minX + 60 * mm), y: sy(header)))
        s.addLine(to: CGPoint(x: sx(page.minX + 60 * mm), y: sy(linesEnd)))
        s.move(to: CGPoint(x: screen.minX, y: sy(linesEnd)))
        s.addLine(to: CGPoint(x: screen.maxX, y: sy(linesEnd)))
      }
      out.append(.stroke(s, t.major, px(1.6 * weight)))
      if !cornell {
        let m = CGMutablePath()
        m.move(to: CGPoint(x: sx(page.minX + 25 * mm), y: screen.minY))
        m.addLine(to: CGPoint(x: sx(page.minX + 25 * mm), y: screen.maxY))
        out.append(.stroke(m, t.margin, px(1.6 * weight)))
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
    return out
  }

  /// Paints into a SwiftUI canvas.
  static func draw(
    _ style: PaperStyle, page: CGRect, in ctx: GraphicsContext, origin: CGPoint, scale: CGFloat, dark: Bool, weight: CGFloat = 1, print: Bool = false
  ) {
    var c = ctx
    let screen = CGRect(x: (page.minX - origin.x) * scale, y: (page.minY - origin.y) * scale, width: page.width * scale, height: page.height * scale)
    c.clip(to: Path(screen))
    for op in ops(style, page: page, origin: origin, scale: scale, dark: dark, weight: weight, print: print) {
      switch op {
      case .fill(let p, let color): c.fill(Path(p), with: .color(Color(uiColor: color)))
      case .stroke(let p, let color, let w): c.stroke(Path(p), with: .color(Color(uiColor: color)), lineWidth: w)
      }
    }
  }

  /// Paints into Core Graphics (world units already mapped by the context's transform at [scale]).
  static func draw(_ style: PaperStyle, page: CGRect, in cg: CGContext, scale: CGFloat, dark: Bool, weight: CGFloat = 1) {
    cg.saveGState()
    cg.clip(to: page)
    // Ops are in screen units at `scale`; the context already scales world units, so undo that here.
    cg.translateBy(x: 0, y: 0)
    cg.scaleBy(x: 1 / scale, y: 1 / scale)
    for op in ops(style, page: page, origin: .zero, scale: scale, dark: dark, weight: weight) {
      switch op {
      case .fill(let p, let color):
        cg.addPath(p)
        cg.setFillColor(color.cgColor)
        cg.fillPath()
      case .stroke(let p, let color, let w):
        cg.addPath(p)
        cg.setStrokeColor(color.cgColor)
        cg.setLineWidth(w)
        cg.strokePath()
      }
    }
    cg.restoreGState()
  }
}

/// The top of a notebook's first page, for library cards and paper tiles: the page fills the box
/// (cut at the bottom or sides), [zoom] times closer.
struct PaperPreview: View {
  var style: PaperStyle
  var landscape = false
  var dark = false
  var zoom: CGFloat = 1

  var body: some View {
    Canvas { ctx, size in
      let page = Pages.of(landscape: landscape)
      let pw = CGFloat(page.width), ph = CGFloat(page.height)
      let scale = max(size.width / pw, size.height / ph) * zoom
      PaperPainter.draw(style, page: CGRect(x: 0, y: 0, width: pw, height: ph), in: ctx, origin: .zero, scale: scale, dark: dark, print: true)
    }
  }
}
