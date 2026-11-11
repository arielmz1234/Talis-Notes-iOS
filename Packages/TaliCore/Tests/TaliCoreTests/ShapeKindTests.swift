import Foundation
import Testing
@testable import TaliCore

/// The Shapes tool's kinds, as Android's `ShapeKind.create` / `buildShape` draw them.
struct ShapeKindTests {
  @Test func aNearlySquareRectangleIsASquare() throws {
    guard case let .poly(p, true, _, _, _) = ShapeKind.RECTANGLE.drawn(Pt(0, 0), Pt(100, 97)) else { Issue.record("not a poly"); return }
    #expect(abs(p[0].dist(p[1]) - p[1].dist(p[2])) < 0.01)
    guard case let .poly(q, true, _, _, _) = ShapeKind.RECTANGLE.drawn(Pt(0, 0), Pt(100, 60)) else { Issue.record("not a poly"); return }
    #expect(abs(q[1].dist(q[2]) - 60) < 0.01)
  }

  @Test func linesKeepToTidyAnglesUnlessTheirEndStuck() {
    guard case let .line(a, b, _, true, _) = ShapeKind.ARROW.drawn(Pt(0, 0), Pt(200, 8)) else { Issue.record("not an arrow"); return }
    #expect(abs(a.y - b.y) < 0.01)
    guard case let .line(_, kept, _, _, _) = ShapeKind.LINE.drawn(Pt(0, 0), Pt(200, 8), keepEnd: true) else { Issue.record("not a line"); return }
    #expect(kept == Pt(200, 8))
  }

  @Test func aSupportHangsFromWhereThePenLanded() throws {
    let g = ShapeKind.PIN_SUPPORT.drawn(Pt(50, 50), Pt(50, 110))
    let all = g.paths(1).joined()
    let top = try #require(all.min { $0.y < $1.y })
    #expect(abs(top.y - 50) < 0.01 && abs(top.x - 50) < 0.01)
  }

  @Test func aCircleIsDrawnFromItsCentre() {
    guard case let .ellipse(c, rx, ry, _, _) = ShapeKind.CIRCLE.drawn(Pt(10, 10), Pt(40, 50)) else { Issue.record("not a circle"); return }
    #expect(c == Pt(10, 10) && rx == 50 && ry == 50)
  }

  @Test func everyOfferedKindDrawsSomething() {
    for k in ShapeKind.offered {
      #expect(!k.drawn(Pt(0, 0), Pt(120, 80)).paths(2).isEmpty, "\(k)")
    }
  }
}
