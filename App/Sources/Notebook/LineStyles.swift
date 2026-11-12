import SwiftUI
import TaliCore

func lineStyleName(_ style: LineStyle) -> String {
  switch style {
  case .SOLID: L("line_style_solid")
  case .DOTTED: L("line_style_dotted")
  case .LONG_DASH: L("line_style_long_dash")
  case .SHORT_DASH: L("line_style_short_dash")
  case .DOT_DASH: L("line_style_dot_dash")
  case .MIXED_DASH: L("line_style_mixed_dash")
  }
}

extension LineStyle {
  func dash(width: CGFloat) -> [CGFloat] { intervals(width: Float(width)).map { CGFloat($0) } }
}

/// Android's `LineStylePicker`: the six line styles as tiles, three to a row, one highlight gliding to the chosen one.
struct LineStylePicker: View {
  @Binding var selected: LineStyle
  @Environment(\.tali) private var c
  @Namespace private var glide

  var body: some View {
    VStack(spacing: 6) {
      ForEach([Array(LineStyle.allCases.prefix(3)), Array(LineStyle.allCases.dropFirst(3))], id: \.self) { row in
        HStack(spacing: 6) {
          ForEach(row, id: \.self) { style in tile(style) }
        }
      }
    }
  }

  private func tile(_ style: LineStyle) -> some View {
    let on = style == selected
    return VStack(spacing: 4) {
      LineSample(style: style, color: on ? c.accent : c.ink)
      Text(lineStyleName(style)).font(TaliType.labelSmall).foregroundStyle(on ? c.accent : c.inkMuted).lineLimit(1).padding(.horizontal, 4)
    }
    .padding(.vertical, 8)
    .frame(maxWidth: .infinity)
    .background {
      if on { RoundedRectangle(cornerRadius: 14).fill(c.accentSoft).matchedGeometryEffect(id: "line", in: glide) }
    }
    .overlay(RoundedRectangle(cornerRadius: 14).stroke(on ? Color.clear : c.line, lineWidth: 1))
    .contentShape(Rectangle())
    .onTapGesture {
      withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) { selected = style }
    }
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(lineStyleName(style))
    .accessibilityAddTraits(on ? [.isButton, .isSelected] : .isButton)
  }
}

/// Android's `LineSample`: a short S-shaped stroke drawn in the style, like a pen mark.
struct LineSample: View {
  var style: LineStyle
  var color: Color
  var width: CGFloat = 1.8

  var body: some View {
    Canvas { ctx, size in
      var path = Path()
      path.move(to: CGPoint(x: size.width * 0.12, y: size.height * 0.82))
      path.addCurve(
        to: CGPoint(x: size.width * 0.88, y: size.height * 0.18), control1: CGPoint(x: size.width * 0.55, y: size.height * 0.95),
        control2: CGPoint(x: size.width * 0.45, y: size.height * 0.05))
      ctx.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: width, lineCap: .round, dash: style.dash(width: width)))
    }
    .frame(width: 58, height: 30)
  }
}
