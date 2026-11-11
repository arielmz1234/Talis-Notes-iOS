import QuartzCore
import SwiftUI

/// What a gliding highlight is painted with: one colour, or colours running left to right across
/// the whole container (Android's horizontal gradient brushes, which span the container).
enum SlideFill: Equatable {
  case color(Color)
  case across([Color])
}

/// One highlight that glides from option to option, instead of each option switching its own
/// background (Android's `SlidingSelection`). Options say where they are with `slidingOption`; the
/// container draws the highlight with `slidingHighlight`. Its edges move on springs, the leading
/// edge stiffer than the trailing one, so it stretches as it travels and settles into the new option.
extension View {
  /// Marks this as the option [key] of the selection [group]. [fill] overrides the container's
  /// highlight for this option (a folder's own colour); the highlight blends between them as it
  /// moves. [clipped] options are cut to the group's `slidingClip` area (a scrolled list).
  func slidingOption(_ key: some Hashable, in group: Namespace.ID, fill: SlideFill? = nil, clipped: Bool = false) -> some View {
    let id = SlideID(group: group, key: key)
    return transformAnchorPreference(key: SlideMap.self, value: .bounds) { $0.options[id] = SlideOption(bounds: $1, fill: fill, clipped: clipped) }
  }

  /// The visible part of a scrolling list of [group]'s options.
  func slidingClip(in group: Namespace.ID) -> some View {
    // Merged with what's inside: setting it outright would drop every option in the list.
    transformAnchorPreference(key: SlideMap.self, value: .bounds) { $0.clips[group] = $1 }
  }

  /// Draws [group]'s highlight under the option [selected], or nothing when it's nil. A [ring] width
  /// draws an outline instead of a fill; [lift] adds a soft shadow under it; [above] draws it over
  /// the options (for swatches that would hide it).
  func slidingHighlight(
    _ group: Namespace.ID, selected: AnyHashable?, fill: SlideFill, corner: CGFloat, ring: CGFloat = 0, lift: Bool = false, above: Bool = false
  ) -> some View {
    modifier(SlidingHighlight(group: group, selected: selected, fill: fill, corner: corner, ring: ring, lift: lift, above: above))
  }
}

private struct SlideID: Hashable {
  let group: Namespace.ID
  let key: AnyHashable
}

private struct SlideOption {
  let bounds: Anchor<CGRect>
  let fill: SlideFill?
  let clipped: Bool
}

private struct SlideMap: PreferenceKey {
  var options: [SlideID: SlideOption] = [:]
  var clips: [Namespace.ID: Anchor<CGRect>] = [:]

  static var defaultValue: SlideMap { SlideMap() }
  static func reduce(value: inout SlideMap, nextValue: () -> SlideMap) {
    let next = nextValue()
    value.options.merge(next.options) { $1 }
    value.clips.merge(next.clips) { $1 }
  }
}

private struct SlidingHighlight: ViewModifier {
  let group: Namespace.ID
  let selected: AnyHashable?
  let fill: SlideFill
  let corner: CGFloat
  let ring: CGFloat
  let lift: Bool
  let above: Bool
  @State private var glide = Glide()
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  func body(content: Content) -> some View {
    if above {
      content.overlayPreferenceValue(SlideMap.self) { map in layer(map) }
    } else {
      content.backgroundPreferenceValue(SlideMap.self) { map in layer(map) }
    }
  }

  private func layer(_ map: SlideMap) -> some View {
    GeometryReader { g in
      let option = selected.flatMap { map.options[SlideID(group: group, key: $0)] }
      let target = option.flatMap { o -> CGRect? in
        var r = g[o.bounds]
        if o.clipped, let clip = map.clips[group] { r = r.intersection(g[clip]) }
        return !r.isNull && r.width > 0 && r.height > 0 ? r : nil
      }
      GlidePaint(glide: glide, corner: corner, ring: ring, lift: lift)
        .onChange(of: GlideTarget(key: selected, rect: target, fill: option?.fill ?? fill), initial: true) { _, t in
          glide.go(t, reduceMotion: reduceMotion)
        }
    }
    .allowsHitTesting(false)
  }
}

private struct GlideTarget: Equatable {
  let key: AnyHashable?
  let rect: CGRect?
  let fill: SlideFill
}

/// Paints the highlight where [glide] has it now.
private struct GlidePaint: View {
  let glide: Glide
  let corner: CGFloat
  let ring: CGFloat
  let lift: Bool

