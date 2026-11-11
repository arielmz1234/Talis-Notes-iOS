import SwiftUI
import TaliCore
import UIKit

/// Everything that decides how a notebook's paper looks.
struct PaperSpec: Equatable, Sendable {
  var style: PaperStyle
  var dark = false
  /// One of her own papers, drawn instead of [style].
  var custom: CustomPaper?
  /// Her colours for the built-in [style].
  var look: PaperLook?
  var weight: CGFloat = 1

  /// A picture paper's image, at a size that suits a page.
  var picture: CGImage? { custom?.image.flatMap { PaperPicture.image($0) } }
}

/// Draws the papers the way Android's `canvas/PaperRenderer.kt` does: patterns in world units, lines
/// in world widths (never thinner than 0.75 pt on screen), faded out as they get too close together,
/// each page's pattern starting at its own top edge. The drawing is a list of operations so SwiftUI
/// (previews) and Core Graphics (the notebook's pages, page pictures, PDF export) share it.
enum PaperPainter {
  static let mm: CGFloat = 160 / 25.4
  static var darkPaper: UIColor { color(PaperTones.darkPaper) }
  private static let dotWorld: CGFloat = 1.3 / 0.45

  static func color(_ argb: UInt32) -> UIColor { UIColor(argb: Int32(bitPattern: argb)) }

  enum Op {
    case fill(CGPath, UIColor)
    case stroke(CGPath, UIColor, CGFloat)
    /// A picture paper filling [CGRect] (screen units), its middle cropped to that shape.
    case picture(CGRect, alpha: CGFloat)
  }

