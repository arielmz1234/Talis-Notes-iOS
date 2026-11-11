import Foundation

// A port of the Android app's `model/ShapePacks.kt`: the subjects, their shapes and the small
// drawing language the designs are written in. Same ids and numbers; keep the two in step.

/// One subject's shapes. [name] is English (the app shows it in its own language).
public struct ShapePack: Sendable, Identifiable {
  public let id: String
  public let name: String
  public let shapes: [PackShape]
}

/// How a subject shape follows the pen as it's drawn.
public enum PackMode: Sendable {
  /// Keeps its proportions, as big as the dragged box allows (a person, a flask, a gear).
  case symbol
  /// Drawn like a line from one end to the other (a resistor, a spring, a timeline): its ends keep
  /// to tidy angles, so it connects to things.
  case line
}

/// One shape in a subject: one of the built-in kinds ([kind], the civil engineering symbols), a
/// shape with joints ([template]), or a fixed design drawn in its own frame and fitted to the pen.
public struct PackShape: Sendable, Identifiable {
  public let id: String
  public let label: String
  public let mode: PackMode
  let design: ShapeGeometry?
  public let kind: ShapeKind?
  public let template: ShapeTemplate?
  private let frame: Rect

  init(id: String, label: String, mode: PackMode, design: ShapeGeometry? = nil, kind: ShapeKind? = nil, template: ShapeTemplate? = nil) {
    self.id = id
    self.label = label
    self.mode = mode
    self.design = design
    self.kind = kind
    self.template = template
    frame = design.flatMap { Rect.around($0.paths(1).joined()) } ?? Rect(0, 0, 1, 1)
  }

  /// For the panel's tile.
  public var icon: ShapeGeometry { design ?? template?.tile ?? kind!.inBox(Pt(0, 0), Pt(100, 100)) }

  public var drawnAsLine: Bool { kind?.drawnAsLine ?? (mode == .line) }

  public var drawnFromPoint: Bool { kind?.drawnFromPoint ?? false }

  /// For hold-to-shape: how its lines are spread, to compare with a drawn stroke (designs only).
  public var cloud: ShapeMatcher.Cloud? {
    (design ?? template?.icon).flatMap { ShapeMatcher.cloud($0.paths(CustomShape.referencePen)) }
  }

  /// Over the box a held stroke covered; one drawn like a line runs from the stroke's [first] point to its [last].
  public func placeOver(_ box: Rect, _ first: Pt, _ last: Pt) -> ShapeGeometry {
    mode == .line ? create(first, last) : create(Pt(box.left, box.top), Pt(box.right, box.bottom))
  }

  /// The shape drawn from where the pen landed ([p0]) to where it is ([p1]).
  public func create(_ p0: Pt, _ p1: Pt) -> ShapeGeometry {
    if let kind { return kind.create(p0, p1) }
    if let template { return .param(template.create(p0, p1)) }
    guard let design else { return .group([]) }
    let w = max(abs(p1.x - p0.x), 8), h = max(abs(p1.y - p0.y), 8)
    let s = min(w / max(frame.width, 1), h / max(frame.height, 1))
    let cx = (p0.x + p1.x) / 2, cy = (p0.y + p1.y) / 2
    return design.transformed(Affine(a: s, d: s, tx: cx - frame.center.x * s, ty: cy - frame.center.y * s))
  }
}

/// A small drawing language for the designs (y goes down, as on the page).
struct Draw {
  private(set) var parts: [ShapeGeometry] = []

  mutating func line(_ x1: Float, _ y1: Float, _ x2: Float, _ y2: Float, arrow: Bool = false, both: Bool = false) {
    parts.append(.line(a: Pt(x1, y1), b: Pt(x2, y2), arrowStart: both, arrowEnd: arrow || both, ticks: false))
  }

  /// A closed outline through the points (x, y, x, y, …).
  mutating func poly(_ xy: Float...) { poly(xy) }

  mutating func poly(_ xy: [Float]) { parts.append(.poly(points: Draw.pts(xy), closed: true)) }

  /// An open run of straight pieces.
  mutating func open(_ xy: Float...) { open(xy) }

