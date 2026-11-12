import SwiftUI
import TaliCore

/// The Shapes tool's own look, apart from the pen she writes with (Android's `ShapeStylePicker`),
/// in two columns that fill the panel: a preview, the outline colours and the fill colours on the
/// left; size, the two opacities (the outline's and the fill's), the line style and the shape
/// switches on the right. On a narrow screen the columns go one under the other.
struct ShapeStylePicker: View {
  var pen: PenSlot
  var compact: Bool
  @Environment(\.tali) private var c
  @AppStorage(ShapeSettings.Key.style) private var styleJSON = ""
  @AppStorage(ShapeSettings.Key.followsPen) private var followsPen = false
  @AppStorage(ShapeSettings.Key.snapShapes) private var snapShapes = true
  @AppStorage(ShapeSettings.Key.holdToShape) private var holdToShape = true

  private var own: ShapeLook { ShapeSettings.own(styleJSON) }

  private func update(_ change: (inout ShapeLook) -> Void) {
    var s = own
    change(&s)
    styleJSON = ShapeSettings.json(of: s)
  }

  var body: some View {
    let look = ShapeSettings.look(own: own, followsPen: followsPen, pen: pen)
    Spacer().frame(height: 12)
    if compact {
      VStack(alignment: .leading, spacing: 12) {
        colours(look)
        settings(look)
      }
    } else {
      // Android's columns share the panel 1 to 1.15.
      HStack(alignment: .top, spacing: 20) {
        colours(look).frame(width: 264)
        settings(look).frame(maxWidth: .infinity)
      }
    }
  }

  /// Following the pen, its colour, size and line come from the pen in use: those choices rest.
  private var resting: Double { followsPen ? 0.4 : 1 }

  private func colours(_ look: ShapeLook) -> some View {
    let outline = UInt32(bitPattern: look.color) | 0xFF00_0000
    let fill = look.fill.map { UInt32(bitPattern: $0) | 0xFF00_0000 }
    return VStack(alignment: .leading, spacing: 0) {
      ShapeStylePreview(look: look).frame(height: 88)
      Spacer().frame(height: 12)
      SectionLabel(text: L("outline_colour"))
      Spacer().frame(height: 6)
      ColourFlow {
        ForEach(Array(Palettes.shared.saved.enumerated()), id: \.element) { i, col in
          ColorDot(color: Color(argb: col), selected: col | 0xFF00_0000 == outline, size: 26) {
            if !followsPen { update { $0.color = Int32(bitPattern: col | 0xFF00_0000) } }
          }
          .accessibilityIdentifier("shape-outline-\(i)")
        }
      }
      .opacity(resting)
      Spacer().frame(height: 10)
      SectionLabel(text: L("fill"))
      Spacer().frame(height: 6)
      ColourFlow {
        NoneDot(selected: fill == nil, size: 26) { update { $0.fill = nil } }
        ForEach(Array(Palettes.shared.saved.enumerated()), id: \.element) { i, col in
          ColorDot(color: Color(argb: col), selected: col | 0xFF00_0000 == fill, size: 26) { update { $0.fill = Int32(bitPattern: col | 0xFF00_0000) } }
            .accessibilityIdentifier("shape-fill-\(i)")
        }
      }
    }
  }

