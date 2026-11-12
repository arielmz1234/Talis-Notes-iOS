import SwiftUI
import TaliCore

/// The menu over what's picked up (Android's `SelectionMenu`). Folded it shows only the everyday
/// actions: Crop first for a picture, Copy, Cut, Duplicate, Draw a box around it, Delete. The arrow
/// adds the rest in the same row, right after itself: Colour, Thickness, to front, to back, the two
/// mirrors, lock or unlock, Edit text, Save as shape. The row scrolls sideways when the screen is
/// too narrow for it. Colour and Thickness each open one drop-down under the row, as wide as it.
struct SelectionMenu: View {
  var info: SelectionInfo
  /// The widest the menu may be (the screen less a gap each side).
  var maxWidth: CGFloat
  /// ⋯ adds the rest of the buttons in the same row, right after itself.
  @Binding var more: Bool
  var onSaveShape: () -> Void = {}
  var onCrop: () -> Void = {}
  var onCommand: (CanvasCommand) -> Void
  @Environment(\.tali) private var c
  /// Colour or Thickness, dropped down under the row (one at a time).
  @State private var extra: Extra?
  @State private var thickness: Float = 2.5

  enum Extra { case colour, thickness }

  static let button: CGFloat = 44
  /// The hairline and the arrow after the folded buttons.
  static let arrow: CGFloat = 35
  static let padding: CGFloat = 6

  /// How wide the folded buttons are (copy to the arrow): the menu is placed by it, so opening
  /// keeps its left side and the arrow where they were and grows to the right.
  static func foldedWidth(_ info: SelectionInfo) -> CGFloat { CGFloat(info.croppable ? 6 : 5) * button + arrow }

  private static func restCount(_ info: SelectionInfo) -> Int {
    5 + (!info.hasImage || info.count > 1 ? 1 : 0) + (info.lineSize != nil ? 1 : 0) + (info.textId != nil ? 1 : 0) + (info.hasDrawing ? 1 : 0)
  }

  /// How wide the menu shows its row: all of it, or as much as the screen has room for (it scrolls).
  static func shownWidth(_ info: SelectionInfo, more: Bool, maxWidth: CGFloat) -> CGFloat {
    min(foldedWidth(info) + (more ? CGFloat(restCount(info)) * button : 0), max(maxWidth - 2 * padding, 120))
  }

