import SwiftUI
import TaliCore

/// A segmented control for two to four options (Android's `Segmented`): a sunken track with 12 pt
/// corners, and a white pill that glides to the chosen option. Each option gets the room its label
/// needs plus an even share of the rest.
struct Segmented<T: Hashable>: View {
  var options: [T]
  @Binding var selected: T
  var label: (T) -> String
  @Environment(\.tali) private var c
  @Namespace private var glide

  var body: some View {
    HStack(spacing: 3) {
      ForEach(options, id: \.self) { o in
        let on = o == selected
        Text(label(o)).font(TaliType.labelLarge).foregroundStyle(on ? c.ink : c.inkMuted).lineLimit(1)
          .fixedSize()
          .padding(.vertical, 8).padding(.horizontal, 6)
          .frame(maxWidth: .infinity)
          .slidingOption(o, in: glide)
          .contentShape(Rectangle())
          .onTapGesture {
            withAnimation(.easeOut(duration: 0.2)) { selected = o }
          }
          .accessibilityAddTraits(on ? [.isButton, .isSelected] : .isButton)
          .accessibilityIdentifier("option-\(String(describing: o))")
      }
    }
    .padding(3)
    .slidingHighlight(glide, selected: selected, fill: .color(c.surface), corner: 10, lift: true)
    .background(RoundedRectangle(cornerRadius: 12).fill(c.sunken))
  }
}

/// The colours offered for covers and folders, the chosen one ringed in ink; the ring glides
/// between them (Android's `CoverSwatches`).
struct CoverSwatches: View {
  var current: UInt32
  var spacing: CGFloat = 8
  /// At most this many in a row (Android's `maxItemsInEachRow`); otherwise as many as fit.
  var perRow: Int? = nil
  var onPick: (UInt32) -> Void
  @Environment(\.tali) private var c
  @Namespace private var ring

  var body: some View {
    let columns = perRow.map { Array(repeating: GridItem(.fixed(26), spacing: spacing), count: $0) } ?? [GridItem(.adaptive(minimum: 26, maximum: 26), spacing: spacing)]
    LazyVGrid(columns: columns, alignment: .leading, spacing: spacing) {
      ForEach(Covers.all, id: \.self) { col in
        Circle().fill(Color(argb: col)).frame(width: 26, height: 26)
          .slidingOption(col, in: ring)
          .contentShape(Circle())
          .onTapGesture { onPick(col) }
          .accessibilityAddTraits(col == current ? [.isButton, .isSelected] : .isButton)
      }
    }
    .slidingHighlight(ring, selected: current, fill: .color(c.ink), corner: 100, ring: 2, above: true)
  }
}
