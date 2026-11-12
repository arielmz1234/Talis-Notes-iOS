import PencilKit
import UIKit

/// Covered area of [cg] (alpha summed), in square world units at [scale].
func area(_ cg: CGImage, scale: CGFloat) -> CGFloat {
  let w = cg.width, h = cg.height
  var buf = [UInt8](repeating: 0, count: w * h * 4)
  let ctx = CGContext(data: &buf, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
  ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
  var a: CGFloat = 0
  for i in stride(from: 3, to: buf.count, by: 4) { a += CGFloat(buf[i]) / 255 }
  return a / (scale * scale)
}

func lines(_ s: InkStroke, _ box: CGRect, scale: CGFloat) -> CGImage {
  let w = Int(box.width * scale), h = Int(box.height * scale)
  let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
  ctx.translateBy(x: 0, y: CGFloat(h))
  ctx.scaleBy(x: scale, y: -scale)
  ctx.translateBy(x: -box.minX, y: -box.minY)
  s.draw(in: ctx, dark: false)
  return ctx.makeImage()!
}

let scale: CGFloat = 10
for pen in [PenType.FINELINER, .FOUNTAIN, .CALLIGRAPHY, .PENCIL, .HIGHLIGHTER] {
  for size: Float in [2.4, 4, 8] {
    for (pressure, azimuth) in [(Float(0.3), Float(0.2)), (0.6, 0.9), (0.95, 2.4)] {
      for shape in ["line", "circle", "wave"] {
        let pts = (0...160).map { i -> InkInput in
          let t = Float(i) / 160
          let (x, y): (Float, Float) =
            switch shape {
            case "circle": (100 + 60 * cos(t * 2 * .pi), 100 + 60 * sin(t * 2 * .pi))
            case "wave": (20 + 160 * t, 100 + 30 * sin(t * 4 * .pi))
            default: (20 + 160 * t, 100 + 20 * t)
            }
          return InkInput(x: x, y: y, t: t * 1.2, pressure: pressure, tilt: 0.4, orientation: azimuth)
        }
        let s = InkStroke(id: "", z: 0, pen: pen, color: Int32(bitPattern: 0xFF00_0000), size: size, inputs: InkInputs(points: pts, tool: .stylus))
        let box = CGRect(s.bounds).insetBy(dx: -8, dy: -8)
        let page = area(PKDrawing(strokes: [s.pkStroke(mask: nil)]).image(from: box, scale: scale).cgImage!, scale: scale)
        let pdf = area(lines(s, box, scale: scale), scale: scale)
        print("\(pen) \(size) \(shape) pressure \(pressure) azimuth \(azimuth):", String(format: "PDF / page %.2f", pdf / max(page, 0.001)))
      }
    }
  }
}
