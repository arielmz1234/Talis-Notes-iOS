import Foundation

// Ports of the Android app's `ShapeStyle` (`model/Pen.kt`), the Shapes tool's choice of shape
// (`lastShape`, `buildShape`) and the fill tool's colour (`AppSettings.fillArgb`). Keep them in step.

/// How the Shapes tool draws (Android's `ShapeStyle`; SwiftUI has a `ShapeStyle` of its own), set
/// in its own panel, not borrowed from the pen in use: outline colour, thickness, line style and
/// [opacity], and a fill colour for closed shapes (nil = none) with its own [fillOpacity]. Colours
/// are kept opaque; the opacities are applied when drawing.
public struct ShapeLook: Sendable, Equatable {
  public var color: Int32
  public var size: Float
  public var line: String
  public var fill: Int32?
  public var opacity: Float
  public var fillOpacity: Float

  public static let minSize: Float = 0.5
  public static let maxSize: Float = 12
  public static let minOpacity: Float = 0.1

  /// The line styles, by the names Android stores (`LineStyle`).
  public static let lines = ["SOLID", "DOTTED", "LONG_DASH", "SHORT_DASH", "DOT_DASH", "MIXED_DASH"]

  public init(color: Int32, size: Float, line: String = "SOLID", fill: Int32? = nil, opacity: Float = 1, fillOpacity: Float = 0.5) {
    self.color = color
    self.size = size
    self.line = line
    self.fill = fill
    self.opacity = opacity
    self.fillOpacity = fillOpacity
  }

  public var outlineArgb: Int32 { Self.withOpacity(color, opacity) }

  public var fillArgb: Int32? { fill.map { Self.withOpacity($0, fillOpacity) } }

  public static func withOpacity(_ color: Int32, _ opacity: Float, least: Float = minOpacity) -> Int32 {
    let alpha = UInt32(255 * min(max(opacity, least), 1))
    return Int32(bitPattern: (alpha << 24) | (UInt32(bitPattern: color) & 0x00FF_FFFF))
  }

  /// Drawn like a pen: its colour, size and line, keeping this style's own fill and opacities.
  public func following(color: Int32, size: Float, line: String) -> ShapeLook {
    var out = self
    out.color = Int32(bitPattern: UInt32(bitPattern: color) | 0xFF00_0000)
    out.size = min(max(size, Self.minSize), Self.maxSize)
    out.line = line
    return out
  }

  /// [geometry] as the Shapes tool keeps it: only a closed shape takes the fill.
  public func row(_ geometry: ShapeGeometry) -> ShapeRow {
    ShapeRow(geometry: geometry, pen: "FINELINER", color: outlineArgb, size: size, fill: geometry.closed ? fillArgb : nil, line: line)
  }

  // MARK: JSON (as Android's settings keep it)

  public init?(json o: [String: Any]) {
    guard let color = o["color"] as? NSNumber, let size = o["size"] as? NSNumber else { return nil }
    self.init(
      color: Int32(truncatingIfNeeded: color.int64Value), size: size.floatValue, line: o["line"] as? String ?? "SOLID",
      fill: (o["fill"] as? NSNumber).map { Int32(truncatingIfNeeded: $0.int64Value) }, opacity: (o["opacity"] as? NSNumber)?.floatValue ?? 1,
      fillOpacity: (o["fillOpacity"] as? NSNumber)?.floatValue ?? 0.5)
  }

  public var json: [String: Any] {
    func num(_ f: Float) -> Double { Double("\(f)") ?? Double(f) }
    var o: [String: Any] = ["color": Int(color), "size": num(size)]
    if line != "SOLID" { o["line"] = line }
    if let fill { o["fill"] = Int(fill) }
    if opacity != 1 { o["opacity"] = num(opacity) }
    if fillOpacity != 0.5 { o["fillOpacity"] = num(fillOpacity) }
    return o
  }
}

/// Which shape the Shapes tool draws, as Android's settings keep it in `lastShape`: a standard
/// shape's name, "pack:" and a subject shape's id, or "custom:" and a saved shape's id.
public enum ShapeChoice: Sendable, Equatable {
  case kind(ShapeKind)
  case pack(String)
  case custom(String)

  private static let customPrefix = "custom:"
  private static let packPrefix = "pack:"

