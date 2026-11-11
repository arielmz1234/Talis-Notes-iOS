import SwiftUI
import TaliCore

/// A shape kind drawn small (Android's `ShapeIcon`): built on a 66-unit grid and scaled, so
/// arrowheads are the same share of the tile at any size.
struct ShapeIcon: View {
  var kind: ShapeKind
  var color: Color
  var size: CGFloat = 26

  var body: some View {
    Canvas { ctx, sz in
      let grid: Float = 66, pad: Float = 8
      let mid = Pt(grid / 2, grid / 2), r = grid / 2 - pad
      let g: ShapeGeometry
      switch kind {
      // Drawn from their centre, so their icons are built round the tile's middle.
      case .CIRCLE: g = .ellipse(center: mid, rx: r, ry: r, rotation: 0)
      case .PART_CIRCLE: g = .sector(center: mid, radius: r, start: .pi / 4, sweep: 1.5 * .pi)
      case .ELLIPSE: g = kind.inBox(Pt(pad, pad + 14), Pt(grid - pad, grid - pad - 14))
      default: g = kind.inBox(Pt(pad, pad), Pt(grid - pad, grid - pad))
      }
      let k = sz.width / CGFloat(grid)
      var path = Path()
      for line in g.paths(2.6) where line.count > 1 {
        path.move(to: CGPoint(x: CGFloat(line[0].x) * k, y: CGFloat(line[0].y) * k))
        for p in line.dropFirst() { path.addLine(to: CGPoint(x: CGFloat(p.x) * k, y: CGFloat(p.y) * k)) }
      }
      ctx.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round))
    }
    .frame(width: size, height: size)
  }
}

/// Any shape drawn small, fitted to the square (Android's `GeometryIcon`): a subject's shape or one of hers.
struct GeometryIcon: View {
  var geometry: ShapeGeometry
  var color: Color
  var size: CGFloat = 30

  var body: some View {
    Canvas { ctx, sz in
      let s = sz.width, m = s * 0.12
      let paths = geometry.paths(CustomShape.referencePen)
      guard let box = Rect.around(paths.joined()) else { return }
      let k = (s - 2 * m) / CGFloat(max(box.width, box.height, 1))
      let ox = (s - CGFloat(box.width) * k) / 2 - CGFloat(box.left) * k
      let oy = (s - CGFloat(box.height) * k) / 2 - CGFloat(box.top) * k
      var path = Path()
      for line in paths where line.count > 1 {
        path.addLines(line.map { CGPoint(x: ox + CGFloat($0.x) * k, y: oy + CGFloat($0.y) * k) })
      }
      ctx.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: s * 0.055, lineCap: .round, lineJoin: .round))
    }
    .frame(width: size, height: size)
  }
}

/// What the Shapes tool is set to draw, as an icon (the toolbar's button while the tool is on).
struct ShapeChoiceIcon: View {
  var source: ShapeSource
  var color: Color
  var size: CGFloat

  var body: some View {
    switch source {
    case .kind(let k): ShapeIcon(kind: k, color: color, size: size)
    case .pack(let s): GeometryIcon(geometry: s.icon, color: color, size: size)
    case .custom(let s): GeometryIcon(geometry: s.geometry, color: color, size: size)
    }
  }
}

/// The name of a shape kind in the app's language (Android's `ShapeKind.nameRes`).
func shapeName(_ k: ShapeKind) -> String { L("shape_" + k.rawValue.lowercased()) }

/// Choosing what the Shapes tool draws (Android's `pickShape`, `pickPackShape`, `pickCustomShape`):
/// the choice is kept as Android keeps it, and choosing switches to the tool and closes its panel.
@MainActor
struct ShapePicker {
  @Binding var stored: String
  /// The standard shape last chosen: what's drawn again when a saved shape in use is deleted.
  @Binding var kind: ShapeKind
  var toolOn: Bool
  var onPicked: () -> Void

