import Foundation

/// Where a selection's chips, its rotate handle and a shape's dots sit on screen, which of them a touch
/// takes, and what dragging them does (Android's `NoteCanvasView`: `resizeChip`, `moveChip`,
/// `rotateHandle`, `handleAt`, `SCALE_SELECTION`, `ROTATE_SELECTION`). Positions are in screen points
/// (Android's dp); the drags are in world units.
public enum SelectionHandles {
  /// How near a chip, the rotate handle or a dot a touch has to land.
  public static let hit: Float = 24
  /// The least a shape's dot reaches, however small the shape.
  static let minHit: Float = 9
  /// A shape smaller than this on screen shows no dots: zoomed in, they come back.
  public static let tinyShape: Float = 32
  /// How far the selection's frame stands off what's picked up.
  public static let pad: Float = 8
  static let chipOffset: Float = 14
  static let rotateDrop: Float = 30
  /// How close a turn has to come to a 45° step to snap onto it (5°).
  static let snapTurn: Float = 0.087

  /// The resize chip sits just off the frame's bottom-right corner, clear of a shape's own corner dot.
  public static func resizeChip(_ frame: Rect) -> Pt { Pt(frame.right + chipOffset, frame.bottom + chipOffset) }

  /// The move chip mirrors it at the bottom-left.
  public static func moveChip(_ frame: Rect) -> Pt { Pt(frame.left - chipOffset, frame.bottom + chipOffset) }

  /// The rotate handle hangs below the middle of the frame, and lower still when one of the shape's
  /// own [dots] sits under the middle, so the two never sit on each other.
  public static func rotateHandle(_ frame: Rect, dots: [Pt] = []) -> Pt {
    var y = frame.bottom + rotateDrop
    let under = dots.filter { abs($0.x - frame.center.x) < hit * 1.5 && $0.y > frame.bottom - hit }.map(\.y).max()
    if let under { y = max(y, under + rotateDrop) }
    return Pt(frame.center.x, y)
  }

  /// How big a shape is on screen for sizing its dots: the length of a line, arc or curve, the
  /// shorter side of anything else.
  public static func shapeSize(_ g: ShapeGeometry, on screen: Rect) -> Float {
    switch g {
    case .line, .arc, .curve: max(screen.width, screen.height)
    default: min(screen.width, screen.height)
    }
  }

  /// Smaller dots on a small shape, so they don't cover it.
  public static func dotRadius(shapeSize: Float) -> Float { min(max(shapeSize * 0.12, 4.5), 6.5) }

  /// The dot under [touch], or nil. Dots reach less far on a small shape; a touch on the shape that's
  /// nearer its middle than the nearest dot moves the shape instead; and a chip nearer than the dot
  /// takes the touch. [area] is the shape's frame on screen.
  public static func dot(at touch: Pt, dots: [Pt], shapeSize: Float, area: Rect, chips: [Pt]) -> Int? {
    if dots.isEmpty || shapeSize < tinyShape { return nil }
    let dists = dots.map { $0.dist(touch) }
    guard let i = dists.indices.min(by: { dists[$0] < dists[$1] }) else { return nil }
    let reach = min(max(shapeSize * 0.3, minHit), hit)
    if dists[i] >= reach { return nil }
    if area.contains(touch) && area.center.dist(touch) < dists[i] { return nil }
    if chips.contains(where: { $0.dist(touch) < dists[i] }) { return nil }
    return i
  }

  /// The resize chip dragged from [start] to [now]: everything scales evenly about the top-left of
  /// [bounds], between a tenth and ten times, and never down to nothing.
  public static func scale(_ bounds: Rect, from start: Pt, to now: Pt) -> Affine {
    let anchor = Pt(bounds.left, bounds.top), corner = Pt(bounds.right, bounds.bottom)
    let s = min(max(now.dist(anchor) / max(1, start.dist(anchor)), 0.1), 10)
    if corner.dist(anchor) * s < 4 { return .identity }
    return .scaleAround(anchor, s)
  }

  /// How far the rotate handle dragged from [start] to [now] turns the selection about [pivot]. It
  /// snaps to 45° steps when close, by the way the selection faces on the page ([facing] when the
  /// turn began), so it lands level, upright or diagonal however it started.
  public static func turn(about pivot: Pt, from start: Pt, to now: Pt, facing: Float) -> Float {
    var angle = (now - pivot).angle() - (start - pivot).angle()
    let step = Float.pi / 4
    let snapped = javaRound((facing + angle) / step) * step - facing
    if abs(angle - snapped) < snapTurn { angle = snapped }
    return angle
  }

