import PencilKit
import SwiftUI
import TaliCore

// The notebook's main toolbar and its panels, ported from Android's `ui/notebook/Toolbar.kt` and
// `Panels.kt`: the pen tray (pens standing at the bottom edge, the active one lifted), the arrow to
// the pen's settings, her first few colours, her three thicknesses, then the tools.

/// Which panel hangs under the toolbar.
enum PanelKind { case pen, eraser, lasso, shapes, fill }

/// How the lasso is set, which its toolbar button shows (Android: the lasso drawn dotted, a dotted
/// circle for free form, a screenshot sign for the screenshot lasso).
enum LassoKind { case lasso, freeForm, screenshot }

/// A pen drawn like a real tool standing in a tray (Android's `PenGlyph`): neutral body, a coloured
/// band, and a tip shaped by its style. 26 × 56 pt, the tip pointing up.
struct PenGlyph: View {
  var type: PenType
  var color: Color
  var line = LineStyle.SOLID
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
      let pattern = type == .DASHED ? LineStyle.SHORT_DASH : line
      if pattern != .SOLID {
        let w = 2 * u
        var down = Path()
        down.move(to: CGPoint(x: cx, y: bodyTop + 18 * u))
        down.addLine(to: CGPoint(x: cx, y: size.height))
        ctx.stroke(down, with: .color(color.opacity(0.75)), style: StrokeStyle(lineWidth: w, lineCap: .round, dash: pattern.dash(width: w)))
      }
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
  var shape: ShapeSource = .kind(.LINE)
  var lasso: LassoKind = .lasso
  /// The keyboard: a new text box to type in.
  var onKeyboard: () -> Void = {}
  var onInsert: (InsertChoice) -> Void = { _ in }
  /// The notebook's voice memos, for the mic (pressed while recording, it stops).
  var memos: MemoModel?
  var onVoice: () -> Void = {}
  var showColors = true
  /// On a phone the tools fold into one button (Android's `MainToolbarPhone`).
  var compactTools = false
  /// How wide the folded tools may be when they drop down.
  var toolsRoom: CGFloat = .infinity
  @State private var toolsOpen = false
  @Environment(\.tali) private var c
  @Namespace private var toolGlide

  private var activeId: String? { if case .pen(let id) = tool { id } else { nil } }
  private var activeIndex: Int? { pens.firstIndex { $0.id == activeId } }

  var body: some View {
    VStack(spacing: 6) {
      pensBar
      if compactTools && toolsOpen {
        ToolStrip(items: toolItems, selected: toolKey, room: toolsRoom)
          .padding(.horizontal, 6).padding(.vertical, 4)
          .frame(height: 60)
          .cloudSurface(radius: 22, crown: .edge)
          .transition(.opacity.combined(with: .scale(scale: 0.9, anchor: .top)))
      }
    }
    .onChange(of: tool) { _, _ in if compactTools { withAnimation(.easeOut(duration: 0.14)) { toolsOpen = false } } }
    .animation(Ease.outStrong(duration: 0.22), value: activeIndex.map { Palettes.shared.toolbarCount(for: pens[$0]) })
  }

