import SwiftUI

/// A card over the screen, as Android's `DialogCard` shows one: the screen dims behind it, the card
/// sits in the middle (above the keyboard), and a tap outside closes it. Drawn by the app rather
/// than as a system sheet, so iOS adds no panel of its own behind the card. It arrives from 96%
/// with a strong ease-out and leaves faster than it came.
struct DialogOverlay<Card: View>: View {
  var onClose: () -> Void
  @ViewBuilder var card: Card
  @Environment(\.tali) private var c

  var body: some View {
    ZStack {
      c.scrim.ignoresSafeArea()
        .onTapGesture(perform: onClose)
        .transition(.opacity)
        .accessibilityHidden(true)
      card
        .padding(24)
        .transition(.asymmetric(insertion: .opacity.combined(with: .scale(scale: 0.96)), removal: .opacity.combined(with: .scale(scale: 0.98))))
    }
    .accessibilityAddTraits(.isModal)
  }
}
