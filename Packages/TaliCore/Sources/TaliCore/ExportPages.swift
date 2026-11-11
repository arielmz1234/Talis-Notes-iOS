import Foundation

/// How an exported PDF is cut into pages (Android's `PdfLayout`).
public enum PdfLayout: Sendable, CaseIterable {
  /// The notebook's own pages, or A4 pages cut from an endless canvas.
  case a4Pages
  /// Everything on one long page, sized to fit.
  case onePage
  /// Each imported PDF page (a slide) a page again, with the notes written round it.
  case pdfPages
}

/// The pages of an exported PDF, in world units (Android's `Exporter.pdf` page choice).
public enum ExportPages {
  /// PDF points per world unit: 72 pt per inch, 160 units per inch.
  public static let ptPerUnit: Float = 72 / 160
  /// Room left round the writing on one long page or cut A4 pages.
  public static let margin: Float = 48
  /// PDF pages max out at 200 inches; taller content is split into several tall pages.
  public static let maxSide: Float = 14000 / ptPerUnit

  /// Something on the page: where it is, and whether it's an imported PDF page.
  public struct Item: Sendable {
    public var bounds: Rect
    public var pdfPage: Bool
    public init(_ bounds: Rect, pdfPage: Bool = false) {
      self.bounds = bounds
      self.pdfPage = pdfPage
    }
  }

  /// [pageCount] is set for a paged notebook (its pages, empty ones included, in [pages]' shape);
  /// [fixedGrid] cuts an endless canvas on the grid the page guides show instead of round the writing.
  public static func pages(_ layout: PdfLayout, items: [Item], pages: Pages, pageCount: Int?, fixedGrid: Bool = false) -> [Rect] {
    let content = items.map(\.bounds).reduce(nil) { (acc: Rect?, r) in acc?.union(r) ?? r }?.outset(margin) ?? Rect(0, 0, 1322, 1871)
    switch layout {
    case .onePage:
      return splitTall(content)
    case .a4Pages:
      if let pageCount { return pages.all(pageCount) }
      let grid = fixedGrid ? fixedA4(items) : a4(content)
      let used = grid.filter { page in items.contains { $0.bounds.intersects(page) } }
      return used.isEmpty ? Array(grid.prefix(1)) : used
    case .pdfPages:
      let out = pdfPages(items)
      return out.isEmpty ? splitTall(content) : out
    }
  }

  /// A page's size in PDF points, rounded up, so an A4 page is exactly 595 × 842 wherever it sits
  /// (a page far down the column is a hair over in Float).
  public static func points(_ page: Rect) -> (width: Int, height: Int) {
    func up(_ v: Float) -> Int { Int((v * ptPerUnit - 0.01).rounded(.up)) }
    return (up(page.width), up(page.height))
  }

  static func splitTall(_ content: Rect) -> [Rect] {
    if content.height <= maxSide && content.width <= maxSide { return [content] }
    var out: [Rect] = []
    var top = content.top
    while top < content.bottom {
      out.append(Rect(content.left, top, content.left + min(content.width, maxSide), min(content.bottom, top + maxSide)))
      top += maxSide
    }
    return out
  }

  /// One page per imported PDF page, top to bottom, each taking the notes whose middle lies between
  /// its top and the next page's top.
  static func pdfPages(_ items: [Item]) -> [Rect] {
    let slides = items.filter(\.pdfPage).sorted { $0.bounds.top < $1.bounds.top }
    let others = items.filter { !$0.pdfPage }
    return slides.enumerated().map { i, page in
      let bandTop = i == 0 ? -Float.infinity : page.bounds.top
      let bandBottom = i + 1 < slides.count ? slides[i + 1].bounds.top : Float.infinity
      return others.filter { $0.bounds.center.y >= bandTop && $0.bounds.center.y < bandBottom }.reduce(page.bounds) { $0.union($1.bounds) }
    }
  }

  /// The A4 pages of the fixed grid that the writing touches, row by row.
  static func fixedA4(_ items: [Item]) -> [Rect] {
    let w = A4.width, h = A4.height
    guard let b = items.map(\.bounds).reduce(nil, { (acc: Rect?, r) in acc?.union(r) ?? r }) else { return [Rect(0, 0, w, h)] }
    var out: [Rect] = []
    for row in Int(floorf(b.top / h))...Int(floorf(b.bottom / h)) {
      for col in Int(floorf(b.left / w))...Int(floorf(b.right / w)) {
        out.append(Rect(Float(col) * w, Float(row) * h, Float(col + 1) * w, Float(row + 1) * h))
      }
    }
    return out
  }

  /// The content tiled into upright A4 pages, row by row, the grid centred on it.
  static func a4(_ content: Rect) -> [Rect] {
    let w = A4.width, h = A4.height
    let cols = max(Int((content.width / w).rounded(.up)), 1)
    let rows = max(Int((content.height / h).rounded(.up)), 1)
    let left = content.center.x - Float(cols) * w / 2
    var out: [Rect] = []
    for row in 0..<rows {
      for col in 0..<cols {
        out.append(Rect(left + Float(col) * w, content.top + Float(row) * h, left + Float(col + 1) * w, content.top + Float(row + 1) * h))
      }
    }
    return out
  }
}
