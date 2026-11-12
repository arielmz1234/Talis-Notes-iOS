import Foundation

/// The Android app's pen types (stored by name in an ink item's `pen` column). Sizes are world units.
public enum PenType: String, CaseIterable, Codable, Sendable {
  case FINELINER, FOUNTAIN, PENCIL, CALLIGRAPHY, HIGHLIGHTER
  /// The old dashed pen, kept so strokes written with it still load; any pen can dash now (`LineStyle`).
  case DASHED

  public var defaultSize: Float {
    switch self {
    case .FINELINER, .PENCIL: 2.5
    case .FOUNTAIN: 3
    case .CALLIGRAPHY: 7
    case .HIGHLIGHTER: 18
    case .DASHED: 2.4
    }
  }

  /// Every pen goes down to the same thinnest line, so changing a pen's type keeps her thickness.
  public var minSize: Float { 0.5 }

  public var maxSize: Float {
    switch self {
    case .CALLIGRAPHY: 30
    case .HIGHLIGHTER: 40
    default: 20
    }
  }

  public var isHighlighter: Bool { self == .HIGHLIGHTER }

  /// Whether it can draw dotted and dashed lines (a highlighter always draws solid).
  public var takesLineStyle: Bool { self != .HIGHLIGHTER && self != .DASHED }

  /// The pens offered in the pen settings.
  public static let offered: [PenType] = [.FINELINER, .FOUNTAIN, .PENCIL, .CALLIGRAPHY, .HIGHLIGHTER]
}

/// How a line is drawn along its length, for any pen and for shapes (Android's `LineStyle`).
public enum LineStyle: String, CaseIterable, Codable, Sendable {
  case SOLID, DOTTED, LONG_DASH, SHORT_DASH, DOT_DASH, MIXED_DASH

  /// The visible lengths of the parts in multiples of the line's thickness, alternating drawn and
  /// gap, repeated (a drawn part of 0 is a round dot).
  public var pattern: [Float] {
    switch self {
    case .SOLID: []
    case .DOTTED: [0, 1.7]
    case .LONG_DASH: [6, 2.4]
    case .SHORT_DASH: [2.4, 2]
    case .DOT_DASH: [4, 2, 0, 2]
    case .MIXED_DASH: [6, 2, 2.2, 2]
    }
  }

  /// The dash lengths for a round-capped line [width] wide: the round ends stick out half the width
  /// past each piece, so pieces are that much shorter and gaps that much longer.
  public func intervals(width: Float, shortest: Float = 0.01) -> [Float] {
    pattern.enumerated().map { i, v in i % 2 == 0 ? max((v - 1) * width, shortest) : (v + 1) * width }
  }
}

public enum Dashes {
  /// [path] cut into the pieces of [line] for a line [size] thick (Android's `StrokeFactory.dashes`).
  /// Short paths (arrow barbs, small details) stay solid, since a pattern on them just looks broken.
  public static func cut(_ path: [Pt], size: Float, line: LineStyle) -> [[Pt]] {
    let pattern = line.intervals(width: size, shortest: 0.05)
    guard !pattern.isEmpty, path.count > 1, Geo.pathLength(path) >= pattern.reduce(0, +) * 2.5 else { return [path] }
    var out: [[Pt]] = []
    var current = [path[0]]
    var part = 0
    var left = pattern[0]
    for i in 0..<(path.count - 1) {
      var a = path[i]
      let b = path[i + 1]
      var seg = a.dist(b)
      while seg > 0 {
        let drawing = part % 2 == 0
        if seg < left {
          left -= seg
          if drawing { current.append(b) }
          seg = 0
        } else {
          let cut = a + (b - a) * (left / seg)
          if drawing {
            current.append(cut)
            out.append(current)
          } else {
            current = [cut]
          }
          seg -= left
          a = cut
          part = (part + 1) % pattern.count
          left = pattern[part]
        }
      }
    }
    if part % 2 == 0, current.count >= 2 { out.append(current) }
    return out
  }
}

