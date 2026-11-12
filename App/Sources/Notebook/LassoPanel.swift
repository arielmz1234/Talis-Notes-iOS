import SwiftUI
import TaliCore

/// How the lasso picks things up, app-wide, under the names Android's `AppSettings` uses. Views
/// watch the same keys with `@AppStorage`; the canvas reads them here when it needs them.
@MainActor
enum LassoSettings {
  enum Key {
    static let free = "lassoFree"
    static let shot = "lassoShot"
    static let locked = "lassoLocked"
    static let images = "lassoSelectsImages"
    /// The pens the lasso leaves alone, by name, comma-separated (Android's `lassoAffects` set to false).
    static let leaves = "lassoLeaves"
  }

  private static var store: UserDefaults { .standard }

  /// Free form: trace over or touch things, instead of circling them.
  static var free: Bool { store.bool(forKey: Key.free) }
  /// The lasso takes a picture of the rectangle around what's drawn, instead of picking it up.
  static var shot: Bool { store.bool(forKey: Key.shot) }
  /// The lasso picks locked things up too (to move them or unlock them).
  static var pickLocked: Bool { store.bool(forKey: Key.locked) }
  static var snapShapes: Bool { store.object(forKey: ShapeSettings.Key.snapShapes) as? Bool ?? true }

  static func left(_ list: String) -> Set<String> { Set(list.split(separator: ",").map(String.init)) }

  /// Whether the lasso picks up something made with [pen]; pictures and text (no pen) follow Images.
  static func hits(_ pen: PenType?) -> Bool {
    guard let pen else { return store.object(forKey: Key.images) as? Bool ?? true }
    return !left(store.string(forKey: Key.leaves) ?? "").contains(pen.rawValue)
  }
}

/// The lasso's settings (Android's `LassoPanel`, titled Select): the classic loop or free form, the
/// screenshot lasso, what it picks up, and whether locked things come too.
struct LassoPanel: View {
  @AppStorage(LassoSettings.Key.free) private var free = false
  @AppStorage(LassoSettings.Key.shot) private var shot = false
  @AppStorage(LassoSettings.Key.locked) private var pickLocked = false
  @AppStorage(LassoSettings.Key.images) private var images = true
  @AppStorage(LassoSettings.Key.leaves) private var leaves = ""
  @Environment(\.tali) private var c

  var body: some View {
    ScrollingPanel(width: 340) {
      VStack(alignment: .leading, spacing: 0) {
        Text(L("select")).font(TaliType.titleLarge).foregroundStyle(c.ink)
        Spacer().frame(height: 14)
        Segmented(options: [false, true], selected: $free) { $0 ? L("free_form") : L("lasso") }
        Spacer().frame(height: 10)
        Text(shot ? L("draw_around_anything_to_take_a") : free ? L("trace_over_or_touch_anything_to") : L("circle_anything_to_move_resize_recolour"))
          .font(TaliType.bodyMedium).foregroundStyle(c.inkMuted).fixedSize(horizontal: false, vertical: true)
        Spacer().frame(height: 6)
        ToggleRow(label: L("screenshot"), on: $shot, detail: L("the_lasso_takes_a_picture_of")).accessibilityIdentifier("lasso-screenshot")
        Spacer().frame(height: 14)
        SectionLabel(text: L("picks_up"))
        Spacer().frame(height: 8)
        FlowChips {
          ForEach(PenType.offered, id: \.self) { type in
            PickChip(label: penName(type), on: !LassoSettings.left(leaves).contains(type.rawValue)) { on in
              var left = LassoSettings.left(leaves)
              if on { left.remove(type.rawValue) } else { left.insert(type.rawValue) }
              leaves = PenType.offered.map(\.rawValue).filter(left.contains).joined(separator: ",")
            }
          }
          PickChip(label: L("images"), on: images) { images = $0 }
        }
        Spacer().frame(height: 10)
        ToggleRow(label: L("pick_up_locked_items"), on: $pickLocked, detail: L("to_move_them_or_unlock_them")).accessibilityIdentifier("lasso-locked")
      }
    }
  }
}

/// A compact on/off chip (Android's `FilterChip`): blue with a tick when on, a quiet outline when off.
struct PickChip: View {
  var label: String
  var on: Bool
  var onChange: (Bool) -> Void
  @Environment(\.tali) private var c

  var body: some View {
    Button {
      onChange(!on)
    } label: {
      HStack(spacing: 4) {
        if on { Image(systemName: "checkmark").font(.system(size: 12, weight: .semibold)).foregroundStyle(c.blue) }
        Text(label).font(TaliType.labelLarge).foregroundStyle(on ? c.blue : c.inkMuted)
      }
      .padding(.leading, on ? 8 : 12).padding(.trailing, 12).padding(.vertical, 7)
      .background(RoundedRectangle(cornerRadius: 12).fill(on ? c.blueSoft : .clear))
      .overlay(RoundedRectangle(cornerRadius: 12).stroke(on ? c.sky : c.line, lineWidth: 1))
      .contentShape(Rectangle())
      .animation(.easeOut(duration: 0.2), value: on)
    }
    .buttonStyle(.plain)
    .accessibilityAddTraits(on ? .isSelected : [])
  }
}