  private var pensBar: some View {
    HStack(spacing: 0) {
      // The pen tray: pens stand at the bottom edge, the active one lifted.
      HStack(alignment: .bottom, spacing: 0) {
        ForEach(pens) { pen in
          let on = pen.id == activeId
          PenGlyph(type: pen.type, color: Color(uiColor: UIColor(argb: pen.color)), line: pen.lineStyle)
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
        let quick = Array(Palettes.shared.colors(for: pen).prefix(Palettes.shared.toolbarCount(for: pen)))
        if !quick.isEmpty {
          HStack(spacing: 0) {
            ForEach(quick, id: \.self) { col in
              ColorDot(color: Color(argb: col), selected: UInt32(bitPattern: pen.color) | 0xFF00_0000 == col | 0xFF00_0000, size: 22) {
                pens[i].color = Int32(bitPattern: col)
              }
              .accessibilityLabel(L("colour"))
              .accessibilityIdentifier(String(format: "toolbar-colour-%06X", col & 0xFF_FFFF))
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
      if compactTools {
        // A phone (Android's `MainToolbarPhone`): one button showing the tool in use drops the tools
        // down in a bar of their own, and closes whatever panel was open.
        Button {
          withAnimation(Ease.outStrong(duration: 0.2)) {
            toolsOpen.toggle()
            panel = nil
          }
        } label: {
          HStack(spacing: 0) {
            Group {
              if tool == .shape {
                ShapeChoiceIcon(source: shape, color: c.blue, size: 22)
              } else if tool == .fill {
                FillIcon(color: c.blue)
              } else if tool == .lasso {
                lassoIcon(c.blue)
              } else {
                Image(systemName: currentToolIcon).font(.system(size: 19)).foregroundStyle(isPen ? c.ink : c.blue)
              }
            }
            .frame(width: 24, height: 24)
            Image(systemName: "chevron.down").font(.system(size: 13, weight: .semibold)).foregroundStyle(c.inkMuted)
              .rotationEffect(.degrees(toolsOpen ? 180 : 0))
              .frame(width: 20, height: 20)
          }
          .padding(.leading, 8).padding(.trailing, 4)
          .frame(height: 44)
          .background(RoundedRectangle(cornerRadius: 14).fill(toolsOpen || !isPen ? c.blueSoft : .clear))
          .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle(scale: 0.9))
        .accessibilityLabel(L("more_tools"))
        .accessibilityIdentifier("tools-button")
        .padding(.trailing, 2)
      } else {
        HStack(spacing: 0) { ForEach(toolItems) { $0.view } }.padding(.trailing, 2)
      }
    }
    .padding(.horizontal, 6).padding(.vertical, 4)
    .frame(height: 60)
    .cloudSurface(radius: 22, crown: .edge)
  }

  /// The tools: eraser, lasso, fill, laser, shapes, insert, the mic, then the keyboard (a new text box).
  private var toolItems: [ToolStrip.Item] {
    var items = [
      ToolStrip.Item(id: "eraser", view: AnyView(toolButton(.eraser, icon: "eraser", label: L("eraser"), id: "eraser"))),
      ToolStrip.Item(
        id: "lasso",
        view: AnyView(toolButton(.lasso, icon: "lasso", label: lasso == .screenshot ? L("screenshot_lasso") : lasso == .freeForm ? L("free_form_select") : L("lasso"), id: "lasso"))),
      ToolStrip.Item(id: "fill", view: AnyView(toolButton(.fill, icon: "", label: L("fill"), id: "fill"))),
      ToolStrip.Item(id: "laser", view: AnyView(toolButton(.laser, icon: "laser.burst", label: L("laser"), id: "laser"))),
      ToolStrip.Item(id: "shapes", view: AnyView(toolButton(.shape, icon: "square.on.circle", label: L("shapes"), id: "shapes"))),
      ToolStrip.Item(id: "insert", view: AnyView(InsertButton { toolsOpen = false; onInsert($0) })),
    ]
    if let memos { items.append(ToolStrip.Item(id: "voice", view: AnyView(MicButton(memos: memos) { toolsOpen = false; onVoice() }))) }
    items.append(
      ToolStrip.Item(
        id: "keyboard",
        view: AnyView(
          Button {
            toolsOpen = false
            onKeyboard()
          } label: {
            Image(systemName: "keyboard").font(.system(size: 19)).foregroundStyle(c.ink).frame(width: 44, height: 44).contentShape(Rectangle())
          }
          .buttonStyle(PressStyle(scale: 0.9))
          .accessibilityLabel(L("keyboard"))
          .accessibilityIdentifier("tool-keyboard"))))
    return items
  }

  private var toolKey: String? {
    switch tool {
    case .eraser: "eraser"
    case .lasso: "lasso"
    case .fill: "fill"
    case .laser: "laser"
    case .shape: "shapes"
    case .pen: nil
    }
  }

  private var isPen: Bool { if case .pen = tool { true } else { false } }

  @ViewBuilder private func lassoIcon(_ color: Color) -> some View {
    switch lasso {
    case .screenshot: Image(systemName: "camera.viewfinder").font(.system(size: 19)).foregroundStyle(color)
    case .freeForm: SelectIcon(kind: .freeForm, color: color)
    case .lasso: SelectIcon(kind: .lasso, color: color)
    }
  }

  private var currentToolIcon: String {
    switch tool {
    case .eraser: "eraser"
    case .lasso: "lasso"
    case .laser: "laser.burst"
    case .shape, .fill: "square.on.circle"
    case .pen: "square.grid.2x2"
    }
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
  private func toolButton(_ t: Tool, icon: String, label: String, id: String) -> some View {
    let on = tool == t
    return Button {
      // On a phone, choosing a tool folds the tools away again.
      if compactTools { withAnimation(.easeOut(duration: 0.14)) { toolsOpen = false } }
      if tool == t {
        if t == .eraser { withAnimation(Ease.outStrong(duration: 0.18)) { panel = panel == .eraser ? nil : .eraser } }
        if t == .lasso { withAnimation(Ease.outStrong(duration: 0.18)) { panel = panel == .lasso ? nil : .lasso } }
        if t == .shape { withAnimation(Ease.outStrong(duration: 0.18)) { panel = panel == .shapes ? nil : .shapes } }
        if t == .fill { withAnimation(Ease.outStrong(duration: 0.18)) { panel = panel == .fill ? nil : .fill } }
      } else {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.82)) { tool = t }
        // The Shapes tool opens its panel straight away, to choose what to draw.
        withAnimation(.easeOut(duration: 0.12)) { panel = t == .shape ? .shapes : nil }
      }
    } label: {
      Group {
        // While on, the Shapes tool shows the shape it draws.
        if t == .shape && on {
          ShapeChoiceIcon(source: shape, color: c.blue, size: 24)
        } else if t == .fill {
          FillIcon(color: on ? c.blue : c.ink)
        } else if t == .lasso {
          lassoIcon(on ? c.blue : c.ink)
        } else {
          Image(systemName: icon).font(.system(size: 19)).foregroundStyle(on ? c.blue : c.ink)
        }
      }
        .frame(width: 44, height: 44)
        .background {
          if on { RoundedRectangle(cornerRadius: 14).fill(c.blueSoft).matchedGeometryEffect(id: "tool", in: toolGlide) }
        }
        // Its own 44 pt and no more: the rounded highlight of the tool in use took taps meant for
        // the tool before it (seen on iOS 27: with the lasso on, a tap on the eraser reached the lasso).
        .contentShape(Rectangle())
    }
    .buttonStyle(PressStyle(scale: 0.9))
    .accessibilityLabel(label)
    .accessibilityAddTraits(on ? .isSelected : [])
    .accessibilityIdentifier("tool-\(id)")
  }
}

/// The tools after the pens (Android's `ToolStrip`). When they all fit they sit in a row. When the
/// bar runs out of room they're split into pages with an arrow at the end, and the arrow goes to
/// the next page, so nothing is cut off.
struct ToolStrip: View {
  struct Item: Identifiable {
    let id: String
    let view: AnyView
  }

  var items: [Item]
  /// The tool in use, whose page shows when the strip opens.
  var selected: String?
  var room: CGFloat
  @State private var page = 0
  @Environment(\.tali) private var c

  static let item: CGFloat = 44
  static let arrow: CGFloat = 30

  /// The tools in pages that fit [room], one page when they all do.
  static func pages<T>(_ items: [T], room: CGFloat) -> [[T]] {
    if room >= item * CGFloat(items.count) + 2 { return [items] }
    let per = min(max(Int((room - arrow) / item), 1), max(items.count, 1))
    return stride(from: 0, to: items.count, by: per).map { Array(items[$0..<min($0 + per, items.count)]) }
  }

  var body: some View {
    let pages = Self.pages(items, room: room)
    let shown = min(page, pages.count - 1)
    let last = shown == pages.count - 1
    HStack(spacing: 0) {
      HStack(spacing: 0) { ForEach(pages[shown]) { $0.view } }
        .id(shown)
        .transition(.opacity)
      if pages.count > 1 {
        Button {
          withAnimation(Ease.outStrong(duration: 0.24)) { page = last ? 0 : shown + 1 }
        } label: {
          Image(systemName: "chevron.right").font(.system(size: 15, weight: .semibold)).foregroundStyle(c.inkMuted)
            .rotationEffect(.degrees(last ? 180 : 0))
            .frame(width: Self.arrow, height: 44).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(last ? L("first_tools") : L("more_tools"))
        .accessibilityIdentifier("tools-page")
      } else {
        Spacer().frame(width: 2)
      }
    }
    .onChange(of: selected, initial: true) { _, key in
      if let at = pages.firstIndex(where: { $0.contains { $0.id == key } }) { page = at }
    }
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
    Button(action: action) { ColorDotFace(color: color, selected: selected, size: size) }
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
                StepSlider(value: Binding(get: { pen.size }, set: { pen = pen.withSize($0) }), range: pen.type.minSize...pen.type.maxSize, step: 0.5)
                Text(String(format: "%.1f", pen.size)).font(TaliType.titleSmall).foregroundStyle(c.ink).frame(width: 40)
              }
            }
            .padding(.horizontal, 14).padding(.vertical, 10)
            .frame(width: 300)
            .presentationCompactAdaptation(.popover)
            .presentationBackground(c.surface)
          }
      }
    }
    .padding(.leading, 4)
  }
}

