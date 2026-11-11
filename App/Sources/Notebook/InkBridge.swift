import PencilKit
import TaliCore
import UIKit

/// The Android app's pen types (stored by name in the `pen` column).
enum PenType: String, CaseIterable, Codable, Sendable {
  case FINELINER, FOUNTAIN, PENCIL, CALLIGRAPHY, HIGHLIGHTER, DASHED

  var defaultSize: Float {
    switch self {
    case .FINELINER, .PENCIL: 2.5
    case .FOUNTAIN: 3
    case .CALLIGRAPHY: 7
    case .HIGHLIGHTER: 18
    case .DASHED: 2.4
    }
  }
  var maxSize: Float {
    switch self {
    case .CALLIGRAPHY: 30
    case .HIGHLIGHTER: 40
    default: 20
    }
  }
  static let offered: [PenType] = [.FINELINER, .FOUNTAIN, .PENCIL, .CALLIGRAPHY, .HIGHLIGHTER]

  /// The PencilKit ink that draws it live.
  var ink: PKInk.InkType {
    switch self {
    case .FINELINER, .DASHED: .monoline
    case .FOUNTAIN, .CALLIGRAPHY: .fountainPen
    case .PENCIL: .pencil
    case .HIGHLIGHTER: .marker
    }
  }

  /// Width varies with pressure.
  var pressureSensitive: Bool { self == .FOUNTAIN || self == .CALLIGRAPHY || self == .PENCIL }
}

/// One pen in the toolbar (Android's `PenSlot`, the parts ported so far).
struct PenSlot: Codable, Hashable, Identifiable, Sendable {
  var id: String
  var type: PenType
  var color: Int32
  var size: Float
  /// Her three thicknesses (empty until she sets them) and which one is in use (Android's `sizes`, `sizeSlot`).
  var sizes: [Float] = []
  var sizeSlot = 1
  /// How many of its palette's colours sit in the toolbar; nil until set (the app-wide number).
  var toolbarColors: Int? = nil

  init(id: String, type: PenType, color: Int32, size: Float, sizes: [Float] = [], sizeSlot: Int = 1, toolbarColors: Int? = nil) {
    self.id = id
    self.type = type
    self.color = color
    self.size = size
    self.sizes = sizes
    self.sizeSlot = sizeSlot
    self.toolbarColors = toolbarColors
  }

  // Missing keys take their defaults, as kotlinx.serialization does (pens saved before these fields, or from Android).
  init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    id = try c.decode(String.self, forKey: .id)
    type = try c.decode(PenType.self, forKey: .type)
    color = try c.decode(Int32.self, forKey: .color)
    size = try c.decode(Float.self, forKey: .size)
    sizes = try c.decodeIfPresent([Float].self, forKey: .sizes) ?? []
    sizeSlot = try c.decodeIfPresent(Int.self, forKey: .sizeSlot) ?? 1
    toolbarColors = try c.decodeIfPresent(Int.self, forKey: .toolbarColors)
  }

  static let highlighterAlpha: UInt32 = 0x66
  static let defaultColors: [UInt32] = [
    0xFF1B_1F2A, 0xFF4A_5160, 0xFF1F_5FD1, 0xFFD8_3A3A, 0xFF1E_9E6A, 0xFFF0_8A24, 0xFF7A_4FD8, 0xFFFF_D60A, 0xFFFF_6FA8, 0xFF9B_6BF2, 0xFF5A_A9E6,
  ]

  static let defaults: [PenSlot] = [
    PenSlot(id: "p1", type: .FINELINER, color: Int32(bitPattern: defaultColors[0]), size: 2.4),
    PenSlot(id: "p2", type: .FOUNTAIN, color: Int32(bitPattern: defaultColors[2]), size: 3),
    PenSlot(id: "p4", type: .FINELINER, color: Int32(bitPattern: defaultColors[3]), size: 2.4),
    PenSlot(id: "p5", type: .HIGHLIGHTER, color: Int32(bitPattern: defaultColors[7]), size: 18),
  ]

  /// The colour strokes are stored in: highlighters see-through, everything else opaque (`Brushes.inkColor`).
  var inkColor: Int32 {
    let c = UInt32(bitPattern: color)
    return Int32(bitPattern: type == .HIGHLIGHTER ? (c & 0x00FF_FFFF) | (PenSlot.highlighterAlpha << 24) : c | 0xFF00_0000)
  }
}

extension UIColor {
  convenience init(argb v: Int32) {
    let c = UInt32(bitPattern: v)
    self.init(
      red: CGFloat((c >> 16) & 0xFF) / 255, green: CGFloat((c >> 8) & 0xFF) / 255, blue: CGFloat(c & 0xFF) / 255, alpha: CGFloat((c >> 24) & 0xFF) / 255)
  }

  var argb: Int32 {
    var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
    getRed(&r, green: &g, blue: &b, alpha: &a)
    func byte(_ x: CGFloat) -> UInt32 { UInt32(max(0, min(255, (x * 255).rounded()))) }
    return Int32(bitPattern: byte(a) << 24 | byte(r) << 16 | byte(g) << 8 | byte(b))
  }
}

/// A stroke stored the Android way, with the pen it was written with.
struct InkStroke {
  var id: String
  var z: Int64
  var pen: PenType
  /// Extra tags from the pen column ("PEN/STYLE/SQUARE/LOCKED"), kept so nothing is lost.
  var tags: [String]
  var color: Int32
  var size: Float
  var inputs: InkInputs