  mutating func open(_ xy: [Float]) { parts.append(.poly(points: Draw.pts(xy), closed: false)) }

  /// A smooth curve through the points (repeat the first point at the end for a closed loop).
  mutating func curve(_ xy: Float...) { curve(Draw.pts(xy)) }

  mutating func curve(_ points: [Pt]) { parts.append(.poly(points: points, closed: false, smooth: true)) }

  mutating func rect(_ l: Float, _ t: Float, _ r: Float, _ b: Float) { poly(l, t, r, t, r, b, l, b) }

  mutating func circle(_ cx: Float, _ cy: Float, _ r: Float) { ellipse(cx, cy, r, r) }

  mutating func ellipse(_ cx: Float, _ cy: Float, _ rx: Float, _ ry: Float) {
    parts.append(.ellipse(center: Pt(cx, cy), rx: rx, ry: ry, rotation: 0))
  }

  /// An arc of a circle, from [fromDeg] going [sweepDeg] (positive turns clockwise on the page).
  mutating func arc(_ cx: Float, _ cy: Float, _ r: Float, _ fromDeg: Float, _ sweepDeg: Float, arrow: Bool = false) {
    parts.append(.arc(center: Pt(cx, cy), radius: r, start: Draw.rad(fromDeg), sweep: Draw.rad(sweepDeg), arrowEnd: arrow))
  }

  /// Part of an ellipse as a smooth curve (so it can stretch), from [fromDeg] to [toDeg].
  mutating func ellipseArc(_ cx: Float, _ cy: Float, _ rx: Float, _ ry: Float, _ fromDeg: Float, _ toDeg: Float) {
    let n = 12
    curve((0...n).map { i in
      let a = Draw.rad(fromDeg + (toDeg - fromDeg) * Float(i) / Float(n))
      return Pt(cx + rx * cosf(a), cy + ry * sinf(a))
    })
  }

  /// A line between two circles' centres, stopping at their edges (radius [r]).
  mutating func link(_ x1: Float, _ y1: Float, _ x2: Float, _ y2: Float, _ r: Float, arrow: Bool = false) {
    let a = Pt(x1, y1), b = Pt(x2, y2)
    let dir = (b - a).normalized()
    parts.append(.line(a: a + dir * r, b: b - dir * r, arrowStart: false, arrowEnd: arrow, ticks: false))
  }

  /// A little person: head and shoulders, [h] tall, standing on ([x], [bottom]).
  mutating func person(_ x: Float, _ bottom: Float, _ h: Float) {
    circle(x, bottom - h * 0.72, h * 0.2)
    arc(x, bottom, h * 0.42, 180, 180)
    line(x - h * 0.42, bottom, x + h * 0.42, bottom)
  }

  /// A cloud (for the cloud and the thought bubble): four round bumps on a flat base, fitted into
  /// the box from ([l], [t]) to ([r], [b]) (drawn on a 100 × 60 grid, scaled evenly).
  mutating func cloud(_ l: Float, _ t: Float, _ r: Float, _ b: Float) {
    let s = min((r - l) / 100, (b - t) / 60)
    let ox = l + ((r - l) - 100 * s) / 2
    let oy = t + ((b - t) - 60 * s) / 2
    func x(_ v: Float) -> Float { ox + v * s }
    func y(_ v: Float) -> Float { oy + v * s }
    arc(x(18), y(40), 16 * s, 90, 180)
    arc(x(38), y(26), 20 * s, 180, 140)
    arc(x(62), y(26), 18 * s, 215, 145)
    arc(x(82), y(40), 16 * s, 270, 180)
    line(x(18), y(56), x(82), y(56))
  }

  // Always a group, even of one piece: a symbol moves, resizes and turns whole, with no dots to
  // pull single corners out of shape.
  func build() -> ShapeGeometry { .group(parts) }

  private static func pts(_ xy: [Float]) -> [Pt] { (0..<(xy.count / 2)).map { Pt(xy[2 * $0], xy[2 * $0 + 1]) } }

  private static func rad(_ d: Float) -> Float { Float(Double(d) * .pi / 180) }
}