  var choice: ShapeChoice { ShapeChoice(stored: stored) }

  func pick(_ k: ShapeKind) {
    kind = k
    stored = ShapeChoice.kind(k).stored
    onPicked()
  }

  /// A subject's shape: one of the built-in kinds (the civil engineering symbols) or a design of its own.
  func pick(_ shape: PackShape) {
    if let k = shape.kind { return pick(k) }
    stored = ShapeChoice.pack(shape.id).stored
    onPicked()
  }

  func pick(_ shape: CustomShape) {
    stored = ShapeChoice.custom(shape.id).stored
    onPicked()
  }

  func lit(_ k: ShapeKind) -> Bool { toolOn && choice == .kind(k) }
  func lit(_ shape: PackShape) -> Bool { toolOn && (shape.kind.map { choice == .kind($0) } ?? (choice == .pack(shape.id))) }
  func lit(_ shape: CustomShape) -> Bool { toolOn && choice == .custom(shape.id) }
}

/// Whether the Shapes panel shows its Style tab, kept while the app is open (as on Android).
@MainActor
private enum ShapesPanelTab {
  static var styling = false
}

/// The Shapes tool's panel (Android's `ShapesPanel`): two tabs, the shapes to draw and how they're
/// drawn. Choose shows the standard shapes, then the subjects she starred, then hers; every subject
/// is under More shapes.
struct ShapesPanel: View {
  var picker: ShapePicker
  /// The pen the tool follows when its style is Like the pen.
  var pen: PenSlot
  /// A narrow screen: the Style tab's two columns go one under the other.
  var compact = false
  var onBrowse: () -> Void
  @Environment(\.tali) private var c
  @State private var styling = ShapesPanelTab.styling
  @AppStorage(ShapeSettings.Key.starredPacks) private var starredList = ""
  @AppStorage(ShapeSettings.Key.customShapes) private var customJSON = "[]"

  var body: some View {
    ScrollingPanel(width: 588) {
      HStack {
        Text(L("shapes")).font(TaliType.titleLarge).foregroundStyle(c.ink)
        Spacer(minLength: 12)
        Segmented(options: [false, true], selected: $styling) { $0 ? L("style") : L("choose") }
          .frame(width: 220)
          .accessibilityIdentifier("shapes-tabs")
      }
      Spacer().frame(height: 4)
      if styling {
        ShapeStylePicker(pen: pen, compact: compact)
      } else {
        choose
      }
    }
    .onChange(of: styling) { _, v in ShapesPanelTab.styling = v }
  }