  /// What to draw over [area] (world units; one page, or what's in view of an endless canvas), where
  /// world → screen is `(p - origin) * scale`. [print] draws every line however close (PDF, previews).
  static func ops(_ spec: PaperSpec, area: CGRect, endless: Bool = false, origin: CGPoint, scale: CGFloat, print: Bool = false) -> [Op] {
    func sx(_ x: CGFloat) -> CGFloat { (x - origin.x) * scale }
    func sy(_ y: CGFloat) -> CGFloat { (y - origin.y) * scale }
    func onScreen(_ r: CGRect) -> CGRect { CGRect(x: sx(r.minX), y: sy(r.minY), width: r.width * scale, height: r.height * scale) }
    let screen = onScreen(area)
    let anchorY = endless ? 0 : area.minY
    let k = spec.weight
    func px(_ world: CGFloat) -> CGFloat { print ? world * scale : max(world * scale, 0.75) }
    func fade(_ step: CGFloat, from: CGFloat) -> CGFloat { print ? 1 : min(max((step - from) / 10, 0), 1) }
    func faded(_ c: UInt32, _ a: CGFloat) -> UIColor { let u = color(c); return u.withAlphaComponent(u.cgColor.alpha * a) }
    /// The A4 pages the laid-out papers and pictures fill: the page itself, or the portrait A4 grid an endless canvas keeps.
    var pages: [CGRect] {
      guard endless else { return [area] }
      let w = CGFloat(A4.width), h = CGFloat(A4.height)
      var out: [CGRect] = []
      for row in Int(floor(area.minY / h))...Int(floor(area.maxY / h)) {
        for col in Int(floor(area.minX / w))...Int(floor(area.maxX / w)) { out.append(CGRect(x: CGFloat(col) * w, y: CGFloat(row) * h, width: w, height: h)) }
      }
      return out
    }
    var out: [Op] = []

    func grid(_ spacing: CGFloat, _ c: UInt32, _ width: CGFloat, horizontalOnly: Bool) {
      let step = spacing * scale
      if step < 5, !print { return }
      let a = fade(step, from: 5)
      let p = CGMutablePath()
      var y = ((area.minY - anchorY) / spacing).rounded(.up) * spacing + anchorY
      while y <= area.maxY {
        p.move(to: CGPoint(x: screen.minX, y: sy(y)))
        p.addLine(to: CGPoint(x: screen.maxX, y: sy(y)))
        y += spacing
      }
      if !horizontalOnly {
        var x = (area.minX / spacing).rounded(.up) * spacing
        while x <= area.maxX {
          p.move(to: CGPoint(x: sx(x), y: screen.minY))
          p.addLine(to: CGPoint(x: sx(x), y: screen.maxY))
          x += spacing
        }
      }
      out.append(.stroke(p, faded(c, a), px(width)))
    }

    func dots(_ spacing: CGFloat, _ c: UInt32) {
      let step = spacing * scale
      if step < 7, !print { return }
      let d = dotWorld * min(k, 3) * scale
      let r = (print ? d : max(d, 1.5)) / 2
      let p = CGMutablePath()
      var y = ((area.minY - anchorY) / spacing).rounded(.down) * spacing + anchorY
      while y <= area.maxY {
        var x = (area.minX / spacing).rounded(.down) * spacing
        while x <= area.maxX {
          p.addEllipse(in: CGRect(x: sx(x) - r, y: sy(y) - r, width: r * 2, height: r * 2))
          x += spacing
        }
        y += spacing
      }
      out.append(.fill(p, faded(c, fade(step, from: 7))))
    }

    /// Equilateral triangles of [side]: upright lines, and lines at ±30°.
    func isometric(_ side: CGFloat, _ c: UInt32, _ width: CGFloat) {
      let h = side * 0.866_025_4
      let step = h * scale
      if step < 6, !print { return }
      let t: CGFloat = 0.577_350_26
      let p = CGMutablePath()
      func line(_ x0: CGFloat, _ y0: CGFloat, _ x1: CGFloat, _ y1: CGFloat) {
        p.move(to: CGPoint(x: sx(x0), y: sy(y0)))
        p.addLine(to: CGPoint(x: sx(x1), y: sy(y1)))
      }
      var x = (area.minX / h).rounded(.up) * h
      while x <= area.maxX {
        line(x, area.minY, x, area.maxY)
        x += h
      }
      var rising = ((area.minY + area.minX * t - anchorY) / side).rounded(.down) * side + anchorY
      while rising <= area.maxY + area.maxX * t {
        line(area.minX, rising - area.minX * t, area.maxX, rising - area.maxX * t)
        rising += side
      }
      var falling = ((area.minY - area.maxX * t - anchorY) / side).rounded(.down) * side + anchorY
      while falling <= area.maxY - area.minX * t {
        line(area.minX, falling + area.minX * t, area.maxX, falling + area.maxX * t)
        falling += side
      }
      out.append(.stroke(p, faded(c, fade(step, from: 6)), px(width)))
    }

    /// Ruled: a header line, a red margin and 8 mm lines. Cornell: a title strip, a cue column,
    /// ruled notes beside it and a summary box across the bottom.
    func laidOut(_ r: CGRect, cornell: Bool, _ t: PaperTones) {
      let spacing = 8 * mm
      let a = fade(spacing * scale, from: 5)
      let header = r.minY + 28 * mm
      let linesEnd = cornell ? r.maxY - 50 * mm : r.maxY - 12 * mm
      if a > 0 {
        let p = CGMutablePath()
        var y = header + spacing
        while y <= linesEnd - spacing * 0.5 {
          p.move(to: CGPoint(x: sx(r.minX), y: sy(y)))
          p.addLine(to: CGPoint(x: sx(r.maxX), y: sy(y)))
          y += spacing
        }
        out.append(.stroke(p, faded(t.blueLine, a), px(1.2 * k)))
      }
      let s = CGMutablePath()
      s.move(to: CGPoint(x: sx(r.minX), y: sy(header)))
      s.addLine(to: CGPoint(x: sx(r.maxX), y: sy(header)))
      if cornell {
        s.move(to: CGPoint(x: sx(r.minX + 60 * mm), y: sy(header)))
        s.addLine(to: CGPoint(x: sx(r.minX + 60 * mm), y: sy(linesEnd)))
        s.move(to: CGPoint(x: sx(r.minX), y: sy(linesEnd)))
        s.addLine(to: CGPoint(x: sx(r.maxX), y: sy(linesEnd)))
      }
      out.append(.stroke(s, color(t.major), px(1.6 * k)))
      if !cornell {
        let m = CGMutablePath()
        m.move(to: CGPoint(x: sx(r.minX + 25 * mm), y: sy(r.minY)))
        m.addLine(to: CGPoint(x: sx(r.minX + 25 * mm), y: sy(r.maxY)))
        out.append(.stroke(m, color(t.margin), px(1.6 * k)))
      }
    }

    if let cp = spec.custom {
      if cp.image != nil {
        out.append(.fill(CGPath(rect: screen, transform: nil), spec.dark ? darkPaper : .white))
        for r in pages { out.append(.picture(onScreen(r), alpha: CGFloat(min(max(cp.opacity, 0.15), 1)))) }
        return out
      }
      out.append(.fill(CGPath(rect: screen, transform: nil), spec.dark ? darkPaper : UIColor(argb: cp.paperColor)))
      let line = PaperTones.customLine(cp, dark: spec.dark)
      let spacing = CGFloat(min(max(cp.spacingMm, 2), 30)) * mm
      switch cp.pattern {
      case .BLANK: break
      case .DOTS: dots(spacing, line)
      case .LINES: grid(spacing, line, 1.2 * k, horizontalOnly: true)
      case .ISOMETRIC: isometric(spacing, line, 1 * k)
      default: grid(spacing, line, 1 * k, horizontalOnly: false)
      }
      if cp.margin {
        let x = sx((endless ? 0 : area.minX) + 25 * mm)
        let m = CGMutablePath()
        m.move(to: CGPoint(x: x, y: screen.minY))
        m.addLine(to: CGPoint(x: x, y: screen.maxY))
        out.append(.stroke(m, color(PaperTones.customMargin(cp, dark: spec.dark)), px(1.4 * k)))
      }
      return out
    }

    let t = PaperTones.of(dark: spec.dark, look: spec.look)
    out.append(.fill(CGPath(rect: screen, transform: nil), color(t.paper)))
    switch spec.style {
    case .BLANK: break
    case .DOTS: dots(5 * mm, t.line)
    case .GRID: grid(5 * mm, t.blueLine, 1 * k, horizontalOnly: false)
    case .LINES: grid(8 * mm, t.blueLine, 1.2 * k, horizontalOnly: true)
    case .ENGINEERING:
      grid(2 * mm, t.minor, 0.8 * k, horizontalOnly: false)
      grid(10 * mm, t.major, 1.3 * k, horizontalOnly: false)
    case .ISOMETRIC: isometric(6 * mm, t.blueLine, 1 * k)
    case .CORNELL: for r in pages { laidOut(r, cornell: true, t) }
    case .RULED: for r in pages { laidOut(r, cornell: false, t) }
    }
    return out
  }

