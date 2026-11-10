import SwiftUI
import TaliCore

/// The papers to choose from (Android's `PaperPicker`): as many tiles as fit on one row (up to
/// [perRow]) with More at the end; More unfolds the rest underneath. Blank, Lines and Grid come
/// first; the paper in use takes the first place when it isn't on the first row. The chosen tile
/// sits on a soft wash that glides between them.
struct PaperPicker: View {
  @Binding var style: PaperStyle
  var tileWidth: CGFloat = 62
  var perRow = 4
  var dark = false
  @Environment(\.tali) private var c
  @State private var expanded = false
  @State private var width: CGFloat = 0
  @Namespace private var glide

  static let folded: [PaperStyle] = [.BLANK, .LINES, .GRID]

  private var fit: Int {
    guard width > 0 else { return max(2, perRow) }
    return min(max(Int((width + 4) / (tileWidth + 4)), 2), max(2, perRow))
  }

  var body: some View {
    let usual = Array((PaperPicker.folded + PaperStyle.allCases.filter { !PaperPicker.folded.contains($0) }).prefix(fit - 1))
    let first = usual.contains(style) ? usual : Array(([style] + usual).prefix(fit - 1))
    let rest = PaperStyle.allCases.filter { !first.contains($0) }
    VStack(alignment: .leading, spacing: 4) {
      HStack(spacing: 4) {
        ForEach(first, id: \.self) { tile($0) }
        moreTile
      }
      if expanded {
        LazyVGrid(columns: Array(repeating: GridItem(.fixed(tileWidth), spacing: 4), count: fit), alignment: .leading, spacing: 4) {
          ForEach(Array(rest.enumerated()), id: \.element) { i, p in
            tile(p).transition(.opacity.combined(with: .offset(y: -8)).animation(Ease.outStrong(duration: 0.22).delay(Double(min(i / fit, 3)) * 0.04)))
          }
        }
        .transition(.opacity)
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(GeometryReader { g in Color.clear.onAppear { width = g.size.width }.onChange(of: g.size.width) { _, w in width = w } })
  }

  private func tile(_ p: PaperStyle) -> some View {
    let on = p == style
    return Button {
      withAnimation(.spring(response: 0.3, dampingFraction: 0.82)) { style = p }
    } label: {
      VStack(spacing: 4) {
        PaperPreview(style: p, dark: dark, zoom: 2.6)
          .frame(width: tileWidth * 0.62, height: tileWidth * 0.62 / 1.22)
          .clipShape(RoundedRectangle(cornerRadius: 8))
          .overlay(RoundedRectangle(cornerRadius: 8).stroke(on ? c.accent : c.line.opacity(0.6), lineWidth: on ? 1.5 : 1))
        Text(paperName(p)).font(TaliFont.body(10, .semibold)).foregroundStyle(on ? c.accent : c.inkMuted).lineLimit(1).padding(.horizontal, 2)
      }
      .padding(.vertical, 6)
      .frame(width: tileWidth)
      .background {
        if on { RoundedRectangle(cornerRadius: 10).fill(c.accentSoft).matchedGeometryEffect(id: "paper", in: glide) }
      }
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .accessibilityLabel(paperName(p))
    .accessibilityAddTraits(on ? [.isButton, .isSelected] : .isButton)
  }

  private var moreTile: some View {
    Button {
      withAnimation(Ease.outStrong(duration: expanded ? 0.18 : 0.26)) { expanded.toggle() }
    } label: {
      VStack(spacing: 4) {
        RoundedRectangle(cornerRadius: 8).fill(c.sunken)
          .frame(width: tileWidth * 0.62, height: tileWidth * 0.62 / 1.22)
          .overlay(Image(systemName: "chevron.down").font(.system(size: 15, weight: .semibold)).foregroundStyle(c.inkMuted).rotationEffect(.degrees(expanded ? 180 : 0)))
        Text(expanded ? L("fewer") : L("more")).font(TaliFont.body(10, .semibold)).foregroundStyle(c.inkMuted).lineLimit(1)
      }
      .padding(.vertical, 6)
      .frame(width: tileWidth)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
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
