import SwiftUI

/// The menu over what the lasso picked up (Android's folded selection menu): Copy, Cut, Duplicate,
/// Draw a box around it, Delete, on a soft-edged cloud. It sits above the selection, or below it
/// when there's no room above, and keeps clear of the toolbars.
struct SelectionMenu: View {
  var onCommand: (CanvasCommand) -> Void
  @Environment(\.tali) private var c

  var body: some View {
    HStack(spacing: 0) {
      ToolIcon(system: "doc.on.doc", label: L("copy_hold_anywhere_to_paste_it")) { onCommand(.copySelection) }
      ToolIcon(system: "scissors", label: L("cut_hold_anywhere_to_paste_it")) { onCommand(.cutSelection) }
      ToolIcon(system: "plus.square.on.square", label: L("duplicate")) { onCommand(.duplicateSelection) }
      ToolIcon(system: "square", label: L("draw_a_box_around_it")) { onCommand(.boxSelection) }
      ToolIcon(system: "trash", label: L("delete")) { onCommand(.deleteSelection) }
    }
    .padding(.horizontal, 6).padding(.vertical, 4)
    .frame(height: 52)
    .cloudSurface(radius: 22, crown: .softEdge)
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
        .background(GeometryReader { g in Color.clear.onAppear { size = g.size } })
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