private func symbol(_ id: String, _ label: String, _ block: (inout Draw) -> Void) -> PackShape {
  var d = Draw()
  block(&d)
  return PackShape(id: id, label: label, mode: .symbol, design: d.build())
}

private func builtIn(_ kind: ShapeKind) -> PackShape {
  let name = kind.rawValue.replacingOccurrences(of: "_", with: " ").lowercased()
  return PackShape(id: "kind-\(kind.rawValue)", label: name.prefix(1).uppercased() + name.dropFirst(), mode: .symbol, kind: kind)
}

/// A shape with joints: dots that change what it is (more cells, a level, a bar's height).
private func jointed(_ label: String, _ template: ShapeTemplate) -> PackShape {
  PackShape(id: template.id, label: label, mode: template.mode == .line ? .line : .symbol, template: template)
}

public enum ShapePacks {
  private typealias T = ShapeTemplates

  private static let social = ShapePack(
    id: "social", name: "Social Sciences",
    shapes: [
      symbol("person", "Person") { $0.person(50, 95, 90) },
      jointed("Group", T.group),
      jointed("Network", T.network),
      jointed("Family tree", T.familyTree),
      symbol("male", "Male") { d in
        d.circle(40, 60, 26)
        d.line(58, 42, 88, 12, arrow: true)
      },
      symbol("female", "Female") { d in
        d.circle(50, 36, 26)
        d.line(50, 62, 50, 96)
        d.line(34, 80, 66, 80)
      },
      jointed("Speech bubble", T.speech),
      symbol("globe", "Globe") { d in
        d.circle(50, 50, 40)
        d.ellipse(50, 50, 17, 40)
        d.line(10, 50, 90, 50)
        d.curve(16, 30, 50, 24, 84, 30)
        d.curve(16, 70, 50, 76, 84, 70)
      },
      jointed("Timeline", T.timeline),
      jointed("Venn diagram", T.venn),
    ])

  private static let business = ShapePack(
    id: "business", name: "Business & Management",
    shapes: [
      jointed("Org chart", T.orgChart),
      jointed("Bar chart", T.barChart),
      jointed("Pie chart", T.pieChart),
      jointed("Growth chart", T.growth),
      jointed("Funnel", T.funnel),
      jointed("SWOT grid", T.swot),
      jointed("Gantt chart", T.gantt),
      jointed("Target", T.target),
      jointed("Coins", T.coins),
      jointed("Document", T.document),
    ])

  private static let computing = ShapePack(
    id: "computing", name: "Computer Science & IT",
    shapes: [
      jointed("Database", T.database),
      jointed("Start / end", T.terminal),
      jointed("Subroutine", T.subroutine),
      jointed("Binary tree", T.binaryTree),
      jointed("Directed graph", T.graph),
      jointed("Array", T.array),
      jointed("Linked list", T.linkedList),
      jointed("Stack", T.stack),
      jointed("Computer", T.computer),
      symbol("cloud", "Cloud") { $0.cloud(0, 20, 100, 80) },
    ])

  private static let law = ShapePack(
    id: "law", name: "Law",
    shapes: [
      jointed("Scales of justice", T.scales),
      symbol("gavel", "Gavel") { d in
        d.poly(18, 22, 42, 6, 58, 30, 34, 46)
        d.line(46, 38, 86, 76)
        d.rect(54, 84, 96, 94)
      },
      jointed("Courthouse", T.courthouse),
      jointed("Column", T.column),
      jointed("Contract", T.contract),
      symbol("shield", "Shield") { $0.curve(50, 8, 84, 16, 82, 55, 50, 92, 18, 55, 16, 16, 50, 8) },
      jointed("Court hierarchy", T.courtLevels),
      jointed("Two parties", T.parties),
      symbol("handcuffs", "Handcuffs") { d in
        d.circle(26, 64, 18)
        d.circle(74, 64, 18)
        d.line(30, 46, 42, 32)
        d.line(70, 46, 58, 32)
        d.ellipse(50, 30, 9, 5)
      },
      symbol("law-book", "Law book") { d in
        d.open(50, 24, 10, 14, 10, 80, 50, 90)
        d.open(50, 24, 90, 14, 90, 80, 50, 90)
        d.line(50, 24, 50, 90)
      },
    ])