  /// Paints into a SwiftUI canvas.
  static func draw(_ spec: PaperSpec, area: CGRect, in ctx: GraphicsContext, origin: CGPoint, scale: CGFloat, print: Bool = false, picture: CGImage? = nil) {
    var c = ctx
    c.clip(to: Path(CGRect(x: (area.minX - origin.x) * scale, y: (area.minY - origin.y) * scale, width: area.width * scale, height: area.height * scale)))
    for op in ops(spec, area: area, origin: origin, scale: scale, print: print) {
      switch op {
      case .fill(let p, let color): c.fill(Path(p), with: .color(Color(uiColor: color)))
      case .stroke(let p, let color, let w): c.stroke(Path(p), with: .color(Color(uiColor: color)), lineWidth: w)
      case .picture(let r, let alpha):
        guard let img = picture.flatMap({ PaperPicture.cropped($0, to: r.size, dim: spec.dark) }) else { continue }
        var p = c
        p.opacity = alpha
        p.draw(Image(decorative: img, scale: 1), in: r)
      }
    }
  }

  /// Paints into Core Graphics, whose transform already maps world units at [scale].
  static func draw(_ spec: PaperSpec, area: CGRect, endless: Bool = false, in cg: CGContext, scale: CGFloat, print: Bool = false, picture: CGImage? = nil) {
    cg.saveGState()
    cg.clip(to: area)
    // Ops are in screen units at `scale`; the context already scales world units, so undo that here.
    cg.scaleBy(x: 1 / scale, y: 1 / scale)
    for op in ops(spec, area: area, endless: endless, origin: .zero, scale: scale, print: print) {
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
      case .picture(let r, let alpha):
        guard let img = picture.flatMap({ PaperPicture.cropped($0, to: r.size, dim: spec.dark) }) else { continue }
        cg.saveGState()
        cg.setAlpha(alpha)
        cg.translateBy(x: r.minX, y: r.maxY)
        cg.scaleBy(x: 1, y: -1)
        cg.interpolationQuality = .high
        cg.draw(img, in: CGRect(origin: .zero, size: r.size))
        cg.restoreGState()
      }
    }
    cg.restoreGState()
  }
}