/// A panel that drops below the toolbar (Android's `Panel` and `PanelColumn`): a cloud surface
/// without bumps, never taller than the room under the toolbar; what doesn't fit scrolls.
struct ToolPanel<Content: View>: View {
  var width: CGFloat
  @ViewBuilder var content: Content
  @Environment(\.tali) private var c

  var body: some View {
    ViewThatFits(in: .vertical) {
      column
      ScrollViewReader { proxy in
        ScrollView { column.padding(.bottom, 20) }
          .scrollIndicators(.hidden)
          .environment(\.showInPanel) { id in withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo(id, anchor: .bottom) } }
          .overlay(alignment: .bottom) {
            LinearGradient(colors: [c.cloudBelly.opacity(0), c.cloudBelly], startPoint: .top, endPoint: .bottom).frame(height: 28).allowsHitTesting(false)
          }
      }
    }
    // Its own width, or less on a phone so it never runs off the screen.
    .frame(maxWidth: width, alignment: .leading)
    .padding(18)
    .cloudSurface(radius: 22, crown: .none, shadowDepth: 10)
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("tool-panel")
  }

  private var column: some View { VStack(alignment: .leading, spacing: 0) { content } }
}

extension EnvironmentValues {
  /// Scrolls a panel that doesn't fit so the part with this id shows.
  @Entry var showInPanel: (String) -> Void = { _ in }
}

