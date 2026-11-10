import Foundation

/// A4 in world units, matching the PDF's points (595 × 842 pt at 72/160 pt per unit).
public enum A4 {
  public static let width: Float = 595 / (72 / 160)
  public static let height: Float = 842 / (72 / 160)
}

/// Where the pages of a paged notebook sit on the canvas: one column of pages from the origin with a
/// small gap between them (ported from Android's `canvas/Pages.kt`). A4 upright or on its side, or for a
/// PDF or picture added on its own, the shape of its first page, as long on its long side as A4.
public struct Pages: Hashable, Sendable {
  public let width: Float
  public let height: Float

  private init(_ width: Float, _ height: Float) {
    self.width = width
    self.height = height
  }

  public static let gap: Float = 40
  public static let portrait = Pages(A4.width, A4.height)
  public static let landscape = Pages(A4.height, A4.width)

  public var isLandscape: Bool { width > height }
  public var pitch: Float { height + Pages.gap }
  /// Width over height.
  public var aspect: Float { width / height }

  public func rect(_ index: Int) -> Rect { Rect(0, Float(index) * pitch, width, Float(index) * pitch + height) }
  public func all(_ count: Int) -> [Rect] { (0..<max(count, 0)).map(rect) }

  /// The page a height falls on (the gap below a page counts as that page).
  public func indexAt(_ y: Float) -> Int { Int(floorf(y / pitch)) }

  /// Whether x, y lies on one of the first [count] pages.
  public func contains(_ count: Int, _ x: Float, _ y: Float) -> Bool {
    if x < 0 || x > width || y < 0 { return false }
    let i = indexAt(y)
    return i < count && y - Float(i) * pitch <= height
  }

  /// Where a stroke or shape is shown on the first [count] pages: never past a page's sides; with
  /// [between] (Write between pages) across the gaps, otherwise on its own page (where a stroke
  /// began, or where most of a shape is: [anchorY]).
  public func clip(anchorY: Float, count: Int, between: Bool) -> Rect? {
    if count <= 0 { return nil }
    if between { return Rect(0, 0, width, rect(count - 1).bottom) }
    return rect(min(max(indexAt(anchorY), 0), count - 1))
  }

  /// How many pages it takes to hold everything down to [content]'s bottom edge.
  public func needed(_ content: Rect?) -> Int {
    guard let content else { return 1 }
    return max(indexAt(content.bottom) + 1, 1)
  }

  /// The pages left after deleting [gone] (by index) from [count]: the order to lay them out in.
  public static func withoutPages(_ count: Int, _ gone: Set<Int>) -> [Int] { (0..<count).filter { !gone.contains($0) } }

  /// Every page, each one in [copied] followed straight after by its copy.
  public static func withCopies(_ count: Int, _ copied: Set<Int>) -> [Int] { (0..<count).flatMap { copied.contains($0) ? [$0, $0] : [$0] } }

  /// Where page [p] ends up when page [from] is moved to position [to].
  public static func movedIndex(_ p: Int, from: Int, to: Int) -> Int {
    if p == from { return to }
    if from < to && p >= from + 1 && p <= to { return p - 1 }
    if from > to && p >= to && p < from { return p + 1 }
    return p
  }

  /// A4 pages, or with [aspect] (width over height) pages of that shape.
  public static func of(landscape: Bool, aspect: Float? = nil) -> Pages {
    guard let raw = aspect, raw.isFinite, raw > 0 else { return landscape ? .landscape : .portrait }
    let a = min(max(raw, 0.25), 4)
    let long = A4.height
    return a >= 1 ? Pages(long, long / a) : Pages(long * a, long)
  }
}