  /// From an item row of kind 0, or nil for other items (or a pen this version doesn't know).
  init?(row: ItemRow) {
    guard row.kind == 0, let penText = row.pen else { return nil }
    let parts = penText.split(separator: "/").map(String.init)
    guard let pen = PenType(rawValue: parts.first ?? ""), let inputs = try? InkCodec.decode(row.payload) else { return nil }
    id = row.id
    z = row.z
    self.pen = pen
    tags = Array(parts.dropFirst())
    color = row.color
    size = row.size
    self.inputs = inputs
  }

  init(id: String, z: Int64, pen: PenType, tags: [String] = [], color: Int32, size: Float, inputs: InkInputs) {
    self.id = id
    self.z = z
    self.pen = pen
    self.tags = tags
    self.color = color
    self.size = size
    self.inputs = inputs
  }

  var row: ItemRow {
    let b = bounds
    return ItemRow(
      id: id, z: z, kind: 0, pen: ([pen.rawValue] + tags).joined(separator: "/"), color: color, size: size, payload: InkCodec.encode(inputs),
      l: b.left, t: b.top, r: b.right, b: b.bottom)
  }

  /// Where it's drawn: its samples grown by half the pen.
  var bounds: TaliCore.Rect {
    (inputs.bounds ?? TaliCore.Rect(0, 0, 0, 0)).outset(size / 2)
  }

  // MARK: PencilKit

  /// The force PencilKit is given for a stored pressure: pens without pressure always the neutral 1
  /// (a finger's stroke stores 0, which PencilKit drew as a hairline), others never below a light touch.
  private func force(_ pressure: CGFloat) -> CGFloat {
    pen.pressureSensitive ? max(pressure * 2, 0.4) : 1
  }

  /// The PencilKit stroke that draws it, kept to [mask] (its page) when given.
  func pkStroke(mask: UIBezierPath?) -> PKStroke {
    let ink = PKInk(pen.ink, color: UIColor(argb: color))
    let start = Date(timeIntervalSinceReferenceDate: 0)
    let w = CGFloat(size)
    let points = inputs.points.map { p -> PKStrokePoint in
      let pressure = CGFloat(p.pressure ?? 0.5)
      let width = pen.pressureSensitive ? w * (0.55 + 0.9 * pressure) : w
      let tilt = CGFloat(p.tilt ?? 0)
      return PKStrokePoint(
        location: CGPoint(x: CGFloat(p.x), y: CGFloat(p.y)), timeOffset: TimeInterval(p.t), size: CGSize(width: width, height: width),
        opacity: 1, force: force(pressure), azimuth: CGFloat(p.orientation ?? 0), altitude: .pi / 2 - tilt, secondaryScale: 1)
    }
    return PKStroke(ink: ink, path: PKStrokePath(controlPoints: points, creationDate: start), transform: .identity, mask: mask)
  }

  /// A stroke PencilKit just drew, in world units (the canvas's drawing is kept at zoom 1).
  static func from(_ s: PKStroke, pen: PenSlot, id: String, z: Int64) -> InkStroke {
    let t = s.transform
    let pts = s.path.map { p -> InkInput in
      let at = p.location.applying(t)
      // Android's pressure is 0...1; half of Apple Pencil's force (which runs to about 4) reads the same.
      let pressure = Float(min(max(p.force / 2, 0), 1))
      return InkInput(
        x: Float(at.x), y: Float(at.y), t: Float(p.timeOffset), pressure: pressure, tilt: Float(max(0, .pi / 2 - p.altitude)),
        orientation: Float(p.azimuth.truncatingRemainder(dividingBy: 2 * .pi) + (p.azimuth < 0 ? 2 * .pi : 0)))
    }
    return InkStroke(id: id, z: z, pen: pen.type, color: pen.inkColor, size: pen.size, inputs: InkInputs(points: pts, tool: .stylus))
  }
}

extension CGRect {
  init(_ r: TaliCore.Rect) {
    self.init(x: CGFloat(r.left), y: CGFloat(r.top), width: CGFloat(r.width), height: CGFloat(r.height))
  }
}

/// How much wider PencilKit draws a live stroke than the tool width it's given, per ink (measured in
/// the simulator: monoline 2.4 → points 4.40, about 1.83×). The tool is given the pen's size divided
/// by this, so live strokes are the pen's real width, the width Android draws and the width they
/// reload at. Learned again from each stroke of an ink without pressure, so it stays right.
@MainActor
enum InkWidth {
  static func factor(_ ink: PKInk.InkType) -> CGFloat {
    let stored = UserDefaults.standard.double(forKey: "inkWidth-\(ink.rawValue)")
    if stored > 0 { return CGFloat(stored) }
    return ink == .monoline ? 1.83 : 1
  }

  /// The tool width that draws a stroke [size] wide with [ink].
  static func toolWidth(_ size: Float, _ ink: PKInk.InkType) -> CGFloat { CGFloat(size) / factor(ink) }

  /// A live stroke drawn with [toolWidth] came out with points [pointSize] wide.
  static func learn(_ ink: PKInk.InkType, toolWidth: CGFloat, pointSize: CGFloat) {
    guard toolWidth > 0.1, pointSize > 0.1 else { return }
    let f = min(max(pointSize / toolWidth, 0.5), 3)
    UserDefaults.standard.set(Double(f), forKey: "inkWidth-\(ink.rawValue)")
  }
}
