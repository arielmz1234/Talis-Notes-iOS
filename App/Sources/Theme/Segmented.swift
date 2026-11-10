import SwiftUI

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
          .background {
            if on {
              RoundedRectangle(cornerRadius: 10).fill(c.surface)
                .shadow(color: c.glow.opacity(0.12), radius: 3, y: 1)
                .matchedGeometryEffect(id: "pill", in: glide)
            }
          }
          .contentShape(Rectangle())
          .onTapGesture {
            withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) { selected = o }
          }
          .accessibilityAddTraits(on ? [.isButton, .isSelected] : .isButton)
      }
    }
    .padding(3)
    .background(RoundedRectangle(cornerRadius: 12).fill(c.sunken))
  }
}
