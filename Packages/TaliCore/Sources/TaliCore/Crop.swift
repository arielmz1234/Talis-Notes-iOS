import Foundation

/// Cropping a picture in place (Android's `CropEdit`, `dragCrop`, `finishCrop`): the whole picture
/// stays where it would sit uncropped and a frame inside it says what shows.
public struct CropEdit: Equatable, Sendable {
  public var picture: PictureRow
  /// Where the whole picture sits on the page.
  public let whole: Rect
  public var frame: Rect

  /// The smallest frame side, in points on screen.
  public static let least: Float = 28
  /// A side brought this near (points on screen) to the picture's own edge goes right onto it.
  public static let stick: Float = 8

  public init(_ p: PictureRow) {
    picture = p
    whole = p.whole
    frame = p.rect
  }

  /// The eight handles in order: top-left, top, top-right, right, bottom-right, bottom, bottom-left, left.
  public static func handles(_ f: Rect) -> [Pt] {
    let c = f.center
    return [Pt(f.left, f.top), Pt(c.x, f.top), Pt(f.right, f.top), Pt(f.right, c.y), Pt(f.right, f.bottom), Pt(c.x, f.bottom), Pt(f.left, f.bottom), Pt(f.left, c.y)]
  }

  /// The frame [from] with handle [grab] (0-7, or 8 for the whole frame) moved by [dx], [dy] world
  /// units at [zoom] screen points per unit: kept inside the picture and at least [least] across.
  public func dragged(_ grab: Int, from f: Rect, dx: Float, dy: Float, zoom: Float) -> Rect {
    let w = whole
    let least = Self.least / zoom, stick = Self.stick / zoom
    func near(_ v: Float, _ edge: Float) -> Float { abs(v - edge) < stick ? edge : v }
    if grab == 8 {
      let mx = min(max(dx, w.left - f.left), w.right - f.right)
      let my = min(max(dy, w.top - f.top), w.bottom - f.bottom)
      return Rect(f.left + mx, f.top + my, f.right + mx, f.bottom + my)
    }
    var l = f.left, t = f.top, r = f.right, b = f.bottom
    if [0, 6, 7].contains(grab) { l = min(max(near(f.left + dx, w.left), w.left), r - least) }
    if [0, 1, 2].contains(grab) { t = min(max(near(f.top + dy, w.top), w.top), b - least) }
    if [2, 3, 4].contains(grab) { r = min(max(near(f.right + dx, w.right), l + least), w.right) }
    if [4, 5, 6].contains(grab) { b = min(max(near(f.bottom + dy, w.bottom), t + least), w.bottom) }
    return Rect(l, t, r, b)
  }

  /// The picture as the frame leaves it: the part shown in fractions of the whole (none when it's all
  /// of it), shown where the frame is.
  public var finished: PictureRow {
    let w = whole, f = frame
    let part = Rect((f.left - w.left) / w.width, (f.top - w.top) / w.height, (f.right - w.left) / w.width, (f.bottom - w.top) / w.height)
    let all = part.left < 0.002 && part.top < 0.002 && part.right > 0.998 && part.bottom > 0.998
    return picture.cropped(all ? nil : part, shown: all ? w : f)
  }

  /// Pictures that can be cropped: not a PDF's page, an area fill, mirrored or locked.
  public static func croppable(_ p: PictureRow) -> Bool { !p.pdfPage && p.walls.isEmpty && !p.file.hasPrefix("fill-") && !p.flipX && !p.flipY && !p.locked }
}
