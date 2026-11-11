import CoreGraphics
import TaliCore

/// Ink shaped as Android's brushes shape it, where PencilKit has no ink like it. Such a stroke sits
/// in the drawing as a plain wide stroke of its colour showing through a mask of its outline, so the
/// lasso, undo and the page order treat it like any other stroke. The live layer draws the same
/// outline while it's written, so nothing changes when the pen lifts.
enum InkLook: Equatable {
  case band
  case chisel
  /// Android's line brushes: round pieces of one width whatever the pen, so pressure doesn't show.
  case pieces(LineStyle)

  /// Nil when one of PencilKit's own inks draws the stroke.
  init?(pen: PenType, line: LineStyle, square: Bool) {
    if pen.isHighlighter {
      self = square ? .chisel : .band
    } else if line != .SOLID {
      self = .pieces(line)
    } else {
      return nil
    }
  }

  init?(_ pen: PenSlot) { self.init(pen: pen.type, line: pen.lineStyle, square: pen.square) }

  /// PencilKit draws a monoline point narrower than its size, so the stroke under the mask is this
  /// much wider than the pen to be sure of covering the outline.
  static let coverPerSize: CGFloat = 3
  static let coverExtra: CGFloat = 4

  /// Android's stock highlighter tip with its corners left sharp: a bar the pen's size long and a
  /// quarter of it thick, turned 150° from the x axis towards the y axis, however the pen is held.
  private static let chiselThickness: CGFloat = 0.25
  private static let chiselTurn: CGFloat = 150 * .pi / 180

  func outline(size: CGFloat, points: [CGPoint]) -> CGPath {
    let width = max(size, 0.1)
    switch self {
    case .band:
      return InkLook.centre(points).copy(strokingWithWidth: width, lineCap: .round, lineJoin: .round, miterLimit: 2)
    case .chisel:
      return InkLook.swept(InkLook.chiselTip(width), along: points)
    case .pieces(let line):
      let dashes = line.intervals(width: Float(width)).map { CGFloat($0) }
      return InkLook.centre(points).copy(dashingWithPhase: 0, lengths: dashes).copy(strokingWithWidth: width, lineCap: .round, lineJoin: .round, miterLimit: 2)
    }
  }

  static func centre(_ points: [CGPoint]) -> CGPath {
    let path = CGMutablePath()
    guard let first = points.first else { return path }
    path.move(to: first)
    guard points.count > 1 else {
      path.addLine(to: CGPoint(x: first.x + 0.1, y: first.y))
      return path
    }
    for i in 1..<(points.count - 1) {
      let p = points[i], next = points[i + 1]
      path.addQuadCurve(to: CGPoint(x: (p.x + next.x) / 2, y: (p.y + next.y) / 2), control: p)
    }
    path.addLine(to: points[points.count - 1])
    return path
  }

  private static func chiselTip(_ size: CGFloat) -> [CGPoint] {
    let c = cos(chiselTurn), s = sin(chiselTurn)
    let x = size * chiselThickness / 2, y = size / 2
    return [(-x, -y), (x, -y), (x, y), (-x, y)].map { CGPoint(x: $0.0 * c - $0.1 * s, y: $0.0 * s + $0.1 * c) }
  }

  /// Every piece winds the same way, so the non-zero fill treats their overlaps as one even shape
  /// (pieces winding opposite ways left stripes).
  private static func swept(_ tip: [CGPoint], along points: [CGPoint]) -> CGPath {
    let path = CGMutablePath()
    func at(_ p: CGPoint) -> [CGPoint] { tip.map { CGPoint(x: p.x + $0.x, y: p.y + $0.y) } }
    guard let first = points.first else { return path }
    if points.count == 1 {
      path.addLines(between: hull(at(first)))
      path.closeSubpath()
    }
    for (p, q) in zip(points, points.dropFirst()) {
      path.addLines(between: hull(at(p) + at(q)))
      path.closeSubpath()
    }
    return path
  }

  private static func hull(_ points: [CGPoint]) -> [CGPoint] {
    let sorted = points.sorted { $0.x != $1.x ? $0.x < $1.x : $0.y < $1.y }
    func chain(_ pts: some Sequence<CGPoint>) -> [CGPoint] {
      var out: [CGPoint] = []
      for p in pts {
        while out.count >= 2 {
          let o = out[out.count - 2], a = out[out.count - 1]
          if (a.x - o.x) * (p.y - o.y) - (a.y - o.y) * (p.x - o.x) > 0 { break }
          out.removeLast()
        }
        out.append(p)
      }
      return out
    }
    return chain(sorted).dropLast() + chain(sorted.reversed()).dropLast()
  }
}