/// Something added to a panel after it opened (the colour picker) comes into view by itself:
/// below the fold of a panel that scrolls, it would look as if nothing had happened.
struct ShownWhenAdded: ViewModifier {
  var id: String
  @Environment(\.showInPanel) private var show

  func body(content: Content) -> some View {
    // After this pass of layout: the panel hasn't grown to hold it yet when it first appears.
    content.id(id).task {
      try? await Task.sleep(for: .milliseconds(60))
      show(id)
    }
  }
}

/// The active pen's settings (Android's `PenPanel`): its type, a sample stroke, its three
/// thicknesses, the size slider, its colours and how many of them sit in the toolbar.
struct PenPanel: View {
  @Binding var pen: PenSlot
  var onAddPen: () -> Void
  /// Nil for the last pen, which stays.
  var onRemovePen: (() -> Void)?
  @Environment(\.tali) private var c
  @Namespace private var types
  @State private var pickingColour = false

  var body: some View {
    ToolPanel(width: 392) {
      HStack(spacing: 4) {
        ForEach(PenType.offered, id: \.self) { t in
          PenGlyph(type: t, color: t == pen.type ? Color(uiColor: UIColor(argb: pen.color)) : Color(argb: 0xFF8E_95A2), line: t.takesLineStyle ? pen.line : .SOLID)
            .frame(width: 58, height: 66, alignment: .bottom)
            .background {
              if t == pen.type { RoundedRectangle(cornerRadius: 14).fill(c.accentSoft).matchedGeometryEffect(id: "type", in: types) }
            }
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .contentShape(Rectangle())
            .onTapGesture {
              withAnimation(.spring(response: 0.3, dampingFraction: 0.82)) { pen = pen.withType(t) }
            }
            .accessibilityLabel(penName(t))
            .accessibilityAddTraits(t == pen.type ? [.isButton, .isSelected] : .isButton)
        }
      }
      Spacer().frame(height: 10)
      Text(penName(pen.type)).font(TaliType.titleMedium).foregroundStyle(c.ink)
      Spacer().frame(height: 10)
      StrokePreview(pen: pen)
      Spacer().frame(height: 12)
      Segmented(options: [0, 1, 2], selected: Binding(get: { min(max(pen.sizeSlot, 0), 2) }, set: { pen = pen.pickSize($0) })) {
        String(format: "%.1f", pen.presetSizes[$0])
      }
      Spacer().frame(height: 8)
      HStack(spacing: 0) {
        Text(L("size")).font(TaliType.bodyMedium).foregroundStyle(c.inkMuted).frame(width: 44, alignment: .leading)
        StepSlider(value: Binding(get: { pen.size }, set: { pen = pen.withSize($0) }), range: pen.type.minSize...pen.type.maxSize, step: 0.5)
        Text(String(format: "%.1f", pen.size)).font(TaliType.titleSmall).foregroundStyle(c.ink).frame(width: 40).padding(.leading, 8)
      }
      if pen.type.takesLineStyle {
        Spacer().frame(height: 10)
        SectionLabel(text: L("line"))
        Spacer().frame(height: 8)
        LineStylePicker(selected: Binding(get: { pen.lineStyle }, set: { pen.line = $0 }))
      }
      if pen.type.isHighlighter {
        Spacer().frame(height: 12)
        SectionLabel(text: L("draws"))
        Spacer().frame(height: 8)
        Segmented(options: [true, false], selected: Binding(get: { pen.straight }, set: { pen.freehand = !$0 })) { $0 ? L("straight_lines") : L("freehand") }
        Spacer().frame(height: 12)
        SectionLabel(text: L("tip"))
        Spacer().frame(height: 8)
        Segmented(options: [false, true], selected: Binding(get: { pen.square }, set: { pen.squareTip = $0 })) { $0 ? L("square") : L("round") }
      }
      Spacer().frame(height: 10)
      SectionLabel(text: pen.type == .HIGHLIGHTER ? L("highlighter_colours") : L("colours"))
      Spacer().frame(height: 8)
      ReorderableColors(
        colors: Palettes.shared.colors(for: pen), selected: UInt32(bitPattern: pen.color), inToolbar: Palettes.shared.toolbarCount(for: pen),
        onPick: { pen.color = Int32(bitPattern: $0) },
        onReorder: { order in Palettes.shared.edit(for: pen) { SavedColours.reordered($0, to: order) } },
        onRemove: { color in Palettes.shared.edit(for: pen) { SavedColours.removing(color, from: $0) } },
        onAdd: { withAnimation(.easeOut(duration: 0.18)) { pickingColour.toggle() } })
      Spacer().frame(height: 12)
      Text(L("in_the_toolbar_with_this_pen")).font(TaliType.bodyMedium).foregroundStyle(c.ink)
      Text(L("the_colours_before_the_line_hold")).font(TaliType.bodySmall).foregroundStyle(c.inkFaint)
      Spacer().frame(height: 8)
      Segmented(options: Array(0...6), selected: Binding(get: { Palettes.shared.toolbarCount(for: pen) }, set: { pen.toolbarColors = $0 })) {
        $0 == 0 ? L("none") : "\($0)"
      }
      if pickingColour {
        Spacer().frame(height: 12)
        ColourPicker(
          initial: UInt32(bitPattern: pen.color),
          onChange: { pen.color = Int32(bitPattern: $0) },
          onSave: { color in
            Palettes.shared.edit(for: pen) { SavedColours.saving(color, in: $0) }
            pen.color = Int32(bitPattern: color)
            withAnimation(.easeOut(duration: 0.18)) { pickingColour = false }
          }
        )
        .modifier(ShownWhenAdded(id: "colour-picker"))
      }
      Spacer().frame(height: 12)
      HStack(spacing: 10) {
        Button(L("add_a_pen"), action: onAddPen).buttonStyle(QuietButtonStyle())
        if let onRemovePen { Button(L("remove_this_pen"), action: onRemovePen).buttonStyle(QuietButtonStyle(warning: true)) }
      }
    }
  }
}

