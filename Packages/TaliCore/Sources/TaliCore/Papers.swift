import Foundation

/// A paper she made herself (Android's `model/CustomPaper.kt`), kept in settings in Android's JSON
/// shape: a picture filling each A4 page, or a pattern at her own spacing and colours.
public struct CustomPaper: Codable, Hashable, Sendable, Identifiable {
  public var id: String
  public var name: String
  /// A file in the app's images folder, or nil for a designed pattern.
  public var image: String?
  public var pattern: PaperStyle
  public var spacingMm: Float
  public var lineColor: Int32
  public var paperColor: Int32
  /// A school-notebook margin line down the left of each page.
  public var margin: Bool
  /// How strongly the lines (or the picture) show, 0.15...1.
  public var opacity: Float
  /// Its own line thickness; nil follows the app-wide one.
  public var lineWeight: Float?

  /// How a notebook's paper column names one of these.
  public static let prefix = "custom:"

  public init(
    id: String, name: String, image: String? = nil, pattern: PaperStyle = .LINES, spacingMm: Float = 8, lineColor: Int32 = Int32(bitPattern: 0xFFDA_DADA),
    paperColor: Int32 = Int32(bitPattern: 0xFFFF_FFFF), margin: Bool = false, opacity: Float = 1, lineWeight: Float? = nil
  ) {
    self.id = id
    self.name = name
    self.image = image
    self.pattern = pattern
    self.spacingMm = spacingMm
    self.lineColor = lineColor
    self.paperColor = paperColor
    self.margin = margin
    self.opacity = opacity
    self.lineWeight = lineWeight
  }

  public init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    let d = CustomPaper(id: try c.decode(String.self, forKey: .id), name: try c.decode(String.self, forKey: .name))
    self.init(
      id: d.id, name: d.name, image: try c.decodeIfPresent(String.self, forKey: .image),
      pattern: (try? c.decodeIfPresent(PaperStyle.self, forKey: .pattern)) ?? d.pattern,
      spacingMm: try c.decodeIfPresent(Float.self, forKey: .spacingMm) ?? d.spacingMm,
      lineColor: try c.decodeIfPresent(Int32.self, forKey: .lineColor) ?? d.lineColor,
      paperColor: try c.decodeIfPresent(Int32.self, forKey: .paperColor) ?? d.paperColor,
      margin: try c.decodeIfPresent(Bool.self, forKey: .margin) ?? d.margin,
      opacity: try c.decodeIfPresent(Float.self, forKey: .opacity) ?? d.opacity,
      lineWeight: try c.decodeIfPresent(Float.self, forKey: .lineWeight))
  }

  /// [argb] with its alpha scaled by the paper's opacity.
  public func faded(_ argb: Int32) -> Int32 {
    let u = UInt32(bitPattern: argb)
    let a = min(max(Int(Float(u >> 24) * min(max(opacity, 0.15), 1)), 0), 255)
    return Int32(bitPattern: UInt32(a) << 24 | (u & 0x00FF_FFFF))
  }
}

/// A built-in paper's own colours, set on its edit card (nil keeps the usual ones).
public struct PaperLook: Codable, Hashable, Sendable {
  public var line: Int32?
  public var paper: Int32?

  public init(line: Int32? = nil, paper: Int32? = nil) {
    self.line = line
    self.paper = paper
  }

  public var isEmpty: Bool { line == nil && paper == nil }
}

/// How heavy paper lines are drawn (1 is standard): the card's five choices.
public enum PaperWeight {
  public static let choices: [Float] = [0.6, 1, 2, 3.5, 5]

  public static func nearest(_ v: Float) -> Float { choices.min { abs($0 - v) < abs($1 - v) } ?? 1 }

  /// What a paper is drawn at: hers by its own setting, a built-in one by its card, else the app-wide one.
  public static func of(_ style: PaperStyle, custom: CustomPaper?, weights: [String: Float], fallback: Float) -> Float {
    if let custom { return custom.lineWeight ?? fallback }
    return weights[style.rawValue] ?? fallback
  }
}

/// The colours a paper is drawn in, as ARGB (Android's `PaperRenderer` fields): quiet light grey on
/// white, or near-black with a hint of plum and dimmed lines on dark paper.
public struct PaperTones: Equatable, Sendable {
  public var paper: UInt32
  public var line: UInt32
  public var blueLine: UInt32
  public var minor: UInt32
  public var major: UInt32
  public var margin: UInt32

  public static let darkPaper: UInt32 = 0xFF1C_1A23

