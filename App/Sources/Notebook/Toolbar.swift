import SwiftUI

// The notebook's main toolbar and its panels, ported from Android's `ui/notebook/Toolbar.kt` and
// `Panels.kt`: the pen tray (pens standing at the bottom edge, the active one lifted), the arrow to
// the pen's settings, her first few colours, her three thicknesses, then the tools.

/// Which panel hangs under the toolbar.
enum PanelKind { case pen, eraser }

/// Saved colours (Android's `savedColors` / `highlighterColors`) and how many sit in the toolbar.
enum Palette {
  static let defaultHighlighter: [UInt32] = [0xFFFF_D60A, 0xFFFF_6FA8, 0xFF5A_A9E6, 0xFF7D_DB8A, 0xFFFF_A94D]

  static var saved: [UInt32] {
    get { (UserDefaults.standard.array(forKey: "savedColors") as? [Int])?.map { UInt32(truncatingIfNeeded: $0) } ?? PenSlot.defaultColors }
    set { UserDefaults.standard.set(newValue.map { Int($0) }, forKey: "savedColors") }
  }
  static var highlighter: [UInt32] {
    get { (UserDefaults.standard.array(forKey: "highlighterColors") as? [Int])?.map { UInt32(truncatingIfNeeded: $0) } ?? defaultHighlighter }
    set { UserDefaults.standard.set(newValue.map { Int($0) }, forKey: "highlighterColors") }
  }
  /// How many colours a pen shows in the toolbar until it has its own number (Android's default 3).
  static var toolbarColors: Int { UserDefaults.standard.object(forKey: "toolbarColors") as? Int ?? 3 }

  static func colors(for pen: PenSlot) -> [UInt32] { pen.type == .HIGHLIGHTER ? highlighter : saved }
  static func toolbarCount(for pen: PenSlot) -> Int { pen.toolbarColors ?? toolbarColors }
}

extension PenSlot {
  /// The three thicknesses; until she sets them, a thinner and a thicker one around [size] (Android's `presetSizes`).
  var presetSizes: [Float] {
    if sizes.count == 3 { return sizes }
    func half(_ v: Float) -> Float { (v * 2).rounded() / 2 }
    let minSize: Float = 0.5
    let thin = min(max(half(size * 0.6), minSize), size)
    let thick = min(max(half(size * 1.6), size), type.maxSize)
    switch min(max(sizeSlot, 0), 2) {
    case 0: return [size, min(half(size * 1.6), type.maxSize), min(half(size * 2.5), type.maxSize)]
    case 2: return [max(half(size * 0.4), minSize), thin, size]
    default: return [thin, size, thick]
    }
  }

  /// A new thickness for the one of the three she's on.
  func withSize(_ v: Float) -> PenSlot {
    var p = self
    var all = presetSizes
    all[min(max(sizeSlot, 0), 2)] = v
    p.size = v
    p.sizes = all
    return p
  }

  /// Switches to her [i]th thickness.
  func pickSize(_ i: Int) -> PenSlot {
    var p = self
    let all = presetSizes
    p.sizeSlot = i
    p.size = all[i]
    p.sizes = all
    return p
  }
}

/// A pen drawn like a real tool standing in a tray (Android's `PenGlyph`): neutral body, a coloured
/// band, and a tip shaped by its style. 26 × 56 pt, the tip pointing up.
struct PenGlyph: View {
  var type: PenType
  var color: Color
  @Environment(\.tali) private var c

