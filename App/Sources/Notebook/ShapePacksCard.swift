import SwiftUI
import TaliCore

/// Every subject's shapes (Android's `ShapePacksDialog`): the subjects down the left (a star keeps
/// one in the Shapes panel, for the whole app), the chosen subject's shapes on the right. Picking a
/// shape starts drawing it. On a phone the subjects run along the top instead, where there's room.
struct ShapePacksCard: View {
  var picker: ShapePicker
  /// The screen it's shown over: narrow ones get the phone's arrangement, short ones a shorter card.
  var size: CGSize
  var onClose: () -> Void
  @Environment(\.tali) private var c
  @AppStorage(ShapeSettings.Key.starredPacks) private var starredList = ""
  /// The subject whose shapes show: at first the first one she starred, else the first.
  @State private var shown = ShapePacks.all.first { ShapeSettings.starred(from: UserDefaults.standard.string(forKey: ShapeSettings.Key.starredPacks) ?? "").contains($0.id) }?.id

  private var starred: Set<String> { ShapeSettings.starred(from: starredList) }

  private var pack: ShapePack { ShapePacks.all.first { $0.id == shown } ?? ShapePacks.all[0] }

  var body: some View {
    let narrow = size.width < 600
    VStack(alignment: .leading, spacing: 0) {
      Text(L("more_shapes")).font(TaliType.titleLarge).foregroundStyle(c.ink)
      Spacer().frame(height: 4)
      Text(L("star_a_subject_to_keep_its")).font(TaliType.bodySmall).foregroundStyle(c.inkMuted)
      Spacer().frame(height: 14)
      if narrow {
        ScrollView(.horizontal) {
          HStack(spacing: 6) { ForEach(ShapePacks.all) { subject($0, narrow: true) } }
        }
        .scrollIndicators(.hidden)
        Spacer().frame(height: 12)
        FittedScroll(limit: max(size.height - 330, 160)) { shapes }
      } else {
        HStack(alignment: .top, spacing: 18) {
          ScrollView {
            VStack(spacing: 0) { ForEach(ShapePacks.all) { subject($0, narrow: false) } }
          }
          .scrollIndicators(.hidden)
          .frame(width: 250)
          ScrollView { shapes }.scrollIndicators(.hidden)
        }
        .frame(height: min(CGFloat(ShapePacks.all.count) * 42, max(size.height - 260, 200)))
      }
      Spacer().frame(height: 16)
      HStack {
        Spacer()
        Button(L("done"), action: onClose).buttonStyle(QuietButtonStyle()).accessibilityIdentifier("packs-done")
      }
    }
    .padding(28)
    .frame(maxWidth: 860)
    .cloudSurface(radius: 24, crown: .none, shadowDepth: 12)
  }

  private var shapes: some View {
    VStack(alignment: .leading, spacing: 0) {
      Text(subjectName(pack)).font(TaliType.titleMedium).foregroundStyle(c.ink)
      Text(starred.contains(pack.id) ? L("in_your_shapes_panel") : L("tap_the_star_to_keep_these")).font(TaliType.bodySmall).foregroundStyle(c.inkFaint)
      PackTiles(pack: pack, picker: picker)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  private func subject(_ p: ShapePack, narrow: Bool) -> some View {
    let on = p.id == pack.id
    let name = subjectName(p)
    return HStack(spacing: 0) {
      Text(name).font(TaliType.bodyMedium).foregroundStyle(on ? c.accent : c.ink).lineLimit(1)
        .frame(maxWidth: narrow ? nil : .infinity, alignment: .leading)
      StarToggle(on: starred.contains(p.id), label: starred.contains(p.id) ? L("take_n_out_of_the_shapes", name) : L("add_n_to_the_shapes_panel", name)) {
        starredList = ShapeSettings.list(of: starred.symmetricDifference([p.id]))
      }
      .accessibilityIdentifier("star-\(p.id)")
    }
    .padding(.leading, 12)
    .frame(height: 42)
    .background(RoundedRectangle(cornerRadius: 12).fill(on ? c.accentSoft : (narrow ? c.background : .clear)))
    .contentShape(Rectangle())
    .onTapGesture { withAnimation(.easeOut(duration: 0.2)) { shown = p.id } }
    .accessibilityElement(children: .contain)
    .accessibilityLabel(name)
    .accessibilityAddTraits(on ? [.isButton, .isSelected] : .isButton)
    .accessibilityIdentifier("subject-\(p.id)")
  }
}