/// A picture paper's image: loaded once at a size, its middle cropped to the page's shape (filling it
/// without stretching), dimmed to about a third on dark paper so ink stays readable.
enum PaperPicture {
  nonisolated(unsafe) private static var cache: [String: CGImage] = [:]
  nonisolated(unsafe) private static var crops: [String: CGImage] = [:]
  private static let lock = NSLock()

  static func image(_ file: String, maxPixels: Int = 2400) -> CGImage? {
    let key = "\(file)@\(maxPixels)"
    lock.lock()
    defer { lock.unlock() }
    if let hit = cache[key] { return hit }
    guard !file.contains("/") else { return nil }
    let url = AppFiles.folders.images.appendingPathComponent(file)
    guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
    let opts: [CFString: Any] = [
      kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceThumbnailMaxPixelSize: maxPixels, kCGImageSourceCreateThumbnailWithTransform: true,
    ]
    guard let img = CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary) else { return nil }
    cache[key] = img
    return img
  }

  static func cropped(_ img: CGImage, to size: CGSize, dim: Bool) -> CGImage? {
    guard size.width > 0, size.height > 0 else { return nil }
    let aspect = size.width / size.height
    let key = "\(ObjectIdentifier(img).hashValue)-\(Int(aspect * 1000))-\(dim)"
    lock.lock()
    defer { lock.unlock() }
    if let hit = crops[key] { return hit }
    let w = CGFloat(img.width), h = CGFloat(img.height)
    let crop = w / h > aspect
      ? CGRect(x: ((w - h * aspect) / 2).rounded(), y: 0, width: (h * aspect).rounded(), height: h)
      : CGRect(x: 0, y: ((h - w / aspect) / 2).rounded(), width: w, height: (w / aspect).rounded())
    guard var out = img.cropping(to: crop) else { return nil }
    if dim, let ctx = CGContext(data: nil, width: out.width, height: out.height, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) {
      let r = CGRect(x: 0, y: 0, width: out.width, height: out.height)
      ctx.draw(out, in: r)
      ctx.setBlendMode(.multiply)
      ctx.setFillColor(UIColor(red: 0.35, green: 0.35, blue: 0.38, alpha: 1).cgColor)
      ctx.fill(r)
      if let dimmed = ctx.makeImage() { out = dimmed }
    }
    crops[key] = out
    return out
  }
}

/// The top of a notebook's first page, for library cards: the page fills the box (cut at the bottom
/// or sides), [zoom] times closer.
struct PaperPreview: View {
  var style: PaperStyle
  var landscape = false
  var dark = false
  var zoom: CGFloat = 1
  var custom: CustomPaper?

  var body: some View {
    let spec = PaperSettings.shared.spec(style, custom: custom, dark: dark)
    let picture = custom?.image.flatMap { PaperPicture.image($0, maxPixels: 640) }
    Canvas { ctx, size in
      let page = Pages.of(landscape: landscape)
      let pw = CGFloat(page.width), ph = CGFloat(page.height)
      let scale = max(size.width / pw, size.height / ph) * zoom
      PaperPainter.draw(spec, area: CGRect(x: 0, y: 0, width: pw, height: ph), in: ctx, origin: .zero, scale: scale, print: true, picture: picture)
    }
  }
}

/// A small square of a built-in paper (Android's `PaperSwatch`): on dark paper as the dark page it
/// would be, in her own colours and line thickness when she has set them.
struct PaperSwatch: View {
  var style: PaperStyle
  var dark = false
  var look: PaperLook?
  var weight: CGFloat = 1
  @Environment(\.tali) private var c