  /// Her colours for a built-in paper apply on light paper only.
  public static func of(dark: Bool, look: PaperLook? = nil) -> PaperTones {
    var t =
      dark
      ? PaperTones(paper: darkPaper, line: 0xFF5E_5C66, blueLine: 0xFF40_3E48, minor: 0xFF2A_2931, major: 0xFF4A_4852, margin: 0x99E0_7A90)
      : PaperTones(paper: 0xFFFF_FFFF, line: 0xFFC4_C4C4, blueLine: 0xFFDA_DADA, minor: 0xFFED_EDED, major: 0xFFCF_CFCF, margin: 0xFFF0_A0B4)
    guard !dark, let look else { return t }
    if let l = look.line.map({ UInt32(bitPattern: $0) }) {
      t.line = l
      t.blueLine = l
      t.major = l
      t.minor = (l & 0x00FF_FFFF) | (UInt32(Float(l >> 24) * 0.45) << 24)
    }
    if let p = look.paper { t.paper = UInt32(bitPattern: p) }
    return t
  }

  /// Her own pattern's line colour: on dark paper lightened like ink and see-through, then faded.
  public static func customLine(_ cp: CustomPaper, dark: Bool) -> UInt32 {
    let base = dark ? Int32(bitPattern: (UInt32(bitPattern: DarkInk.onDarkPaper(cp.lineColor)) & 0x00FF_FFFF) | 0x7000_0000) : cp.lineColor
    return UInt32(bitPattern: cp.faded(base))
  }

  /// Her own paper's margin line.
  public static func customMargin(_ cp: CustomPaper, dark: Bool) -> UInt32 {
    UInt32(bitPattern: cp.faded(Int32(bitPattern: dark ? 0x99E0_7A90 : 0xFFF0_A0B4)))
  }
}

/// How a colour shows on dark paper (Android's `Brushes.onDarkPaper`): dark inks flip to their light
/// counterpart with the same hue, and every colour is lifted enough to read on black. Alpha is kept.
public enum DarkInk {
  public static func onDarkPaper(_ argb: Int32) -> Int32 {
    let u = UInt32(bitPattern: argb)
    var (h, s, l) = hsl(u)
    l = min(max(l < 0.5 ? 1 - l : l, 0.62), 0.9)
    return Int32(bitPattern: (rgb(h, s, l) & 0x00FF_FFFF) | (u & 0xFF00_0000))
  }

  /// androidx `ColorUtils.colorToHSL`.
  static func hsl(_ argb: UInt32) -> (Float, Float, Float) {
    let r = Float((argb >> 16) & 0xFF) / 255, g = Float((argb >> 8) & 0xFF) / 255, b = Float(argb & 0xFF) / 255
    let mx = max(r, g, b), mn = min(r, g, b), delta = mx - mn
    let l = (mx + mn) / 2
    var h: Float = 0, s: Float = 0
    if mx != mn {
      if mx == r {
        h = ((g - b) / delta).truncatingRemainder(dividingBy: 6)
      } else if mx == g {
        h = (b - r) / delta + 2
      } else {
        h = (r - g) / delta + 4
      }
      s = delta / (1 - abs(2 * l - 1))
    }
    h = (h * 60).truncatingRemainder(dividingBy: 360)
    if h < 0 { h += 360 }
    return (min(max(h, 0), 360), min(max(s, 0), 1), min(max(l, 0), 1))
  }

  /// androidx `ColorUtils.HSLToColor`, as opaque RGB.
  static func rgb(_ h: Float, _ s: Float, _ l: Float) -> UInt32 {
    let c = (1 - abs(2 * l - 1)) * s
    let m = l - 0.5 * c
    let x = c * (1 - abs((h / 60).truncatingRemainder(dividingBy: 2) - 1))
    func v(_ f: Float) -> UInt32 { UInt32(min(max((255 * f).rounded(), 0), 255)) }
    let (r, g, b): (Float, Float, Float)
    switch Int(h) / 60 {
    case 0: (r, g, b) = (c + m, x + m, m)
    case 1: (r, g, b) = (x + m, c + m, m)
    case 2: (r, g, b) = (m, c + m, x + m)
    case 3: (r, g, b) = (m, x + m, c + m)
    case 4: (r, g, b) = (x + m, m, c + m)
    default: (r, g, b) = (c + m, m, x + m)
    }
    return 0xFF00_0000 | v(r) << 16 | v(g) << 8 | v(b)
  }
}
