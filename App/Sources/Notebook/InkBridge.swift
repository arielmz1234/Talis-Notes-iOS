import PencilKit
import TaliCore
import UIKit

/// How each Android pen type is drawn here.
extension PenType {
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

  /// The old dashed pen drew short dashes.
  var line: LineStyle {
    pen == .DASHED ? .SHORT_DASH : tags.lazy.compactMap(LineStyle.init(rawValue:)).first ?? .SOLID
  }

  var square: Bool { tags.contains("SQUARE") }

  var locked: Bool { tags.contains("LOCKED") }

  /// Android's pen column: "PEN/STYLE" for a dotted or dashed stroke, "HIGHLIGHTER/SQUARE" for the square tip.
  static func tags(for pen: PenSlot) -> [String] {
    (pen.lineStyle == .SOLID ? [] : [pen.lineStyle.rawValue]) + (pen.square ? ["SQUARE"] : [])
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
    if let look = InkLook(pen: pen, line: line, square: square) {
      let at = inputs.points.map { CGPoint(x: CGFloat($0.x), y: CGFloat($0.y)) }
      var shape = look.outline(size: CGFloat(size), points: at)
      if let mask, !mask.bounds.contains(shape.boundingBoxOfPath) { shape = shape.intersection(mask.cgPath) }
      let cover = CGFloat(size) * InkLook.coverPerSize + InkLook.coverExtra
      let under = PKStrokePath(
        controlPoints: zip(at, inputs.points).map { p, i in
          PKStrokePoint(location: p, timeOffset: TimeInterval(i.t), size: CGSize(width: cover, height: cover), opacity: 1, force: 1, azimuth: 0, altitude: .pi / 2, secondaryScale: 1)
        }, creationDate: Date())
      return PKStroke(ink: PKInk(.monoline, color: UIColor(argb: color)), path: under, transform: .identity, mask: UIBezierPath(cgPath: shape))
    }
    let ink = PKInk(pen.ink, color: UIColor(argb: color))
    let start = Date(timeIntervalSinceReferenceDate: 0)
    // Built like PencilKit's own live points for this ink (see InkWidth).
    let style = InkWidth.pointStyle(pen.ink)
    let w = CGFloat(size) * style.perSize
    let points = inputs.points.map { p -> PKStrokePoint in
      let pressure = CGFloat(p.pressure ?? 0.5)
      let width = pen.pressureSensitive ? w * (0.55 + 0.9 * pressure) : w
      let tilt = CGFloat(p.tilt ?? 0)
      return PKStrokePoint(
        location: CGPoint(x: CGFloat(p.x), y: CGFloat(p.y)), timeOffset: TimeInterval(p.t), size: CGSize(width: width, height: width),
        opacity: 1, force: force(pressure), azimuth: CGFloat(p.orientation ?? 0), altitude: .pi / 2 - tilt, secondaryScale: style.secondary)
    }
    return PKStroke(ink: ink, path: PKStrokePath(controlPoints: points, creationDate: start), transform: .identity, mask: mask)
  }

  /// A stroke PencilKit just drew, in world units (the canvas's drawing is kept at zoom 1).
  static func from(_ s: PKStroke, pen: PenSlot, id: String, z: Int64, tags: [String]? = nil) -> InkStroke {
    let t = s.transform
    // A finger has no pressure: its force reads 0, and stored as the lightest touch a fountain pen's
    // stroke came back as a hairline, here and on Android. It's kept as a medium touch instead.
    let finger = !s.path.contains { $0.force > 0 }
    let pts = s.path.map { p -> InkInput in
      let at = p.location.applying(t)
      // Android's pressure is 0...1; half of Apple Pencil's force (which runs to about 4) reads the same.
      let pressure = finger ? 0.5 : Float(min(max(p.force / 2, 0), 1))
      return InkInput(
        x: Float(at.x), y: Float(at.y), t: Float(p.timeOffset), pressure: pressure, tilt: Float(max(0, .pi / 2 - p.altitude)),
        orientation: Float(p.azimuth.truncatingRemainder(dividingBy: 2 * .pi) + (p.azimuth < 0 ? 2 * .pi : 0)))
    }
    return InkStroke(id: id, z: z, pen: pen.type, tags: tags ?? InkStroke.tags(for: pen), color: pen.inkColor, size: pen.size, inputs: InkInputs(points: pts, tool: .stylus))
  }
}

extension CGRect {
  init(_ r: TaliCore.Rect) {
    self.init(x: CGFloat(r.left), y: CGFloat(r.top), width: CGFloat(r.width), height: CGFloat(r.height))
  }
}

/// Making rebuilt strokes look like live ones. PencilKit's live points don't carry the tool width it
/// was given: a monoline tool of width 1.31 gave points 2.8 wide with a secondary scale of 0.36, and
/// points built from stored strokes with the plain size drew about half as wide. So the tool gets the
/// pen's size divided by a fixed factor (monoline 1.83, which draws the pen's width), and every live
/// stroke of an ink without pressure records its points' size per pen size and secondary scale, which
/// stored strokes are rebuilt with: live and reloaded strokes then draw the same.
@MainActor
enum InkWidth {
  static func factor(_ ink: PKInk.InkType) -> CGFloat { ink == .monoline ? 1.83 : 1 }

  /// The tool width that draws a stroke [size] wide with [ink].
  static func toolWidth(_ size: Float, _ ink: PKInk.InkType) -> CGFloat { CGFloat(size) / factor(ink) }

  /// Point size per pen size, and secondary scale, as live strokes of [ink] have them.
  nonisolated static func pointStyle(_ ink: PKInk.InkType) -> (perSize: CGFloat, secondary: CGFloat) {
    let d = UserDefaults.standard
    let per = d.double(forKey: "inkPoint-\(ink.rawValue)")
    let sec = d.double(forKey: "inkSecondary-\(ink.rawValue)")
    if per > 0 { return (CGFloat(per), CGFloat(sec > 0 ? sec : 1)) }
    // Before any live stroke: what the simulator showed for monoline.
    return ink == .monoline ? (1.17, 0.36) : (1, 1)
  }

  /// A live stroke drawn by a pen [size] wide had points [pointSize] wide with [secondary].
  static func learn(_ ink: PKInk.InkType, size: Float, pointSize: CGFloat, secondary: CGFloat) {
    guard size > 0.1, pointSize > 0.05, secondary > 0 else { return }
    UserDefaults.standard.set(Double(pointSize / CGFloat(size)), forKey: "inkPoint-\(ink.rawValue)")
    UserDefaults.standard.set(Double(secondary), forKey: "inkSecondary-\(ink.rawValue)")
  }
}
