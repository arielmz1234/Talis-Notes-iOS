import Foundation
import Testing
@testable import TaliCore

/// Android's `ShapePacksTest`, ported, plus how a shape with joints is stored.
struct ShapePacksTests {
  private let shapes = ShapePacks.all.flatMap(\.shapes)
  private var jointed: [PackShape] { shapes.filter { $0.template != nil } }

  private func points(_ g: ShapeGeometry, _ pen: Float = 2) -> [Pt] { Array(g.paths(pen).joined()) }

  private func param(_ g: ShapeGeometry) -> ParamShape? {
    if case let .param(p) = g { p } else { nil }
  }

  private func parts(_ g: ParamShape) -> [ShapeGeometry] {
    if case let .group(parts, _) = g.drawn() { parts } else { [] }
  }

  /// Where a drawing connects to things, as Android's `snapFeatures` gives them: ends, corners,
  /// the middles of sides and round shapes' centres.
  private func features(_ g: ShapeGeometry) -> [Pt] {
    switch g {
    case let .line(a, b, _, _, _): [a, b, (a + b) * 0.5]
    case let .poly(points, closed, false, _, _):
      points + points.indices.dropLast(closed ? 0 : 1).map { (points[$0] + points[($0 + 1) % points.count]) * 0.5 }
    case let .poly(points, _, true, _, _): [points[0], points[points.count - 1]]
    case let .ellipse(center, _, _, _, _): [center]
    case let .arc(center, radius, start, sweep, _): [center, center + Pt.polar(radius, start), center + Pt.polar(radius, start + sweep)]
    case let .group(parts, _): parts.flatMap(features)
    case let .param(p): features(p.drawn())
    default: []
    }
  }