  var body: some View {
    let a = glide.shown
    let edges = glide.edges
    let mix = glide.mix
    let from = glide.from
    let to = glide.to
    Canvas { ctx, size in
      guard a > 0.001 else { return }
      let scale = 0.88 + 0.12 * a
      let w = (edges.r - edges.l) * scale
      let h = (edges.b - edges.t) * scale
      guard w > 0, h > 0 else { return }
      let cx = (edges.l + edges.r) / 2
      let cy = (edges.t + edges.b) / 2
      var rect = CGRect(x: cx - w / 2, y: cy - h / 2, width: w, height: h)
      let radius = min(corner * scale, min(w, h) / 2)
      if lift {
        let shadow = Color(argb: 0xFF26_222E)
        ctx.fill(Path(roundedRect: rect.offsetBy(dx: 0, dy: 1.5), cornerRadius: radius), with: .color(shadow.opacity(0.05 * a)))
        ctx.fill(Path(roundedRect: rect.offsetBy(dx: 0, dy: 0.5), cornerRadius: radius), with: .color(shadow.opacity(0.04 * a)))
      }
      if ring > 0 { rect = rect.insetBy(dx: ring / 2, dy: ring / 2) }
      let shape = Path(roundedRect: rect, cornerRadius: max(radius - ring / 2, 0))
      func paint(_ fill: SlideFill, _ alpha: Double) {
        let shading: GraphicsContext.Shading =
          switch fill {
          case .color(let c): .color(c.opacity(alpha))
          case .across(let cs):
            .linearGradient(Gradient(colors: cs.map { $0.opacity(alpha) }), startPoint: .zero, endPoint: CGPoint(x: size.width, y: 0))
          }
        if ring > 0 { ctx.stroke(shape, with: shading, lineWidth: ring) } else { ctx.fill(shape, with: shading) }
      }
      if let from, mix < 1 { paint(from, a * (1 - mix)) }
      if let to { paint(to, a * mix) }
    }
  }
}

/// The highlight's moving parts: its four edges on springs, how shown it is (popping in from a
/// little smaller), and the blend between two options' own fills.
@MainActor @Observable
private final class Glide {
  struct Edges: Equatable {
    var l: CGFloat = 0, t: CGFloat = 0, r: CGFloat = 0, b: CGFloat = 0
  }

  private(set) var edges = Edges()
  private(set) var shown: Double = 0
  private(set) var mix: Double = 1
  private(set) var from: SlideFill?
  private(set) var to: SlideFill?

  @ObservationIgnored private var key: AnyHashable?
  @ObservationIgnored private var edgeMotion: [Motion] = Array(repeating: Motion(), count: 4)
  @ObservationIgnored private var shownMotion = Motion()
  @ObservationIgnored private var fade: (start: CFTimeInterval, from: Double)?
  @ObservationIgnored private var blend: CFTimeInterval?
  @ObservationIgnored private var link: CADisplayLink?
  @ObservationIgnored private var last: CFTimeInterval = 0

  /// A value riding a spring towards its target.
  struct Motion {
    var target: CGFloat = 0
    var velocity: CGFloat = 0
    var spring: Spring? = nil
    var threshold: CGFloat = 0.25
  }

  // Android's LEAD, TRAIL, EVEN and POP springs (mass 1).
  private static func spring(_ ratio: Double, _ stiffness: Double) -> Spring {
    Spring(mass: 1, stiffness: stiffness, damping: 2 * ratio * stiffness.squareRoot())
  }
  private static let lead = spring(0.8, 750)
  private static let trail = spring(0.86, 330)
  private static let even = spring(0.84, 500)
  private static let pop = spring(0.62, 400)

