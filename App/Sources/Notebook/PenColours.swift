import SwiftUI
import TaliCore

/// Her saved colours, kept between launches (Android's `savedColors`, and `highlighterColors`
/// for the highlighter's own palette). Views that read them redraw when they change.
@MainActor @Observable
final class Palettes {
  static let shared = Palettes()

  private(set) var saved: [UInt32]
  private(set) var highlighter: [UInt32]
  /// Android's app-wide number of toolbar colours: what a pen shows until it has its own number.
  let toolbarColors = 3

  private init() {
    PenStore.resetForTests()
    saved = Palettes.read("savedColors") ?? PenSlot.defaultColors
    highlighter = Palettes.read("highlighterColors") ?? PenSlot.defaultHighlighterColors
  }

  private static func read(_ key: String) -> [UInt32]? {
    (UserDefaults.standard.array(forKey: key) as? [Int])?.map { UInt32(truncatingIfNeeded: $0) }
  }

  func colors(for pen: PenSlot) -> [UInt32] { pen.type.isHighlighter ? highlighter : saved }

  func toolbarCount(for pen: PenSlot) -> Int { pen.toolbarColors ?? toolbarColors }

  func edit(for pen: PenSlot, _ change: ([UInt32]) -> [UInt32]) {
    if pen.type.isHighlighter {
      highlighter = change(highlighter)
      UserDefaults.standard.set(highlighter.map { Int($0) }, forKey: "highlighterColors")
    } else {
      saved = change(saved)
      UserDefaults.standard.set(saved.map { Int($0) }, forKey: "savedColors")
    }
  }
}

/// Android's `ReorderableColors`: tap a colour to use it; hold one and drag it to a new place (the
/// others make room as it passes); hold one without moving for "Remove colour". A thin line after
/// the first [inToolbar] sets apart the ones beside the pens.
struct ReorderableColors: View {
  var colors: [UInt32]
  var selected: UInt32
  var inToolbar: Int
  var onPick: (UInt32) -> Void
  var onReorder: ([UInt32]) -> Void
  var onRemove: (UInt32) -> Void
  var onAdd: () -> Void

  @Environment(\.tali) private var c
  @State private var width: CGFloat = 0
  /// While dragging, the order shown follows the finger; it's saved when she lets go.
  @State private var order: [UInt32] = []
  @State private var dragging: UInt32?
  @State private var dragAt = CGPoint.zero
  @State private var dragFrom = CGPoint.zero
  @State private var moved = false
  @State private var removeTarget: UInt32?

  private static let dot = CGFloat(SavedColours.Layout.dot)

  var body: some View {
    let shown = dragging == nil ? colors : order
    let layout = SavedColours.Layout(count: shown.count, inToolbar: inToolbar, width: Float(width))
    ZStack(alignment: .topLeading) {
      ForEach(Array(shown.enumerated()), id: \.element) { i, color in
        let lifted = dragging == color
        let home = CGPoint(x: CGFloat(layout.colors[i].x), y: CGFloat(layout.colors[i].y))
        let chosen = color | 0xFF00_0000 == selected | 0xFF00_0000
        ColorDotFace(color: Color(argb: color), selected: chosen)
          .scaleEffect(lifted ? 1.18 : 1)
          .offset(x: lifted ? dragAt.x - Self.dot / 2 : home.x, y: lifted ? dragAt.y - Self.dot / 2 : home.y)
          .zIndex(lifted ? 1 : 0)
          .animation(lifted ? nil : .spring(response: 0.28, dampingFraction: 0.82), value: home)
          .animation(.easeOut(duration: 0.16), value: lifted)
          .onTapGesture { onPick(color) }
          .gesture(holdAndDrag(color, home: home, layout: layout))
          .popover(isPresented: Binding(get: { removeTarget == color }, set: { if !$0 { removeTarget = nil } })) {
            Button(L("remove_colour")) {
              removeTarget = nil
              onRemove(color)
            }
            .buttonStyle(QuietButtonStyle(warning: true))
            .padding(10)
            .presentationCompactAdaptation(.popover)
            .presentationBackground(c.surface)
          }
          .accessibilityAddTraits(chosen ? [.isButton, .isSelected] : .isButton)
          .accessibilityLabel(L("colour"))
          .accessibilityIdentifier(String(format: "colour-%06X", color & 0xFF_FFFF))
      }
      if let at = layout.divider {
        RoundedRectangle(cornerRadius: 1).fill(c.accent.opacity(0.45)).frame(width: 2, height: 24)
          .frame(width: CGFloat(SavedColours.Layout.dividerWidth), height: Self.dot)
          .offset(x: CGFloat(at.x), y: CGFloat(at.y))
      }
      Button(action: onAdd) {
        ZStack {
          Circle().stroke(c.inkFaint, style: StrokeStyle(lineWidth: 1.5, dash: [4, 4])).frame(width: 26, height: 26)
          Image(systemName: "plus").font(.system(size: 14, weight: .semibold)).foregroundStyle(c.inkMuted)
        }
        .frame(width: Self.dot, height: Self.dot)
        .contentShape(Circle())
      }
      .buttonStyle(.plain).contentShape(Rectangle())
      .accessibilityLabel(L("add_a_colour"))
      .offset(x: CGFloat(layout.add.x), y: CGFloat(layout.add.y))
    }
    .frame(maxWidth: .infinity, minHeight: CGFloat(layout.height), maxHeight: CGFloat(layout.height), alignment: .topLeading)
    .background(GeometryReader { g in Color.clear.onAppear { width = g.size.width }.onChange(of: g.size.width) { _, w in width = w } })
    .coordinateSpace(name: "colours")
  }