/// One pen in the toolbar: a style, colour and size she has set up (Android's `PenSlot`, with its
/// field names, so pens saved by either app read the same).
public struct PenSlot: Codable, Hashable, Identifiable, Sendable {
  public var id: String
  public var type: PenType
  public var color: Int32
  public var size: Float
  public var line: LineStyle
  /// A highlighter with a square tip instead of a round one.
  public var squareTip: Bool
  /// A highlighter that follows the hand instead of drawing straight lines.
  public var freehand: Bool
  /// Her three thicknesses (empty until she sets them) and which one [size] is.
  public var sizes: [Float]
  public var sizeSlot: Int
  /// How many of its palette's colours sit in the toolbar; nil until set (the app-wide number).
  public var toolbarColors: Int?

  public init(
    id: String, type: PenType, color: Int32, size: Float, line: LineStyle = .SOLID, squareTip: Bool = false, freehand: Bool = false,
    sizes: [Float] = [], sizeSlot: Int = 1, toolbarColors: Int? = nil
  ) {
    self.id = id
    self.type = type
    self.color = color
    self.size = size
    self.line = line
    self.squareTip = squareTip
    self.freehand = freehand
    self.sizes = sizes
    self.sizeSlot = sizeSlot
    self.toolbarColors = toolbarColors
  }

