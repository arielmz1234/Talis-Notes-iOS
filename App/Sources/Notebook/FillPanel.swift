import SwiftUI
import TaliCore

/// The fill tool's panel (Android's `FillPanel`): a colour, or "None" to take fills away, and how
/// strongly it covers the paper. Tap inside a closed shape to fill the shape; tap inside an area
/// drawn around by hand to fill it behind the writing.
struct FillPanel: View {
  @Environment(\.tali) private var c
  @AppStorage(ShapeSettings.Key.fillColor) private var colour = ShapeSettings.defaultFill
  @AppStorage(ShapeSettings.Key.fillNone) private var none = false
  @AppStorage(ShapeSettings.Key.fillOpacity) private var opacity = ShapeSettings.defaultFillOpacity

  var body: some View {
    ToolPanel(width: 360) {
      Text(L("fill")).font(TaliType.titleLarge).foregroundStyle(c.ink)
      Spacer().frame(height: 14)
      Text(L("tap_inside_a_shape_or_inside")).font(TaliType.bodyMedium).foregroundStyle(c.inkMuted)
      Spacer().frame(height: 14)
      SectionLabel(text: L("colour"))
      Spacer().frame(height: 8)
      LazyVGrid(columns: [GridItem(.adaptive(minimum: 38, maximum: 38), spacing: 2)], alignment: .leading, spacing: 2) {
        ForEach(Array(Palette.saved.enumerated()), id: \.element) { i, col in
          ColorDot(color: Color(argb: col), selected: !none && UInt32(truncatingIfNeeded: colour) == col) {
            colour = Int(col)
            none = false
          }
          .accessibilityIdentifier("fill-colour-\(i)")
        }
        NoneDot(selected: none) { none = true }
      }
      if none {
        Spacer().frame(height: 10)
        Text(L("tap_a_filled_shape_or_area")).font(TaliType.bodySmall).foregroundStyle(c.inkFaint)
      } else {
        Spacer().frame(height: 12)
        OpacitySlider(label: L("opacity"), value: Float(opacity), least: FillColour.minOpacity, enabled: true, labelWidth: 64) { opacity = Double($0) }
      }
    }
  }
}

/// The fill tool's icon: a tipped paint pot with a drop and a bar of colour under it (the outline
/// Android's toolbar uses), drawn on a 24-unit grid.
struct FillIcon: View {
  var color: Color
  var size: CGFloat = 22

  var body: some View {
    Canvas { ctx, sz in
      let k = sz.width / 24
      func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x * k, y: y * k) }
      var p = Path()
      p.move(to: pt(16.56, 8.94))
      p.addLine(to: pt(7.62, 0))
      p.addLine(to: pt(6.21, 1.41))
      p.addLine(to: pt(8.59, 3.79))
      p.addLine(to: pt(3.44, 8.94))
      p.addCurve(to: pt(3.44, 11.06), control1: pt(2.85, 9.53), control2: pt(2.85, 10.48))
      p.addLine(to: pt(8.94, 16.56))
      p.addCurve(to: pt(10, 17), control1: pt(9.23, 16.85), control2: pt(9.62, 17))
      p.addCurve(to: pt(11.06, 16.56), control1: pt(10.38, 17), control2: pt(10.77, 16.85))
      p.addLine(to: pt(16.56, 11.06))
      p.addCurve(to: pt(16.56, 8.94), control1: pt(17.15, 10.48), control2: pt(17.15, 9.53))
      p.closeSubpath()
      p.move(to: pt(5.21, 10))
      p.addLine(to: pt(10, 5.21))
      p.addLine(to: pt(14.79, 10))
      p.closeSubpath()
      p.move(to: pt(19, 11.5))
      p.addCurve(to: pt(17, 15), control1: pt(19, 11.5), control2: pt(17, 13.67))
      p.addCurve(to: pt(19, 17), control1: pt(17, 16.1), control2: pt(17.9, 17))
      p.addCurve(to: pt(21, 15), control1: pt(20.1, 17), control2: pt(21, 16.1))
      p.addCurve(to: pt(19, 11.5), control1: pt(21, 13.67), control2: pt(19, 11.5))
      p.closeSubpath()
      p.addRect(CGRect(x: 2 * k, y: 20 * k, width: 20 * k, height: 4 * k))
      ctx.fill(p, with: .color(color), style: FillStyle(eoFill: true))
    }
    .frame(width: size, height: size)
    .accessibilityHidden(true)
  }
}
