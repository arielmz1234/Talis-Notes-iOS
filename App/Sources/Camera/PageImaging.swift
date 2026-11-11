import CoreImage
import TaliCore
import UIKit

/// What the camera does to a picture (Android's `PageImage`): straighten the page out of it and
/// give it a look. Safe off the main thread.
enum PageImaging {
  /// Photos are kept at most this long on their long side.
  static let maxSide: CGFloat = 3000
  /// Shown while cropping and choosing a look.
  static let viewSide: CGFloat = 1600

  private static let context = CIContext()

  /// The page inside [quad] pulled out flat, its sides as long as the longer of each pair.
  static func straightened(_ image: UIImage, _ quad: Quad, maxSide: CGFloat) -> UIImage {
    guard quad != Quad.whole(), let cg = image.cgImage else { return image.scaled(maxSide: maxSide) }
    let w = CGFloat(cg.width), h = CGFloat(cg.height)
    let out = quad.straightenedSize(Float(w), Float(h), maxSide: Float(maxSide))
    // Core Image counts up from the bottom.
    func v(_ p: UnitPt) -> CIVector { CIVector(x: CGFloat(p.x) * w, y: (1 - CGFloat(p.y)) * h) }
    let filter = CIFilter(name: "CIPerspectiveCorrection")!
    filter.setValue(CIImage(cgImage: cg), forKey: kCIInputImageKey)
    filter.setValue(v(quad.tl), forKey: "inputTopLeft")
    filter.setValue(v(quad.tr), forKey: "inputTopRight")
    filter.setValue(v(quad.br), forKey: "inputBottomRight")
    filter.setValue(v(quad.bl), forKey: "inputBottomLeft")
    guard let flat = filter.outputImage else { return image }
    let sized = flat.transformed(by: CGAffineTransform(scaleX: CGFloat(out.width) / flat.extent.width, y: CGFloat(out.height) / flat.extent.height))
    let target = CGRect(x: sized.extent.minX, y: sized.extent.minY, width: CGFloat(out.width).rounded(), height: CGFloat(out.height).rounded())
    guard let result = context.createCGImage(sized, from: target) else { return image }
    return UIImage(cgImage: result)
  }

  static func looked(_ image: UIImage, _ look: Look) -> UIImage {
    guard look != .original, let cg = image.cgImage else { return image }
    let w = cg.width, h = cg.height
    var px = [UInt8](repeating: 0, count: w * h * 4)
    let space = CGColorSpaceCreateDeviceRGB()
    guard let ctx = CGContext(data: &px, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4, space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return image }
    ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
    var out = PageLooks.looked(px, width: w, height: h, look)
    let made = out.withUnsafeMutableBytes { buf -> CGImage? in
      CGContext(data: buf.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4, space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)?.makeImage()
    }
    return made.map { UIImage(cgImage: $0) } ?? image
  }

  /// A photo of a tilted problem sheet on a dark desk under a warm lamp, for UI tests (the simulator
  /// has no camera).
  static func samplePhoto() -> UIImage {
    let size = CGSize(width: 2000, height: 1500)
    let format = UIGraphicsImageRendererFormat()
    format.scale = 1
    return UIGraphicsImageRenderer(size: size, format: format).image { r in
      let cg = r.cgContext
      UIColor(red: 0.24, green: 0.19, blue: 0.15, alpha: 1).setFill()
      cg.fill(CGRect(origin: .zero, size: size))
      let page = UIBezierPath()
      page.move(to: CGPoint(x: 520, y: 170))
      page.addLine(to: CGPoint(x: 1560, y: 250))
      page.addLine(to: CGPoint(x: 1480, y: 1380))
      page.addLine(to: CGPoint(x: 420, y: 1290))
      page.close()
      cg.saveGState()
      page.addClip()
      let colors = [UIColor(red: 0.98, green: 0.95, blue: 0.86, alpha: 1).cgColor, UIColor(red: 0.72, green: 0.66, blue: 0.56, alpha: 1).cgColor]
      let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors as CFArray, locations: [0, 1])!
      cg.drawLinearGradient(gradient, start: CGPoint(x: 600, y: 200), end: CGPoint(x: 1500, y: 1400), options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
      cg.translateBy(x: 520, y: 170)
      cg.rotate(by: 0.077)
      let attrs: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 54, weight: .medium), .foregroundColor: UIColor(red: 0.1, green: 0.15, blue: 0.45, alpha: 1)]
      for (i, line) in ["Problem 3", "A beam 4 m long carries", "a load of 12 kN at its middle.", "Find the reactions R1, R2."].enumerated() {
        (line as NSString).draw(at: CGPoint(x: 90, y: 120 + CGFloat(i) * 110), withAttributes: attrs)
      }
      UIColor(red: 0.1, green: 0.15, blue: 0.45, alpha: 1).setStroke()
      let beam = UIBezierPath(rect: CGRect(x: 160, y: 680, width: 700, height: 50))
      beam.lineWidth = 6
      beam.stroke()
      cg.restoreGState()
    }
  }
}

extension UIImage {
  /// At most [maxSide] pixels on its long side.
  func scaled(maxSide: CGFloat) -> UIImage {
    let w = size.width * scale, h = size.height * scale
    let s = maxSide / max(w, h)
    if s >= 1, imageOrientation == .up { return self }
    let target = CGSize(width: max(1, (w * min(s, 1)).rounded()), height: max(1, (h * min(s, 1)).rounded()))
    let format = UIGraphicsImageRendererFormat()
    format.scale = 1
    return UIGraphicsImageRenderer(size: target, format: format).image { _ in draw(in: CGRect(origin: .zero, size: target)) }
  }

  /// Drawn the way it's meant to be seen (a camera's EXIF turn applied), at most [maxSide] long.
  func upright(maxSide: CGFloat) -> UIImage {
    let w = size.width, h = size.height
    let s = min(maxSide / max(w, h), 1)
    let target = CGSize(width: max(1, (w * s).rounded()), height: max(1, (h * s).rounded()))
    let format = UIGraphicsImageRendererFormat()
    format.scale = 1
    return UIGraphicsImageRenderer(size: target, format: format).image { _ in draw(in: CGRect(origin: .zero, size: target)) }
  }

  /// Turned a quarter clockwise [quarters] times.
  func turned(_ quarters: Int) -> UIImage {
    let q = ((quarters % 4) + 4) % 4
    guard q != 0, let cg = cgImage else { return self }
    let w = CGFloat(cg.width), h = CGFloat(cg.height)
    let out = q % 2 == 0 ? CGSize(width: w, height: h) : CGSize(width: h, height: w)
    let format = UIGraphicsImageRendererFormat()
    format.scale = 1
    return UIGraphicsImageRenderer(size: out, format: format).image { r in
      let c = r.cgContext
      c.translateBy(x: out.width / 2, y: out.height / 2)
      c.rotate(by: CGFloat(q) * .pi / 2)
      c.translateBy(x: -w / 2, y: -h / 2)
      UIImage(cgImage: cg).draw(in: CGRect(x: 0, y: 0, width: w, height: h))
    }
  }
}