  var body: some View {
    Canvas { ctx, size in
      let u = size.width / 26
      let cx = size.width / 2
      let bodyFill = c.isDark ? Color(argb: 0xFFD6_CFEC) : Color(argb: 0xFFF1_ECFA)
      let outline = c.isDark ? Color(argb: 0xFFA9_9DCC) : Color(argb: 0xFFD8_CCEE)
      let wood = Color(argb: 0xFFE9_C9A0)
      let half = (type == .HIGHLIGHTER ? 8 : 6.5) * u
      let bodyTop = 20 * u
      let bodyRect = CGRect(x: cx - half, y: bodyTop, width: half * 2, height: size.height - bodyTop + 6 * u)
      ctx.fill(Path(roundedRect: bodyRect, cornerRadius: 3 * u), with: .color(bodyFill))
      ctx.stroke(Path(roundedRect: bodyRect, cornerRadius: 3 * u), with: .color(outline), lineWidth: u)
      ctx.fill(Path(CGRect(x: cx - half, y: bodyTop + 9 * u, width: half * 2, height: 4 * u)), with: .color(color))
      func cone(_ top: CGFloat, _ topHalf: CGFloat) {
        var p = Path()
        p.move(to: CGPoint(x: cx - half, y: bodyTop))
        p.addLine(to: CGPoint(x: cx - topHalf, y: top))
        p.addLine(to: CGPoint(x: cx + topHalf, y: top))
        p.addLine(to: CGPoint(x: cx + half, y: bodyTop))
        p.closeSubpath()
        ctx.fill(p, with: .color(bodyFill))
        ctx.stroke(p, with: .color(outline), lineWidth: u)
      }
      switch type {
      case .FINELINER, .DASHED:
        cone(9 * u, 1.6 * u)
        ctx.fill(Path(roundedRect: CGRect(x: cx - 1.6 * u, y: 4 * u, width: 3.2 * u, height: 8 * u), cornerRadius: 1.6 * u), with: .color(color))
      case .FOUNTAIN:
        var nib = Path()
        nib.move(to: CGPoint(x: cx - half + 1.5 * u, y: bodyTop))
        nib.addQuadCurve(to: CGPoint(x: cx, y: 2 * u), control: CGPoint(x: cx - half * 0.6, y: 9 * u))
        nib.addQuadCurve(to: CGPoint(x: cx + half - 1.5 * u, y: bodyTop), control: CGPoint(x: cx + half * 0.6, y: 9 * u))
        nib.closeSubpath()
        ctx.fill(nib, with: .color(color))
        var slit = Path()
        slit.move(to: CGPoint(x: cx, y: 6 * u))
        slit.addLine(to: CGPoint(x: cx, y: 14 * u))
        ctx.stroke(slit, with: .color(bodyFill), lineWidth: u)
        ctx.fill(Path(ellipseIn: CGRect(x: cx - 1.3 * u, y: 13.2 * u, width: 2.6 * u, height: 2.6 * u)), with: .color(bodyFill))
      case .PENCIL:
        var p = Path()
        p.move(to: CGPoint(x: cx - half, y: bodyTop))
        p.addLine(to: CGPoint(x: cx, y: 3 * u))
        p.addLine(to: CGPoint(x: cx + half, y: bodyTop))
        p.closeSubpath()
        ctx.fill(p, with: .color(wood))
        var lead = Path()
        lead.move(to: CGPoint(x: cx - 2.3 * u, y: 10 * u))
        lead.addLine(to: CGPoint(x: cx, y: 3 * u))
        lead.addLine(to: CGPoint(x: cx + 2.3 * u, y: 10 * u))
        lead.closeSubpath()
        ctx.fill(lead, with: .color(color))
      case .CALLIGRAPHY:
        cone(10 * u, 3.5 * u)
        var tip = Path()
        tip.move(to: CGPoint(x: cx - 3.5 * u, y: 10 * u))
        tip.addLine(to: CGPoint(x: cx + 3.5 * u, y: 5 * u))
        tip.addLine(to: CGPoint(x: cx + 3.5 * u, y: 8 * u))
        tip.addLine(to: CGPoint(x: cx - 3.5 * u, y: 13 * u))
        tip.closeSubpath()
        ctx.fill(tip, with: .color(color))
      case .HIGHLIGHTER:
        cone(11 * u, 5 * u)
        var tip = Path()
        tip.move(to: CGPoint(x: cx - 5 * u, y: 11 * u))
        tip.addLine(to: CGPoint(x: cx + 5 * u, y: 5 * u))
        tip.addLine(to: CGPoint(x: cx + 5 * u, y: 11 * u))
        tip.closeSubpath()
        ctx.fill(tip, with: .color(color.opacity(0.85)))
      }
    }
    .frame(width: 26, height: 56)
  }
}

