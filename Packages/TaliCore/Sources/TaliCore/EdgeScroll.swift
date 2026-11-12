import Foundation

/// Scrolling the page while something is carried to a screen edge (Android's `edgeVelocity` and
/// `edgeStep`): nothing outside the edge zones, then a gentle ramp the deeper into a zone it goes,
/// and only once it has rested there a moment (passing an edge on the way somewhere doesn't scroll).
public struct EdgeScroll: Sendable, Equatable {
  /// How close to an edge, in screen points, the carried thing starts the page scrolling.
  public var zone: Float
  /// How long it must rest in a zone first, in seconds.
  public var dwell: Double
  private var since: Double?
  private var lastFrame: Double?

  /// A picked-up selection, and a voice memo: a deeper zone and a shorter wait for the memo (it's a
  /// small button, held by a fingertip).
  public static let selection = EdgeScroll(zone: 100, dwell: 0.12)
  public static let memo = EdgeScroll(zone: 140, dwell: 0.06)

  /// The fastest scroll, deep in a zone, in points per second.
  public static let fastest: Float = 900

  public init(zone: Float, dwell: Double) {
    self.zone = zone
    self.dwell = dwell
  }

  /// Points per second to scroll (in the direction to look) with the carried thing at [p] on a
  /// screen of [screen]. The top zone reaches at least a little below the toolbars ([topClearance]).
  public func velocity(at p: Pt, screen: Pt, topClearance: Float) -> Pt {
    let top = max(zone, topClearance + 20)
    func push(_ dist: Float, _ z: Float) -> Float {
      let t = min(max((z - dist) / z, 0), 1)
      return t * t
    }
    return Pt((push(screen.x - p.x, zone) - push(p.x, zone)) * Self.fastest, (push(screen.y - p.y, zone) - push(p.y, top)) * Self.fastest)
  }

  /// One frame at [now] (seconds) with the carried thing at [p]: how far to scroll this frame.
  public mutating func step(now: Double, at p: Pt, screen: Pt, topClearance: Float) -> Pt {
    defer { lastFrame = now }
    let v = velocity(at: p, screen: screen, topClearance: topClearance)
    guard v != .zero else {
      since = nil
      return .zero
    }
    let start = since ?? now
    since = start
    guard now - start >= dwell, let last = lastFrame else { return .zero }
    return v * Float(min(now - last, 0.032))
  }
}