  /// The angle shown while turning: counter-clockwise is positive, as in maths class. A line reads
  /// 0...179, anything else -180...179.
  public static func turnDegrees(_ facing: Float, line: Bool) -> Int {
    let d = Int((-Double(facing) * 180 / .pi + 0.5).rounded(.down))
    func floorMod(_ a: Int, _ n: Int) -> Int { ((a % n) + n) % n }
    return line ? floorMod(d, 180) : floorMod(d + 180, 360) - 180
  }
}

extension ShapeGeometry {
  /// Which way it faces on the page (radians, y down), or nil when it has no way of its own.
  public var facing: Float? {
    switch self {
    case let .line(a, b, _, _, _): (b - a).angle()
    // Level with its arrows hanging down is 0°.
    case let .load(a, b, depth, _): (b - a).angle() + (depth < 0 ? .pi : 0)
    case let .poly(_, _, _, rotation, _): rotation
    case let .ellipse(_, _, _, rotation, _): rotation
    case let .triangle(_, _, _, turn): turn
    case let .group(_, turn): turn
    case let .curve(points): points.count > 1 ? (points[points.count - 1] - points[0]).angle() : nil
    case .arc, .sector, .param: nil
    }
  }
}

/// The measuring badges beside a line, arc, circle, part circle or triangle being changed or showing
/// its dots (Android's `drawMeasure`, `measureLine`, `clearSpot`): what they say and where they sit,
/// clear of the pen, the chips and the dots.
public enum Measure {
  public static let badgeHeight: Float = 24

  public struct Badge: Equatable, Sendable {
    public var label: String
    public var at: Pt
  }

  public enum Phase: Equatable, Sendable {
    /// Just showing its dots; [frame] is the selection's frame on screen.
    case idle(frame: Rect)
    /// Being drawn, or dot [dot] being dragged.
    case changing(dot: Int?)
  }

  private static func fixed(_ v: Float) -> String { String(format: "%.1f", locale: Locale(identifier: "en_US_POSIX"), Double(v)) }

  /// World units as centimetres at print size (a unit prints at 72/160 pt).
  public static func cm(_ world: Float) -> String { fixed(world * 2.54 / 160) }

  /// A line's angle from level (counter-clockwise, 0...179) and its printed length.
  public static func line(_ a: Pt, _ b: Pt) -> String? {
    let v = b - a
    if v.length() < 1 { return nil }
    var degrees = Int((-Double(atan2f(v.y, v.x)) * 180 / .pi + 0.5).rounded(.down))
    if degrees < 0 { degrees += 180 }
    if degrees == 180 { degrees = 0 }
    return "\(degrees)°  ·  \(fixed(a.dist(b) * (72 / 160) / 72 * 2.54)) cm"
  }

  /// The badges for [g]. [toScreen] maps world to screen and [width] says how wide a badge with that
  /// label is.
  public static func badges(_ g: ShapeGeometry, _ phase: Phase, toScreen: (Pt) -> Pt, width: (String) -> Float) -> [Badge] {
    let h = badgeHeight
    switch g {
    case let .line(a, b, _, _, _): return lineBadge(a, b, phase, toScreen, width)
    // A distributed load reads like its line: how steep it is and how long.
    case let .load(a, b, _, _): return lineBadge(a, b, phase, toScreen, width)
    case let .arc(center, radius, _, _, arrowEnd):
      return arrowEnd ? [] : [Badge(label: "\(g.arcDegrees)°  ·  r \(cm(radius)) cm", at: toScreen(center))]
    case let .ellipse(center, rx, _, _, _):
      guard g.isCircle else { return [] }
      // The diameter is twice the radius as shown, so the two always agree (3.0 and 6.0, not 6.1).
      let r = cm(rx)
      let label = "r \(r) cm  ·  ⌀ \(fixed((Float(r) ?? 0) * 2)) cm"
      // Beside the middle of its radius line, on the upper side.
      let c = toScreen(center), e = toScreen(g.ellipsePoint(0))
      let n = upper((e - c).normalized())
      let off = abs(n.x) * width(label) / 2 + abs(n.y) * h / 2 + 8
      return [Badge(label: label, at: (c + e) * 0.5 + n * off)]
    case .triangle:
      // Each corner's angle, just inside the corner, while it's being drawn or reshaped.
      guard case .changing = phase else { return [] }
      let corners = g.handles().map(toScreen)
      let mid = (corners[0] + corners[1] + corners[2]) / 3
      return zip(corners, g.triangleAngles).map { corner, angle in
        let v = mid - corner
        return Badge(label: "\(Int(javaRound(angle)))°", at: corner + v.normalized() * min(v.length() * 0.55, 46))
      }
    case let .sector(center, radius, start, sweep):
      let f = g.sectorFraction
      let label = "\(Int(javaRound(f * 100)))%  ·  \(Int(javaRound(f * 360)))°  ·  r \(cm(radius)) cm"
      let c = toScreen(center)
      if f > 0.6 { return [Badge(label: label, at: c)] }
      // The centre is a corner of the slice: sit just behind it, away from the curve.
      let away = Pt.polar(1, start + sweep / 2) * -1
      let off = abs(away.x) * width(label) / 2 + abs(away.y) * h / 2 + 10
      return [Badge(label: label, at: c + away * off)]
    default: return []
    }
  }