/// The main toolbar (Android's `MainToolbar`): a cloud bar with many bumps along its top edge.
struct MainToolbar: View {
  @Binding var pens: [PenSlot]
  @Binding var tool: Tool
  @Binding var panel: PanelKind?
  var showColors = true
  @Environment(\.tali) private var c
  @Namespace private var toolGlide

  private var activeId: String? { if case .pen(let id) = tool { id } else { nil } }
  private var activeIndex: Int? { pens.firstIndex { $0.id == activeId } }

  var body: some View {
    HStack(spacing: 0) {
      // The pen tray: pens stand at the bottom edge, the active one lifted.
      HStack(alignment: .bottom, spacing: 0) {
        ForEach(pens) { pen in
          let on = pen.id == activeId
          PenGlyph(type: pen.type, color: Color(uiColor: UIColor(argb: pen.color)))
            .offset(y: on ? 2 : 16)
            .frame(width: 34, height: 56, alignment: .top)
            .contentShape(Rectangle())
            .onTapGesture { tapPen(pen) }
            .accessibilityLabel(penName(pen.type))
            .accessibilityAddTraits(.isButton)
            .accessibilityIdentifier("pen-\(pen.id)")
        }
      }
      .frame(height: 56, alignment: .bottom)
      .clipped()
      .padding(.horizontal, 4)
      .animation(.spring(response: 0.35, dampingFraction: 0.6), value: activeId)
      // The pen's settings open from the little arrow.
      Button {
        if activeId == nil, let first = pens.first { tool = .pen(first.id) }
        withAnimation(Ease.outStrong(duration: 0.18)) { panel = panel == .pen ? nil : .pen }
      } label: {
        Image(systemName: "chevron.down").font(.system(size: 15, weight: .semibold)).foregroundStyle(panel == .pen ? c.accent : c.inkMuted)
          .rotationEffect(.degrees(panel == .pen ? 180 : 0))
          .frame(width: 28, height: 44)
          .background(RoundedRectangle(cornerRadius: 10).fill(panel == .pen ? c.accentSoft : .clear))
      }
      .buttonStyle(.plain)
      .accessibilityLabel(L("pen_settings"))
      if showColors, let i = activeIndex {
        let pen = pens[i]
        let count = Palette.toolbarCount(for: pen)
        if count > 0 {
          HStack(spacing: 0) {
            ForEach(Array(Palette.colors(for: pen).prefix(count)), id: \.self) { col in
              ColorDot(color: Color(argb: col), selected: UInt32(bitPattern: pen.color) | 0xFF00_0000 == col | 0xFF00_0000, size: 22) {
                pens[i].color = Int32(bitPattern: col)
              }
            }
          }
          .padding(.leading, 2)
          .transition(.opacity)
          BarDivider().padding(.leading, 0)
        }
        QuickSizes(pen: $pens[i])
          .transition(.opacity)
      }
      BarDivider()
      HStack(spacing: 0) {
        toolButton(.eraser, icon: "eraser", label: L("eraser"))
        toolButton(.lasso, icon: "lasso", label: L("lasso"))
      }
      .padding(.trailing, 2)
    }
    .padding(.horizontal, 6).padding(.vertical, 4)
    .frame(height: 60)
    .cloudSurface(radius: 22, crown: .edge)
  }

  private func tapPen(_ pen: PenSlot) {
    if activeId == pen.id {
      withAnimation(Ease.outStrong(duration: 0.18)) { panel = panel == .pen ? nil : .pen }
    } else {
      tool = .pen(pen.id)
      withAnimation(.easeOut(duration: 0.12)) { panel = nil }
    }
  }