/// Android's `StrokePreview`, drawn by the code that draws stored strokes so it can't differ from the page.
struct StrokePreview: View {
  var pen: PenSlot
  @Environment(\.tali) private var c
  @Environment(\.displayScale) private var displayScale

  /// Android lays the sample out this size in world units, so thicknesses read the same here.
  private static let world = CGSize(width: 392, height: 70)

  var body: some View {
    GeometryReader { geo in
      Image(uiImage: StrokePreview.picture(pen, scale: displayScale * geo.size.width / StrokePreview.world.width))
        .resizable()
        .frame(width: geo.size.width, height: geo.size.height)
    }
    .aspectRatio(StrokePreview.world.width / StrokePreview.world.height, contentMode: .fit)
    .background(c.paper)
    .clipShape(RoundedRectangle(cornerRadius: 14))
    .overlay(RoundedRectangle(cornerRadius: 14).stroke(c.line, lineWidth: 1))
    .accessibilityHidden(true)
  }

  static func sample(_ pen: PenSlot) -> InkStroke {
    let w = Float(world.width), h = Float(world.height)
    let inputs: InkInputs
    if pen.straight {
      inputs = StraightLine.inputs(Pt(w * 0.12, h / 2), Pt(w * 0.88, h / 2))
    } else {
      let points = (0...90).map { i -> InkInput in
        let f = Float(i) / 90
        return InkInput(x: 14 + (w - 28) * f, y: h / 2 + sinf(f * 2 * .pi) * h * 0.22, t: Float(i) * 0.006, pressure: 0.35 + 0.55 * sinf(f * .pi))
      }
      inputs = InkInputs(points: points, tool: .stylus)
    }
    return InkStroke(id: "", z: 0, pen: pen.type, tags: InkStroke.tags(for: pen), color: pen.inkColor, size: pen.size, inputs: inputs)
  }