  // Missing keys take their defaults, as kotlinx.serialization does (pens saved before a field existed, or by Android).
  public init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    id = try c.decode(String.self, forKey: .id)
    type = try c.decode(PenType.self, forKey: .type)
    color = try c.decode(Int32.self, forKey: .color)
    size = try c.decode(Float.self, forKey: .size)
    line = try c.decodeIfPresent(LineStyle.self, forKey: .line) ?? .SOLID
    squareTip = try c.decodeIfPresent(Bool.self, forKey: .squareTip) ?? false
    freehand = try c.decodeIfPresent(Bool.self, forKey: .freehand) ?? false
    sizes = try c.decodeIfPresent([Float].self, forKey: .sizes) ?? []
    sizeSlot = try c.decodeIfPresent(Int.self, forKey: .sizeSlot) ?? 1
    toolbarColors = try c.decodeIfPresent(Int.self, forKey: .toolbarColors)
  }

  public static let maxPens = 8
  public static let highlighterAlpha: UInt32 = 0x66
  public static let defaultColors: [UInt32] = [
    0xFF1B_1F2A, 0xFF4A_5160, 0xFF1F_5FD1, 0xFFD8_3A3A, 0xFF1E_9E6A, 0xFFF0_8A24, 0xFF7A_4FD8, 0xFFFF_D60A, 0xFFFF_6FA8, 0xFF9B_6BF2, 0xFF5A_A9E6,
  ]
  public static let defaultHighlighterColors: [UInt32] = [0xFFFF_D60A, 0xFFFF_6FA8, 0xFF5A_A9E6, 0xFF6E_E07A, 0xFFFF_A24D, 0xFFB2_8DFF]

  public static let defaults: [PenSlot] = [
    PenSlot(id: "p1", type: .FINELINER, color: Int32(bitPattern: defaultColors[0]), size: 2.4),
    PenSlot(id: "p2", type: .FOUNTAIN, color: Int32(bitPattern: defaultColors[2]), size: 3),
    PenSlot(id: "p4", type: .FINELINER, color: Int32(bitPattern: defaultColors[3]), size: 2.4),
    PenSlot(id: "p5", type: .HIGHLIGHTER, color: Int32(bitPattern: defaultColors[7]), size: 18),
  ]

  /// The colour strokes are stored in: highlighters see-through, everything else opaque (`Brushes.inkColor`).
  public var inkColor: Int32 { PenSlot.inkColor(type, color) }

  public static func inkColor(_ type: PenType, _ color: Int32) -> Int32 {
    let c = UInt32(bitPattern: color)
    return Int32(bitPattern: type.isHighlighter ? (c & 0x00FF_FFFF) | (highlighterAlpha << 24) : c | 0xFF00_0000)
  }

  private var slot: Int { min(max(sizeSlot, 0), 2) }

  /// The three thicknesses; until she sets them, a thinner and a thicker one around [size].
  public var presetSizes: [Float] {
    if sizes.count == 3 { return sizes }
    func half(_ v: Float) -> Float { (v * 2).rounded() / 2 }
    let thin = min(max(half(size * 0.6), type.minSize), size)
    let thick = min(max(half(size * 1.6), size), type.maxSize)
    switch slot {
    case 0: return [size, min(half(size * 1.6), type.maxSize), min(half(size * 2.5), type.maxSize)]
    case 2: return [max(half(size * 0.4), type.minSize), thin, size]
    default: return [thin, size, thick]
    }
  }

  /// A new thickness for the one of the three she's on.
  public func withSize(_ v: Float) -> PenSlot {
    var p = self
    var all = presetSizes
    all[slot] = v
    p.size = v
    p.sizes = all
    return p
  }

  /// Switches to her [i]th thickness.
  public func pickSize(_ i: Int) -> PenSlot {
    var p = self
    let all = presetSizes
    p.sizeSlot = i
    p.size = all[i]
    p.sizes = all
    return p
  }

  /// Another pen type with her thickness and colour kept (only held within what the new pen can do).
  public func withType(_ t: PenType) -> PenSlot {
    var p = self
    let all = presetSizes.map { min(max($0, t.minSize), t.maxSize) }
    p.type = t
    p.size = min(max(size, t.minSize), t.maxSize)
    p.sizes = all
    return p
  }

  /// The pens with a new one at the end (Android's `addPen`): a fineliner in her first saved colour.
  /// Nil when the toolbar is full.
  public static func adding(id: String, firstColor: UInt32?, to pens: [PenSlot]) -> [PenSlot]? {
    guard pens.count < maxPens else { return nil }
    return pens + [PenSlot(id: id, type: .FINELINER, color: Int32(bitPattern: firstColor ?? defaultColors[0]), size: PenType.FINELINER.defaultSize)]
  }

  /// The pens without [id] (Android's `removeActivePen`). Nil for the last pen, which stays.
  public static func removing(_ id: String, from pens: [PenSlot]) -> [PenSlot]? {
    guard pens.count > 1, pens.contains(where: { $0.id == id }) else { return nil }
    return pens.filter { $0.id != id }
  }

  /// Draws straight lines from where the pen lands to where it is (the highlighter's default).
  public var straight: Bool { type.isHighlighter && !freehand }

  /// Whether the tip is square (only a highlighter has the choice).
  public var square: Bool { type.isHighlighter && squareTip }

  /// The line it actually draws: a highlighter is always solid.
  public var lineStyle: LineStyle { type.takesLineStyle ? line : .SOLID }

  /// Saved pens brought up to date (Android's `AppSettings.migrated`): the old Dashed pen is a
  /// fineliner drawing short dashes, the built-in pencil has left the toolbar, and every pen has its own id.
  public static func migrated(_ saved: [PenSlot]) -> [PenSlot] {
    var pens = saved.map { p -> PenSlot in
      guard p.type == .DASHED else { return p }
      var q = p
      q.type = .FINELINER
      q.line = .SHORT_DASH
      return q
    }
    if pens.count > 1 { pens.removeAll { $0.id == "p3" && $0.type == .PENCIL } }
    var seen = Set<String>()
    for i in pens.indices where !seen.insert(pens[i].id).inserted {
      pens[i].id += "-\(i)"
      seen.insert(pens[i].id)
    }
    return pens
  }
}

/// The straight highlighter (Android's `Mode.STRAIGHT`): a line from where the pen landed to where it is.
public enum StraightLine {
  /// A line this close to level or upright snaps to it.
  public static let snapDegrees: Double = 4

