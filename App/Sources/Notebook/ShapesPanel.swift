import SwiftUI
import TaliCore

/// A shape kind drawn small (Android's `ShapeIcon`): built on a 66-unit grid and scaled, so
/// arrowheads are the same share of the tile at any size.
struct ShapeIcon: View {
  var kind: ShapeKind
  var color: Color
  var size: CGFloat = 26

  var body: some View {
    Canvas { ctx, sz in
      let grid: Float = 66, pad: Float = 8
      let g = kind.inBox(Pt(pad, pad + (kind == .ELLIPSE ? 14 : 0)), Pt(grid - pad, grid - pad - (kind == .ELLIPSE ? 14 : 0)))
      let k = sz.width / CGFloat(grid)
      var path = Path()
      for line in g.paths(2.6) where line.count > 1 {
        path.move(to: CGPoint(x: CGFloat(line[0].x) * k, y: CGFloat(line[0].y) * k))
        for p in line.dropFirst() { path.addLine(to: CGPoint(x: CGFloat(p.x) * k, y: CGFloat(p.y) * k)) }
      }
      ctx.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round))
    }
    .frame(width: size, height: size)
  }
}

/// The name of a shape kind in the app's language (Android's `ShapeKind.nameRes`).
func shapeName(_ k: ShapeKind) -> String { L("shape_" + k.rawValue.lowercased()) }

/// The Shapes tool's panel (Android's `ShapesPanel`, its Choose tab): a tile per shape, the chosen
/// one in soft blue. The engineering symbols sit under Civil (on Android they're the Civil subject).
struct ShapesPanel: View {
  @Binding var kind: ShapeKind
  var onPick: () -> Void = {}
  @Environment(\.tali) private var c

  private let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 6)

  var body: some View {
    ToolPanel(width: 600) {
      Text(L("shapes")).font(TaliType.titleLarge).foregroundStyle(c.ink)
      Spacer().frame(height: 12)
      section(L("shapes"), ShapeKind.offered.filter { !$0.engineering })
      Spacer().frame(height: 12)
      section(L("subject_civil"), ShapeKind.offered.filter(\.engineering))
    }
  }

  private func section(_ title: String, _ kinds: [ShapeKind]) -> some View {
    VStack(alignment: .leading, spacing: 6) {
      Text(title).font(TaliType.labelMedium).foregroundStyle(c.inkFaint)
      LazyVGrid(columns: columns, spacing: 8) {
        ForEach(kinds, id: \.self) { k in tile(k) }
      }
    }
  }

  private func tile(_ k: ShapeKind) -> some View {
    let on = k == kind
    return Button {
      withAnimation(.easeOut(duration: 0.15)) { kind = k }
      onPick()
    } label: {
      VStack(spacing: 4) {
        ShapeIcon(kind: k, color: on ? c.blue : c.ink)
        Text(shapeName(k)).font(TaliType.labelSmall).foregroundStyle(on ? c.blue : c.inkMuted).lineLimit(1).minimumScaleFactor(0.7)
      }
      .frame(maxWidth: .infinity).frame(height: 62)
      .background(RoundedRectangle(cornerRadius: 12).fill(on ? c.blueSoft : c.accentSoft.opacity(0.5)))
    }
    .buttonStyle(PressStyle(scale: 0.95))
    .accessibilityLabel(shapeName(k))
    .accessibilityIdentifier("shape-\(k.rawValue)")
  }
}
