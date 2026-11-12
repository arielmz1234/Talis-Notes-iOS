import SwiftUI
import TaliCore

/// What the library's + can add (Android's `AddMenu.kt`), in its order.
enum AddChoice: CaseIterable {
  case notebook, file, camera, photo
}

/// The library's + (Android's `AddButton`): a 48 pt rounded square in the violet-to-blue gradient
/// whose + turns into × while its card is open.
struct AddButton: View {
  @Binding var open: Bool
  @Environment(\.tali) private var c

  var body: some View {
    Button {
      withAnimation(Ease.outStrong(duration: 0.24)) { open.toggle() }
    } label: {
      Image(systemName: "plus").font(.system(size: 22, weight: .medium)).foregroundStyle(c.onAccent)
        .rotationEffect(.degrees(open ? 45 : 0))
        .frame(width: 48, height: 48)
        .background(RoundedRectangle(cornerRadius: 16).fill(c.accentGradient))
    }
    .buttonStyle(PressStyle(scale: 0.94))
    .accessibilityLabel(L("add"))
    .accessibilityIdentifier("add")
    .anchorPreference(key: AddButtonBounds.self, value: .bounds) { $0 }
  }
}

/// Where the + is, so its card can open under it above everything else.
struct AddButtonBounds: PreferenceKey {
  static var defaultValue: Anchor<CGRect>? { nil }
  static func reduce(value: inout Anchor<CGRect>?, nextValue: () -> Anchor<CGRect>?) { value = nextValue() ?? value }
}

/// The + card (Android's `AddCard`): its rows drift in one after another. The library puts it under
/// the button, lined up with its outer edge, growing out of that corner.
struct AddCard: View {
  var choices: [AddChoice]
  var onPick: (AddChoice) -> Void

  var body: some View {
    VStack(spacing: 0) {
      ForEach(Array(choices.enumerated()), id: \.element) { i, choice in
        AddRow(index: i, choice: choice) { onPick(choice) }
      }
    }
    .padding(8)
    .cloudSurface(radius: 22)
  }
}

private struct AddRow: View {
  var index: Int
  var choice: AddChoice
  var action: () -> Void
  @Environment(\.tali) private var c
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var shown = false

  var body: some View {
    let (icon, tint, title, detail, id) = look
    Button(action: action) {
      HStack(spacing: 14) {
        Image(systemName: icon).font(.system(size: 20)).foregroundStyle(tint)
          .frame(width: 44, height: 44)
          .background(RoundedRectangle(cornerRadius: 14).fill(tint.opacity(c.isDark ? 0.22 : 0.12)))
        VStack(alignment: .leading, spacing: 0) {
          Text(title).font(TaliType.titleSmall).foregroundStyle(c.ink)
          Text(detail).font(TaliType.bodySmall).foregroundStyle(c.inkMuted)
        }
        Spacer(minLength: 0)
      }
      .padding(.horizontal, 10).padding(.vertical, 9)
      .contentShape(Rectangle())
    }
    .buttonStyle(RowPressStyle())
    .opacity(shown ? 1 : 0)
    .offset(y: shown || reduceMotion ? 0 : 10)
    .accessibilityIdentifier(id)
    .onAppear {
      withAnimation(Ease.outStrong(duration: 0.26).delay(0.04 + Double(index) * 0.035)) { shown = true }
    }
  }

  private var look: (String, Color, String, String, String) {
    switch choice {
    case .notebook: ("book.pages", c.accent, L("notebook"), L("blank_pages_to_write_on"), "add-notebook")
    case .file: ("doc.badge.arrow.up", KindBadge.tint(.pdf, dark: c.isDark), L("add_file"), L("a_pdf_or_pictures_from_your_files"), "add-file")
    case .camera: ("camera", KindBadge.tint(.picture, dark: c.isDark), L("add_camera"), L("a_photo_of_the_board_or_a_page"), "add-camera")
    case .photo: ("photo", KindBadge.tint(.picture, dark: c.isDark), L("add_photo"), L("from_your_gallery"), "add-photo")
    }
  }
}

/// A row that darkens a touch while pressed (Android's ripple on a card row).
struct RowPressStyle: ButtonStyle {
  @Environment(\.tali) private var c
  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .background(RoundedRectangle(cornerRadius: 16).fill(c.ink.opacity(configuration.isPressed ? 0.06 : 0)))
      .contentShape(Rectangle())
      .animation(.easeOut(duration: configuration.isPressed ? 0.05 : 0.2), value: configuration.isPressed)
  }
}
