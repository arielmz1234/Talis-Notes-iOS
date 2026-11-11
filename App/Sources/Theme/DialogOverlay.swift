import SwiftUI

/// A card over the screen, as Android's `DialogCard` shows one: the screen dims behind it (unless
/// [dim] is off, as for confirmations), the card sits in the middle (above the keyboard), and a tap
/// outside closes it. Drawn by the app rather than as a system sheet, so iOS adds no panel of its
/// own behind the card. It arrives from 96% with a strong ease-out and leaves faster than it came.
struct DialogOverlay<Card: View>: View {
  var dim = true
  var onClose: () -> Void
  @ViewBuilder var card: Card
  @Environment(\.tali) private var c

  var body: some View {
    ZStack {
      (dim ? c.scrim : Color.clear).contentShape(Rectangle()).ignoresSafeArea()
        .onTapGesture(perform: onClose)
        .transition(.opacity)
        .accessibilityHidden(true)
      GeometryReader { geo in
        card
          // Never wider than the screen less 24 pt each side, whatever its contents would like.
          .frame(maxWidth: max(geo.size.width - 48, 0))
          .frame(width: geo.size.width, height: geo.size.height)
      }
      .padding(.vertical, 24)
        .transition(.asymmetric(insertion: .opacity.combined(with: .scale(scale: 0.96)), removal: .opacity.combined(with: .scale(scale: 0.98))))
    }
    .accessibilityAddTraits(.isModal)
  }
}

/// The card itself (Android's `DialogCard` column): the soft cloud surface on a lilac shadow,
/// 28 pt inside, as wide as the screen allows up to [width].
struct DialogCard<Content: View>: View {
  var width: CGFloat = 520
  @ViewBuilder var content: Content

  var body: some View {
    VStack(alignment: .leading, spacing: 0) { content }
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(28)
      .cloudSurface(radius: 24, crown: .none, shadowDepth: 12)
      .frame(maxWidth: width)
  }
}

/// The middle of a card, between its title and its buttons (Android's `CardBody`): on a screen too
/// short for the card it scrolls, so the buttons under it are never cut off.
struct CardBody<Content: View>: View {
  var maxHeight: CGFloat = .infinity
  @ViewBuilder var content: Content

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 0) { content }
        // Room at the sides, as Compose leaves across a scroll, for a gliding ring overshooting the last option.
        .padding(.horizontal, 6)
    }
    .padding(.horizontal, -6)
    .scrollBounceBehavior(.basedOnSize)
    .frame(maxHeight: maxHeight)
    .fixedSize(horizontal: false, vertical: true)
  }
}

/// Buttons at the end of a card, Cancel before the main one (Android's `ButtonRow`, end-aligned).
struct CardButtons<Content: View>: View {
  @ViewBuilder var content: Content
  var body: some View {
    HStack(spacing: 10) {
      Spacer(minLength: 0)
      content
    }
  }
}