  private var rowWidth: CGFloat { Self.foldedWidth(info) + (more ? CGFloat(Self.restCount(info)) * Self.button : 0) }
  private var shownWidth: CGFloat { Self.shownWidth(info, more: more, maxWidth: maxWidth) }

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Group {
        // The row scrolls sideways only when the screen is too narrow for it.
        if rowWidth > shownWidth {
          ScrollView(.horizontal, showsIndicators: false) { row }
            .frame(width: shownWidth, height: Self.button)
            .accessibilityIdentifier("selection-row")
        } else {
          row
        }
      }
      if more, let extra {
        Group {
          switch extra {
          case .colour: colours
          case .thickness: thicknessRow
          }
        }
        .frame(width: shownWidth)
        .padding(.top, 2).padding(.bottom, 4)
        .transition(.opacity)
      }
    }
    .padding(.horizontal, Self.padding).padding(.vertical, 4)
    .cloudSurface(radius: 22, crown: .softEdge)
    .onChange(of: info.count) { _, _ in
      more = false
      extra = nil
    }
    .onChange(of: info.lineSize, initial: true) { _, size in thickness = size ?? thickness }
  }

  private var row: some View {
    HStack(spacing: 0) {
      folded
      if more { rest.transition(.opacity) }
    }
    .frame(width: rowWidth, height: Self.button, alignment: .leading)
    .clipped()
  }

  private var folded: some View {
    HStack(spacing: 0) {
      // A picture: cropping first, as it's what's most often wanted right after adding one.
      if info.croppable { ToolIcon(system: "crop", label: L("crop"), action: onCrop).accessibilityIdentifier("selection-crop") }
      ToolIcon(system: "doc.on.doc", label: L("copy_hold_anywhere_to_paste_it")) { onCommand(.copySelection) }.accessibilityIdentifier("selection-copy")
      ToolIcon(system: "scissors", label: L("cut_hold_anywhere_to_paste_it")) { onCommand(.cutSelection) }.accessibilityIdentifier("selection-cut")
      ToolIcon(system: "plus.square.on.square", label: L("duplicate")) { onCommand(.duplicateSelection) }.accessibilityIdentifier("selection-duplicate")
      // A rectangle round it, drawn with the pen in use.
      ToolIcon(system: "square", label: L("draw_a_box_around_it")) { onCommand(.boxSelection) }.accessibilityIdentifier("selection-box")
      ToolIcon(system: "trash", label: L("delete")) { onCommand(.deleteSelection) }.accessibilityIdentifier("selection-delete")
      Rectangle().fill(c.line).frame(width: 1, height: 24).padding(.horizontal, 2)
      // Like the toolbar's chevron: > opens the rest to its right, and turns round into < to fold them away.
      Button {
        withAnimation(Ease.outStrong(duration: 0.22)) {
          more.toggle()
          extra = nil
        }
      } label: {
        Image(systemName: "chevron.right").font(.system(size: 15, weight: .semibold)).foregroundStyle(c.inkMuted)
          .rotationEffect(.degrees(more ? 180 : 0)).frame(width: 30, height: 44).contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .accessibilityLabel(more ? L("fewer_options") : L("more_options"))
      .accessibilityIdentifier("selection-more")
    }
    .frame(width: Self.foldedWidth(info), alignment: .leading)
  }

  /// The rest of what the menu has, as plain buttons; colour and thickness each open their own row.
  private var rest: some View {
    HStack(spacing: 0) {
      if !info.hasImage || info.count > 1 { toggleIcon("paintpalette", L("colour"), .colour).accessibilityIdentifier("selection-colour") }
      if info.lineSize != nil { toggleIcon("lineweight", L("thickness"), .thickness).accessibilityIdentifier("selection-thickness") }
      ToolIcon(system: "square.3.layers.3d.top.filled", label: L("bring_to_front")) { onCommand(.arrangeSelection(true)) }.accessibilityIdentifier("selection-front")
      ToolIcon(system: "square.3.layers.3d.bottom.filled", label: L("send_to_back")) { onCommand(.arrangeSelection(false)) }.accessibilityIdentifier("selection-back")
      // Writing and shapes flip; pictures and text keep facing the right way.
      drawnIcon(.mirrorLeftRight, L("mirror_left_to_right")) { onCommand(.mirrorSelection(true)) }.accessibilityIdentifier("selection-mirror-h")
      drawnIcon(.mirrorUpsideDown, L("mirror_upside_down")) { onCommand(.mirrorSelection(false)) }.accessibilityIdentifier("selection-mirror-v")
      // Locked things stay put: the lasso, taps and the eraser leave them alone.
      ToolIcon(system: info.locked ? "lock.open" : "lock", label: info.locked ? L("unlock") : L("lock_in_place")) { onCommand(.lockSelection) }
        .accessibilityIdentifier("selection-lock")
      if let id = info.textId {
        ToolIcon(system: "square.and.pencil", label: L("edit_text")) { onCommand(.editText(id)) }.accessibilityIdentifier("selection-edit-text")
      }
      if info.hasDrawing { ToolIcon(system: "sparkles", label: L("save_as_shape"), action: onSaveShape).accessibilityIdentifier("save-as-shape") }
    }
  }

  /// The selection's colour: the dots spread evenly across the menu's width, wrapping into
  /// lined-up columns only when they don't fit.
  private var colours: some View {
    let palette = Palette.saved
    let perRow = min(max(Int(shownWidth / 38), 1), max(palette.count, 1))
    let rows = stride(from: 0, to: palette.count, by: perRow).map { Array(palette[$0..<min($0 + perRow, palette.count)]) }
    return VStack(spacing: 0) {
      ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
        HStack(spacing: 0) {
          ForEach(row, id: \.self) { col in
            ColorDot(color: Color(argb: col), selected: info.color.map { $0 | 0xFF00_0000 == col | 0xFF00_0000 } ?? false, size: 28) { onCommand(.recolourSelection(col)) }
              .frame(maxWidth: .infinity)
              .accessibilityIdentifier("selection-colour-\(palette.firstIndex(of: col) ?? 0)")
          }
          // Keep the columns lined up on a shorter last row.
          ForEach(0..<(perRow - row.count), id: \.self) { _ in Color.clear.frame(maxWidth: .infinity).frame(height: 1) }
        }
      }
    }
  }

  /// Thickness and line style of the writing and shapes picked up: side by side when the menu is
  /// wide enough, else one above the other. The drawing follows the slider as it moves; the change
  /// is saved (one undo step) when it's let go.
  private var thicknessRow: some View {
    let slider = HStack(spacing: 0) {
      StepSlider(value: Binding(get: { thickness }, set: { v in
        thickness = v
        onCommand(.previewThickness(v))
      }), range: 0.5...40, step: 0.5) {
        onCommand(.thickenSelection(thickness))
      }
      Text(String(format: "%.1f", thickness)).font(TaliType.titleSmall).foregroundStyle(c.ink).frame(width: 40).padding(.leading, 8)
    }
    let styles = CompactLineStylePicker(selected: info.line ?? "SOLID") { onCommand(.lineSelection($0)) }
    return Group {
      if info.line == nil {
        slider
      } else if shownWidth >= 500 {
        HStack(spacing: 8) {
          slider.frame(maxWidth: .infinity)
          styles.frame(maxWidth: .infinity)
        }
      } else {
        VStack(spacing: 2) {
          slider
          styles
        }
      }
    }
    .padding(.leading, 4)
  }

  private func toggleIcon(_ icon: String, _ label: String, _ kind: Extra) -> some View {
    Button {
      withAnimation(Ease.outStrong(duration: 0.2)) { extra = extra == kind ? nil : kind }
    } label: {
      Image(systemName: icon).font(.system(size: 19)).foregroundStyle(extra == kind ? c.accent : c.ink)
        .frame(width: 44, height: 44)
        .background { if extra == kind { RoundedRectangle(cornerRadius: 14).fill(c.accentSoft) } }
        .contentShape(Rectangle())
    }
    .buttonStyle(PressStyle(scale: 0.9))
    .accessibilityLabel(label)
  }

  private func drawnIcon(_ kind: SelectIcon.Kind, _ label: String, action: @escaping () -> Void) -> some View {
    Button(action: action) {
      SelectIcon(kind: kind, color: c.ink, size: 22).frame(width: 44, height: 44).contentShape(Rectangle())
    }
    .buttonStyle(PressStyle(scale: 0.9))
    .accessibilityLabel(label)
  }
}