  /// Eraser and lasso share one highlight that glides between them (blue, as on Android).
  private func toolButton(_ t: Tool, icon: String, label: String) -> some View {
    let on = tool == t
    return Button {
      if tool == t {
        if t == .eraser { withAnimation(Ease.outStrong(duration: 0.18)) { panel = panel == .eraser ? nil : .eraser } }
      } else {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.82)) { tool = t }
        withAnimation(.easeOut(duration: 0.12)) { panel = nil }
      }
    } label: {
      Image(systemName: icon).font(.system(size: 19)).foregroundStyle(on ? c.blue : c.ink)
        .frame(width: 44, height: 44)
        .background {
          if on { RoundedRectangle(cornerRadius: 14).fill(c.blueSoft).matchedGeometryEffect(id: "tool", in: toolGlide) }
        }
    }
    .buttonStyle(PressStyle(scale: 0.9))
    .accessibilityLabel(label)
    .accessibilityIdentifier("tool-\(label)")
  }
}

struct BarDivider: View {
  @Environment(\.tali) private var c
  var body: some View { Rectangle().fill(c.line).frame(width: 1, height: 28).padding(.horizontal, 6) }
}

/// A colour to pick (Android's `ColorDot`): the dot with a hairline edge, and a ring when chosen.
struct ColorDot: View {
  var color: Color
  var selected: Bool
  var size: CGFloat = 30
  var action: () -> Void
  @Environment(\.tali) private var c

  var body: some View {
    Button(action: action) {
      Circle().fill(color).overlay(Circle().stroke(Color.black.opacity(0.13), lineWidth: 1))
        .frame(width: size, height: size)
        .padding(4)
        .overlay(Circle().stroke(c.accent, lineWidth: 2).opacity(selected ? 1 : 0))
        .animation(.spring(response: 0.25, dampingFraction: 0.8), value: selected)
    }
    .buttonStyle(.plain)
  }
}

/// Three dots, small to large by her three thicknesses, one highlighted (Android's `QuickSizes`).
/// Tapping the one in use opens a small slider to set it.
struct QuickSizes: View {
  @Binding var pen: PenSlot
  @Environment(\.tali) private var c
  @State private var editing = false
  @Namespace private var glide

  var body: some View {
    let sizes = pen.presetSizes
    let current = min(max(pen.sizeSlot, 0), 2)
    let rank = sizes.indices.sorted { sizes[$0] < sizes[$1] }
    HStack(spacing: 0) {
      ForEach(0..<3, id: \.self) { i in
        let dot = CGFloat(4 + 4 * (rank.firstIndex(of: i) ?? i))
        Circle().fill(i == current ? c.accent : c.inkMuted).frame(width: dot, height: dot)
          .frame(width: 28, height: 36)
          .background {
            if i == current { RoundedRectangle(cornerRadius: 12).fill(c.accentSoft).matchedGeometryEffect(id: "size", in: glide) }
          }
          .contentShape(Rectangle())
          .onTapGesture {
            if i == current {
              editing = true
            } else {
              withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) { pen = pen.pickSize(i) }
            }
          }
          .accessibilityLabel(L("thickness_n", i + 1))
          .accessibilityAddTraits(.isButton)
          .popover(isPresented: Binding(get: { editing && i == current }, set: { editing = $0 })) {
            VStack(alignment: .leading, spacing: 6) {
              Text(L("thickness_n", i + 1)).font(TaliType.titleSmall).foregroundStyle(c.ink)
              HStack {
                StepSlider(value: Binding(get: { pen.size }, set: { pen = pen.withSize($0) }), range: 0.5...pen.type.maxSize, step: 0.5)
                Text(String(format: "%.1f", pen.size)).font(TaliType.titleSmall).foregroundStyle(c.ink).frame(width: 40)
              }
            }
            .padding(.horizontal, 14).padding(.vertical, 10)
            .frame(width: 300)
            .presentationCompactAdaptation(.popover)
          }
      }
    }
    .padding(.leading, 4)
  }
}

/// A panel that drops below the toolbar (Android's `Panel`): a cloud surface without bumps.
struct ToolPanel<Content: View>: View {
  var width: CGFloat
  @ViewBuilder var content: Content
  var body: some View {
    VStack(alignment: .leading, spacing: 0) { content }
      .frame(width: width, alignment: .leading)
      .padding(18)
      .cloudSurface(radius: 22, crown: .none, shadowDepth: 10)
  }
}