  @ViewBuilder private var choose: some View {
    let starred = ShapeSettings.starred(from: starredList)
    Spacer().frame(height: 12)
    SectionLabel(text: L("shape_group_basic"))
    Spacer().frame(height: 8)
    ShapeTileGrid {
      ForEach(ShapeKind.offered.filter { !$0.engineering }, id: \.self) { k in
        ShapeTile(label: shapeName(k), on: picker.lit(k), id: "shape-\(k.rawValue)", action: { picker.pick(k) }) { ShapeIcon(kind: k, color: $0, size: 30) }
      }
    }
    ForEach(ShapePacks.all.filter { starred.contains($0.id) }) { pack in
      Spacer().frame(height: 12)
      HStack(spacing: 0) {
        SectionLabel(text: subjectName(pack))
        StarToggle(on: true, label: L("take_n_out_of_the_shapes", subjectName(pack))) {
          starredList = ShapeSettings.list(of: starred.subtracting([pack.id]))
        }
      }
      PackTiles(pack: pack, picker: picker)
    }
    if picker.choice == .kind(.PART_CIRCLE) {
      Spacer().frame(height: 10)
      Text(L("part_circle_drag_from_the_centre")).font(TaliType.bodySmall).foregroundStyle(c.inkMuted)
    }
    MyShapes(picker: picker, json: $customJSON)
    Spacer().frame(height: 14)
    Button(action: onBrowse) {
      HStack(spacing: 12) {
        Image(systemName: "square.on.circle").font(.system(size: 19)).foregroundStyle(c.accent).frame(width: 22)
        VStack(alignment: .leading, spacing: 0) {
          Text(L("more_shapes")).font(TaliType.titleSmall).foregroundStyle(c.ink)
          Text(L("shapes_for_each_subject_engineering_law")).font(TaliType.bodySmall).foregroundStyle(c.inkMuted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        Image(systemName: "chevron.right").font(.system(size: 15, weight: .semibold)).foregroundStyle(c.accent)
      }
      .padding(.horizontal, 14).padding(.vertical, 12)
      .background(RoundedRectangle(cornerRadius: 14).fill(c.accentSoft.opacity(0.6)))
    }
    .buttonStyle(PressStyle(scale: 0.98))
    .accessibilityIdentifier("more-shapes")
  }
}

/// A subject's shapes as tiles; the one the Shapes tool is drawing is lit.
struct PackTiles: View {
  var pack: ShapePack
  var picker: ShapePicker

  var body: some View {
    Spacer().frame(height: 8)
    ShapeTileGrid {
      ForEach(pack.shapes) { shape in
        ShapeTile(label: subjectShapeName(shape), on: picker.lit(shape), id: "pack-\(shape.id)", action: { picker.pick(shape) }) { tint in
          if let kind = shape.kind { ShapeIcon(kind: kind, color: tint, size: 30) } else { GeometryIcon(geometry: shape.icon, color: tint) }
        }
      }
    }
  }
}

/// Her own saved shapes: pick one to draw it, press and hold for rename and delete.
private struct MyShapes: View {
  var picker: ShapePicker
  @Binding var json: String
  @Environment(\.tali) private var c
  @State private var renaming: CustomShape?
  @State private var deleting: CustomShape?

  var body: some View {
    let shapes = ShapeSettings.shapes(from: json)
    Spacer().frame(height: 12)
    SectionLabel(text: L("my_shapes"))
    Spacer().frame(height: 8)
    if shapes.isEmpty {
      HStack(spacing: 10) {
        Image(systemName: "sparkles").font(.system(size: 17)).foregroundStyle(c.blue).frame(width: 20)
        Text(L("draw_a_shape_you_use_a")).font(TaliType.bodySmall).foregroundStyle(c.inkMuted).frame(maxWidth: .infinity, alignment: .leading)
      }
      .padding(.horizontal, 14).padding(.vertical, 12)
      .background(RoundedRectangle(cornerRadius: 14).fill(c.blueSoft.opacity(0.55)))
    } else {
      ShapeTileGrid {
        ForEach(shapes) { shape in
          ShapeTile(label: shape.name, on: picker.lit(shape), id: "custom-\(shape.name)", action: { picker.pick(shape) }) { GeometryIcon(geometry: shape.geometry, color: $0) }
            .contextMenu {
              Button { renaming = shape } label: { Label(L("rename"), systemImage: "pencil") }
              Button(role: .destructive) { deleting = shape } label: { Label(L("delete"), systemImage: "trash") }
            }
        }
      }
      Spacer().frame(height: 6)
      Text(L("press_and_hold_a_shape_to")).font(TaliType.bodySmall).foregroundStyle(c.inkFaint)
        .alert(L("rename_shape"), isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } }), presenting: renaming) { shape in
          RenameField(initial: shape.name) { name in rename(shape, to: name) }
        }
        .confirmationDialog(
          deleting.map { L("delete_n", $0.name) } ?? "", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
          titleVisibility: .visible, presenting: deleting
        ) { shape in
          Button(L("delete"), role: .destructive) { delete(shape) }
        } message: { _ in
          Text(L("it_will_no_longer_be_offered"))
        }
    }
  }

  private func rename(_ shape: CustomShape, to name: String) {
    let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !name.isEmpty else { return }
    json = ShapeSettings.json(of: ShapeSettings.shapes(from: json).map { $0.id == shape.id ? CustomShape(id: $0.id, name: name, geometry: $0.geometry) : $0 })
  }

  private func delete(_ shape: CustomShape) {
    if picker.choice == .custom(shape.id) { picker.stored = ShapeChoice.kind(picker.kind).stored }
    json = ShapeSettings.json(of: ShapeSettings.shapes(from: json).filter { $0.id != shape.id })
  }
}

