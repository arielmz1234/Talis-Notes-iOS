import TaliCore
import UIKit

/// What Android draws over the page column in screen units (`drawPages`, `drawPullIndicator`,
/// `drawPageGuides`): each page's "2/5" in its bottom corner, the add-page sign while she pulls past
/// the last page, and on an endless canvas the A4 page guides. It covers the screen and moves with
/// the view, under the writing.
final class PageChrome: UIView {
  private var numbers: [UILabel] = []
  private let ring = CAShapeLayer()
  private let signText = UILabel()
  private let guides = CAShapeLayer()

  override init(frame: CGRect) {
    super.init(frame: frame)
    isUserInteractionEnabled = false
    backgroundColor = .clear
    guides.fillColor = nil
    guides.strokeColor = UIColor(argb: Int32(bitPattern: 0x669B_7BE0)).cgColor
    guides.lineWidth = 1.2
    guides.lineDashPattern = [5, 4]
    layer.addSublayer(guides)
    ring.fillColor = nil
    ring.lineWidth = 1.6
    ring.lineCap = .round
    layer.addSublayer(ring)
    signText.font = .systemFont(ofSize: 12)
    signText.textAlignment = .center
    addSubview(signText)
  }

  required init?(coder: NSCoder) { fatalError() }

  /// "2/5" in the bottom-right corner of each page given (screen rects), 10 pt in and 9 pt up.
  func showNumbers(_ pages: [(rect: CGRect, label: String)], darkPaper: Bool) {
    while numbers.count < pages.count {
      let l = UILabel()
      l.font = .systemFont(ofSize: 11)
      addSubview(l)
      numbers.append(l)
    }
    let color = UIColor(argb: Int32(bitPattern: darkPaper ? 0x88FF_FFFF : 0x6600_0000))
    for (i, l) in numbers.enumerated() {
      guard i < pages.count else {
        l.isHidden = true
        continue
      }
      let (r, text) = pages[i]
      l.isHidden = false
      l.text = text
      l.textColor = color
      l.sizeToFit()
      l.frame.origin = CGPoint(x: r.maxX - 10 - l.bounds.width, y: r.maxY - 9 - l.font.ascender)
    }
  }

  /// The sign under the last page, whose bottom is at [lastBottom] on screen; nil hides it.
  func showSign(_ sign: PagePull.Sign?, lastBottom: CGFloat, dark: Bool) {
    guard let sign else {
      CATransaction.begin()
      CATransaction.setDisableActions(true)
      ring.isHidden = true
      CATransaction.commit()
      signText.isHidden = true
      return
    }
    let ready: Bool
    if case .release = sign { ready = true } else { ready = false }
    let tone = UIColor(argb: Int32(bitPattern: dark ? 0xFFC9_C3D6 : 0xFF77_718A)).withAlphaComponent(CGFloat(sign.alpha))
    let c = CGPoint(x: bounds.width / 2, y: (lastBottom + bounds.height) / 2 - 10)
    let r: CGFloat = 13, s: CGFloat = 6
    let p = UIBezierPath(arcCenter: c, radius: r, startAngle: 0, endAngle: .pi * 2, clockwise: true)
    if ready {
      p.move(to: CGPoint(x: c.x - s, y: c.y))
      p.addLine(to: CGPoint(x: c.x + s, y: c.y))
      p.move(to: CGPoint(x: c.x, y: c.y - s))
      p.addLine(to: CGPoint(x: c.x, y: c.y + s))
    } else {
      p.move(to: CGPoint(x: c.x, y: c.y + s))
      p.addLine(to: CGPoint(x: c.x, y: c.y - s))
      p.addLine(to: CGPoint(x: c.x - s * 0.7, y: c.y - s * 0.3))
      p.move(to: CGPoint(x: c.x, y: c.y - s))
      p.addLine(to: CGPoint(x: c.x + s * 0.7, y: c.y - s * 0.3))
    }
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    ring.isHidden = false
    ring.path = p.cgPath
    ring.strokeColor = tone.cgColor
    CATransaction.commit()
    signText.isHidden = false
    signText.text = ready ? L("release_to_add_a_page") : L("drag_for_a_new_page")
    signText.textColor = tone
    signText.sizeToFit()
    signText.center = CGPoint(x: c.x, y: c.y + r + 18 - signText.font.ascender + signText.bounds.height / 2)
  }

  /// Faint dashed A4 page edges, where the exported pages will break; [lines] in screen units.
  func showGuides(_ lines: [(CGPoint, CGPoint)]) {
    let p = CGMutablePath()
    for (a, b) in lines {
      p.move(to: a)
      p.addLine(to: b)
    }
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    guides.path = lines.isEmpty ? nil : p
    CATransaction.commit()
  }
}