  /// Where the line from [start] ends for a pen at [p]: level or upright when within a few degrees.
  /// A tap leaves a short mark, as the freehand highlighter does.
  public static func end(from start: Pt, to p: Pt) -> Pt {
    var end = p
    let v = p - start
    if v.length() > 0.5 {
      let a = Double(atan2f(v.y, v.x)) * 180 / .pi
      let off = (a.truncatingRemainder(dividingBy: 90) + 90).truncatingRemainder(dividingBy: 90)
      if off < snapDegrees || off > 90 - snapDegrees {
        let r = Float((a / 90).rounded() * 90 * .pi / 180)
        end = start + Pt(cosf(r), sinf(r)) * v.length()
      }
    }
    if end.dist(start) < 0.1 { end = start + Pt(0.1, 0) }
    return end
  }

  /// The line's pen samples (Android's `StrokeFactory.straightLine`): finely spaced near both ends,
  /// far apart along the middle, 2 ms apart, at an even pressure.
  public static func inputs(_ a: Pt, _ b: Pt) -> InkInputs {
    let fine: Float = 0.25, endRun: Float = 8, middleSteps: Float = 24
    let len = a.dist(b)
    var points: [InkInput] = []
    var t: Float = 0
    var last: Pt?
    func add(_ p: Pt) {
      if let l = last, l.dist(p) < 0.01 { return }
      points.append(InkInput(x: p.x, y: p.y, t: t, pressure: 0.55))
      t += 0.002
      last = p
    }
    guard len >= 0.01 else {
      add(a)
      return InkInputs(points: points, tool: .stylus)
    }
    let end = min(endRun, len / 2)
    func at(_ d: Float) -> Pt { a + (b - a) * (d / len) }
    var d: Float = 0
    while d < end {
      add(at(d))
      d += fine
    }
    let middle = len - 2 * end
    let n = max(Int((middle / max(len / middleSteps, fine)).rounded(.up)), 1)
    for k in 0..<n { add(at(end + middle * Float(k) / Float(n))) }
    d = len - end
    while d < len {
      add(at(d))
      d += fine
    }
    add(b)
    return InkInputs(points: points, tool: .stylus)
  }
}

/// The precise eraser (Android's `StrokeFactory.split`).
public enum StrokeCut {
  /// Splits a stroke where the eraser passed: [erased] says whether a point is under the eraser.
  /// Samples are filled in first, at most [maxGap] apart, so a gap between sparse samples can still
  /// be cut. Nil when nothing was erased; pieces keep their pressure, tilt and timing.
  public static func split(_ inputs: InkInputs, maxGap: Float, erased: (Float, Float) -> Bool) -> [InkInputs]? {
    var runs: [[InkInput]] = []
    var open = false
    var removedAny = false
    for p in densify(inputs.points, maxGap: maxGap) {
      if erased(p.x, p.y) {
        removedAny = true
        open = false
      } else if open {
        runs[runs.count - 1].append(p)
      } else {
        runs.append([p])
        open = true
      }
    }
    guard removedAny else { return nil }
    return runs.filter { $0.count >= 2 }.map { InkInputs(points: $0, tool: inputs.tool, strokeUnitLength: inputs.strokeUnitLength, noiseSeed: inputs.noiseSeed) }
  }

  static func densify(_ points: [InkInput], maxGap: Float) -> [InkInput] {
    var out: [InkInput] = []
    out.reserveCapacity(points.count * 2)
    var prev: InkInput?
    for cur in points {
      if let p = prev {
        let steps = Int(hypotf(cur.x - p.x, cur.y - p.y) / maxGap)
        if steps > 0 {
          for k in 1...steps {
            let f = Float(k) / Float(steps + 1)
            let pressure: Float? = if let a = p.pressure, let b = cur.pressure { a + (b - a) * f } else { cur.pressure }
            out.append(InkInput(x: p.x + (cur.x - p.x) * f, y: p.y + (cur.y - p.y) * f, t: p.t + (cur.t - p.t) * f, pressure: pressure, tilt: cur.tilt, orientation: cur.orientation))
          }
        }
      }
      out.append(cur)
      prev = cur
    }
    return out
  }

