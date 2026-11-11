import Foundation

/// Pulling up past the last page to add one (Android's `pulling`, `effectivePull`, `finishPull`).
/// Every length is in points on screen, measured as how far below the last page the screen reaches.
/// A pull only counts when the fingers land with the notebook already at its end, and only from
/// there: whatever already showed below the last page (zoomed out, it can be a lot) isn't a pull.
public struct PagePull: Equatable, Sendable {
  /// The room always left under the last page.
  public static let rest: Float = 32
  /// How far it can be pulled.
  public static let most: Float = 210
  /// Let go past this and a page is added.
  public static let adds: Float = 150

  public private(set) var pulling = false
  private var offset: Float = 0

  public init() {}

  public enum Sign: Equatable, Sendable {
    case drag(alpha: Float)
    case release(alpha: Float)

    public var alpha: Float {
      switch self {
      case .drag(let a), .release(let a): a
      }
    }
  }

  public enum Release: Equatable, Sendable {
    /// Not a pull (or not past the room that's always there).
    case none
    case addPage
    case springBack
  }

  /// Fingers landed with the screen reaching [below] past the last page.
  public mutating func begin(below: Float, allowed: Bool = true) {
    pulling = allowed && below >= PagePull.rest - 4
    offset = pulling ? max(0, below - PagePull.rest) : 0
  }

  /// The fingers zoomed: from now on this gesture is no pull.
  public mutating func cancel() { pulling = false }

  public func pull(below: Float) -> Float { below - offset }

  /// The small sign under the last page while pulling: "Drag for a new page", then "Release to add a page".
  public func sign(below: Float) -> Sign? {
    guard pulling else { return nil }
    let p = pull(below: below)
    guard p >= PagePull.rest + 6 else { return nil }
    let alpha = min(max((p - PagePull.rest - 6) / 40, 0), 1)
    return p >= PagePull.adds ? .release(alpha: alpha) : .drag(alpha: alpha)
  }

  /// The fingers left: far enough adds a page, otherwise it springs back.
  public mutating func end(below: Float) -> Release {
    defer { pulling = false }
    guard pulling else { return .none }
    let p = pull(below: below)
    if p <= PagePull.rest + 1 { return .none }
    return p >= PagePull.adds ? .addPage : .springBack
  }
}
