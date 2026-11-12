import SwiftUI
import TaliCore

/// A notebook's paper: a built-in style or one of hers (stored as "custom:<id>").
enum PaperChoice: Hashable {
  case style(PaperStyle)
  case custom(String)

  var key: String {
    switch self {
    case .style(let s): s.rawValue
    case .custom(let id): id
    }
  }
}

/// The papers to choose from (Android's `PaperPicker`): as many tiles as fit on one row (up to
/// [perRow]) with More at the end; More unfolds the rest, her own papers and Your own underneath.
/// Blank, Lines and Grid come first; the paper in use takes the first place when it isn't on the
/// first row (changed only while folded, so a paper picked from the open list doesn't jump up under
/// her finger). The paper in use wears a small pencil: tapping it again opens its card. Hers are
/// removed by holding them.
struct PaperPicker: View {
  @Binding var choice: PaperChoice
  var customs: [CustomPaper] = []
  var tileWidth: CGFloat = 62
  var perRow = 4
  var dark = false
  var onAdd: (() -> Void)?
  var onRemove: ((CustomPaper) -> Void)?
  var onEditCurrent: (() -> Void)?
  @Environment(\.tali) private var c
  @State private var expanded = false
  @State private var width: CGFloat = 0
  @State private var shownCurrent: PaperChoice?
  @State private var removing: CustomPaper?
  @Namespace private var glide

  static let folded: [PaperStyle] = [.BLANK, .LINES, .GRID]

  init(
    choice: Binding<PaperChoice>, customs: [CustomPaper] = [], tileWidth: CGFloat = 62, perRow: Int = 4, dark: Bool = false, onAdd: (() -> Void)? = nil,
    onRemove: ((CustomPaper) -> Void)? = nil, onEditCurrent: (() -> Void)? = nil
  ) {
    _choice = choice
    self.customs = customs
    self.tileWidth = tileWidth
    self.perRow = perRow
    self.dark = dark
    self.onAdd = onAdd
    self.onRemove = onRemove
    self.onEditCurrent = onEditCurrent
  }

  /// Built-in papers only (the new-notebook card).
  init(style: Binding<PaperStyle>, tileWidth: CGFloat = 62, perRow: Int = 4, dark: Bool = false) {
    self.init(
      choice: Binding(get: { .style(style.wrappedValue) }, set: { if case .style(let s) = $0 { style.wrappedValue = s } }), tileWidth: tileWidth,
      perRow: perRow, dark: dark)
  }

  private var fit: Int {
    guard width > 0 else { return max(2, perRow) }
    return min(max(Int((width + 4) / (tileWidth + 4)), 2), max(2, perRow))
  }

  private var all: [PaperChoice] {
    PaperPicker.folded.map(PaperChoice.style) + PaperStyle.allCases.filter { !PaperPicker.folded.contains($0) }.map(PaperChoice.style)
      + customs.map { .custom($0.id) }
  }