  var body: some View {
    let chosen: UInt32? = dark ? nil : look?.line.map { UInt32(bitPattern: $0) }
    func ink(_ usual: UInt32) -> Color {
      if dark {
        switch usual {
        case 0xFFED_EDED: return Color(argb: 0xFF2E_2D35)
        case 0xFFDA_DADA, 0xFFD2_D2D2: return Color(argb: 0xFF45_434D)
        case 0xFFF0_A0B4: return Color(argb: 0x99E0_7A90)
        default: return Color(argb: 0xFF5E_5C66)
        }
      }
      guard let chosen else { return Color(argb: usual) }
      if usual == 0xFFED_EDED { return Color(argb: chosen).opacity(0.45) }
      return usual == 0xFFF0_A0B4 ? Color(argb: usual) : Color(argb: chosen)
    }
    let paper = dark ? Color(argb: PaperTones.darkPaper) : look?.paper.map { Color(argb: UInt32(bitPattern: $0)) } ?? .white
    let line = c.line
    return Canvas { ctx, size in
      let rect = CGRect(origin: .zero, size: size)
      let shape = Path(roundedRect: rect, cornerRadius: 8)
      ctx.clip(to: shape)
      ctx.fill(shape, with: .color(paper))
      let step = size.width / 7
      let w = 0.5 + 0.5 * min(max(weight, 0.3), 5)
      func stroke(_ p: Path, _ col: Color, _ width: CGFloat) { ctx.stroke(p, with: .color(col), lineWidth: width) }
      // Stops half a step short of the edge: a line landing right on it showed as a stray bright line.
      func grid(_ s: CGFloat, _ col: Color, _ width: CGFloat, both: Bool) {
        var p = Path()
        var y = s
        while y < size.height - s * 0.5 {
          p.move(to: CGPoint(x: 0, y: y))
          p.addLine(to: CGPoint(x: size.width, y: y))
          y += s
        }
        if both {
          var x = s
          while x < size.width - s * 0.5 {
            p.move(to: CGPoint(x: x, y: 0))
            p.addLine(to: CGPoint(x: x, y: size.height))
            x += s
          }
        }
        stroke(p, col, width)
      }
      if step >= 2 {
        switch style {
        case .BLANK: break
        case .DOTS:
          let r = 1.4 * (0.6 + 0.4 * min(max(weight, 0.3), 3))
          var p = Path()
          var y = step
          while y < size.height - step * 0.5 {
            var x = step
            while x < size.width - step * 0.5 {
              p.addEllipse(in: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2))
              x += step
            }
            y += step
          }
          ctx.fill(p, with: .color(ink(0xFFC4_C4C4)))
        case .GRID: grid(step, ink(0xFFDA_DADA), w, both: true)
        case .LINES: grid(step * 1.4, ink(0xFFD2_D2D2), 1.2 * w, both: false)
        case .ENGINEERING:
          grid(step / 2.5, ink(0xFFED_EDED), 0.8 * w, both: true)
          grid(step * 2, ink(0xFFCF_CFCF), 1.2 * w, both: true)
        case .ISOMETRIC:
          let h = step * 1.2, t: CGFloat = 0.577_350_26
          var p = Path()
          var x = h
          while x < size.width {
            p.move(to: CGPoint(x: x, y: 0))
            p.addLine(to: CGPoint(x: x, y: size.height))
            x += h
          }
          let side = h / 0.866_025_4
          var k = -size.width * t
          while k < size.height + size.width * t {
            p.move(to: CGPoint(x: 0, y: k))
            p.addLine(to: CGPoint(x: size.width, y: k - size.width * t))
            p.move(to: CGPoint(x: 0, y: k))
            p.addLine(to: CGPoint(x: size.width, y: k + size.width * t))
            k += side
          }
          stroke(p, ink(0xFFDA_DADA), w)
        case .CORNELL, .RULED:
          let header = size.height * 0.2
          let end = style == .CORNELL ? size.height * 0.74 : size.height
          var p = Path()
          var y = header + step
          while y < end - step * 0.4 {
            p.move(to: CGPoint(x: 0, y: y))
            p.addLine(to: CGPoint(x: size.width, y: y))
            y += step
          }
          stroke(p, ink(0xFFDA_DADA), w)
          var s = Path()
          s.move(to: CGPoint(x: 0, y: header))
          s.addLine(to: CGPoint(x: size.width, y: header))
          if style == .CORNELL {
            s.move(to: CGPoint(x: size.width * 0.3, y: header))
            s.addLine(to: CGPoint(x: size.width * 0.3, y: end))
            s.move(to: CGPoint(x: 0, y: end))
            s.addLine(to: CGPoint(x: size.width, y: end))
          }
          stroke(s, ink(0xFFBD_BDBD), 1.3 * w)
          if style == .RULED {
            var m = Path()
            m.move(to: CGPoint(x: size.width * 0.18, y: 0))
            m.addLine(to: CGPoint(x: size.width * 0.18, y: size.height))
            stroke(m, ink(0xFFF0_A0B4), 1.2 * w)
          }
        }
      }
      ctx.stroke(shape, with: .color(line), lineWidth: 1)
    }
  }
}

