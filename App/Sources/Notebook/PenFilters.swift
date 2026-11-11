import SwiftUI
import TaliCore

/// Which pens the eraser and the lasso act on, kept between launches as Android keeps them
/// (`eraserAffects`, `lassoAffects`, `lassoSelectsImages`).
enum PenFilters {
  static func load(_ key: String) -> PenFilter {
    PenStore.resetForTests()
    return PenFilter((UserDefaults.standard.dictionary(forKey: key) as? [String: Bool]) ?? [:])
  }

  static func save(_ filter: PenFilter, _ key: String) {
    UserDefaults.standard.set(filter.choices, forKey: key)
  }
}

struct LassoSettings: Equatable {
  var affects = PenFilter()
  /// Android's `lassoSelectsImages`: everything that isn't written with a pen.
  var images = true
}

/// Android's `FilterChip`: a compact on/off chip, blue with a tick when on, a quiet outline when off.
struct FilterChip: View {
  var label: String
  var on: Bool
  var onChange: (Bool) -> Void
  @Environment(\.tali) private var c

  var body: some View {
    HStack(spacing: 4) {
      if on { Image(systemName: "checkmark").font(.system(size: 12, weight: .bold)).foregroundStyle(c.blue).transition(.scale(scale: 0.6).combined(with: .opacity)) }
      Text(label).font(TaliType.labelLarge).foregroundStyle(on ? c.blue : c.inkMuted)
    }
    .padding(.leading, on ? 8 : 12).padding(.trailing, 12).padding(.vertical, 7)
    .background(RoundedRectangle(cornerRadius: 12).fill(on ? c.blueSoft : .clear))
    .overlay(RoundedRectangle(cornerRadius: 12).stroke(on ? c.sky : c.line, lineWidth: 1))
    .contentShape(RoundedRectangle(cornerRadius: 12))
    .onTapGesture {
      withAnimation(.easeOut(duration: 0.2)) { onChange(!on) }
    }
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(label)
    .accessibilityAddTraits(on ? [.isButton, .isSelected] : .isButton)
  }
}

struct FlowRow: SwiftUI.Layout {
  var spacing: CGFloat = 8

  private func rows(_ width: CGFloat, _ subviews: Subviews) -> (frames: [CGRect], height: CGFloat) {
    var frames: [CGRect] = []
    var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0
    for view in subviews {
      let size = view.sizeThatFits(.unspecified)
      if x > 0, x + size.width > width {
        x = 0
        y += rowHeight + spacing
        rowHeight = 0
      }
      frames.append(CGRect(origin: CGPoint(x: x, y: y), size: size))
      x += size.width + spacing
      rowHeight = max(rowHeight, size.height)
    }
    return (frames, y + rowHeight)
  }

  func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
    let width = proposal.width ?? .infinity
    let laid = rows(width, subviews)
    return CGSize(width: width.isFinite ? width : (laid.frames.map(\.maxX).max() ?? 0), height: laid.height)
  }

  func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
    for (view, frame) in zip(subviews, rows(bounds.width, subviews).frames) {
      view.place(at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY), proposal: ProposedViewSize(frame.size))
    }
  }
}

struct PenFilterChips: View {
  @Binding var filter: PenFilter
  var images: Binding<Bool>?

  var body: some View {
    FlowRow {
      ForEach(PenType.offered, id: \.self) { type in
        FilterChip(label: penName(type), on: filter.hits(type)) { filter.set(type, $0) }
          .accessibilityIdentifier("filter-\(type.rawValue)")
      }
      if let images { FilterChip(label: L("images"), on: images.wrappedValue) { images.wrappedValue = $0 } }
    }
  }
}

/// The lasso's settings (the part of Android's `LassoPanel` about what it picks up).
struct LassoPanel: View {
  @Binding var settings: LassoSettings
  @Environment(\.tali) private var c

  var body: some View {
    ToolPanel(width: 340) {
      Text(L("select")).font(TaliType.titleLarge).foregroundStyle(c.ink)
      Spacer().frame(height: 14)
      Text(L("circle_anything_to_move_resize_recolour")).font(TaliType.bodyMedium).foregroundStyle(c.inkMuted)
      Spacer().frame(height: 14)
      SectionLabel(text: L("picks_up"))
      Spacer().frame(height: 8)
      PenFilterChips(filter: $settings.affects, images: $settings.images)
    }
  }
}