  public init(stored: String) {
    if stored.hasPrefix(Self.customPrefix) {
      self = .custom(String(stored.dropFirst(Self.customPrefix.count)))
    } else if stored.hasPrefix(Self.packPrefix), ShapePacks.shape(String(stored.dropFirst(Self.packPrefix.count))) != nil {
      self = .pack(String(stored.dropFirst(Self.packPrefix.count)))
    } else {
      self = .kind(Self.kind(stored))
    }
  }

  /// The standard shape [stored] names (Line when it names none); Square, which is no longer
  /// offered, is the rectangle, which snaps to a square.
  public static func kind(_ stored: String) -> ShapeKind {
    let k = ShapeKind(rawValue: stored) ?? .LINE
    return k == .SQUARE ? .RECTANGLE : k
  }

  public var stored: String {
    switch self {
    case .kind(let k): k.rawValue
    case .pack(let id): Self.packPrefix + id
    case .custom(let id): Self.customPrefix + id
    }
  }

  /// What it draws: her saved shape or the subject's shape when it's still there, otherwise the
  /// standard shape last chosen ([kind]).
  public func source(custom shapes: [CustomShape], kind: ShapeKind) -> ShapeSource {
    switch self {
    case .kind(let k): return .kind(k)
    case .pack(let id): return ShapePacks.shape(id).map(ShapeSource.pack) ?? .kind(kind)
    case .custom(let id): return shapes.first { $0.id == id }.map(ShapeSource.custom) ?? .kind(kind)
    }
  }
}

/// The shape the Shapes tool draws: a standard one, a subject's, or one she saved.
public enum ShapeSource: Sendable {
  case kind(ShapeKind)
  case pack(PackShape)
  case custom(CustomShape)

  /// As drawn from where the pen landed ([p0]) to where it is ([p1]). Anything drawn like a line
  /// keeps to tidy angles, unless [keepEnd] (its end locked onto something).
  public func drawn(_ p0: Pt, _ p1: Pt, keepEnd: Bool = false) -> ShapeGeometry {
    switch self {
    case .kind(let k): return k.drawn(p0, p1, keepEnd: keepEnd)
    case .custom(let shape): return shape.fitInto(p0, p1)
    case .pack(let shape):
      if !keepEnd && shape.drawnAsLine, case let .line(_, end, _, _, _) = ShapeRecognizer.snappedLine(p0, p1) { return shape.create(p0, end) }
      return shape.create(p0, p1)
    }
  }
}

extension ShapeGeometry {
  /// While a rectangle is exactly square or an ellipse exactly round, the two ends of the dotted
  /// line shown across it as it's drawn (corner to corner, or a diameter at 45°), so she can see
  /// it locked on (Android's `drawSquareHint`, `PolyShape.isSquare`, `EllipseShape.round`).
  public var squareHint: (Pt, Pt)? {
    switch self {
    case let .poly(points, true, _, rotation) where points.count == 4:
      let c = Geo.centroid(points)
      let local = points.map { ($0 - c).rotated(-rotation) }
      let w = local.map(\.x).max()! - local.map(\.x).min()!, h = local.map(\.y).max()! - local.map(\.y).min()!
      guard w >= 1e-3, h >= 1e-3, local.allSatisfy({ abs(abs($0.x) - w / 2) < w * 0.02 && abs(abs($0.y) - h / 2) < h * 0.02 }) else { return nil }
      let a = points[0].dist(points[1]), b = points[1].dist(points[2])
      return abs(a - b) < max(a, b) * 0.005 ? (points[0], points[2]) : nil
    case let .ellipse(center, rx, ry, rotation) where abs(rx - ry) < max(rx, ry) * 0.01 && rx > 4:
      func point(_ t: Float) -> Pt { center + Pt(rx * cosf(t), ry * sinf(t)).rotated(rotation) }
      return (point(0.75 * .pi), point(1.75 * .pi))
    default:
      return nil
    }
  }
}

/// The fill tool's colour with its opacity, 0.15 to 1 (Android's `AppSettings.fillArgb`).
public enum FillColour {
  public static let minOpacity: Float = 0.15

  public static func argb(_ color: Int32, opacity: Float) -> Int32 { ShapeLook.withOpacity(color, opacity, least: minOpacity) }
}