/// A small picture of one of her papers (Android's `CustomPaperSwatch`): her picture, or her pattern
/// drawn as if the swatch showed a strip about 60 mm wide.
struct CustomPaperSwatch: View {
  var paper: CustomPaper
  var dark = false

  var body: some View {
    if let file = paper.image {
      ZStack {
        dark ? Color(argb: PaperTones.darkPaper) : Color.white
        if let img = PaperPicture.image(file, maxPixels: 240) {
          Image(decorative: img, scale: 1).resizable().scaledToFill()
            .opacity(Double(min(max(paper.opacity, 0.15), 1)) * (dark ? 0.4 : 1))
        }
      }
      .clipShape(RoundedRectangle(cornerRadius: 8))
    } else {
      pattern
    }
  }

  private var pattern: some View {
    let cp = paper
    let line = Color(argb: PaperTones.customLine(cp, dark: dark))
    let margin = Color(argb: UInt32(bitPattern: cp.faded(Int32(bitPattern: 0xFFF0_A0B4))))
    let back = dark ? Color(argb: PaperTones.darkPaper) : Color(argb: UInt32(bitPattern: cp.paperColor))
    return Canvas { ctx, size in
      let shape = Path(roundedRect: CGRect(origin: .zero, size: size), cornerRadius: 8)
      ctx.clip(to: shape)
      ctx.fill(shape, with: .color(back))
      let step = size.width * CGFloat(cp.spacingMm) / 60
      let weight = CGFloat(min(max(cp.lineWeight ?? Float(PaperSettings.shared.lineWeight), 0.3), 5))
      let w = 0.5 + 0.5 * weight
      if step >= 2 {
        switch cp.pattern {
        case .BLANK: break
        case .DOTS:
          let r = max(1, step / 9) * (0.6 + 0.4 * min(weight, 3))
          var p = Path()
          var y = step
          while y < size.height {
            var x = step
            while x < size.width {
              p.addEllipse(in: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2))
              x += step
            }
            y += step
          }
          ctx.fill(p, with: .color(line))
        default:
          var p = Path()
          var y = step
          while y < size.height {
            p.move(to: CGPoint(x: 0, y: y))
            p.addLine(to: CGPoint(x: size.width, y: y))
            y += step
          }
          if cp.pattern != .LINES {
            var x = step
            while x < size.width {
              p.move(to: CGPoint(x: x, y: 0))
              p.addLine(to: CGPoint(x: x, y: size.height))
              x += step
            }
          }
          ctx.stroke(p, with: .color(line), lineWidth: w)
        }
      }
      if cp.margin {
        var m = Path()
        m.move(to: CGPoint(x: size.width * 0.2, y: 0))
        m.addLine(to: CGPoint(x: size.width * 0.2, y: size.height))
        ctx.stroke(m, with: .color(margin), lineWidth: 1.2 * w)
      }
      ctx.stroke(shape, with: .color(Color(argb: 0x2200_0000)), lineWidth: 0.6)
    }
  }
}