  /// Whether the eraser sweeping from [a] to [b], reaching [reach] either side, touches the line through [points].
  public static func touches(_ points: [Pt], _ a: Pt, _ b: Pt, reach: Float) -> Bool {
    guard let first = points.first else { return false }
    if points.count == 1 { return Geo.distToSegment(first, a, b) <= reach }
    for i in 0..<(points.count - 1) where segmentDistance(points[i], points[i + 1], a, b) <= reach { return true }
    return false
  }

  static func segmentDistance(_ p1: Pt, _ p2: Pt, _ q1: Pt, _ q2: Pt) -> Float {
    func side(_ a: Pt, _ b: Pt, _ c: Pt) -> Float { (b - a).cross(c - a) }
    let d1 = side(q1, q2, p1), d2 = side(q1, q2, p2), d3 = side(p1, p2, q1), d4 = side(p1, p2, q2)
    if (d1 > 0) != (d2 > 0), (d3 > 0) != (d4 > 0), d1 != 0, d2 != 0, d3 != 0, d4 != 0 { return 0 }
    return min(Geo.distToSegment(p1, q1, q2), Geo.distToSegment(p2, q1, q2), Geo.distToSegment(q1, p1, p2), Geo.distToSegment(q2, p1, p2))
  }
}

/// The laser pointer's trails (Android's `LaserTrail`, `drawLaser`): every stroke stays fully lit
/// while she keeps pointing; once the laser has been off the page for [idle], everything fades and
/// thins together over [fade]. Nothing is kept.
public struct Laser: Sendable {
  public static let idle: Double = 1.0
  public static let fade: Double = 0.45

  public struct Trail: Sendable {
    public var dots: [Pt]
    /// When it began fading; nil while it's still lit.
    public var fadeAt: Double?
  }

  public private(set) var trails: [Trail] = []
  public private(set) var down = false
  public private(set) var tip = Pt.zero
  private var liftedAt: Double = 0

  public init() {}

  /// Pointing again brings back whatever was still fading: it all stays lit together.
  public mutating func start(_ p: Pt) {
    for i in trails.indices { trails[i].fadeAt = nil }
    trails.append(Trail(dots: [p], fadeAt: nil))
    down = true
    tip = p
  }

  public mutating func move(_ p: Pt) {
    guard down, !trails.isEmpty else { return }
    trails[trails.count - 1].dots.append(p)
    tip = p
  }

  public mutating func end(at now: Double) {
    guard down else { return }
    down = false
    liftedAt = now
  }

  /// Brings the trails up to [now]: starts the fade once it's been left alone, drops what has faded.
  /// Returns whether there's still something to draw.
  public mutating func step(at now: Double) -> Bool {
    if !down, now - liftedAt >= Laser.idle {
      for i in trails.indices where trails[i].fadeAt == nil { trails[i].fadeAt = liftedAt + Laser.idle }
    }
    trails.removeAll { t in t.fadeAt.map { now - $0 > Laser.fade } ?? false }
    return down || !trails.isEmpty
  }

  /// How lit a trail is at [now], 1 to 0: it dims quickly at first, then lingers faintly for a moment.
  public static func life(_ trail: Trail, at now: Double) -> Float {
    guard let from = trail.fadeAt else { return 1 }
    let t = Float(min(max((now - from) / fade, 0), 1))
    return 1 - t * (2 - t)
  }

  /// The glow's and the core's widths (screen points) and opacities for a trail this lit.
  public static func glow(_ life: Float) -> (width: Float, alpha: Float) { (8 + 4 * life, 70 / 255 * life) }
  public static func core(_ life: Float) -> (width: Float, alpha: Float) { (2.2 + 1.3 * life, life) }
}
