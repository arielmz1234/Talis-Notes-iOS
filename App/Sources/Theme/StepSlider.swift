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

/// − or +: one step per tap; held, it repeats, faster the longer it's held.
private struct StepButton: View {
  var system: String
  var label: String
  var enabled: Bool
  var onStep: () -> Void
  var done: () -> Void
  @Environment(\.tali) private var c
  @State private var repeating: Task<Void, Never>?

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
    .contentShape(Circle())
    .onTapGesture {
      guard enabled else { return }
      onStep()
      done()
    }
    .onLongPressGesture(minimumDuration: 0.35, maximumDistance: 30) {
      // Held: keep stepping until let go (the press ends the task).
    } onPressingChanged: { pressing in
      repeating?.cancel()
      guard pressing, enabled else {
        if !pressing { done() }
        return
      }
      repeating = Task { @MainActor in
        try? await Task.sleep(for: .milliseconds(400))
        var delay = 140
        while !Task.isCancelled {
          onStep()
          try? await Task.sleep(for: .milliseconds(delay))
          delay = max(delay - 12, 40)
        }
      }
    }
    .accessibilityLabel(label)
    .accessibilityAddTraits(.isButton)
  }
}
