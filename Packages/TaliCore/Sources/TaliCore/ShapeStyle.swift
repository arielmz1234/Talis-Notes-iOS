import Foundation

/// How the Shapes tool draws, set in its own panel (Android's `ShapeStyle`): outline colour,
/// thickness, line style and [opacity], and a fill colour for closed shapes (nil = none) with its
/// own [fillOpacity]. Colours are kept opaque; the opacities are applied when drawing. Stored with
/// Android's field names, so settings read the same on both.
public struct ShapeStyle: Codable, Equatable, Sendable {
  public var color: Int32
  public var size: Float
  public var line: String
  public var fill: Int32?
  public var opacity: Float
  public var fillOpacity: Float

  public static let minSize: Float = 0.5
  public static let maxSize: Float = 12
  public static let minOpacity: Float = 0.1

  public init(color: Int32, size: Float, line: String = "SOLID", fill: Int32? = nil, opacity: Float = 1, fillOpacity: Float = 0.5) {
    self.color = color
    self.size = size
    self.line = line
    self.fill = fill
    self.opacity = opacity
    self.fillOpacity = fillOpacity
  }

  // Missing keys take their defaults, as kotlinx.serialization does.
  public init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    color = try c.decode(Int32.self, forKey: .color)
    size = try c.decode(Float.self, forKey: .size)
    line = try c.decodeIfPresent(String.self, forKey: .line) ?? "SOLID"
    fill = try c.decodeIfPresent(Int32.self, forKey: .fill)
    opacity = try c.decodeIfPresent(Float.self, forKey: .opacity) ?? 1
    fillOpacity = try c.decodeIfPresent(Float.self, forKey: .fillOpacity) ?? 0.5
  }

  /// The outline colour with its opacity.
  public var outlineArgb: Int32 { Self.withOpacity(color, opacity) }

  /// The fill with its opacity, or nil for none.
  public var fillArgb: Int32? { fill.map { Self.withOpacity($0, fillOpacity) } }

  /// [color] with its alpha set from [opacity] (at least `minOpacity`), as Android's `withOpacity`.
  public static func withOpacity(_ color: Int32, _ opacity: Float) -> Int32 {
    let a = UInt32(Int(255 * min(max(opacity, minOpacity), 1)))
    return Int32(bitPattern: (a << 24) | (UInt32(bitPattern: color) & 0x00FF_FFFF))
  }

  /// The Shapes tool's own style, before she sets one: the first pen's starting colour and 2.4.
  public static func own(_ saved: ShapeStyle?, firstColor: Int32) -> ShapeStyle {
    saved ?? ShapeStyle(color: firstColor, size: 2.4)
  }

  /// How the Shapes tool draws (Android's `shapeLook`): its own style; or, following the pen, the
  /// pen's colour, size (kept within the shape range) and line, keeping its own fill and opacities.
  public static func look(own: ShapeStyle, followsPen: Bool, penColor: Int32, penSize: Float, penLine: String = "SOLID") -> ShapeStyle {
    guard followsPen else { return own }
    var s = own
    s.color = Int32(bitPattern: UInt32(bitPattern: penColor) | 0xFF00_0000)
    s.size = min(max(penSize, minSize), maxSize)
    s.line = penLine
    return s
  }
}
