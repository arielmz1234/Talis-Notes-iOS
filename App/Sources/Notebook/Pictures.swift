import ImageIO
import TaliCore
import UIKit

/// A picture on the page with its image, as the page layer draws it.
struct PlacedPicture: @unchecked Sendable {
  var row: PictureRow
  var image: CGImage
  var rect: CGRect { CGRect(row.rect) }
}

/// A picture item (kind 2) with its image, read from the app's images folder at a size that suits
/// the page (a PDF page or photo is never decoded at full size).
func picture(from row: ItemRow) -> PlacedPicture? {
  guard let p = PictureRow(row) else { return nil }
  return placed(p)
}

func placed(_ p: PictureRow) -> PlacedPicture? {
  pictureImage(p, pixelsPerUnit: 2, cap: 2400).map { PlacedPicture(row: p, image: $0) }
}

/// The part of [p]'s picture that shows (its crop), decoded at about [pixelsPerUnit] pixels per world
/// unit on the page and at most [cap] on the whole picture's long side; nil keeps every pixel.
func pictureImage(_ p: PictureRow, pixelsPerUnit: CGFloat?, cap: CGFloat? = nil) -> CGImage? {
  guard !p.file.contains("/"), p.rect.width > 0, p.rect.height > 0 else { return nil }
  let url = AppFiles.folders.images.appendingPathComponent(p.file)
  guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
  var opts: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceCreateThumbnailWithTransform: true]
  if let pixelsPerUnit {
    let whole = p.whole
    let side = CGFloat(max(whole.width, whole.height)) * pixelsPerUnit
    opts[kCGImageSourceThumbnailMaxPixelSize] = max(min(side, cap ?? side), 1)
  }
  guard let image = CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary) else { return nil }
  guard let c = p.crop else { return image }
  let w = CGFloat(image.width), h = CGFloat(image.height)
  let part = CGRect(x: CGFloat(c.left) * w, y: CGFloat(c.top) * h, width: CGFloat(c.width) * w, height: CGFloat(c.height) * h).integral
  return image.cropping(to: part) ?? image
}
