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
      let mid = Pt(grid / 2, grid / 2), r = grid / 2 - pad
      let g: ShapeGeometry
      switch kind {
      // Drawn from their centre, so their icons are built round the tile's middle.
      case .CIRCLE: g = .ellipse(center: mid, rx: r, ry: r, rotation: 0)
      case .PART_CIRCLE: g = .sector(center: mid, radius: r, start: .pi / 4, sweep: 1.5 * .pi)
      case .ELLIPSE: g = kind.inBox(Pt(pad, pad + 14), Pt(grid - pad, grid - pad - 14))
      default: g = kind.inBox(Pt(pad, pad), Pt(grid - pad, grid - pad))
      }
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
  /// The pens and the one in use, for the Style tab's "Like the pen".
  var pens: [PenSlot] = []
  var activePen: String? = nil
  var onPick: () -> Void = {}
  @Environment(\.tali) private var c

  private let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 6)

  /// Two pages: the shapes to draw, and how they're drawn (kept while the app is open, as Android).
  @State private var styling = ShapesPanel.lastStyling
  @MainActor private static var lastStyling = false

  var body: some View {
    ToolPanel(width: 600) {
      HStack {
        Text(L("shapes")).font(TaliType.titleLarge).foregroundStyle(c.ink)
        Spacer(minLength: 12)
        Segmented(options: [false, true], selected: $styling) { $0 ? L("style") : L("choose") }
          .frame(width: 220)
          .accessibilityElement(children: .contain)
          .accessibilityIdentifier("shapes-tabs")
      }
      .onChange(of: styling) { _, v in ShapesPanel.lastStyling = v }
      Spacer().frame(height: 4)
      if styling {
        ShapeStylePicker(pens: pens, activePen: activePen)
      } else {
        Spacer().frame(height: 8)
        section(L("shapes"), ShapeKind.offered.filter { !$0.engineering })
        Spacer().frame(height: 12)
        section(L("subject_civil"), ShapeKind.offered.filter(\.engineering))
      }
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

/// The Shapes tool's own look (Android's `ShapeStylePicker`), apart from the pen she writes with, in
/// two columns that fill the panel: a preview, the outline colours and the fill colours on the left;
/// Its own / Like the pen, size, the two opacities, the line style and the shape switches on the right.
/// On a phone the columns stack and scroll.
struct ShapeStylePicker: View {
  var pens: [PenSlot]
  var activePen: String?
  @AppStorage("shapeStyle") private var raw = ""
  @AppStorage("shapeFollowsPen") private var followsPen = false
  @AppStorage("snapShapes") private var snaps = true
  @AppStorage("holdToShape") private var holdToShape = true
  @Environment(\.horizontalSizeClass) private var sizeClass
  @Environment(\.tali) private var c

  private var own: TaliCore.ShapeStyle { TaliCore.ShapeStyle.own(ShapeLook.decode(raw), firstColor: ShapeLook.firstColor) }
  private var look: TaliCore.ShapeStyle {
    let p = ShapeLook.slot(pens.first { $0.id == activePen }, pens)
    return TaliCore.ShapeStyle.look(own: own, followsPen: followsPen, penColor: p.color, penSize: p.size)
  }
  private func update(_ f: (inout TaliCore.ShapeStyle) -> Void) {
    var s = own
    f(&s)
    raw = ShapeLook.encode(s)
  }

  var body: some View {
    if sizeClass == .compact {
      ScrollView {
        VStack(alignment: .leading, spacing: 14) {
          left
          right
        }
      }
      .frame(maxHeight: 400)
      .padding(.top, 10)
    } else {
      HStack(alignment: .top, spacing: 20) {
        left.frame(maxWidth: .infinity)
        right.frame(maxWidth: .infinity)
      }
      .padding(.top, 12)
    }
  }

  private static func opaque(_ v: Int32) -> UInt32 { UInt32(bitPattern: v) | 0xFF00_0000 }

  private var left: some View {
    let l = look
    let outline = Self.opaque(l.color)
    let fill = l.fill.map(Self.opaque)
    let following = followsPen
    return VStack(alignment: .leading, spacing: 0) {
      ShapeStylePreview(look: l).frame(height: 88)
      Spacer().frame(height: 12)
      SectionLabel(text: L("outline_colour"))
      Spacer().frame(height: 6)
      colours(selected: outline, none: false) { col in
        if !following, let col { update { $0.color = Int32(bitPattern: col | 0xFF00_0000) } }
      }
      .opacity(following ? 0.4 : 1)
      Spacer().frame(height: 10)
      SectionLabel(text: L("fill"))
      Spacer().frame(height: 6)
      colours(selected: fill, none: true) { col in
        update { $0.fill = col.map { Int32(bitPattern: $0 | 0xFF00_0000) } }
      }
    }
  }

  private var right: some View {
    let l = look
    let following = followsPen
    return VStack(alignment: .leading, spacing: 6) {
      HStack {
        Text(L("style")).font(TaliType.bodyMedium).foregroundStyle(c.inkMuted).frame(width: 84, alignment: .leading)
        Segmented(options: [false, true], selected: $followsPen) { $0 ? L("like_the_pen") : L("its_own") }
      }
      HStack {
        Text(L("size")).font(TaliType.bodyMedium).foregroundStyle(c.inkMuted).frame(width: 84, alignment: .leading)
        StepSlider(
          value: Binding(get: { l.size }, set: { v in if !following { update { $0.size = v } } }),
          range: TaliCore.ShapeStyle.minSize...TaliCore.ShapeStyle.maxSize, step: 0.5)
        Text(String(format: "%.1f", l.size)).font(TaliType.titleSmall).foregroundStyle(c.ink).frame(width: 40, alignment: .leading)
      }
      .opacity(following ? 0.4 : 1)
      OpacitySlider(label: L("opacity"), value: l.opacity, enabled: true) { v in update { $0.opacity = v } }
      OpacitySlider(label: L("fill_opacity"), value: l.fillOpacity, enabled: l.fill != nil) { v in update { $0.fillOpacity = v } }
      CompactLineStylePicker(line: l.line, width: l.size) { v in if !following { update { $0.line = v } } }
        .opacity(following ? 0.4 : 1)
        .padding(.top, 4)
      ToggleRow(label: L("snap_to_other_shapes"), on: $snaps, detail: L("ends_and_edges_lock_on_shapes"))
      ToggleRow(label: L("hold_to_perfect_shapes"), on: $holdToShape, detail: L("pause_at_the_end_of_a"))
    }
  }

  /// Her saved colours as dots (with "none" first for the fill), the chosen one ringed.
  private func colours(selected: UInt32?, none: Bool, pick: @escaping (UInt32?) -> Void) -> some View {
    LazyVGrid(columns: [GridItem(.adaptive(minimum: 34, maximum: 34), spacing: 1)], alignment: .leading, spacing: 1) {
      if none { NoneDot(selected: selected == nil) { pick(nil) } }
      ForEach(Palette.saved, id: \.self) { col in
        ColorDot(color: Color(argb: col), selected: selected == (col | 0xFF00_0000), size: 26) { pick(col) }
      }
    }
  }
}

/// An opacity from 10% to 100% in 5% steps, with its percentage; faded while it has nothing to act on.
struct OpacitySlider: View {
  var label: String
  var value: Float
  var enabled: Bool
  var onChange: (Float) -> Void
  @Environment(\.tali) private var c

  var body: some View {
    HStack {
      Text(label).font(TaliType.bodyMedium).foregroundStyle(c.inkMuted).frame(width: 84, alignment: .leading)
      Slider(
        value: Binding(get: { Double(value) }, set: { v in
          onChange(min(max(Float((v * 20).rounded() / 20), TaliCore.ShapeStyle.minOpacity), 1))
        }),
        in: Double(TaliCore.ShapeStyle.minOpacity)...1
      )
      .tint(c.accent)
      .disabled(!enabled)
      Text(L("n", Int((value * 100).rounded()))).font(TaliType.titleSmall).foregroundStyle(c.ink).frame(width: 48, alignment: .leading)
    }
    .opacity(enabled ? 1 : 0.4)
  }
}

/// The "none" choice in a colour ring: an empty circle with a red slash (Android's `NoneDot`).
struct NoneDot: View {
  var selected: Bool
  var action: () -> Void
  @Environment(\.tali) private var c

  var body: some View {
    Button(action: action) {
      Canvas { ctx, sz in
        let r = CGRect(origin: .zero, size: sz).insetBy(dx: 0.5, dy: 0.5)
        ctx.fill(Path(ellipseIn: r), with: .color(c.surface))
        ctx.stroke(Path(ellipseIn: r), with: .color(c.line), lineWidth: 1)
        var slash = Path()
        slash.move(to: CGPoint(x: sz.width * 0.22, y: sz.height * 0.78))
        slash.addLine(to: CGPoint(x: sz.width * 0.78, y: sz.height * 0.22))
        ctx.stroke(slash, with: .color(c.danger), lineWidth: 2)
      }
      .frame(width: 26, height: 26)
      .padding(4)
      .overlay(Circle().stroke(c.accent, lineWidth: 2).opacity(selected ? 1 : 0))
      .animation(.spring(response: 0.25, dampingFraction: 0.8), value: selected)
    }
    .buttonStyle(.plain)
    .accessibilityLabel(L("no_fill"))
  }
}

/// A box and an arrow drawn in the shape style (opacities too), so each change shows at once
/// (Android's `ShapeStylePreview`).
struct ShapeStylePreview: View {
  var look: TaliCore.ShapeStyle
  @Environment(\.tali) private var c

  var body: some View {
    let look = look
    Canvas { ctx, size in
      let w = max(CGFloat(look.size) * 0.9, 1)
      let dash = LineDash.pattern(look.line, width: w) ?? []
      let style = StrokeStyle(lineWidth: w, lineCap: .round, lineJoin: .round, dash: dash)
      let ink = Color(argb: UInt32(bitPattern: look.color) | 0xFF00_0000).opacity(Double(look.opacity))
      let box = CGRect(x: size.width * 0.1, y: size.height * 0.2, width: size.width * 0.42, height: size.height * 0.6)
      if let f = look.fill {
        ctx.fill(Path(box), with: .color(Color(argb: UInt32(bitPattern: f) | 0xFF00_0000).opacity(Double(look.fillOpacity))))
      }
      ctx.stroke(Path(box), with: .color(ink), style: style)
      let a = CGPoint(x: size.width * 0.62, y: size.height * 0.74)
      let b = CGPoint(x: size.width * 0.9, y: size.height * 0.26)
      var line = Path()
      line.move(to: a)
      line.addLine(to: b)
      ctx.stroke(line, with: .color(ink), style: style)
      // The arrowhead stays solid, as on the page.
      let len = max(hypot(b.x - a.x, b.y - a.y), 1)
      let dx = (b.x - a.x) / len
      let dy = (b.y - a.y) / len
      let head = max(10, w * 3.5)
      var barbs = Path()
      for turn: CGFloat in [0.52, -0.52] {
        let bx = dx * cos(turn) - dy * sin(turn)
        let by = dx * sin(turn) + dy * cos(turn)
        barbs.move(to: b)
        barbs.addLine(to: CGPoint(x: b.x - bx * head, y: b.y - by * head))
      }
      ctx.stroke(barbs, with: .color(ink), style: StrokeStyle(lineWidth: w, lineCap: .round))
    }
    .background(RoundedRectangle(cornerRadius: 14).fill(c.paper))
    .clipShape(RoundedRectangle(cornerRadius: 14))
    .overlay(RoundedRectangle(cornerRadius: 14).stroke(c.line, lineWidth: 1))
  }
}

/// Six unlabelled straight strokes, one per line style, the chosen one with a gliding highlight
/// (Android's `CompactLineStylePicker`).
struct CompactLineStylePicker: View {
  var line: String
  var width: Float = 2.4
  var onPick: (String) -> Void
  @Environment(\.tali) private var c
  @Namespace private var glide

  static let styles = ["SOLID", "DOTTED", "LONG_DASH", "SHORT_DASH", "DOT_DASH", "MIXED_DASH"]

  var body: some View {
    HStack(spacing: 2) {
      ForEach(Self.styles, id: \.self) { st in
        let on = st == line
        let tint = on ? c.blue : c.ink
        let w = min(max(CGFloat(width), 1.5), 3.5)
        Canvas { ctx, size in
          var p = Path()
          p.move(to: CGPoint(x: 8, y: size.height / 2))
          p.addLine(to: CGPoint(x: size.width - 8, y: size.height / 2))
          ctx.stroke(p, with: .color(tint), style: StrokeStyle(lineWidth: w, lineCap: .round, dash: LineDash.pattern(st, width: w) ?? []))
        }
        .frame(maxWidth: .infinity)
        .frame(height: 36)
        .background {
          if on { RoundedRectangle(cornerRadius: 10).fill(c.blueSoft).matchedGeometryEffect(id: "line", in: glide) }
        }
        .contentShape(Rectangle())
        .onTapGesture { withAnimation(.spring(response: 0.3, dampingFraction: 0.82)) { onPick(st) } }
        .accessibilityLabel(L("line_style_" + st.lowercased()))
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("line-\(st)")
      }
    }
  }
}
