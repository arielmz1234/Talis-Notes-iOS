import PencilKit
import TaliCore
import UIKit

/// A notebook's library preview (Android's `persistView` → `Exporter.thumbnail`): a paged notebook
/// shows the top of its first page, card-shaped; an endless canvas shows the writing last seen.
/// Saved as `thumbs/<id>.png`, the same file Android keeps (and backups carry).
@MainActor
enum Thumbnail {
  static let cardAspect: CGFloat = 1.32
  static let width: CGFloat = 640

  /// What a paged notebook's card shows of its first [page]: its top, card-shaped; a page much
  /// wider than the card (a slide) is shown whole, centred (Android's `previewRegion`).
  static func previewRegion(_ page: CGRect) -> CGRect {
    if page.width / page.height > 1.5 {
      let h = page.width / cardAspect
      return CGRect(x: page.minX, y: page.midY - h / 2, width: page.width, height: h)
    }
    return CGRect(x: page.minX, y: page.minY, width: page.width, height: min(page.height, page.width / cardAspect))
  }

  /// Renders [region] (world units) of the page layer and the drawing into a PNG and saves it.
  static func save(id: String, region: CGRect, pages: PagesLayer, drawing: PKDrawing, db: NotesDb) {
    guard region.width > 1, region.height > 1 else { return }
    let scale = width / region.width
    let size = CGSize(width: width, height: (region.height * scale).rounded())
    let format = UIGraphicsImageRendererFormat()
    format.scale = 1
    format.opaque = true
    let image = UIGraphicsImageRenderer(size: size, format: format).image { ctx in
      let cg = ctx.cgContext
      UIColor.white.setFill()
      cg.fill(CGRect(origin: .zero, size: size))
      cg.saveGState()
      cg.scaleBy(x: scale, y: scale)
      cg.translateBy(x: -region.minX, y: -region.minY)
      cg.clip(to: region)
      pages.paint(in: cg, scale: scale)
      cg.restoreGState()
      // The writing, drawn by PencilKit itself so it matches the page exactly.
      drawing.image(from: region, scale: scale).draw(in: CGRect(origin: .zero, size: size))
    }
    guard let png = image.pngData() else { return }
    let url = AppFiles.folders.thumbs.appendingPathComponent("\(id).png")
    try? png.write(to: url, options: .atomic)
    try? db.run("UPDATE notebooks SET thumb=? WHERE id=?", [.int(Int64(Date().timeIntervalSince1970 * 1_000_000_000)), .text(id)])
    ThumbnailCache.shared.forget(id)
  }
}

/// Library previews read from disk once per version.
final class ThumbnailCache: @unchecked Sendable {
  static let shared = ThumbnailCache()
  private let cache = NSCache<NSString, UIImage>()

  func image(id: String, version: Int64) -> UIImage? {
    let key = "\(id)/\(version)" as NSString
    if let hit = cache.object(forKey: key) { return hit }
    let url = AppFiles.folders.thumbs.appendingPathComponent("\(id).png")
    guard let img = UIImage(contentsOfFile: url.path) else { return nil }
    cache.setObject(img, forKey: key)
    return img
  }

  func forget(_ id: String) { cache.removeAllObjects() }
}