/// Places the selection menu by the selection's frame (window coordinates), as Android's layout does:
/// above it if there's room under the toolbars, else below it, else just inside its top edge. It's
/// placed by the width of its folded buttons, so opening keeps its left side and the arrow where
/// they were and grows to the right.
struct SelectionMenuLayer: View {
  var info: SelectionInfo
  var narrow: Bool
  var onSaveShape: () -> Void = {}
  var onCrop: () -> Void = {}
  var onCommand: (CanvasCommand) -> Void
  @State private var more = false
  @State private var height: CGFloat = 52

  var body: some View {
    GeometryReader { geo in
      let origin = geo.frame(in: .global).origin
      let rect = info.rect.offsetBy(dx: -origin.x, dy: -origin.y)
      let gap: CGFloat = 14
      let width = SelectionMenu.shownWidth(info, more: more, maxWidth: geo.size.width - 2 * gap) + 2 * SelectionMenu.padding
      let topLimit: CGFloat = narrow ? 196 : 128
      let bottomLimit = geo.size.height - height - gap
      let above = rect.minY - height - gap
      // The rotate handle hangs under the selection: the menu, when it goes below, leaves room for it.
      let below = rect.maxY + gap + (info.rotatable ? 48 : 0)
      let y = above >= topLimit ? above : (below <= bottomLimit ? below : min(max(rect.minY + gap, topLimit), max(bottomLimit, topLimit)))
      let x = min(max(rect.midX - (SelectionMenu.foldedWidth(info) + 2 * SelectionMenu.padding) / 2, gap), max(geo.size.width - width - gap, gap))
      SelectionMenu(info: info, maxWidth: geo.size.width - 2 * gap, more: $more, onSaveShape: onSaveShape, onCrop: onCrop, onCommand: onCommand)
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height = $0 }
        .frame(width: width, alignment: .leading)
        .offset(x: x, y: y)
        .transition(.opacity.combined(with: .scale(scale: 0.96)))
    }
  }
}

/// "Paste" at the place she held (Android's `PasteBubble`): above it, or below it near the top.
struct PasteBubble: View {
  var at: CGPoint
  var onPaste: () -> Void
  @Environment(\.tali) private var c

  var body: some View {
    GeometryReader { geo in
      let origin = geo.frame(in: .global).origin
      let count = Clipboard.items.count
      let y = at.y - origin.y
      Button(action: onPaste) {
        Label(count == 1 ? L("paste") : L("paste_n_items", count), systemImage: "doc.on.clipboard").font(TaliType.labelLarge).foregroundStyle(c.ink)
          .padding(.horizontal, 16).frame(height: 44)
          .cloudSurface(radius: 22, crown: .little, shadowDepth: 5)
      }
      .buttonStyle(PressStyle())
      .accessibilityIdentifier("paste")
      .position(x: min(max(at.x - origin.x, 70), max(geo.size.width - 70, 70)), y: y - 44 >= 96 ? y - 44 : y + 44)
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