/// Chips in rows, wrapping where they don't fit (Android's `FlowRow`, 8 apart).
struct FlowChips: SwiftUI.Layout {
  var spacing: CGFloat = 8

  func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
    let rows = place(subviews, width: proposal.width ?? .infinity)
    return CGSize(width: proposal.width ?? rows.width, height: rows.height)
  }

  func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
    for (i, at) in place(subviews, width: bounds.width).spots.enumerated() {
      subviews[i].place(at: CGPoint(x: bounds.minX + at.x, y: bounds.minY + at.y), proposal: .unspecified)
    }
  }

  private func place(_ subviews: Subviews, width: CGFloat) -> (spots: [CGPoint], width: CGFloat, height: CGFloat) {
    var spots: [CGPoint] = []
    var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0, widest: CGFloat = 0
    for view in subviews {
      let size = view.sizeThatFits(.unspecified)
      if x > 0, x + size.width > width {
        x = 0
        y += rowHeight + spacing
        rowHeight = 0
      }
      spots.append(CGPoint(x: x, y: y))
      x += size.width + spacing
      rowHeight = max(rowHeight, size.height)
      widest = max(widest, x - spacing)
    }
    return (spots, widest, y + rowHeight)
  }
}

/// The lasso's icons drawn as Android's `TaliIcons` draws them, in a 24-unit box: the lasso dotted
/// with its tail, free form as a dotted circle, and the two mirrors.
struct SelectIcon: View {
  enum Kind { case lasso, freeForm, mirrorLeftRight, mirrorUpsideDown }
  var kind: Kind
  var color: Color
  var size: CGFloat = 24

  var body: some View {
    Canvas { ctx, canvasSize in
      let k = canvasSize.width / 24
      func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x * k, y: y * k) }
      let line = StrokeStyle(lineWidth: 1.8 * k, lineCap: .round, lineJoin: .round)
      func dotted(_ cx: CGFloat, _ cy: CGFloat, _ rx: CGFloat, _ ry: CGFloat, dashes: Int, start: CGFloat = 0) -> Path {
        var p = Path()
        let step = 2 * CGFloat.pi / CGFloat(dashes)
        for i in 0..<dashes {
          let t0 = start + CGFloat(i) * step
          let pts = (0...2).map { t0 + step * 0.42 * CGFloat($0) / 2 }.map { pt(cx + rx * cos($0), cy + ry * sin($0)) }
          p.move(to: pts[0])
          p.addLine(to: pts[1])
          p.addLine(to: pts[2])
        }
        return p
      }
      func wedge(_ points: [(CGFloat, CGFloat)]) -> Path {
        var p = Path()
        p.addLines(points.map { pt($0.0, $0.1) })
        p.closeSubpath()
        return p
      }
      switch kind {
      case .lasso:
        var tail = Path()
        tail.move(to: pt(8.2, 14.2))
        tail.addCurve(to: pt(8.8, 17.5), control1: pt(6.9, 15.4), control2: pt(7.2, 17.1))
        tail.addCurve(to: pt(9.4, 20.4), control1: pt(10.2, 17.9), control2: pt(10.4, 19.2))
        ctx.stroke(dotted(12, 9.3, 8.2, 5.5, dashes: 12), with: .color(color), style: line)
        ctx.stroke(tail, with: .color(color), style: line)
      case .freeForm:
        ctx.stroke(dotted(12, 12, 8.4, 8.4, dashes: 12, start: 0.13), with: .color(color), style: line)
      case .mirrorLeftRight, .mirrorUpsideDown:
        // A wedge filled on one side of a gap, its reflection outlined on the other.
        let filled: [(CGFloat, CGFloat)] = [(10.4, 4.6), (10.4, 19.4), (4.2, 16.6), (5.6, 7.2)]
        let outlined: [(CGFloat, CGFloat)] = [(13.6, 4.6), (13.6, 19.4), (19.8, 16.6), (18.4, 7.2)]
        let turn: ((CGFloat, CGFloat)) -> (CGFloat, CGFloat) = { self.kind == .mirrorUpsideDown ? ($0.1, $0.0) : $0 }
        let thin = StrokeStyle(lineWidth: 1.6 * k, lineCap: .round, lineJoin: .round)
        ctx.fill(wedge(filled.map(turn)), with: .color(color))
        ctx.stroke(wedge(filled.map(turn)), with: .color(color), style: thin)
        ctx.stroke(wedge(outlined.map(turn)), with: .color(color), style: thin)
      }
    }
    .frame(width: size, height: size)
  }
}
