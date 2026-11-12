import SwiftUI

/// A slider with − and + on either side for steps of [step] (Android's `StepSlider`). Holding a
/// button keeps stepping, faster the longer it's held; values land on whole steps.
///
/// On iOS 26 the slider is Apple's own with its Liquid Glass thumb, and the − and + are glass
/// buttons: the owner asked for the glass look here even though Android has none. Earlier iOS
/// versions get the plain accent-coloured slider.
struct StepSlider: View {
  @Binding var value: Float
  var range: ClosedRange<Float>
  var step: Float
  var lessLabel = L("thinner")
  var moreLabel = L("thicker")
  var onChangeFinished: () -> Void = {}
  @Environment(\.tali) private var c

  private func snap(_ v: Float) -> Float { min(max((v / step).rounded() * step, range.lowerBound), range.upperBound) }

  var body: some View {
    HStack(spacing: 6) {
      StepButton(system: "minus", label: lessLabel, enabled: value > range.lowerBound + step / 2) { value = snap(value - step) } done: { onChangeFinished() }
      Slider(
        value: Binding(get: { Double(value) }, set: { value = snap(Float($0)) }),
        in: Double(range.lowerBound)...Double(range.upperBound)
      ) { editing in
        if !editing { onChangeFinished() }
      }
      .tint(c.accent)
      .sensoryFeedback(.selection, trigger: value)
      StepButton(system: "plus", label: moreLabel, enabled: value < range.upperBound - step / 2) { value = snap(value + step) } done: { onChangeFinished() }
    }
  }
}

/// − or + (Android's `StepButton`): one step as soon as it's touched; held, it repeats after a pause, faster the longer it's held.
private struct StepButton: View {
  var system: String
  var label: String
  var enabled: Bool
  var onStep: () -> Void
  var done: () -> Void
  @Environment(\.tali) private var c
  @State private var repeating: Task<Void, Never>?
  @State private var pressed = false

  var body: some View {
    let icon = Image(systemName: system).font(.system(size: 15, weight: .semibold))
      .foregroundStyle(enabled ? c.accent : c.inkFaint.opacity(0.5))
      .frame(width: 36, height: 36)
    Group {
      if #available(iOS 26.0, *) {
        icon.glassEffect(.regular.interactive(), in: Circle())
      } else {
        icon.background(Circle().fill(c.sunken))
      }
    }
    .scaleEffect(pressed ? 0.9 : 1)
    .animation(.easeOut(duration: pressed ? 0.09 : 0.16), value: pressed)
    .contentShape(Circle())
    .gesture(
      DragGesture(minimumDistance: 0)
        .onChanged { _ in
          guard !pressed, enabled else { return }
          pressed = true
          onStep()
          repeating = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(420))
            var gap = 110.0
            while !Task.isCancelled {
              onStep()
              try? await Task.sleep(for: .milliseconds(Int(gap)))
              gap = max(gap * 0.85, 35)
            }
          }
        }
        .onEnded { _ in
          repeating?.cancel()
          repeating = nil
          guard pressed else { return }
          pressed = false
          done()
        }
    )
    .accessibilityLabel(label)
    .accessibilityAddTraits(.isButton)
    .accessibilityAction {
      guard enabled else { return }
      onStep()
      done()
    }
  }
}