  private func settings(_ look: ShapeLook) -> some View {
    VStack(alignment: .leading, spacing: 0) {
      HStack(spacing: 0) {
        Text(L("style")).font(TaliType.bodyMedium).foregroundStyle(c.inkMuted).frame(width: 84, alignment: .leading)
        Segmented(options: [false, true], selected: $followsPen) { $0 ? L("like_the_pen") : L("its_own") }
      }
      Spacer().frame(height: 6)
      HStack(spacing: 0) {
        Text(L("size")).font(TaliType.bodyMedium).foregroundStyle(c.inkMuted).frame(width: 84, alignment: .leading)
        StepSlider(value: Binding(get: { look.size }, set: { v in if !followsPen { update { $0.size = v } } }), range: ShapeLook.minSize...ShapeLook.maxSize, step: 0.5)
        Text(String(format: "%.1f", look.size)).font(TaliType.titleSmall).foregroundStyle(c.ink).frame(width: 40, alignment: .trailing).padding(.leading, 8)
      }
      .opacity(resting)
      OpacitySlider(label: L("opacity"), value: look.opacity, least: ShapeLook.minOpacity, enabled: true) { v in update { $0.opacity = v } }
      OpacitySlider(label: L("fill_opacity"), value: look.fillOpacity, least: ShapeLook.minOpacity, enabled: look.fill != nil) { v in update { $0.fillOpacity = v } }
      Spacer().frame(height: 4)
      CompactLineStylePicker(selected: look.line) { l in if !followsPen { update { $0.line = l } } }
        .opacity(resting)
      Spacer().frame(height: 8)
      ToggleRow(label: L("snap_to_other_shapes"), on: $snapShapes, detail: L("ends_and_edges_lock_on_shapes"))
      ToggleRow(label: L("hold_to_perfect_shapes"), on: $holdToShape, detail: L("pause_at_the_end_of_a"))
    }
  }
}

/// Colour dots in rows that wrap, a hair apart.
struct ColourFlow<Content: View>: View {
  @ViewBuilder var content: Content

  var body: some View {
    LazyVGrid(columns: [GridItem(.adaptive(minimum: 34, maximum: 34), spacing: 1)], alignment: .leading, spacing: 1) { content }
  }
}

/// An opacity up to 100% in 5% steps, with its percentage; faded while it has nothing to act on.
struct OpacitySlider: View {
  var label: String
  var value: Float
  var least: Float
  var enabled: Bool
  var labelWidth: CGFloat = 84
  var onChange: (Float) -> Void
  @Environment(\.tali) private var c

  var body: some View {
    HStack(spacing: 0) {
      Text(label).font(TaliType.bodyMedium).foregroundStyle(c.inkMuted).frame(width: labelWidth, alignment: .leading)
      Slider(
        value: Binding(get: { Double(value) }, set: { onChange(min(max(Float(($0 * 20).rounded() / 20), least), 1)) }),
        in: Double(least)...1
      )
      .tint(c.accent)
      .disabled(!enabled)
      .accessibilityLabel(label)
      Text(L("n", Int((value * 100).rounded()))).font(TaliType.titleSmall).foregroundStyle(c.ink).frame(width: 40, alignment: .trailing).padding(.leading, 8)
    }
    .frame(minHeight: 40)
    .opacity(enabled ? 1 : 0.4)
  }
}

/// A box and an arrow drawn in the shape style (opacities too), so each change shows at once.
struct ShapeStylePreview: View {
  var look: ShapeLook
  @Environment(\.tali) private var c

  var body: some View {
    Canvas { ctx, size in
      let w = max(CGFloat(look.size) * 0.9, 1)
      let style = LineStyle(rawValue: look.line) ?? .SOLID
      // Cut into pieces as the page cuts a dashed shape (Android's `StrokeFactory.dashes`).
      func pieces(_ points: [CGPoint]) -> Path {
        var p = Path()
        let line = points.map { Pt(Float($0.x), Float($0.y)) }
        for part in style == .SOLID ? [line] : Dashes.cut(line, size: Float(w), line: style) where part.count > 1 {
          p.addLines(part.map { CGPoint(x: CGFloat($0.x), y: CGFloat($0.y)) })
        }
        return p
      }
      let ink = Color(uiColor: UIColor(argb: look.outlineArgb))
      let box = CGRect(x: size.width * 0.1, y: size.height * 0.2, width: size.width * 0.42, height: size.height * 0.6)
      if let fill = look.fillArgb { ctx.fill(Path(box), with: .color(Color(uiColor: UIColor(argb: fill)))) }
      let corners = [CGPoint(x: box.minX, y: box.minY), CGPoint(x: box.maxX, y: box.minY), CGPoint(x: box.maxX, y: box.maxY), CGPoint(x: box.minX, y: box.maxY), CGPoint(x: box.minX, y: box.minY)]
      ctx.stroke(pieces(corners), with: .color(ink), style: StrokeStyle(lineWidth: w, lineCap: .round, lineJoin: .round))
      let a = CGPoint(x: size.width * 0.62, y: size.height * 0.74), b = CGPoint(x: size.width * 0.9, y: size.height * 0.26)
      ctx.stroke(pieces([a, b]), with: .color(ink), style: StrokeStyle(lineWidth: w, lineCap: .round))
      // The arrowhead stays solid, as on the page.
      let len = hypot(b.x - a.x, b.y - a.y)
      let dir = CGPoint(x: (b.x - a.x) / len, y: (b.y - a.y) / len)
      let head = max(10, w * 3.5)
      var barbs = Path()
      for turn in [0.52, -0.52] {
        barbs.move(to: b)
        barbs.addLine(to: CGPoint(x: b.x - (dir.x * cos(turn) - dir.y * sin(turn)) * head, y: b.y - (dir.x * sin(turn) + dir.y * cos(turn)) * head))
      }
      ctx.stroke(barbs, with: .color(ink), style: StrokeStyle(lineWidth: w, lineCap: .round))
    }
    .background(c.paper)
    .clipShape(RoundedRectangle(cornerRadius: 14))
    .overlay(RoundedRectangle(cornerRadius: 14).stroke(c.line, lineWidth: 1))
    .accessibilityHidden(true)
  }
}

