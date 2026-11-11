import SwiftUI
import TaliCore

/// The notebook's settings that the ⋯ menu changes (Android's per-notebook and app-wide ones).
struct CanvasSettings: Equatable {
  var paper: PaperSpec
  var dark: Bool { paper.dark }
  /// Draw with finger: nil = Auto (iOS's own Apple Pencil setting), true = on, false = off.
  var fingerDraws: Bool?
  /// Tap 2 fingers to undo, 3 to redo.
  var smartUndo: Bool
  /// Write between pages: strokes may cross the gap instead of staying on their own page.
  var between: Bool
}

/// The ⋯ menu (Android's `MoreMenu`), kept compact: the actions as tiles, the paper choices, then
/// one-line switches. Only what's ported shows; the rest joins as it's ported.
struct MoreMenu<Papers: View>: View {
  var paged: Bool
  @ViewBuilder var papers: Papers
  @Binding var dark: Bool
  @Binding var fingerDraws: Bool?
  @Binding var smartUndo: Bool
  @Binding var between: Bool
  @Binding var fullScreen: Bool
  var onPages: () -> Void = {}
  var onExport: () -> Void = {}
  var onFit: () -> Void
  var onViewOnly: () -> Void
  @Environment(\.tali) private var c

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      HStack(spacing: 6) {
        if paged { tile("book.pages", L("pages"), action: onPages) }
        tile("arrow.up.left.and.arrow.down.right", paged ? L("whole_page") : L("everything"), action: onFit)
        tile("square.and.arrow.up", L("export_pdf"), action: onExport)
      }
      Text(L("paper").uppercased()).font(TaliType.labelSmall).tracking(0.66).foregroundStyle(c.inkFaint)
        .padding(.leading, 6).padding(.top, 10).padding(.bottom, 6)
      papers.padding(.horizontal, 2)
      HStack(spacing: 6) {
        chip("moon", L("dark_paper"), on: dark) { dark.toggle() }
      }
      .padding(.top, 8)
      Divider().overlay(c.line).padding(.top, 8).padding(.bottom, 4)
      row("hand.point.up", L("draw_with_finger"), value: fingerDraws == nil ? L("auto") : (fingerDraws! ? L("on") : L("off"))) {
        fingerDraws = fingerDraws == nil ? true : (fingerDraws! ? false : nil)
      }
      row("arrow.uturn.backward", L("tap_2_fingers_to_undo_3"), checked: smartUndo) { smartUndo.toggle() }
      if paged { row("arrow.up.and.down.text.horizontal", L("write_between_pages"), checked: between) { between.toggle() } }
      row("arrow.up.left.and.arrow.down.right.rectangle", L("full_screen"), checked: fullScreen) { fullScreen.toggle() }
      row("eye", L("view_only"), checked: false, action: onViewOnly)
    }
    .padding(.horizontal, 10).padding(.vertical, 8)
    .frame(width: 330)
  }

  /// An action in the top row: icon over a short label.
  private func tile(_ icon: String, _ label: String, action: @escaping () -> Void) -> some View {
    Button(action: action) {
      VStack(spacing: 3) {
        Image(systemName: icon).font(.system(size: 17)).foregroundStyle(c.accent)
        Text(label).font(TaliType.labelMedium).foregroundStyle(c.ink).lineLimit(2).multilineTextAlignment(.center)
      }
      .frame(maxWidth: .infinity).padding(.vertical, 8).padding(.horizontal, 4)
      .background(RoundedRectangle(cornerRadius: 12).fill(c.accentSoft.opacity(0.55)))
    }
    .buttonStyle(PressStyle())
  }

  /// An on/off paper choice, as a chip that fills with the accent when on.
  private func chip(_ icon: String, _ label: String, on: Bool, action: @escaping () -> Void) -> some View {
    Button(action: action) {
      HStack(spacing: 8) {
        Image(systemName: on ? "checkmark" : icon).font(.system(size: 15)).foregroundStyle(on ? c.accent : c.inkMuted)
        Text(label).font(TaliType.labelLarge).foregroundStyle(on ? c.accent : c.ink).lineLimit(2)
        Spacer(minLength: 0)
      }
      .padding(.horizontal, 10).frame(minHeight: 38)
      .background(RoundedRectangle(cornerRadius: 12).fill(on ? c.accentSoft : .clear))
      .overlay(RoundedRectangle(cornerRadius: 12).stroke(on ? .clear : c.line, lineWidth: 1))
      .contentShape(RoundedRectangle(cornerRadius: 12))
      .animation(.easeOut(duration: 0.2), value: on)
    }
    .buttonStyle(.plain)
  }

  /// A one-line setting: a tick when on, or a value for a three-way one.
  private func row(_ icon: String, _ label: String, checked: Bool? = nil, value: String? = nil, action: @escaping () -> Void) -> some View {
    Button(action: action) {
      HStack(spacing: 12) {
        Image(systemName: icon).font(.system(size: 16)).foregroundStyle(c.inkMuted).frame(width: 20)
        Text(label).font(TaliType.bodyMedium).foregroundStyle(c.ink).lineLimit(2).multilineTextAlignment(.leading)
        Spacer(minLength: 10)
        if let value {
          Text(value).font(TaliType.labelLarge).foregroundStyle(c.accent)
        } else if checked == true {
          Image(systemName: "checkmark").font(.system(size: 15, weight: .semibold)).foregroundStyle(c.accent)
        }
      }
      .padding(.horizontal, 6).frame(minHeight: 40).contentShape(Rectangle())
    }
    .buttonStyle(.plain)
  }
}