/// Tiles in rows, six across the panel and fewer on a phone, each as wide as its share.
struct ShapeTileGrid<Content: View>: View {
  @ViewBuilder var content: Content

  var body: some View {
    LazyVGrid(columns: [GridItem(.adaptive(minimum: 93), spacing: 6)], spacing: 6) { content }
  }
}

/// One shape to pick (Android's `ShapeTile`): its icon over its name, in soft blue while it's the one drawn.
struct ShapeTile<Icon: View>: View {
  var label: String
  var on: Bool
  var id: String
  var action: () -> Void
  @ViewBuilder var icon: (Color) -> Icon
  @Environment(\.tali) private var c

  var body: some View {
    Button(action: action) {
      VStack(spacing: 4) {
        icon(on ? c.blue : c.ink)
        Text(label).font(TaliType.labelSmall).foregroundStyle(on ? c.blue : c.inkMuted).lineLimit(1).padding(.horizontal, 2)
      }
      .padding(.vertical, 8)
      .frame(maxWidth: .infinity)
      .background(RoundedRectangle(cornerRadius: 14).fill(on ? c.blueSoft : c.background))
      .contentShape(RoundedRectangle(cornerRadius: 14))
      .animation(.easeOut(duration: 0.22), value: on)
    }
    .buttonStyle(PressStyle(scale: 0.95))
    .accessibilityLabel(label)
    .accessibilityAddTraits(on ? .isSelected : [])
    .accessibilityIdentifier(id)
  }
}

/// A star that keeps something close at hand (Android's `StarToggle`): gold when on, with a little pop.
struct StarToggle: View {
  var on: Bool
  var label: String
  var action: () -> Void
  @Environment(\.tali) private var c

  var body: some View {
    Button(action: action) {
      Image(systemName: on ? "star.fill" : "star").font(.system(size: 20)).foregroundStyle(on ? starGold : c.inkFaint)
        .symbolEffect(.bounce, value: on)
        .frame(width: 40, height: 40).contentShape(Circle())
    }
    .buttonStyle(.plain)
    .accessibilityLabel(label)
    .accessibilityAddTraits(on ? .isSelected : [])
  }
}

/// How tall a tool panel's contents may be: the room between the toolbar and the chips at the bottom.
private struct PanelRoomKey: EnvironmentKey {
  static let defaultValue: CGFloat = 640
}

extension EnvironmentValues {
  var panelRoom: CGFloat {
    get { self[PanelRoomKey.self] }
    set { self[PanelRoomKey.self] = newValue }
  }
}

/// A tool panel that's never taller than the room under the toolbar: it scrolls when it has more
/// (Android's `PanelColumn`), with a soft fade at the bottom to say so.
struct ScrollingPanel<Content: View>: View {
  var width: CGFloat
  @ViewBuilder var content: Content
  @Environment(\.panelRoom) private var room
  @State private var height: CGFloat = 0

  var body: some View {
    let limit = min(max(room, 200), 640)
    ToolPanel(width: width) {
      ScrollView {
        VStack(alignment: .leading, spacing: 0) { content }
          .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height = $0 }
      }
      .scrollIndicators(.hidden)
      .scrollBounceBehavior(.basedOnSize)
      .frame(height: min(height, limit))
      .mask {
        if height > limit {
          LinearGradient(stops: [.init(color: .black, location: 0), .init(color: .black, location: 0.94), .init(color: .clear, location: 1)], startPoint: .top, endPoint: .bottom)
        } else {
          Rectangle()
        }
      }
    }
  }
}