/// The active pen's settings (Android's `PenPanel`): its type, a sample stroke, its three
/// thicknesses, the size slider, its colours and how many of them sit in the toolbar.
struct PenPanel: View {
  @Binding var pen: PenSlot
  @Environment(\.tali) private var c
  @Namespace private var types
  @State private var paletteVersion = 0

  var body: some View {
    ToolPanel(width: 392) {
      HStack(spacing: 4) {
        ForEach(PenType.offered, id: \.self) { t in
          PenGlyph(type: t, color: t == pen.type ? Color(uiColor: UIColor(argb: pen.color)) : Color(argb: 0xFF8E_95A2))
            .frame(width: 58, height: 66, alignment: .bottom)
            .background {
              if t == pen.type { RoundedRectangle(cornerRadius: 14).fill(c.accentSoft).matchedGeometryEffect(id: "type", in: types) }
            }
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .contentShape(Rectangle())
            .onTapGesture {
              withAnimation(.spring(response: 0.3, dampingFraction: 0.82)) {
                pen.type = t
                pen.size = min(max(pen.size, 0.5), t.maxSize)
              }
            }
            .accessibilityLabel(penName(t))
            .accessibilityAddTraits(t == pen.type ? [.isButton, .isSelected] : .isButton)
        }
      }
      Spacer().frame(height: 10)
      Text(penName(pen.type)).font(TaliType.titleMedium).foregroundStyle(c.ink)
      Spacer().frame(height: 10)
      StrokePreview(pen: pen).frame(height: 70)
      Spacer().frame(height: 12)
      Segmented(options: [0, 1, 2], selected: Binding(get: { min(max(pen.sizeSlot, 0), 2) }, set: { pen = pen.pickSize($0) })) {
        String(format: "%.1f", pen.presetSizes[$0])
      }
      Spacer().frame(height: 8)
      HStack(spacing: 0) {
        Text(L("size")).font(TaliType.bodyMedium).foregroundStyle(c.inkMuted).frame(width: 44, alignment: .leading)
        StepSlider(value: Binding(get: { pen.size }, set: { pen = pen.withSize($0) }), range: 0.5...pen.type.maxSize, step: 0.5)
        Text(String(format: "%.1f", pen.size)).font(TaliType.titleSmall).foregroundStyle(c.ink).frame(width: 40).padding(.leading, 8)
      }
      Spacer().frame(height: 10)
      SectionLabel(text: pen.type == .HIGHLIGHTER ? L("highlighter_colours") : L("colours"))
      Spacer().frame(height: 8)
      let palette = Palette.colors(for: pen)
      let inBar = Palette.toolbarCount(for: pen)
      LazyVGrid(columns: Array(repeating: GridItem(.fixed(38), spacing: 2), count: 9), alignment: .leading, spacing: 2) {
        ForEach(Array(palette.enumerated()), id: \.element) { i, col in
          ColorDot(color: Color(argb: col), selected: UInt32(bitPattern: pen.color) | 0xFF00_0000 == col | 0xFF00_0000) {
            pen.color = Int32(bitPattern: col)
          }
          .overlay(alignment: .trailing) {
            // A thin line after the last toolbar colour sets them apart.
            if i == inBar - 1 && inBar < palette.count { Rectangle().fill(c.line).frame(width: 1.5, height: 22).offset(x: 1) }
          }
        }
      }
      Spacer().frame(height: 12)
      Text(L("in_the_toolbar_with_this_pen")).font(TaliType.bodyMedium).foregroundStyle(c.ink)
      Text(L("the_colours_before_the_line_hold")).font(TaliType.bodySmall).foregroundStyle(c.inkFaint)
      Spacer().frame(height: 8)
      Segmented(options: Array(0...6), selected: Binding(get: { Palette.toolbarCount(for: pen) }, set: { pen.toolbarColors = $0 })) {
        $0 == 0 ? L("none") : "\($0)"
      }
    }
  }
}

/// A sample stroke in the pen's colour and size on a strip of paper.
struct StrokePreview: View {
  var pen: PenSlot
  @Environment(\.tali) private var c

