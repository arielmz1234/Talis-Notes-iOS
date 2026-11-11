import TaliCore
import UIKit

struct SelectionChrome {
  var frame: CGRect?
  var outline: [CGPoint] = []
  var resizeChip: CGPoint?
  var moveChip: CGPoint?
  var rotate: (at: CGPoint, stemFrom: CGFloat)?
  var dots: [CGPoint] = []
  var dotRadius: CGFloat = 6.5
  var badges: [Measure.Badge] = []
  var angle: Measure.Badge?
  var hints: [(from: CGPoint, to: CGPoint, centre: Bool)] = []
  /// When a move or a dot drag ended: the chips, hidden meanwhile, fade back in from then.
  var chipsBackAt: Date?

  var isEmpty: Bool {
    frame == nil && outline.isEmpty && resizeChip == nil && moveChip == nil && rotate == nil && dots.isEmpty && badges.isEmpty && angle == nil && hints.isEmpty
  }
}

final class SelectionChromeView: UIView {
  static let accent = UIColor(argb: Int32(bitPattern: 0xFF7A_4ED6))
  /// Blue, to stand apart from the lilac lasso (Android's `handleColor`).
  static let handle = UIColor(argb: Int32(bitPattern: 0xFF4F_7BE8))
  private static let badgeFont = UIFont.systemFont(ofSize: 12.5)
  private static let angleFont = UIFont.systemFont(ofSize: 13)
  private static let chipBack: TimeInterval = 0.16

  private var chrome = SelectionChrome()

  override init(frame: CGRect) {
    super.init(frame: frame)
    isOpaque = false
    backgroundColor = .clear
    isUserInteractionEnabled = false
    isHidden = true
    layer.zPosition = 11
  }

  required init?(coder: NSCoder) { fatalError() }

  static func badgeWidth(_ label: String) -> Float {
    Float((label as NSString).size(withAttributes: [.font: badgeFont]).width) + 18
  }

  func show(_ chrome: SelectionChrome, over canvas: UIScrollView) {
    self.chrome = chrome
    isHidden = chrome.isEmpty
    guard !isHidden else { return }
    // Over what's on screen, in the canvas's own coordinates.
    frame = canvas.bounds
    bounds.origin = canvas.bounds.origin
    setNeedsDisplay()
  }

  override func draw(_ rect: CGRect) {
    guard let cg = UIGraphicsGetCurrentContext() else { return }
    let c = chrome
    cg.setLineCap(.round)
    cg.setLineJoin(.round)
    dashed(cg) {
      if let f = c.frame { cg.addPath(UIBezierPath(roundedRect: f, cornerRadius: 6).cgPath) }
      if let first = c.outline.first {
        cg.move(to: first)
        for p in c.outline.dropFirst() { cg.addLine(to: p) }
        cg.closePath()
      }
      if let r = c.rotate {
        cg.move(to: CGPoint(x: r.at.x, y: r.stemFrom))
        cg.addLine(to: CGPoint(x: r.at.x, y: r.at.y - 6.5))
      }
    }
    for h in c.hints { hint(cg, h.from, h.to, centre: h.centre) }
    if let r = c.rotate {
      disc(cg, r.at, 6.5)
      cg.addArc(center: r.at, radius: 3.2, startAngle: -.pi / 3, endAngle: -.pi / 3 + 280 * .pi / 180, clockwise: false)
      cg.setStrokeColor(Self.handle.cgColor)
      cg.setLineWidth(2)
      cg.strokePath()
    }
    for d in c.dots { disc(cg, d, c.dotRadius) }
    chips(cg, c)
    for b in c.badges { badge(cg, b, Self.badgeFont, extra: 18) }
    if let a = c.angle { badge(cg, a, Self.angleFont, extra: 16) }
  }

  private func dashed(_ cg: CGContext, _ build: () -> Void) {
    cg.saveGState()
    build()
    cg.setStrokeColor(Self.accent.cgColor)
    cg.setLineWidth(1.5)
    cg.setLineCap(.butt)
    cg.setLineDash(phase: 0, lengths: [6, 4])
    cg.strokePath()
    cg.restoreGState()
  }

  private func disc(_ cg: CGContext, _ at: CGPoint, _ radius: CGFloat) {
    let r = CGRect(x: at.x - radius, y: at.y - radius, width: radius * 2, height: radius * 2)
    cg.setFillColor(UIColor.white.cgColor)
    cg.fillEllipse(in: r)
    cg.setStrokeColor(Self.handle.cgColor)
    cg.setLineWidth(2)
    cg.strokeEllipse(in: r)
  }

