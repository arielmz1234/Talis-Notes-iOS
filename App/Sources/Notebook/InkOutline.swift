import PencilKit
import TaliCore
import UIKit

/// A stroke drawn as lines rather than a picture, so a PDF stays sharp however far it's zoomed
/// (Android's `Exporter.pdf` draws Ink's strokes as paths). Strokes with an `InkLook` (dashes, the
/// highlighter) are filled with the outline the page masks them to; the rest are drawn as wide as
/// PencilKit draws the points `pkStroke` gives it.
extension InkStroke {
  func draw(in cg: CGContext, dark: Bool) {
    let colour = UIColor(argb: dark ? DarkInk.onDarkPaper(color) : color).cgColor
    let points = inputs.points.map { CGPoint(x: CGFloat($0.x), y: CGFloat($0.y)) }
    guard let first = points.first else { return }
    if let look = InkLook(pen: pen, line: line, square: square) {
      cg.addPath(look.outline(size: CGFloat(size), points: points))
      cg.setFillColor(colour)
      cg.fillPath()
      return
    }
    cg.setStrokeColor(colour)
    cg.setLineCap(.round)
    cg.setLineJoin(.round)
    let widths = pieceWidths(points)
    guard !widths.isEmpty else {
      cg.setLineWidth(pointWidth(0))
      cg.addLines(between: [first, CGPoint(x: first.x + 0.01, y: first.y)])
      cg.strokePath()
      return
    }
    // Pieces of about the same width are drawn as one line, so the PDF holds a few lines per stroke.
    var start = 0
    while start < widths.count {
      var end = start
      while end + 1 < widths.count, abs(widths[end + 1] - widths[start]) < 0.05 { end += 1 }
      cg.addPath(InkLook.centre(Array(points[start...(end + 1)])))
      cg.setLineWidth(widths[start...end].reduce(0, +) / CGFloat(end - start + 1))
      cg.strokePath()
      start = end + 1
    }
  }

  /// The size of the [i]th point as `pkStroke` builds it.
  private func pointSize(_ i: Int) -> CGFloat {
    let w = CGFloat(size) * InkWidth.pointStyle(pen.ink).perSize
    return pen.pressureSensitive ? w * (0.55 + 0.9 * CGFloat(inputs.points[i].pressure ?? 0.5)) : w
  }

  /// Nothing is drawn thinner (on screen PencilKit keeps such lines a pixel or so wide).
  private static let hairline: CGFloat = 0.5

  /// How wide PencilKit draws the [i]th point, measured in the simulator from PKDrawing images of
  /// points P wide (covered area over length; the force makes no difference): monoline 2P − 4, the
  /// pencil 1.75P − 0.4. The fountain pen is a nib (see `pieceWidths`); a dot of it is about half.
  private func pointWidth(_ i: Int) -> CGFloat {
    let p = pointSize(i)
    let w: CGFloat =
      switch pen.ink {
      case .pencil: 1.75 * p - 0.4
      case .fountainPen: 0.5 * (p - 2)
      default: 2 * p - 4
      }
    return max(w, Self.hairline)
  }

  /// How wide each piece between two samples is drawn. PencilKit's fountain pen is an elliptical nib
  /// turned to the pen's azimuth, P − 2 from its middle to its ends and a quarter of that across
  /// (measured as above), so a piece is as wide as the nib reaches across its direction.
  private func pieceWidths(_ points: [CGPoint]) -> [CGFloat] {
    guard points.count > 1 else { return [] }
    return (0..<(points.count - 1)).map { i in
      guard pen.ink == .fountainPen else { return (pointWidth(i) + pointWidth(i + 1)) / 2 }
      let reach = max((pointSize(i) + pointSize(i + 1)) / 2 - 2, 0)
      let turn = atan2(points[i + 1].y - points[i].y, points[i + 1].x - points[i].x) - CGFloat(inputs.points[i].orientation ?? 0)
      return max(2 * reach * (sin(turn) * sin(turn) + cos(turn) * cos(turn) / 16).squareRoot(), Self.hairline)
    }
  }
}