  private static func picture(_ pen: PenSlot, scale: CGFloat) -> UIImage {
    var image = UIImage()
    // The pen's own colour, whatever the app's theme (PencilKit lightens dark ink in dark mode).
    UITraitCollection(userInterfaceStyle: .light).performAsCurrent {
      image = PKDrawing(strokes: [sample(pen).pkStroke(mask: nil)]).image(from: CGRect(origin: .zero, size: world), scale: max(scale, 1))
    }
    return image
  }
}

/// The eraser's settings (Android's `EraserPanel`): whole strokes or precise, its size, and which pens it erases.
struct EraserPanel: View {
  @Binding var precise: Bool
  @Binding var size: Float
  @Binding var affects: PenFilter
  @Environment(\.tali) private var c

  var body: some View {
    ToolPanel(width: 340) {
      Text(L("eraser")).font(TaliType.titleLarge).foregroundStyle(c.ink)
      Spacer().frame(height: 14)
      Segmented(options: [false, true], selected: $precise) { $0 ? L("precise") : L("whole_strokes") }
      Spacer().frame(height: 14)
      HStack(spacing: 0) {
        Text(L("size")).font(TaliType.bodyMedium).foregroundStyle(c.inkMuted).frame(width: 44, alignment: .leading)
        StepSlider(value: $size, range: 6...64, step: 1)
        Circle().fill(c.sunken).overlay(Circle().stroke(c.inkFaint, lineWidth: 1))
          .frame(width: CGFloat(min(size, 40)), height: CGFloat(min(size, 40))).frame(width: 44, height: 44)
      }
      Spacer().frame(height: 10)
      SectionLabel(text: L("erases"))
      Spacer().frame(height: 8)
      PenFilterChips(filter: $affects, images: nil)
      if !PhoneWriting.onPhone {
        Spacer().frame(height: 14)
        Text(L("tip_double_tap_apple_pencil")).font(TaliType.bodySmall).foregroundStyle(c.inkFaint)
      }
    }
  }
}

/// "3 / 12" with arrows (Android's `PageChip`).
struct PageChip: View {
  var page: Int
  var count: Int
  var onGo: (Int) -> Void
  /// Tapping the number opens the pages overview.
  var onOverview: (() -> Void)?
  @Environment(\.tali) private var c

  var body: some View {
    HStack(spacing: 0) {
      arrow("chevron.up", L("previous_page"), enabled: page > 0) { onGo(page - 1) }
      Button {
        onOverview?()
      } label: {
        Text(L("n_n_3", page + 1, count)).font(TaliType.labelMedium).foregroundStyle(c.inkMuted).padding(.horizontal, 6).padding(.vertical, 6)
      }
      .buttonStyle(.plain)
      .disabled(onOverview == nil)
      .accessibilityHint(L("all_pages"))
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
    .accessibilityIdentifier("zoom-chip")
  }
}