  private func hint(_ cg: CGContext, _ from: CGPoint, _ to: CGPoint, centre: Bool) {
    let color = Self.accent.withAlphaComponent(200 / 255)
    cg.saveGState()
    cg.setStrokeColor(color.cgColor)
    cg.setLineWidth(2.4)
    cg.setLineDash(phase: 0, lengths: [0.1, 6])
    cg.move(to: from)
    cg.addLine(to: to)
    cg.strokePath()
    cg.restoreGState()
    if centre {
      cg.setFillColor(color.cgColor)
      cg.fillEllipse(in: CGRect(x: from.x - 3, y: from.y - 3, width: 6, height: 6))
    }
  }

  private func chips(_ cg: CGContext, _ c: SelectionChrome) {
    guard c.resizeChip != nil || c.moveChip != nil else { return }
    let back = c.chipsBackAt.map { min(max(Date().timeIntervalSince($0) / Self.chipBack, 0), 1) } ?? 1
    let shown = 1 - pow(1 - back, 3)
    func chip(_ at: CGPoint, _ glyph: () -> Void) {
      cg.saveGState()
      if back < 1 {
        cg.setAlpha(shown)
        cg.translateBy(x: at.x, y: at.y)
        cg.scaleBy(x: 0.85 + 0.15 * shown, y: 0.85 + 0.15 * shown)
        cg.translateBy(x: -at.x, y: -at.y)
      }
      disc(cg, at, 13)
      glyph()
      cg.setStrokeColor(Self.handle.cgColor)
      cg.strokePath()
      cg.restoreGState()
    }
    if let at = c.resizeChip {
      chip(at) {
        let a: CGFloat = 4.6, h: CGFloat = 3.2
        cg.setLineWidth(1.8)
        cg.move(to: CGPoint(x: at.x - a, y: at.y - a))
        cg.addLine(to: CGPoint(x: at.x + a, y: at.y + a))
        cg.move(to: CGPoint(x: at.x - a + h, y: at.y - a))
        cg.addLine(to: CGPoint(x: at.x - a, y: at.y - a))
        cg.addLine(to: CGPoint(x: at.x - a, y: at.y - a + h))
        cg.move(to: CGPoint(x: at.x + a - h, y: at.y + a))
        cg.addLine(to: CGPoint(x: at.x + a, y: at.y + a))
        cg.addLine(to: CGPoint(x: at.x + a, y: at.y + a - h))
      }
    }
    if let at = c.moveChip {
      chip(at) {
        let a: CGFloat = 7.2, h: CGFloat = 2.1
        cg.setLineWidth(1.6)
        cg.move(to: CGPoint(x: at.x - a, y: at.y))
        cg.addLine(to: CGPoint(x: at.x + a, y: at.y))
        cg.move(to: CGPoint(x: at.x, y: at.y - a))
        cg.addLine(to: CGPoint(x: at.x, y: at.y + a))
        for (dx, dy): (CGFloat, CGFloat) in [(1, 0), (-1, 0), (0, 1), (0, -1)] {
          let tx = at.x + dx * a, ty = at.y + dy * a
          cg.move(to: CGPoint(x: tx - dx * h - dy * h, y: ty - dy * h - dx * h))
          cg.addLine(to: CGPoint(x: tx, y: ty))
          cg.addLine(to: CGPoint(x: tx - dx * h + dy * h, y: ty - dy * h + dx * h))
        }
      }
    }
    if back < 1 { DispatchQueue.main.async { [weak self] in self?.setNeedsDisplay() } }
  }

  private func badge(_ cg: CGContext, _ b: Measure.Badge, _ font: UIFont, extra: CGFloat) {
    let text = NSAttributedString(string: b.label, attributes: [.font: font, .foregroundColor: UIColor.white])
    let size = text.size()
    let w = size.width + extra, h = CGFloat(Measure.badgeHeight)
    let box = CGRect(x: CGFloat(b.at.x) - w / 2, y: CGFloat(b.at.y) - h / 2, width: w, height: h)
    cg.setFillColor(Self.handle.cgColor)
    cg.addPath(UIBezierPath(roundedRect: box, cornerRadius: h / 2).cgPath)
    cg.fillPath()
    text.draw(at: CGPoint(x: box.midX - size.width / 2, y: box.midY - size.height / 2))
  }
}