/// The "none" choice among colours: an empty circle with a red slash (Android's `NoneDot`).
struct NoneDot: View {
  var selected: Bool
  var size: CGFloat = 30
  var action: () -> Void
  @Environment(\.tali) private var c

  var body: some View {
    Button(action: action) {
      Canvas { ctx, sz in
        let circle = Path(ellipseIn: CGRect(origin: .zero, size: sz).insetBy(dx: 0.5, dy: 0.5))
        ctx.fill(circle, with: .color(c.surface))
        ctx.stroke(circle, with: .color(c.line), lineWidth: 1)
        var slash = Path()
        slash.move(to: CGPoint(x: sz.width * 0.22, y: sz.height * 0.78))
        slash.addLine(to: CGPoint(x: sz.width * 0.78, y: sz.height * 0.22))
        ctx.stroke(slash, with: .color(c.danger), lineWidth: 2)
      }
      .frame(width: size, height: size)
      .padding(4)
      .overlay(Circle().stroke(c.accent, lineWidth: 2).opacity(selected ? 1 : 0))
      .animation(.spring(response: 0.25, dampingFraction: 0.8), value: selected)
    }
    .buttonStyle(.plain)
    .accessibilityLabel(L("no_fill"))
    .accessibilityAddTraits(selected ? .isSelected : [])
    .accessibilityIdentifier("no-fill")
  }
}

/// The six line styles in one row, each a straight stroke with no label (Android's
/// `CompactLineStylePicker`), with a highlight that glides to the chosen one.
struct CompactLineStylePicker: View {
  var selected: String
  var onPick: (String) -> Void
  @Environment(\.tali) private var c
  @Namespace private var glide

  var body: some View {
    HStack(spacing: 2) {
      ForEach(ShapeLook.lines, id: \.self) { line in
        let on = line == selected
        Canvas { ctx, size in
          var p = Path()
          p.move(to: CGPoint(x: size.width * 0.15, y: size.height / 2))
          p.addLine(to: CGPoint(x: size.width * 0.85, y: size.height / 2))
          ctx.stroke(p, with: .color(on ? c.accent : c.ink), style: StrokeStyle(lineWidth: 2, lineCap: .round, dash: (LineStyle(rawValue: line) ?? .SOLID).dash(width: 2)))
        }
        .frame(maxWidth: .infinity).frame(height: 30)
        .background {
          if on { RoundedRectangle(cornerRadius: 10).fill(c.accentSoft).matchedGeometryEffect(id: "line", in: glide) }
        }
        .contentShape(Rectangle())
        .onTapGesture { withAnimation(.spring(response: 0.3, dampingFraction: 0.82)) { onPick(line) } }
        .accessibilityLabel(lineStyleName(line))
        .accessibilityAddTraits(on ? [.isButton, .isSelected] : .isButton)
        .accessibilityIdentifier("line-\(line)")
      }
    }
  }
}