  @Test func everySubjectHasShapesWithUniqueIds() {
    #expect(ShapePacks.all.count == 11)
    let ids = shapes.map(\.id)
    #expect(ids.count == Set(ids).count)
    for pack in ShapePacks.all { #expect(pack.shapes.count >= 5, "\(pack.name)") }
    for s in shapes { #expect(ShapePacks.shape(s.id)?.label == s.label) }
  }

  @Test func everyTemplateIsFoundByItsId() {
    let ids = ShapeTemplates.all.map(\.id)
    #expect(ids.count == Set(ids).count)
    #expect(ids.count == 80)
    for s in jointed { #expect(ShapeTemplates.get(s.id) != nil, "\(s.label)") }
    #expect(Set(jointed.map(\.id)) == Set(ids))
  }

  @Test func lineShapesRunFromEndToEnd() {
    let p0 = Pt(100, 200), p1 = Pt(300, 260)
    let lines = shapes.filter { $0.mode == .line && $0.kind == nil }
    #expect(lines.count == 16)
    for s in lines {
      let f = features(s.create(p0, p1))
      // Its two ends are where the pen started and stopped, so they connect to what they touch.
      #expect(f.contains { $0.dist(p0) < 0.5 }, "\(s.label)")
      #expect(f.contains { $0.dist(p1) < 0.5 }, "\(s.label)")
    }
  }

  @Test func boxShapesStayInTheirBox() throws {
    let p0 = Pt(50, 50), p1 = Pt(250, 170)
    for s in shapes where s.mode != .line && s.kind == nil {
      let g = s.create(p0, p1)
      let b = try #require(Rect.around(points(g, 1)), "\(s.label)")
      // Arrowheads and a speech bubble's tail may reach a little past.
      #expect(b.left >= 40 && b.top >= 40 && b.right <= 262 && b.bottom <= 215, "\(s.label) \(b)")
      #expect(g.paths(1).contains { $0.count > 1 }, "\(s.label)")
    }
  }

  @Test func everyJointCanBeDraggedAndDroppedInPlace() throws {
    for s in jointed {
      let g = try #require(param(s.create(Pt(40, 60), Pt(240, 200))))
      let hs = g.handles()
      #expect(!hs.isEmpty, "\(s.label)")
      let before = g.paths(2).flatMap { $0 }
      for (i, h) in hs.enumerated() {
        // Put back where it is: nothing changes (no creeping as she touches a dot).
        let after = g.withHandle(i, h).paths(2).flatMap { $0 }
        #expect(before.count == after.count, "\(s.label) joint \(i)")
        #expect(zip(before, after).allSatisfy { $0.dist($1) < 0.6 }, "\(s.label) joint \(i) moved")
        // Dragged a long way: still a sensible drawing.
        for d in [Pt(60, 40), Pt(-70, -50)] {
          let moved = g.withHandle(i, h + d).paths(2).flatMap { $0 }
          #expect(!moved.isEmpty && moved.allSatisfy { $0.x.isFinite && $0.y.isFinite }, "\(s.label) joint \(i)")
        }
      }
    }
  }

  @Test func noTwoJointsSitOnEachOther() throws {
    for s in jointed {
      for (p0, p1) in [(Pt(40, 60), Pt(240, 200)), (Pt(0, 0), Pt(90, 70))] {
        let g = try #require(param(s.mode == .line ? s.create(p0, Pt(p1.x, p0.y)) : s.create(p0, p1)))
        let hs = g.handles()
        for i in hs.indices {
          for j in hs.indices where j > i { #expect(hs[i].dist(hs[j]) >= 14, "\(s.label) joints \(i) and \(j)") }
        }
      }
    }
  }

  private func cells(_ g: ParamShape) -> Int {
    parts(g).count { if case .poly(_, true, _, _, _) = $0 { true } else { false } }
  }

  @Test func aLongerStackHasMoreCells() throws {
    let short = ShapeTemplates.stack.create(Pt(0, 0), Pt(70, 100))
    let long = ShapeTemplates.stack.create(Pt(0, 0), Pt(70, 300))
    #expect(cells(long) > cells(short) + 5)
    // And by its bottom dot.
    let i = try #require(short.handles().firstIndex { abs($0.y - 100) < 0.5 })
    #expect(cells(short.withHandle(i, Pt(35, 300))) == cells(long))
  }

  @Test func aTallerTreeHasMoreLevels() {
    func nodes(_ g: ParamShape) -> Int { parts(g).count { if case .ellipse = $0 { true } else { false } } }
    #expect(nodes(ShapeTemplates.binaryTree.create(Pt(0, 0), Pt(200, 90))) == 7)
    #expect(nodes(ShapeTemplates.binaryTree.create(Pt(0, 0), Pt(300, 180))) == 31)
  }

  @Test func aBarsDotSetsOnlyThatBar() {
    let chart = ShapeTemplates.barChart.create(Pt(0, 0), Pt(160, 110))
    let before = parts(chart)
    let after = parts(chart.withHandle(1, Pt(chart.handles()[1].x, 20)))
    // Part 0 is the axes, then one part per bar.
    #expect(before.indices.filter { before[$0] != after[$0] } == [2])
  }

  @Test func aLineShapesEndGoesWhereItsDragged() {
    let r = ShapeTemplates.resistor.create(Pt(0, 0), Pt(120, 0))
    let moved = r.withHandle(1, Pt(60, 90))
    #expect(moved.handles()[1].dist(Pt(60, 90)) < 0.01)
    #expect(moved.handles()[0].dist(Pt(0, 0)) < 0.01)
    let start = moved.withHandle(0, Pt(-30, 10))
    #expect(start.handles()[0].dist(Pt(-30, 10)) < 0.01)
    #expect(start.handles()[1].dist(Pt(60, 90)) < 0.01)
  }

  @Test func aShapeWithJointsIsStoredAndReadBack() throws {
    let fresh = ShapeTemplates.gantt.create(Pt(10, 20), Pt(200, 120))
    let g = fresh.withHandle(0, Pt(60, 30))
    let row = ShapeRow(geometry: .param(g), pen: "FINELINER", color: -1, size: 2.4).row(id: "s", z: 1)
    let back = try #require(ShapeRow(row))
    #expect(back.geometry == .param(g))
    #expect(back.geometry != .param(fresh))
    #expect(row.r > row.l && row.b > row.t)
  }

  /// The JSON kotlinx.serialization writes for a `ParamShape` (worked out from its serializer:
  /// "type" first, default values left out, so an unmoved place has only tx and ty).
  @Test func readsAndWritesAndroidsParamPayload() throws {
    let json = #"{"type":"param","template":"stack","place":{"tx":40.0,"ty":60.0},"w":70.0,"h":120.0}"#
    let o = try #require(JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any])
    let g = try #require(ShapeGeometry.decode(o))
    #expect(g == .param(ParamShape(template: "stack", place: .translate(40, 60), w: 70, h: 120)))
    #expect(g.paths(2).count > 3)
    #expect(g.json as NSDictionary == o as NSDictionary)

    let turned = #"{"type":"param","template":"spring","place":{"a":0.0,"b":1.0,"c":-1.0,"d":0.0,"tx":5.5,"ty":-2.0},"w":150.0,"h":0.0,"v":[14.5]}"#
    let o2 = try #require(JSONSerialization.jsonObject(with: Data(turned.utf8)) as? [String: Any])
    let decoded = try #require(ShapeGeometry.decode(o2))
    let spring = try #require(param(decoded))
    #expect(spring.v == [14.5] && spring.place == Affine(a: 0, b: 1, c: -1, d: 0, tx: 5.5, ty: -2))
    let ends = try #require(spring.lineEnds)
    #expect(ends.0.dist(Pt(5.5, -2)) < 0.001 && ends.1.dist(Pt(5.5, 148)) < 0.001)
    #expect(ShapeGeometry.param(spring).json as NSDictionary == o2 as NSDictionary)
  }

  @Test func aTemplateThisVersionDoesntKnowIsKeptAsItIs() throws {
    let json = #"{"type":"param","template":"hologram","place":{},"w":10.0,"h":20.0,"v":[1.0,2.0]}"#
    let o = try #require(JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any])
    let g = try #require(ShapeGeometry.decode(o))
    #expect(g.paths(2).isEmpty)
    #expect(g.transformed(.identity).json as NSDictionary == o as NSDictionary)
  }

  @Test func aMovedShapeKeepsItsJoints() throws {
    let g = ShapeGeometry.param(ShapeTemplates.thermometer.create(Pt(0, 0), Pt(100, 100)))
    let moved = try #require(param(g.transformed(Affine.translate(30, 40).then(.scaleAround(Pt(30, 40), 2)))))
    #expect(moved.handles()[0].dist(Pt(30 + 100, 40 + 80)) < 0.01)
    let level = moved.withHandle(0, Pt(130, 40 + 2 * 20))
    #expect(level.v == [20])
  }

  @Test func tilesAreDrawnSmallerThanTheShapeItself() throws {
    let tile = try #require(Rect.around(points(ShapeTemplates.resistor.tile)))
    let icon = try #require(Rect.around(points(ShapeTemplates.resistor.icon)))
    #expect(abs(tile.width - 76) < 0.01 && abs(icon.width - 120) < 0.01)
    #expect(points(ShapeTemplates.gear.tile) == points(ShapeTemplates.gear.icon))
  }

  @Test func theCivilSubjectKeepsTheEngineeringSymbols() throws {
    let civil = try #require(ShapePacks.all.first { $0.id == "civil" })
    #expect(civil.shapes.prefix(7).map(\.kind) == [.PIN_SUPPORT, .ROLLER_SUPPORT, .FIXED_SUPPORT, .POINT_LOAD, .DISTRIBUTED_LOAD, .MOMENT, .DIMENSION])
    #expect(civil.shapes[0].id == "kind-PIN_SUPPORT" && civil.shapes[0].label == "Pin support")
    #expect(civil.shapes[3].drawnAsLine && civil.shapes[0].drawnFromPoint)
    #expect(civil.shapes[0].cloud == nil)
  }
}

#if canImport(CoreGraphics) && canImport(ImageIO)
  import CoreGraphics
  import ImageIO

  /// Every subject's shapes on one sheet, joints in red, to look over (Android's
  /// `ShapePacksTest.contactSheet`). Written only when SHAPE_SHEET names a file.
  struct ShapePacksSheet {
    @Test func contactSheet() throws {
      guard let path = ProcessInfo.processInfo.environment["SHAPE_SHEET"], !path.isEmpty else { return }
      let cell = 130, cols = 10, left = 220
      let width = cols * cell + left, height = ShapePacks.all.count * cell
      let cg = try #require(
        CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
      cg.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
      cg.fill(CGRect(x: 0, y: 0, width: width, height: height))
      cg.translateBy(x: 0, y: CGFloat(height))
      cg.scaleBy(x: 1, y: -1)
      cg.setLineCap(.round)
      cg.setLineJoin(.round)
      for (r, pack) in ShapePacks.all.enumerated() {
        for (i, s) in pack.shapes.enumerated() {
          let x0 = Float(left + i * cell + 12), y0 = Float(r * cell + 12)
          let geo: ShapeGeometry
          if let kind = s.kind {
            geo = kind.inBox(Pt(x0, y0), Pt(x0 + 90, y0 + 90))
          } else if s.mode == .line {
            geo = s.create(Pt(x0, y0 + 45), Pt(x0 + 100, y0 + 45))
          } else {
            geo = s.create(Pt(x0, y0), Pt(x0 + 100, y0 + 95))
          }
          cg.setStrokeColor(CGColor(red: 0.16, green: 0.16, blue: 0.24, alpha: 1))
          cg.setLineWidth(1.4)
          for line in geo.paths(1.2) where line.count > 1 {
            cg.addLines(between: line.map { CGPoint(x: CGFloat($0.x), y: CGFloat($0.y)) })
            cg.strokePath()
          }
          if case let .param(p) = geo {
            cg.setFillColor(CGColor(red: 0.86, green: 0.16, blue: 0.24, alpha: 1))
            for h in p.handles() { cg.fillEllipse(in: CGRect(x: CGFloat(h.x) - 3, y: CGFloat(h.y) - 3, width: 6, height: 6)) }
          }
        }
      }
      let image = try #require(cg.makeImage())
      let out = try #require(CGImageDestinationCreateWithURL(URL(fileURLWithPath: path) as CFURL, "public.png" as CFString, 1, nil))
      CGImageDestinationAddImage(out, image, nil)
      #expect(CGImageDestinationFinalize(out))
    }
  }
#endif