  /// The side of a line that faces up the screen.
  private static func upper(_ dir: Pt) -> Pt {
    let n = Pt(-dir.y, dir.x)
    return n.y > 0 || (n.y == 0 && n.x > 0) ? n * -1 : n
  }

  private static func lineBadge(_ ga: Pt, _ gb: Pt, _ phase: Phase, _ toScreen: (Pt) -> Pt, _ width: (String) -> Float) -> [Badge] {
    guard let label = line(ga, gb) else { return [] }
    let w = width(label), h = badgeHeight
    if case let .idle(frame) = phase {
      // The menu is above and the chips and rotate handle below, so it sits under all of them.
      return [Badge(label: label, at: Pt(frame.center.x, frame.bottom + 64))]
    }
    let startMoving = phase == .changing(dot: 0)
    let a = toScreen(startMoving ? gb : ga), m = toScreen(startMoving ? ga : gb)
    let dir = (m - a).normalized()
    if a.dist(m) < w + 90 {
      // Short: just past the end that isn't moving, on the far side from the pen.
      let reach = abs(dir.x) * w / 2 + abs(dir.y) * h / 2 + 14
      return [Badge(label: label, at: a - dir * reach)]
    }
    let n = upper(dir)
    let off = abs(n.x) * w / 2 + abs(n.y) * h / 2 + 10
    return [Badge(label: label, at: (a + m) * 0.5 + n * off)]
  }

  /// Where a [w]×[h] badge wanted at [want] goes: there, unless it would cover one of [avoid] (a chip
  /// or a dot, with its radius) or the [menu], then the nearest clear place around it, sideways first.
  /// Always on a screen [screen] big.
  public static func clearSpot(_ want: Pt, w: Float, h: Float, screen: (w: Float, h: Float), avoid: [(at: Pt, radius: Float)], menu: Rect?) -> Pt {
    func onScreen(_ p: Pt) -> Pt {
      Pt(min(max(p.x, w / 2 + 4), max(screen.w - w / 2 - 4, w / 2 + 4)), min(max(p.y, h / 2 + 4), max(screen.h - h / 2 - 4, h / 2 + 4)))
    }
    func clear(_ p: Pt) -> Bool {
      let box = Rect(p.x - w / 2, p.y - h / 2, p.x + w / 2, p.y + h / 2)
      if let menu, menu.intersects(box) { return false }
      return !avoid.contains { c, radius in
        let nearest = Pt(min(max(c.x, box.left), box.right), min(max(c.y, box.top), box.bottom))
        return c.dist(nearest) < radius + 3
      }
    }
    let first = onScreen(want)
    if avoid.isEmpty || clear(first) { return first }
    let dirs: [Pt] = [Pt(-1, 0), Pt(1, 0), Pt(-0.7, 0.7), Pt(0.7, 0.7), Pt(-0.7, -0.7), Pt(0.7, -0.7), Pt(0, 1), Pt(0, -1)]
    for step in 1...10 {
      for d in dirs {
        let p = onScreen(want + d * (Float(step) * 12))
        if clear(p) { return p }
      }
    }
    return first
  }
}
