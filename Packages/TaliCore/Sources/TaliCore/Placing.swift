import Foundation

/// Where pictures and PDF pages added to a notebook land (Android's `insertImage`, `pageNudge`,
/// `insertPages` and `insertPdfOnPages`).
public enum Placing {
  /// A picture [size] (pixels) across: at most 60% of the [visible] world and [maxUnitsPerPixel]
  /// world units a pixel, centred on [at] (or the middle of the view), each next one of a batch
  /// ([index]) a little down and right.
  public static func picture(size: Pt, visible: Rect, at: Pt?, index: Int, zoom: Float, maxUnitsPerPixel: Float) -> Rect {
    let s = min(visible.width * 0.6 / size.x, visible.height * 0.6 / size.y, maxUnitsPerPixel)
    let w = size.x * s, h = size.y * s
    let step = Float(index) * 36 / zoom
    let c = (at ?? visible.center) + Pt(step, step)
    return Rect(c.x - w / 2, c.y - h / 2, c.x + w / 2, c.y + h / 2)
  }

  /// On pages, moved onto the page it overlaps most (the nearest when none), so it isn't half in a gap.
  public static func ontoPage(_ r: Rect, pages: Pages, count: Int) -> Rect {
    func overlap(_ p: Rect) -> Float { max(0, min(p.right, r.right) - max(p.left, r.left)) * max(0, min(p.bottom, r.bottom) - max(p.top, r.top)) }
    let page = pages.all(max(count, 1)).max { a, b in
      overlap(a) != overlap(b) ? overlap(a) < overlap(b) : a.center.dist(r.center) > b.center.dist(r.center)
    }!
    func fit(_ lo: Float, _ hi: Float, _ a: Float, _ b: Float) -> Float {
      if b - a >= hi - lo { return lo - a }
      if a < lo { return lo - a }
      if b > hi { return hi - b }
      return 0
    }
    let dx = fit(page.left, page.right, r.left, r.right), dy = fit(page.top, page.bottom, r.top, r.bottom)
    return Rect(r.left + dx, r.top + dy, r.right + dx, r.bottom + dy)
  }

  /// PDF pages ([sizes] in world units) added to a paged notebook: one per page from the last page if
  /// it's empty, else after it, each fitted to the top of its page. Returns the first page used.
  public static func pdfOnPages(_ sizes: [Pt], pages: Pages, count: Int, lastIsEmpty: Bool) -> (start: Int, rects: [Rect]) {
    let start = lastIsEmpty ? count - 1 : count
    let rects = sizes.enumerated().map { i, p in
      let r = pages.rect(start + i)
      let s = min(r.width / p.x, r.height / p.y)
      let x = r.left + (r.width - p.x * s) / 2
      return Rect(x, r.top, x + p.x * s, r.top + p.y * s)
    }
    return (start, rects)
  }

  /// PDF pages on an endless canvas: one under the other below what's there (or from the top of the
  /// view), centred on it, a page's gap apart.
  public static func pdfOnCanvas(_ sizes: [Pt], content: Rect?, visible: Rect) -> [Rect] {
    let widest = sizes.map(\.x).max() ?? 0
    let left = (content?.center.x ?? visible.center.x) - widest / 2
    var top = content.map { $0.bottom + 160 } ?? visible.top + 40
    return sizes.map { p in
      let x = left + (widest - p.x) / 2
      defer { top += p.y + Pages.gap }
      return Rect(x, top, x + p.x, top + p.y)
    }
  }
}