  var body: some View {
    let usual = Array(all.prefix(fit - 1))
    let current = expanded ? (shownCurrent ?? choice) : choice
    let known = all.contains(current)
    let first = usual.contains(current) || !known ? usual : Array(([current] + usual).prefix(fit - 1))
    let rest = all.filter { !first.contains($0) }
    VStack(alignment: .leading, spacing: 4) {
      HStack(spacing: 4) {
        ForEach(first, id: \.self) { tile($0) }
        moreTile
      }
      if expanded {
        LazyVGrid(columns: Array(repeating: GridItem(.fixed(tileWidth), spacing: 4), count: fit), alignment: .leading, spacing: 4) {
          ForEach(Array(rest.enumerated()), id: \.element) { i, p in
            tile(p).transition(appearing(i))
          }
          if let onAdd { ownTile(onAdd).transition(appearing(rest.count)) }
        }
        .transition(.opacity)
      }
    }
    .slidingHighlight(glide, selected: choice, fill: .color(c.accentSoft), corner: 10)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(GeometryReader { g in Color.clear.onAppear { width = g.size.width }.onChange(of: g.size.width) { _, w in width = w } })
    .onChange(of: expanded) { _, open in shownCurrent = open ? choice : nil }
    .confirmationDialog(
      removing.map { L("remove_n", $0.name) } ?? "", isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } }), titleVisibility: .visible
    ) {
      Button(L("remove"), role: .destructive) {
        if let p = removing { onRemove?(p) }
        removing = nil
      }
    } message: {
      Text(L("it_disappears_from_the_paper_choices"))
    }
  }

  /// Rows drift down into place and fade in, one after another.
  private func appearing(_ i: Int) -> AnyTransition {
    .opacity.combined(with: .offset(y: -8)).animation(Ease.outStrong(duration: 0.22).delay(Double(min(i / fit, 3)) * 0.04))
  }

  private func name(_ p: PaperChoice) -> String {
    switch p {
    case .style(let s): paperName(s)
    case .custom(let id): customs.first { $0.id == id }?.name ?? ""
    }
  }

  @ViewBuilder private func swatch(_ p: PaperChoice) -> some View {
    switch p {
    case .style(let s):
      PaperSwatch(style: s, dark: dark, look: PaperSettings.shared.looks[s.rawValue], weight: CGFloat(PaperSettings.shared.weight(s, custom: nil)))
    case .custom(let id):
      if let cp = customs.first(where: { $0.id == id }) { CustomPaperSwatch(paper: cp, dark: dark) }
    }
  }

  private var swatchSize: CGSize { CGSize(width: tileWidth * 0.62, height: tileWidth * 0.62 / 1.22) }

  private func tile(_ p: PaperChoice) -> some View {
    let on = p == choice
    let mine = customs.first { if case .custom(let id) = p { $0.id == id } else { false } }
    return VStack(spacing: 4) {
      swatch(p)
        .frame(width: swatchSize.width, height: swatchSize.height)
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(on ? c.accent : .clear, lineWidth: 1.5))
        .overlay(alignment: .topTrailing) {
          if on, onEditCurrent != nil {
            Circle().fill(c.accent).frame(width: 16, height: 16)
              .overlay(Image(systemName: "pencil").font(.system(size: 8, weight: .bold)).foregroundStyle(.white))
              .offset(x: 5, y: -5)
              .transition(.scale(scale: 0.6).combined(with: .opacity))
          }
        }
      Text(name(p)).font(TaliFont.body(10, .semibold)).foregroundStyle(on ? c.accent : c.inkMuted).lineLimit(1).padding(.horizontal, 2)
    }
    .padding(.vertical, 6)
    .frame(width: tileWidth)
    .slidingOption(p, in: glide)
    .contentShape(Rectangle())
    .onTapGesture {
      if on, let onEditCurrent { onEditCurrent() } else { withAnimation(.easeOut(duration: 0.2)) { choice = p } }
    }
    .onLongPressGesture {
      if let mine, onRemove != nil { removing = mine }
    }
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(name(p))
    .accessibilityIdentifier("paper-\(p.key)")
    .accessibilityAddTraits(on ? [.isButton, .isSelected] : .isButton)
  }

  private var moreTile: some View {
    Button {
      withAnimation(Ease.outStrong(duration: expanded ? 0.18 : 0.26)) { expanded.toggle() }
    } label: {
      VStack(spacing: 4) {
        RoundedRectangle(cornerRadius: 8).fill(c.sunken)
          .frame(width: swatchSize.width, height: swatchSize.height)
          .overlay(Image(systemName: "chevron.down").font(.system(size: 15, weight: .semibold)).foregroundStyle(c.inkMuted).rotationEffect(.degrees(expanded ? 180 : 0)))
        Text(expanded ? L("fewer") : L("more")).font(TaliFont.body(10, .semibold)).foregroundStyle(c.inkMuted).lineLimit(1)
      }
      .padding(.vertical, 6)
      .frame(width: tileWidth)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain).contentShape(Rectangle())
    .accessibilityIdentifier("paper-more")
  }

  private func ownTile(_ action: @escaping () -> Void) -> some View {
    Button(action: action) {
      VStack(spacing: 4) {
        RoundedRectangle(cornerRadius: 8).stroke(c.line, lineWidth: 1)
          .frame(width: swatchSize.width, height: swatchSize.height)
          .overlay(Image(systemName: "plus").font(.system(size: 16, weight: .medium)).foregroundStyle(c.accent))
        Text(L("your_own")).font(TaliFont.body(10, .semibold)).foregroundStyle(c.inkMuted).lineLimit(1)
      }
      .padding(.vertical, 6)
      .frame(width: tileWidth)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain).contentShape(Rectangle())
    .accessibilityIdentifier("paper-own")
  }
}

/// A one-line setting with a switch and a short explanation (Android's `ToggleRow`).
struct ToggleRow: View {
  var label: String
  @Binding var on: Bool
  var detail: String?
  @Environment(\.tali) private var c

  var body: some View {
    Toggle(isOn: $on) {
      VStack(alignment: .leading, spacing: 1) {
        Text(label).font(TaliType.bodyMedium).foregroundStyle(c.ink)
        if let detail { Text(detail).font(TaliType.bodySmall).foregroundStyle(c.inkMuted) }
      }
    }
    .tint(c.accent)
    .padding(.vertical, 6).padding(.horizontal, 4)
  }
}

/// How heavy a paper's lines are, as five named choices (Android's `LineWeightChoice`).
struct LineWeightChoice: View {
  @Binding var weight: Float
  var body: some View {
    let names = [L("thin"), L("normal"), L("bold"), L("bolder"), L("heavy")]
    Segmented(
      options: PaperWeight.choices, selected: Binding(get: { PaperWeight.nearest(weight) }, set: { weight = $0 }),
      label: { names[PaperWeight.choices.firstIndex(of: $0) ?? 1] })
  }
}