  private static let health = ShapePack(
    id: "health", name: "Nursing & Health",
    shapes: [
      jointed("Medical cross", T.medCross),
      symbol("heart", "Heart") { $0.curve(50, 90, 16, 56, 8, 30, 25, 12, 42, 14, 50, 28, 58, 14, 75, 12, 92, 30, 84, 56, 50, 90) },
      jointed("Heartbeat", T.heartbeat),
      symbol("capsule", "Capsule") { d in
        d.line(25, 35, 75, 35)
        d.line(25, 65, 75, 65)
        d.arc(25, 50, 15, 90, 180)
        d.arc(75, 50, 15, -90, 180)
        d.line(50, 35, 50, 65)
      },
      jointed("Syringe", T.syringe),
      jointed("Thermometer", T.thermometer),
      symbol("stethoscope", "Stethoscope") { d in
        d.curve(30, 8, 28, 40, 50, 60)
        d.curve(70, 8, 72, 40, 50, 60)
        d.curve(50, 60, 50, 76, 66, 86, 80, 76, 80, 66)
        d.circle(80, 58, 8)
      },
      symbol("body", "Body outline") { d in
        d.circle(50, 12, 8)
        d.poly(40, 22, 60, 22, 75, 55, 68, 57, 58, 35, 58, 60, 62, 95, 54, 95, 50, 66, 46, 95, 38, 95, 42, 60, 42, 35, 32, 57, 25, 55)
      },
      jointed("IV bag", T.ivBag),
      symbol("drop", "Blood drop") { $0.curve(50, 8, 36, 38, 28, 62, 35, 80, 50, 88, 65, 80, 72, 62, 64, 38, 50, 8) },
    ])

  private static let mechanical = ShapePack(
    id: "mechanical", name: "Mechanical Engineering",
    shapes: [
      jointed("Gear", T.gear),
      jointed("Spring", T.spring),
      jointed("Damper", T.damper),
      jointed("Bearing", T.bearing),
      jointed("Pulley", T.pulley),
      jointed("Lever", T.lever),
      jointed("Piston", T.piston),
      jointed("Mass on ground", T.mass),
      jointed("Shaft", T.shaft),
      jointed("Bolt", T.bolt),
    ])

  private static let civil = ShapePack(
    id: "civil", name: "Civil Engineering",
    shapes: [
      builtIn(.PIN_SUPPORT),
      builtIn(.ROLLER_SUPPORT),
      builtIn(.FIXED_SUPPORT),
      builtIn(.POINT_LOAD),
      builtIn(.DISTRIBUTED_LOAD),
      builtIn(.MOMENT),
      builtIn(.DIMENSION),
      jointed("I-beam section", T.iBeam),
      jointed("Truss", T.truss),
      symbol("level", "Level mark") { d in
        d.poly(38, 22, 62, 22, 50, 42)
        d.line(8, 42, 92, 42)
        d.line(28, 50, 72, 50)
        d.line(38, 57, 62, 57)
      },
    ])

  private static let electrical = ShapePack(
    id: "electrical", name: "Electrical Engineering",
    shapes: [
      jointed("Resistor", T.resistor),
      jointed("Capacitor", T.capacitor),
      jointed("Inductor", T.inductor),
      jointed("Diode", T.diode),
      jointed("Battery", T.battery),
      jointed("AC source", T.acSource),
      jointed("Switch", T.switchSymbol),
      jointed("Lamp", T.lamp),
      symbol("ground", "Ground") { d in
        d.line(50, 5, 50, 45)
        d.line(20, 45, 80, 45)
        d.line(30, 57, 70, 57)
        d.line(40, 69, 60, 69)
      },
      jointed("AND gate", T.andGate),
    ])