  private func holdAndDrag(_ color: UInt32, home: CGPoint, layout: SavedColours.Layout) -> some Gesture {
    LongPressGesture(minimumDuration: 0.4)
      .sequenced(before: DragGesture(minimumDistance: 0, coordinateSpace: .named("colours")))
      .onChanged { value in
        guard case .second(true, let drag) = value else { return }
        if dragging == nil {
          order = colors
          dragging = color
          moved = false
          dragFrom = CGPoint(x: home.x + Self.dot / 2, y: home.y + Self.dot / 2)
          dragAt = dragFrom
          UIImpactFeedbackGenerator(style: .light).impactOccurred()
        }
        guard let drag else { return }
        dragAt = CGPoint(x: dragFrom.x + drag.translation.width, y: dragFrom.y + drag.translation.height)
        moved = moved || hypot(drag.translation.width, drag.translation.height) > 2
        let centres = order.indices.map { CGPoint(x: CGFloat(layout.colors[$0].x) + Self.dot / 2, y: CGFloat(layout.colors[$0].y) + Self.dot / 2) }
        if let over = order.indices.min(by: { hypot(centres[$0].x - dragAt.x, centres[$0].y - dragAt.y) < hypot(centres[$1].x - dragAt.x, centres[$1].y - dragAt.y) }),
          order[over] != color, hypot(centres[over].x - dragAt.x, centres[over].y - dragAt.y) < 24
        {
          order = SavedColours.moving(color, onto: order[over], in: order)
        }
      }
      .onEnded { _ in
        guard dragging == color else { return }
        dragging = nil
        if moved { onReorder(order) } else { removeTarget = color }
      }
  }
}

struct ColorDotFace: View {
  var color: Color
  var selected: Bool
  var size: CGFloat = 30
  @Environment(\.tali) private var c

  var body: some View {
    Circle().fill(color).overlay(Circle().stroke(Color.black.opacity(0.13), lineWidth: 1))
      .frame(width: size, height: size)
      .padding(4)
      .overlay(Circle().stroke(c.accent, lineWidth: 2).opacity(selected ? 1 : 0))
      .animation(.spring(response: 0.25, dampingFraction: 0.8), value: selected)
      .contentShape(Circle())
  }
}

/// Android's `ColorPicker`: a saturation and brightness square plus a hue strip. [onChange] fires
/// as she drags; [onSave] adds the colour to her palette.
struct ColourPicker: View {
  var onChange: (UInt32) -> Void
  var onSave: (UInt32) -> Void
  @State private var hue: Double
  @State private var saturation: Double
  @State private var brightness: Double
  @Environment(\.tali) private var c

  init(initial: UInt32, onChange: @escaping (UInt32) -> Void, onSave: @escaping (UInt32) -> Void) {
    self.onChange = onChange
    self.onSave = onSave
    var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
    UIColor(argb: Int32(bitPattern: initial | 0xFF00_0000)).getHue(&h, saturation: &s, brightness: &b, alpha: &a)
    _hue = State(initialValue: Double(h))
    _saturation = State(initialValue: Double(s))
    _brightness = State(initialValue: Double(b))
  }

  private var current: UInt32 {
    UInt32(bitPattern: UIColor(hue: hue, saturation: saturation, brightness: brightness, alpha: 1).argb)
  }

  var body: some View {
    VStack(spacing: 0) {
      GeometryReader { g in
        ZStack(alignment: .topLeading) {
          Color(hue: hue, saturation: 1, brightness: 1)
          LinearGradient(colors: [.white, .white.opacity(0)], startPoint: .leading, endPoint: .trailing)
          LinearGradient(colors: [.black.opacity(0), .black], startPoint: .top, endPoint: .bottom)
        }
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(alignment: .topLeading) {
          Circle().stroke(Color.white, lineWidth: 2.5).frame(width: 18, height: 18)
            .overlay(Circle().stroke(Color.black.opacity(0.33), lineWidth: 1).frame(width: 21, height: 21))
            .offset(x: saturation * g.size.width - 9, y: (1 - brightness) * g.size.height - 9)
        }
        .contentShape(Rectangle())
        .accessibilityElement()
        .accessibilityLabel(L("colour"))
        .accessibilityIdentifier("colour-square")
        .gesture(
          DragGesture(minimumDistance: 0).onChanged { v in
            saturation = min(max(v.location.x / g.size.width, 0), 1)
            brightness = 1 - min(max(v.location.y / g.size.height, 0), 1)
            onChange(current)
          })
      }
      .frame(height: 150)
      Spacer().frame(height: 12)
      GeometryReader { g in
        LinearGradient(colors: stride(from: 0.0, through: 1.0, by: 1.0 / 6).map { Color(hue: $0, saturation: 1, brightness: 1) }, startPoint: .leading, endPoint: .trailing)
          .clipShape(Capsule())
          .overlay(alignment: .leading) {
            let r = g.size.height / 2 + 1
            Circle().stroke(Color.white, lineWidth: 3).frame(width: r * 2, height: r * 2)
              .offset(x: min(max(hue * g.size.width, g.size.height / 2), g.size.width - g.size.height / 2) - r)
          }
          .contentShape(Rectangle())
          .gesture(
            DragGesture(minimumDistance: 0).onChanged { v in
              hue = min(max(v.location.x / g.size.width, 0), 1)
              onChange(current)
            })
      }
      .frame(height: 22)
      Spacer().frame(height: 14)
      HStack(spacing: 12) {
        Circle().fill(Color(argb: current)).overlay(Circle().stroke(c.line, lineWidth: 1)).frame(width: 34, height: 34)
        Text(String(format: "#%06X", current & 0xFF_FFFF)).font(TaliType.titleSmall).foregroundStyle(c.inkMuted)
        Spacer()
        Button(L("save_colour")) { onSave(current) }.buttonStyle(PrimaryButtonStyle())
      }
    }
  }
}