/// The pull past the last page and the view's chrome, as the canvas keeps them.
struct PageChromeState {
  var view: PageChrome?
  var pull = PagePull()
  /// The zoom when the fingers landed: zooming more than 4% makes it no pull.
  var zoomAtDown: CGFloat = 1
}

extension NoteCanvas.Coordinator {
  func installPageChrome(on v: UIScrollView, above pages: UIView) {
    let chrome = PageChrome(frame: v.bounds)
    v.insertSubview(chrome, aboveSubview: pages)
    pageChrome.view = chrome
  }

  /// How far below the last page the screen reaches, in points on screen.
  private var belowLastPage: CGFloat {
    guard let canvas else { return 0 }
    return canvas.contentOffset.y + canvas.bounds.height - CGFloat(layout.rect(pageCount - 1).bottom) * canvas.zoomScale
  }

  func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
    pageChrome.zoomAtDown = scrollView.zoomScale
    // Only a pull that starts at the end of the notebook can open space for a new page.
    pageChrome.pull.begin(below: Float(belowLastPage), allowed: paged && !parent.viewOnly)
  }

  func scrollViewWillEndDragging(_ scrollView: UIScrollView, withVelocity velocity: CGPoint, targetContentOffset: UnsafeMutablePointer<CGPoint>) {
    switch pageChrome.pull.end(below: Float(belowLastPage)) {
    case .none: break
    case .addPage:
      // It takes the space she pulled open.
      pageCount += 1
      updateContent()
      persistPages()
      reportUndo()
      UINotificationFeedbackGenerator().notificationOccurred(.success)
      targetContentOffset.pointee = scrollView.contentOffset
    case .springBack:
      targetContentOffset.pointee = scrollView.contentOffset
    }
    updateChrome()
  }

  /// Zooming out shows more below the last page, which isn't pulling.
  func zoomEndsPull() {
    guard let canvas, pageChrome.pull.pulling else { return }
    if abs(canvas.zoomScale - pageChrome.zoomAtDown) > pageChrome.zoomAtDown * 0.04 { pageChrome.pull.cancel() }
  }

  /// The portrait A4 grid's edges on screen, where an endless canvas's PDF pages break.
  private func guideLines(z: CGFloat, o: CGPoint, size: CGSize) -> [(CGPoint, CGPoint)] {
    let w = CGFloat(A4.width), h = CGFloat(A4.height)
    var lines: [(CGPoint, CGPoint)] = []
    var x = (o.x / z / w).rounded(.down) * w
    while x * z - o.x <= size.width {
      lines.append((CGPoint(x: x * z - o.x, y: 0), CGPoint(x: x * z - o.x, y: size.height)))
      x += w
    }
    var y = (o.y / z / h).rounded(.down) * h
    while y * z - o.y <= size.height {
      lines.append((CGPoint(x: 0, y: y * z - o.y), CGPoint(x: size.width, y: y * z - o.y)))
      y += h
    }
    return lines
  }

  /// Puts the chrome over the screen and lays out what shows there now.
  func updateChrome() {
    guard let canvas, let chrome = pageChrome.view else { return }
    chrome.frame = CGRect(origin: canvas.contentOffset, size: canvas.bounds.size)
    let z = canvas.zoomScale
    let o = canvas.contentOffset
    func screen(_ r: Rect) -> CGRect { CGRect(x: CGFloat(r.left) * z - o.x, y: CGFloat(r.top) * z - o.y, width: CGFloat(r.width) * z, height: CGFloat(r.height) * z) }
    guard paged else {
      chrome.showNumbers([], darkPaper: false)
      chrome.showSign(nil, lastBottom: 0, dark: false)
      chrome.showGuides(parent.settings.pageGuides ? guideLines(z: z, o: o, size: canvas.bounds.size) : [])
      return
    }
    chrome.showGuides([])
    let top = Float(o.y / z), bottom = Float((o.y + canvas.bounds.height) / z)
    let first = max(layout.indexAt(top), 0), last = min(layout.indexAt(bottom), pageCount - 1)
    var shown: [(CGRect, String)] = []
    if first <= last {
      for i in first...last {
        let r = screen(layout.rect(i))
        // Only when the page is big enough to read it.
        if r.height > 240 { shown.append((r, "\(i + 1)/\(pageCount)")) }
      }
    }
    let dark = parent.settings.dark
    chrome.showNumbers(shown, darkPaper: dark)
    let deskDark = dark || canvas.superview?.traitCollection.userInterfaceStyle == .dark
    let lastBottom = screen(layout.rect(pageCount - 1)).maxY
    chrome.showSign(canvas.isDragging ? pageChrome.pull.sign(below: Float(belowLastPage)) : nil, lastBottom: lastBottom, dark: deskDark)
  }
}