  private static let psychology = ShapePack(
    id: "psychology", name: "Psychology",
    shapes: [
      symbol("brain", "Brain") { d in
        d.curve(20, 62, 10, 45, 18, 28, 32, 18, 50, 15, 68, 18, 82, 28, 90, 45, 80, 62, 65, 70, 50, 66, 35, 70, 20, 62)
        d.curve(50, 15, 47, 35, 53, 50, 50, 66)
        d.curve(15, 38, 24, 32, 31, 40, 39, 33, 46, 38)
        d.curve(54, 38, 61, 33, 69, 40, 76, 32, 85, 38)
        d.curve(17, 54, 25, 48, 32, 56, 40, 50, 47, 56)
        d.curve(53, 56, 60, 50, 68, 56, 75, 48, 83, 54)
      },
      symbol("head", "Head profile") { $0.curve(35, 96, 35, 76, 24, 64, 21, 44, 28, 24, 45, 11, 66, 12, 80, 25, 84, 40, 91, 55, 83, 58, 83, 68, 75, 72, 71, 82, 71, 96) },
      jointed("Neuron", T.neuron),
      jointed("Bell curve", T.bellCurve),
      jointed("Maslow pyramid", T.maslow),
      jointed("Thought bubble", T.thought),
      jointed("Eye", T.eye),
      jointed("Face", T.face),
      jointed("Cycle", T.cycle),
      jointed("Scatter plot", T.scatter),
    ])

  private static let economics = ShapePack(
    id: "economics", name: "Economics",
    shapes: [
      jointed("Supply & demand", T.supplyDemand),
      jointed("Axes", T.axes),
      jointed("Demand curve", T.demand),
      jointed("Indifference curves", T.indifference),
      jointed("Production frontier", T.ppf),
      jointed("Cost curves", T.costCurves),
      jointed("Lorenz curve", T.lorenz),
      symbol("circular-flow", "Circular flow") { d in
        d.rect(2, 38, 28, 62)
        d.rect(72, 38, 98, 62)
        d.arc(50, 50, 33, 200, 140, arrow: true)
        d.arc(50, 50, 33, 20, 140, arrow: true)
      },
      jointed("Business cycle", T.businessCycle),
      jointed("Laffer curve", T.laffer),
    ])

  private static let design = ShapePack(
    id: "design", name: "Design & Art",
    shapes: [
      jointed("Colour wheel", T.colourWheel),
      jointed("Rule of thirds", T.thirds),
      symbol("golden-spiral", "Golden spiral") { d in
        d.rect(0, 0, 100, 61.8)
        d.line(61.8, 0, 61.8, 61.8)
        d.line(61.8, 38.2, 100, 38.2)
        d.line(76.4, 38.2, 76.4, 61.8)
        d.line(61.8, 47.2, 76.4, 47.2)
        d.arc(61.8, 61.8, 61.8, 180, 90)
        d.arc(61.8, 38.2, 38.2, 270, 90)
        d.arc(76.4, 38.2, 23.6, 0, 90)
        d.arc(76.4, 47.2, 14.6, 90, 90)
      },
      jointed("Perspective", T.perspective),
      symbol("brush", "Paintbrush") { d in
        d.poly(88, 6, 94, 12, 60, 46, 54, 40)
        d.poly(54, 40, 60, 46, 52, 54, 46, 48)
        d.curve(46, 48, 30, 60, 14, 88, 40, 72, 52, 54)
      },
      jointed("Pencil", T.pencil),
      symbol("palette", "Palette") { d in
        d.curve(50, 10, 84, 18, 96, 48, 82, 78, 56, 86, 50, 72, 38, 68, 26, 82, 8, 62, 10, 30, 50, 10)
        d.circle(36, 30, 6)
        d.circle(58, 24, 6)
        d.circle(78, 40, 6)
        d.circle(76, 62, 6)
      },
      jointed("Picture frame", T.frame),
      jointed("Cube", T.cube),
      symbol("easel", "Easel") { d in
        d.line(50, 4, 20, 96)
        d.line(50, 4, 80, 96)
        d.line(50, 4, 50, 92)
        d.rect(24, 18, 76, 60)
        d.line(18, 64, 82, 64)
      },
    ])

  /// Every subject, in the order the "More shapes" window lists them.
  public static let all: [ShapePack] = [social, business, computing, law, health, mechanical, civil, electrical, psychology, economics, design]

  private static let byId: [String: PackShape] = Dictionary(all.flatMap(\.shapes).map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })

  public static func shape(_ id: String) -> PackShape? { byId[id] }
}
