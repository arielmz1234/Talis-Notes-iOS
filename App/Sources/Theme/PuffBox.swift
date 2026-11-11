import SwiftUI

/// Plays the mist of things being deleted above everything inside a `puffLayerHost`, so it's never
/// cut off by the list, grid or sidebar the thing was in (Android's `PuffLayer`).
@MainActor @Observable
final class PuffLayer {
  struct Puff: Identifiable {
    let id = UUID()
    let rect: CGRect
    let start: Date
  }

  private(set) var puffs: [Puff] = []

  /// A deletion puff over [rect], in screen coordinates.
  func play(_ rect: CGRect) {
    let puff = Puff(rect: rect, start: .now)
    puffs.append(puff)
    DispatchQueue.main.asyncAfter(deadline: .now() + PuffTiming.leave) { [weak self] in self?.puffs.removeAll { $0.id == puff.id } }
  }
}

extension EnvironmentValues {
  @Entry var puffLayer: PuffLayer? = nil
}

extension View {
  /// Deletion puffs of `puffBox`es inside are drawn over all of this, unclipped.
  func puffLayerHost() -> some View { modifier(PuffLayerHost()) }

  /// Lets this come and go on a cloud (Android's `PuffBox`): [leaving] dissolves it into a puff of
  /// mist (the caller removes it `PuffTiming.leave` later); [appearing] lets it settle in as a
  /// lighter puff dissipates around it.
  func puffBox(leaving: Bool, appearing: Bool = false) -> some View { modifier(PuffBox(leaving: leaving, appearing: appearing)) }
}

private struct PuffLayerHost: ViewModifier {
  @State private var layer = PuffLayer()

  func body(content: Content) -> some View {
    content
      .environment(\.puffLayer, layer)
      .overlay {
        GeometryReader { g in
          let origin = g.frame(in: .global).origin
          ForEach(layer.puffs) { p in
            PuffPlayer(start: p.start, duration: PuffTiming.leave, vivid: true)
              .frame(width: p.rect.width, height: p.rect.height)
              .position(x: p.rect.midX - origin.x, y: p.rect.midY - origin.y)
          }
        }
        .environment(\.layoutDirection, .leftToRight)
        .allowsHitTesting(false)
        .ignoresSafeArea()
      }
  }
}

/// Where a puff box was last laid out, kept without redrawing anything.
@MainActor private final class FrameBox {
  var rect: CGRect?
}

private struct PuffBox: ViewModifier {
  var leaving: Bool
  var appearing: Bool
  @Environment(\.puffLayer) private var layer
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var leave: CGFloat = 0
  @State private var arrive: CGFloat
  @State private var localPuff: (start: Date, duration: Double, strength: Double, vivid: Bool)?
  @State private var frame = FrameBox()

  init(leaving: Bool, appearing: Bool) {
    self.leaving = leaving
    self.appearing = appearing
    _arrive = State(initialValue: appearing ? 0 : 1)
  }

  func body(content: Content) -> some View {
    let gone = max(leave, 1 - arrive)
    let motion: CGFloat = reduceMotion ? 0 : 1
    content
      // Out: lift a little and shrink into the mist as it fades and blurs. In: the same, backwards.
      .scaleEffect(1 - 0.07 * gone * motion)
      .offset(y: -10 * leave * motion)
      .blur(radius: 6 * gone * motion)
      .opacity(1 - gone)
      .background {
        GeometryReader { g in
          Color.clear
            .onAppear { frame.rect = g.frame(in: .global) }
            .onChange(of: g.frame(in: .global)) { _, r in frame.rect = r }
        }
      }
      .overlay {
        if let p = localPuff {
          PuffPlayer(start: p.start, duration: p.duration, strength: p.strength, vivid: p.vivid)
        }
      }
      // While it leaves it sits above its neighbours, so the mist drifting over them isn't cut off.
      .zIndex(leaving ? 1 : 0)
      .onChange(of: leaving) { _, now in
        guard now else {
          leave = 0
          return
        }
        if !reduceMotion {
          if let layer, let r = frame.rect { layer.play(r) } else { play(PuffTiming.leave, strength: 1, vivid: true) }
        }
        withAnimation(.timingCurve(0.23, 1, 0.32, 1, duration: 0.22)) { leave = 1 }
      }
      .onAppear {
        guard appearing, arrive < 1 else { return }
        if !reduceMotion { play(0.52, strength: 0.55, vivid: false) }
        withAnimation(.timingCurve(0.23, 1, 0.32, 1, duration: 0.26).delay(0.04)) { arrive = 1 }
      }
  }

  private func play(_ duration: Double, strength: Double, vivid: Bool) {
    let start = Date.now
    localPuff = (start, duration, strength, vivid)
    DispatchQueue.main.asyncAfter(deadline: .now() + duration) {
      if localPuff?.start == start { localPuff = nil }
    }
  }
}
