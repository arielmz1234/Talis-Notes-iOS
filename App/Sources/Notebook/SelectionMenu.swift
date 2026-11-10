import SwiftUI

/// The menu over what the lasso picked up (Android's folded selection menu): Copy, Cut, Duplicate,
/// Draw a box around it, Delete, on a soft-edged cloud. It sits above the selection, or below it
/// when there's no room above, and keeps clear of the toolbars.
struct SelectionMenu: View {
  var onCommand: (CanvasCommand) -> Void
  @Environment(\.tali) private var c
  /// ⋯ adds the rest of the buttons in the same row, right after itself.
  @State private var more = false
  /// Colour or Thickness, dropped down under the row (one at a time).
  @State private var extra: Extra?
  @State private var thickness: Float = 2.5

  enum Extra { case colour, thickness }

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      HStack(spacing: 0) {
        ToolIcon(system: "doc.on.doc", label: L("copy_hold_anywhere_to_paste_it")) { onCommand(.copySelection) }
        ToolIcon(system: "scissors", label: L("cut_hold_anywhere_to_paste_it")) { onCommand(.cutSelection) }
        ToolIcon(system: "plus.square.on.square", label: L("duplicate")) { onCommand(.duplicateSelection) }
        ToolIcon(system: "square", label: L("draw_a_box_around_it")) { onCommand(.boxSelection) }
        ToolIcon(system: "trash", label: L("delete")) { onCommand(.deleteSelection) }
        Rectangle().fill(c.line).frame(width: 1, height: 24).padding(.horizontal, 2)
        // Like the toolbar's chevron: > opens the rest to its right, and turns round into < to fold them away.
        Button {
          withAnimation(Ease.outStrong(duration: 0.22)) {
            more.toggle()
            extra = nil
          }
        } label: {
          Image(systemName: "chevron.right").font(.system(size: 15, weight: .semibold)).foregroundStyle(c.inkMuted)
            .rotationEffect(.degrees(more ? 180 : 0)).frame(width: 30, height: 44)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(more ? L("fewer_options") : L("more_options"))
        if more {
          Group {
            toggleIcon("paintpalette", L("colour"), .colour)
            toggleIcon("lineweight", L("thickness"), .thickness)
            ToolIcon(system: "square.3.layers.3d.top.filled", label: L("bring_to_front")) { onCommand(.arrangeSelection(true)) }
            ToolIcon(system: "square.3.layers.3d.bottom.filled", label: L("send_to_back")) { onCommand(.arrangeSelection(false)) }
            ToolIcon(system: "arrow.left.and.right", label: L("mirror_left_to_right")) { onCommand(.mirrorSelection(true)) }
            ToolIcon(system: "arrow.up.and.down", label: L("mirror_upside_down")) { onCommand(.mirrorSelection(false)) }
          }
          .transition(.opacity.combined(with: .offset(x: -8)))
        }
      }
      .frame(height: 44)
      if let extra {
        Group {
          switch extra {
          case .colour:
            HStack(spacing: 0) {
              ForEach(Palette.saved, id: \.self) { col in
                ColorDot(color: Color(argb: col), selected: false, size: 22) { onCommand(.recolourSelection(col)) }
                  .frame(maxWidth: .infinity)
              }
            }
          case .thickness:
            HStack(spacing: 8) {
              StepSlider(value: $thickness, range: 0.5...20, step: 0.5) { onCommand(.thickenSelection(thickness)) }
              Text(String(format: "%.1f", thickness)).font(TaliType.titleSmall).foregroundStyle(c.ink).frame(width: 40)
            }
            .frame(width: 300)
          }
        }
        .padding(.top, 6)
        .transition(.opacity.combined(with: .offset(y: -6)))
      }
    }
    .padding(.horizontal, 6).padding(.vertical, 4)
    .fixedSize(horizontal: true, vertical: false)
    .cloudSurface(radius: 22, crown: .softEdge)
    .animation(Ease.outStrong(duration: 0.22), value: more)
  }

  private func toggleIcon(_ icon: String, _ label: String, _ kind: Extra) -> some View {
    Button {
      withAnimation(Ease.outStrong(duration: 0.2)) { extra = extra == kind ? nil : kind }
    } label: {
      Image(systemName: icon).font(.system(size: 19)).foregroundStyle(extra == kind ? c.accent : c.ink)
        .frame(width: 44, height: 44)
        .background { if extra == kind { RoundedRectangle(cornerRadius: 14).fill(c.accentSoft) } }
    }
    .buttonStyle(PressStyle(scale: 0.9))
    .accessibilityLabel(label)
  }
}

/// Places the selection menu by the selection's frame (window coordinates), as Android's layout does:
/// above it if there's room under the toolbars, else below it, else just inside its top edge.
struct SelectionMenuLayer: View {
  var selection: CGRect
  var narrow: Bool
  var onCommand: (CanvasCommand) -> Void
  @State private var size = CGSize(width: 290, height: 52)

  var body: some View {
    GeometryReader { geo in
      let origin = geo.frame(in: .global).origin
      let rect = selection.offsetBy(dx: -origin.x, dy: -origin.y)
      let gap: CGFloat = 14
      let topLimit: CGFloat = narrow ? 196 : 128
      let bottomLimit = geo.size.height - size.height - gap
      let above = rect.minY - size.height - gap
      let below = rect.maxY + gap
      let y = above >= topLimit ? above : (below <= bottomLimit ? below : min(max(rect.minY + gap, topLimit), max(bottomLimit, topLimit)))
      let x = min(max(rect.midX - size.width / 2, gap), max(geo.size.width - size.width - gap, gap))
      SelectionMenu(onCommand: onCommand)
        .fixedSize()
        .background(GeometryReader { g in Color.clear.onAppear { size = g.size }.onChange(of: g.size) { _, v in size = v } })
        .position(x: x + size.width / 2, y: y + size.height / 2)
        .transition(.opacity.combined(with: .scale(scale: 0.96)))
    }
  }
}

/// "Paste" at the place she held (Android's `PasteBubble`).
struct PasteBubble: View {
  var at: CGPoint
  var onPaste: () -> Void
  @Environment(\.tali) private var c

  var body: some View {
    GeometryReader { geo in
      let origin = geo.frame(in: .global).origin
      Button(action: onPaste) {
        Label(L("paste"), systemImage: "doc.on.clipboard").font(TaliType.labelLarge).foregroundStyle(c.ink)
          .padding(.horizontal, 16).frame(height: 44)
          .cloudSurface(radius: 22, crown: .little, shadowDepth: 5)
      }
      .buttonStyle(PressStyle())
      .position(x: at.x - origin.x, y: at.y - origin.y - 44)
      .transition(.opacity.combined(with: .scale(scale: 0.94, anchor: .bottom)))
    }
  }
}

/// A short message near the bottom that fades after a few seconds (Android's hint).
struct HintPill: View {
  var text: String
  @Environment(\.tali) private var c

  var body: some View {
    Text(text).font(TaliType.bodyMedium).foregroundStyle(c.ink)
      .padding(.horizontal, 18).padding(.vertical, 11)
      .cloudSurface(radius: 20, crown: .center, shadowDepth: 5)
      .transition(.opacity.combined(with: .offset(y: 10)))
  }
}