  var body: some View {
    Canvas { ctx, size in
      let w = size.width, h = size.height
      var p = Path()
      p.move(to: CGPoint(x: w * 0.1, y: h * 0.62))
      p.addCurve(to: CGPoint(x: w * 0.5, y: h * 0.5), control1: CGPoint(x: w * 0.22, y: h * 0.1), control2: CGPoint(x: w * 0.36, y: h * 0.9))
      p.addCurve(to: CGPoint(x: w * 0.9, y: h * 0.38), control1: CGPoint(x: w * 0.64, y: h * 0.1), control2: CGPoint(x: w * 0.78, y: h * 0.9))
      let width = CGFloat(pen.size) * (pen.type == .HIGHLIGHTER ? 1 : 1.2)
      ctx.stroke(
        p, with: .color(Color(uiColor: UIColor(argb: pen.inkColor))),
        style: StrokeStyle(lineWidth: width, lineCap: pen.type == .HIGHLIGHTER ? .square : .round, lineJoin: .round))
    }
    .background(c.paper)
    .clipShape(RoundedRectangle(cornerRadius: 14))
    .overlay(RoundedRectangle(cornerRadius: 14).stroke(c.line, lineWidth: 1))
  }
}

/// The eraser's settings (Android's `EraserPanel`): whole strokes or precise, and its size.
struct EraserPanel: View {
  @Binding var precise: Bool
  @Binding var size: Float
  @Environment(\.tali) private var c

  var body: some View {
    ToolPanel(width: 340) {
      Text(L("eraser")).font(TaliType.titleLarge).foregroundStyle(c.ink)
      Spacer().frame(height: 14)
      Segmented(options: [false, true], selected: $precise) { $0 ? L("precise") : L("whole_strokes") }
      Spacer().frame(height: 14)
      HStack(spacing: 0) {
        Text(L("size")).font(TaliType.bodyMedium).foregroundStyle(c.inkMuted).frame(width: 44, alignment: .leading)
        StepSlider(value: $size, range: 6...64, step: 1, lessLabel: L("size"), moreLabel: L("size"))
        Circle().fill(c.sunken).overlay(Circle().stroke(c.inkFaint, lineWidth: 1))
          .frame(width: CGFloat(min(size, 40)), height: CGFloat(min(size, 40))).frame(width: 44, height: 44)
      }
    }
  }
}

/// "3 / 12" with arrows (Android's `PageChip`).
struct PageChip: View {
  var page: Int
  var count: Int
  var onGo: (Int) -> Void
  @Environment(\.tali) private var c

  var body: some View {
    HStack(spacing: 0) {
      arrow("chevron.up", L("previous_page"), enabled: page > 0) { onGo(page - 1) }
      Text(L("n_n_3", page + 1, count)).font(TaliType.labelMedium).foregroundStyle(c.inkMuted).padding(.horizontal, 6).padding(.vertical, 6)
      arrow("chevron.down", L("next_page"), enabled: page < count - 1) { onGo(page + 1) }
    }
    .padding(.horizontal, 2)
    .cloudSurface(radius: 12, crown: .none, shadowDepth: 3)
  }

  private func arrow(_ icon: String, _ label: String, enabled: Bool, _ action: @escaping () -> Void) -> some View {
    Button(action: action) {
      Image(systemName: icon).font(.system(size: 14, weight: .semibold)).foregroundStyle(enabled ? c.blue : c.inkFaint.opacity(0.5))
        .frame(width: 32, height: 32)
    }
    .buttonStyle(.plain)
    .disabled(!enabled)
    .accessibilityLabel(label)
  }
}

/// The zoom as a percentage; tapping it fits the page again (Android's `ZoomChip`).
struct ZoomChip: View {
  var zoom: CGFloat
  var onReset: () -> Void
  @Environment(\.tali) private var c

  var body: some View {
    Button(action: onReset) {
      Text(L("n", Int((zoom * 100).rounded()))).font(TaliType.labelMedium).foregroundStyle(c.inkMuted)
        .padding(.horizontal, 12).padding(.vertical, 7)
        .cloudSurface(radius: 12, crown: .none, shadowDepth: 3)
    }
    .buttonStyle(PressStyle())
    .accessibilityLabel(L("reset_zoom"))
  }
}