  func go(_ t: GlideTarget, reduceMotion: Bool) {
    let now = CACurrentMediaTime()
    guard let target = t.rect else {
      // Fade out where it is, so it can come back from there.
      key = nil
      if shown > 0, fade == nil {
        shownMotion.spring = nil
        fade = (now, shown)
        run()
      }
      return
    }
    let sameKey = t.key == key
    let hidden = shown == 0 && fade == nil && shownMotion.spring == nil
    key = t.key
    fade = nil
    if t.fill != to {
      if !hidden && !sameKey && to != nil && !reduceMotion {
        from = to
        mix = 0
        blend = now
      } else {
        from = nil
        mix = 1
        blend = nil
      }
      to = t.fill
    }
    let goal = Edges(l: target.minX, t: target.minY, r: target.maxX, b: target.maxY)
    if hidden || sameKey || reduceMotion {
      // Appearing, or the same option moved (a scroll, a rotation): be there at once.
      edges = goal
      for i in 0..<4 { edgeMotion[i] = Motion(target: value(goal, i)) }
      if reduceMotion { shown = 1; shownMotion = Motion(target: 1) } else if shownMotion.target != 1 || shown < 1 { popIn() }
      run()
      return
    }
    popIn()
    let dx = target.midX - (edges.l + edges.r) / 2
    let dy = target.midY - (edges.t + edges.b) / 2
    // The edge facing the way it moves leads; the other follows a little behind, so it stretches.
    let horizontal = abs(dx) >= abs(dy)
    let springs: [Spring] = [
      horizontal ? (dx < 0 ? Glide.lead : Glide.trail) : Glide.even,
      !horizontal ? (dy < 0 ? Glide.lead : Glide.trail) : Glide.even,
      horizontal ? (dx > 0 ? Glide.lead : Glide.trail) : Glide.even,
      !horizontal ? (dy > 0 ? Glide.lead : Glide.trail) : Glide.even,
    ]
    for i in 0..<4 {
      edgeMotion[i].target = value(goal, i)
      edgeMotion[i].spring = springs[i]
    }
    run()
  }

  private func popIn() {
    shownMotion.target = 1
    shownMotion.threshold = 0.002
    if shownMotion.spring == nil && shown < 1 { shownMotion.spring = Glide.pop }
  }

  private func value(_ e: Edges, _ i: Int) -> CGFloat { [e.l, e.t, e.r, e.b][i] }

  private func run() {
    guard link == nil else { return }
    last = CACurrentMediaTime()
    let proxy = LinkProxy { [weak self] in
      self?.step()
      return self != nil
    }
    let l = CADisplayLink(target: proxy, selector: #selector(LinkProxy.tick(_:)))
    l.add(to: .main, forMode: .common)
    link = l
    step()
  }

  private func step() {
    let now = CACurrentMediaTime()
    let dt = min(max(now - last, 0), 1.0 / 30)
    last = now
    var busy = false
    var e = edges
    for i in 0..<4 {
      guard let s = edgeMotion[i].spring else { continue }
      var v = Double(value(e, i))
      var vel = Double(edgeMotion[i].velocity)
      s.update(value: &v, velocity: &vel, target: Double(edgeMotion[i].target), deltaTime: dt)
      if abs(v - Double(edgeMotion[i].target)) < 0.25 && abs(vel) < 0.25 {
        v = Double(edgeMotion[i].target)
        vel = 0
        edgeMotion[i].spring = nil
      } else {
        busy = true
      }
      edgeMotion[i].velocity = CGFloat(vel)
      switch i {
      case 0: e.l = CGFloat(v)
      case 1: e.t = CGFloat(v)
      case 2: e.r = CGFloat(v)
      default: e.b = CGFloat(v)
      }
    }
    if e != edges { edges = e }
    if let s = shownMotion.spring {
      var v = shown
      var vel = Double(shownMotion.velocity)
      s.update(value: &v, velocity: &vel, target: Double(shownMotion.target), deltaTime: dt)
      if abs(v - Double(shownMotion.target)) < 0.002 && abs(vel) < 0.002 {
        v = Double(shownMotion.target)
        vel = 0
        shownMotion.spring = nil
      } else {
        busy = true
      }
      shownMotion.velocity = CGFloat(vel)
      shown = v
    }
    if let f = fade {
      // Android's tween(150) with its default ease.
      let p = min((now - f.start) / 0.15, 1)
      shown = f.from * (1 - Ease.cubic(0.4, 0, 0.2, 1, p))
      if p >= 1 {
        fade = nil
        shown = 0
      } else {
        busy = true
      }
    }
    if let start = blend {
      let p = min((now - start) / 0.28, 1)
      mix = Ease.cubic(0.4, 0, 0.2, 1, p)
      if p >= 1 {
        blend = nil
        from = nil
      } else {
        busy = true
      }
    }
    if !busy {
      link?.invalidate()
      link = nil
    }
  }
}

/// CADisplayLink holds its target strongly; this keeps it from holding the glide, and stops the
/// link once the glide is gone.
private final class LinkProxy: NSObject {
  let onTick: @MainActor () -> Bool
  init(_ onTick: @escaping @MainActor () -> Bool) { self.onTick = onTick }
  @MainActor @objc func tick(_ link: CADisplayLink) { if !onTick() { link.invalidate() } }
}
