import Foundation

/// Which pen types a tool acts on (Android's `eraserAffects` and `lassoAffects`): every type until
/// it's switched off, stored as Android stores it, a map from the pen's name to on or off.
public struct PenFilter: Equatable, Sendable {
  public var choices: [String: Bool]

  public init(_ choices: [String: Bool] = [:]) { self.choices = choices }

  public func hits(_ pen: PenType) -> Bool { choices[pen.rawValue] != false }

  public mutating func set(_ pen: PenType, _ on: Bool) { choices[pen.rawValue] = on }
}

/// The eraser (Android's `EraserMode` and `eraseSegment`).
public enum Eraser {
  public enum Mode: String, Sendable {
    /// Removes whole strokes and shapes it touches.
    case STROKE
    /// Erases only where it passes, splitting strokes.
    case AREA
  }

  public enum Hit: Equatable, Sendable {
    case missed
    case whole
    /// What's left of the stroke; none when all of it was rubbed out.
    case pieces([InkInputs])
  }

  /// What the eraser does to a stroke [size] thick as it sweeps from [a] to [b], reaching [radius]
  /// either side. The stroke's own thickness counts: its edge is erased, not only its middle line.
  public static func hit(_ inputs: InkInputs, size: Float, mode: Mode, from a: Pt, to b: Pt, radius: Float) -> Hit {
    let reach = radius + size * 0.5
    guard let box = inputs.bounds, let swept = Rect.around([a, b]), box.outset(reach).intersects(swept.outset(0.01)) else { return .missed }
    switch mode {
    case .STROKE:
      return StrokeCut.touches(inputs.points.map { Pt($0.x, $0.y) }, a, b, reach: reach) ? .whole : .missed
    case .AREA:
      guard let left = StrokeCut.split(inputs, maxGap: max(0.5, radius / 2), erased: { x, y in Geo.distToSegment(Pt(x, y), a, b) <= reach }) else { return .missed }
      return .pieces(left)
    }
  }
}

/// Pen samples that follow a polyline exactly, keeping every corner (Android's
/// `StrokeFactory.strokeAlong`): a sample every few units at a slow, even pen speed.
public enum StrokeAlong {
  static let speed: Float = 0.08
  static let spacing: Float = 3

  public static func inputs(_ path: [Pt]) -> InkInputs {
    var points: [InkInput] = []
    var millis: Int64 = 0
    var carry: Float = 0
    var last: Pt?
    func add(_ p: Pt) {
      if let prev = last {
        if prev.dist(p) < 0.05 { return }
        carry += prev.dist(p) / speed
        let dt = Int64(carry)
        carry -= Float(dt)
        millis += dt
      }
      points.append(InkInput(x: p.x, y: p.y, t: Float(millis) / 1000, pressure: 0.55))
      last = p
    }
    for (a, b) in zip(path, path.dropFirst()) {
      let n = max(Int((a.dist(b) / spacing).rounded(.up)), 1)
      for k in 0..<n { add(a + (b - a) * (Float(k) / Float(n))) }
    }
    if let end = path.last { add(end) }
    return InkInputs(points: points, tool: .stylus)
  }
}
