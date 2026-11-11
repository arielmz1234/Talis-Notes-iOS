import SwiftUI
import TaliCore

/// A notebook, laid out like Android's `NotebookScreen`: the canvas with its pages; at the top, back
/// and undo/redo on the left, the main toolbar in the middle (under them when narrow), the name and
/// the eye on the right; the active tool's panel hanging below; the page and zoom chips at the bottom.
struct NotebookView: View {
  var notebook: NotebookMeta
  var onBack: () -> Void
  /// Quick open: another notebook in place of this one (Back still goes to the library).
  var onSwitch: (NotebookMeta) -> Void

  init(notebook: NotebookMeta, onBack: @escaping () -> Void, onSwitch: @escaping (NotebookMeta) -> Void = { _ in }) {
    self.notebook = notebook
    self.onBack = onBack
    self.onSwitch = onSwitch
    _viewing = State(initialValue: PhoneWriting.opensViewOnly(notebook.id, kind: notebook.kind))
    _title = State(initialValue: notebook.title)
    _paper = State(initialValue: notebook.paper)
    _dark = State(initialValue: notebook.dark)
  }
  @Environment(Library.self) private var lib
  @Environment(\.tali) private var c
  @Environment(\.colorScheme) private var scheme
  @State private var tool: Tool = .pen(PenStore.load().first?.id ?? "p1")
  @State private var pens: [PenSlot] = PenStore.load()
  @State private var panel: PanelKind?
  /// What the Shapes tool draws (Android's `lastShape`), and the standard shape last chosen.
  @AppStorage(ShapeSettings.Key.lastShape) private var lastShape = ShapeKind.LINE.rawValue
  @State private var lastKind = ShapeChoice.kind(UserDefaults.standard.string(forKey: ShapeSettings.Key.lastShape) ?? "")
  @AppStorage(ShapeSettings.Key.customShapes) private var customShapesJSON = "[]"
  /// The pen last written with, which the Shapes tool can follow.
  @State private var lastPenId: String?
  @State private var browsingShapes = false
  /// What's picked up, as the shape being named before it joins My shapes.
  @State private var savingShape: ShapeGeometry?
  @AppStorage("eraserPrecise") private var eraserPrecise = false
  @AppStorage("eraserSize") private var eraserSize: Double = 20
  @State private var canUndo = false
  @State private var canRedo = false
  @State private var pageCount = 1
  @State private var page = 0
  @State private var zoom: CGFloat = 1
  @State private var command: CanvasCommand?
  /// On a phone a notebook opens just for looking until Write is tapped (remembered per notebook, on this phone only).
  @State private var viewing: Bool
  /// Toolbars hidden with the eye (Android's focus mode).
  @State private var hidden = false
  /// The notebook's name as shown (tapping the name pill renames it, as on Android).
  @State private var title: String
  @State private var renaming = false
  /// The notebook's paper and dark paper, changed from the ⋯ menu.
  @State private var paper: PaperStyle
  @State private var dark: Bool
  @State private var moreOpen = false
  /// What the lasso picked up (window coordinates), a held spot offering Paste, and a hint line.
  @State private var selection: CGRect?
  @State private var pasteOffer: CGPoint?
  @State private var hint: String?
  @State private var hintTask: Task<Void, Never>?
  @State private var bridge = CanvasBridge()
  @State private var showPages = false
  @State private var exporting = false
  /// Draw with finger: -1 Auto, 0 off, 1 on (app-wide, as on Android).
  @AppStorage("fingerDraws") private var fingerDrawsRaw = -1
  @AppStorage("smartUndo") private var smartUndo = true
  @AppStorage("inkBetweenPages") private var between = false
  @AppStorage("hideNavBar") private var fullScreen = false

  var body: some View {
    GeometryReader { geo in
      let narrow = geo.size.width < 900
      ZStack(alignment: .top) {
        Color(uiColor: dark ? UIColor(argb: Int32(bitPattern: 0xFF2A_2338)) : UIColor(c.desk)).ignoresSafeArea()
        NoteCanvas(
          notebook: notebook, db: lib.db, tool: tool, pens: pens, viewOnly: viewing,
          topClearance: narrow ? 164 : 104,
          settings: CanvasSettings(paper: paper, dark: dark, fingerDraws: fingerDraws, smartUndo: smartUndo, between: between),
          bridge: bridge,
          eraser: EraserSettings(precise: eraserPrecise, size: Float(eraserSize)),
          shape: shapeSource,
          onUndoState: { u, r in
            canUndo = u
            canRedo = r
          },
          onPageCount: { pageCount = $0 },
          onSelection: { r in withAnimation(.easeOut(duration: 0.14)) { selection = r } },
          onHint: { show($0) },
          onPasteOffer: { p in withAnimation(.easeOut(duration: 0.16)) { pasteOffer = p } },
          onView: { p, z in
            page = p
            zoom = z
          },
          command: $command
        )
        .ignoresSafeArea(edges: .bottom)
        // The keyboard (typing in a text box) doesn't push the page up: the canvas scrolls the box into view.
        .ignoresSafeArea(.keyboard)
        // A tap on the page closes an open panel, as on Android.
        .simultaneousGesture(TapGesture().onEnded { if panel != nil { withAnimation(.easeOut(duration: 0.1)) { panel = nil } } })
        VStack(spacing: narrow ? 18 : 0) {
          if viewing {
            HStack(spacing: 10) {
              leftBars
              Spacer(minLength: 10)
              Button {
                withAnimation(.spring(response: 0.32, dampingFraction: 0.85)) {
                  viewing = false
                  PhoneWriting.startWriting(notebook.id)
                  ViewOnly.set(notebook.id, false)
                }
              } label: {
                Label(L("write"), systemImage: "pencil").font(TaliType.labelLarge)
              }
              .buttonStyle(PrimaryButtonStyle())
              .frame(height: 52)
              .accessibilityIdentifier("write")
            }
          } else if hidden {
            HStack {
              Spacer()
              FloatingBar(crown: .softEdge) {
                ToolIcon(system: "eye", label: L("show_toolbars")) { withAnimation(.easeOut(duration: 0.22)) { hidden = false } }
              }
            }
            .transition(.opacity)
          } else if narrow {
            HStack(spacing: 10) {
              leftBars
              Spacer(minLength: 10)
              rightBars(showName: !PhoneWriting.onPhone)
            }
            mainToolbar(showColors: !PhoneWriting.onPhone)
              .transition(.move(edge: .top).combined(with: .opacity))
          } else {
            ZStack(alignment: .top) {
              HStack(spacing: 10) {
                leftBars
                Spacer(minLength: 10)
                rightBars(showName: true)
              }
              .frame(height: 60)
              mainToolbar(showColors: true)
            }
            .transition(.opacity)
          }
          if !hidden, !viewing, let shown = panel {
            Spacer().frame(height: 10)
            Group {
              switch shown {
              case .pen:
                if let i = activePenIndex { PenPanel(pen: $pens[i]) }
              case .eraser:
                EraserPanel(precise: $eraserPrecise, size: Binding(get: { Float(eraserSize) }, set: { eraserSize = Double($0) }))
              case .shapes:
                ShapesPanel(picker: shapePicker, pen: shapePen, compact: geo.size.width < 660) {
                  withAnimation(Ease.outStrong(duration: 0.24)) { browsingShapes = true }
                }
              case .fill:
                FillPanel()
              }
            }
            .environment(\.panelRoom, geo.size.height - (narrow ? 266 : 196))
            .transition(
              .asymmetric(
                insertion: .opacity.combined(with: .scale(scale: 0.97, anchor: .top)).combined(with: .offset(y: -6)),
                removal: .opacity.combined(with: .scale(scale: 0.98, anchor: .top))))
          }
        }
        .padding(.horizontal, 16)
        .padding(.top, 20)
        if let sel = selection, !hidden, !viewing {
          SelectionMenuLayer(selection: sel, narrow: narrow, onSaveShape: bridge.coordinator?.hasDrawingPicked == true ? { saveShape() } : nil) { command = $0 }
            .ignoresSafeArea()
        }
        if let at = pasteOffer {
          // A tap anywhere else takes the offer away.
          Color.clear.contentShape(Rectangle()).ignoresSafeArea()
            .onTapGesture { withAnimation(.easeOut(duration: 0.12)) { pasteOffer = nil } }
          PasteBubble(at: at) { command = .paste }.ignoresSafeArea()
        }
        if showPages {
          ZStack {
            c.scrim.ignoresSafeArea().onTapGesture { withAnimation(.easeOut(duration: 0.16)) { showPages = false } }
            PagesOverview(
              count: pageCount, current: page, bridge: bridge,
              onGo: { command = .goToPage($0) },
              onAdd: { command = .addPage },
              onDelete: { command = .deletePage($0) },
              onClose: { withAnimation(.easeOut(duration: 0.16)) { showPages = false } }
            )
          }
          .transition(.opacity)
        }
        if browsingShapes {
          DialogOverlay(onClose: { withAnimation(.easeOut(duration: 0.16)) { browsingShapes = false } }) {
            ShapePacksCard(picker: shapePicker, size: geo.size) { withAnimation(.easeOut(duration: 0.16)) { browsingShapes = false } }
          }
          .transition(.opacity)
        }
        if let geometry = savingShape {
          DialogOverlay(onClose: { withAnimation(.easeOut(duration: 0.16)) { savingShape = nil } }) {
            SaveShapeCard(geometry: geometry, onClose: { withAnimation(.easeOut(duration: 0.16)) { savingShape = nil } }) { name in
              let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
              let shape = CustomShape(id: String(UUID().uuidString.lowercased().prefix(8)), name: name.isEmpty ? L("my_shape") : name, geometry: geometry)
              customShapesJSON = ShapeSettings.json(of: ShapeSettings.shapes(from: customShapesJSON) + [shape])
              withAnimation(.easeOut(duration: 0.16)) { savingShape = nil }
              bridge.coordinator?.clearSelection()
              show(L("saved_to_my_shapes_hold_the"))
            }
          }
          .transition(.opacity)
        }
        if exporting {
          DialogOverlay(onClose: { withAnimation(.easeOut(duration: 0.16)) { exporting = false } }) {
            ExportCard(bridge: bridge, paged: notebook.pages != nil) { withAnimation(.easeOut(duration: 0.16)) { exporting = false } }
          }
          .transition(.opacity)
        }
        if let hint {
          VStack {
            Spacer()
            HintPill(text: hint).padding(.bottom, 64)
          }
          .allowsHitTesting(false)
        }
        // The page and zoom chips, bottom right.
        if !hidden {
          VStack {
            Spacer()
            HStack(spacing: 8) {
              Spacer()
              if notebook.pages != nil {
                PageChip(page: page, count: pageCount) { command = .goToPage($0) }
              }
              ZoomChip(zoom: zoom) { command = .fitZoom }
            }
          }
          .padding(.horizontal, 16)
          .padding(.bottom, 12)
          .transition(.opacity)
        }
      }
    }
    .environment(\.tali, barColors)
    .alert(L("rename"), isPresented: $renaming) {
      RenameField(initial: title) { name in
        lib.rename(notebook.id, to: name)
        title = lib.notebooks.first { $0.id == notebook.id }?.title ?? name
      }
    }
    .onChange(of: pens) { _, new in PenStore.save(new) }
    .onChange(of: tool) { old, _ in if case .pen(let id) = old { lastPenId = id } }
    .onChange(of: paper) { _, p in try? lib.db.run("UPDATE notebooks SET paper=? WHERE id=?", [.text(p.rawValue), .text(notebook.id)]) }
    .onChange(of: dark) { _, d in try? lib.db.run("UPDATE notebooks SET dark=? WHERE id=?", [.int(d ? 1 : 0), .text(notebook.id)]) }
    .statusBarHidden(fullScreen)
    .persistentSystemOverlays(fullScreen ? .hidden : .automatic)
  }

  /// Shows [text] for a few seconds.
  private func show(_ text: String) {
    hintTask?.cancel()
    withAnimation(Ease.outStrong(duration: 0.22)) { hint = text }
    hintTask = Task { @MainActor in
      try? await Task.sleep(for: .seconds(2.8))
      guard !Task.isCancelled else { return }
      withAnimation(.easeOut(duration: 0.2)) { hint = nil }
    }
  }

  private var activePenIndex: Int? {
    if case .pen(let id) = tool { return pens.firstIndex { $0.id == id } }
    return nil
  }

  private func mainToolbar(showColors: Bool) -> some View {
    MainToolbar(pens: $pens, tool: $tool, panel: $panel, shape: shapeSource, onKeyboard: { panel = nil; command = .newText }, showColors: showColors, compactTools: PhoneWriting.onPhone)
  }

  private func saveShape() {
    guard let geometry = bridge.coordinator?.selectionGeometry() else { return }
    withAnimation(Ease.outStrong(duration: 0.24)) { savingShape = geometry }
  }

  private var shapeSource: ShapeSource {
    ShapeChoice(stored: lastShape).source(custom: ShapeSettings.shapes(from: customShapesJSON), kind: lastKind)
  }

  /// Choosing a shape switches to the Shapes tool and closes what it was chosen from, so she can draw it straight away.
  private var shapePicker: ShapePicker {
    ShapePicker(stored: $lastShape, kind: $lastKind, toolOn: tool == .shape) {
      tool = .shape
      withAnimation(.easeOut(duration: 0.12)) {
        panel = nil
        browsingShapes = false
      }
    }
  }

  private var shapePen: PenSlot {
    ShapeSettings.shapeSlot(active: activePenIndex.map { pens[$0] } ?? pens.first { $0.id == lastPenId }, pens: pens)
  }

  private var fingerDraws: Bool? { fingerDrawsRaw < 0 ? nil : fingerDrawsRaw == 1 }

  /// In dark mode the bars over a white page are the soft mist, as on Android.
  private var barColors: TaliColors {
    let f = ColorTheme.current
    return scheme == .dark && !dark ? f.mist : (scheme == .dark ? f.dark : f.light)
  }

  /// Back on a little cloud of its own, then undo and redo (Android's `TitlePill`).
  private var leftBars: some View {
    HStack(spacing: 10) {
      FloatingBar(crown: .little) {
        ToolIcon(system: "arrow.backward", label: L("back"), action: onBack).accessibilityIdentifier("back")
      }
      if !PhoneWriting.onPhone || !viewing {
        QuickOpen(current: notebook.id, onOpen: onSwitch)
      }
      if !viewing {
        FloatingBar(crown: .softEdge) {
          ToolIcon(system: "arrow.uturn.backward", label: L("undo"), enabled: canUndo) { command = .undo }
          ToolIcon(system: "arrow.uturn.forward", label: L("redo"), enabled: canRedo) { command = .redo }
        }
      }
    }
  }

  /// The notebook's name with a pencil (no crown), then the eye, in the top-right corner.
  private func rightBars(showName: Bool) -> some View {
    HStack(spacing: 10) {
      if showName {
        FloatingBar(crown: .none, height: 44) {
          HStack(spacing: 8) {
            Text(title).font(TaliType.titleSmall).foregroundStyle(barColors.ink).lineLimit(1).frame(maxWidth: 200, alignment: .leading)
            Image(systemName: "pencil").font(.system(size: 14)).foregroundStyle(barColors.inkFaint)
          }
          .padding(.leading, 10).padding(.trailing, 8).padding(.vertical, 6)
          .contentShape(Rectangle())
          .onTapGesture { renaming = true }
          .accessibilityAddTraits(.isButton)
          .accessibilityHint(L("rename"))
        }
      }
      FloatingBar(crown: .softEdge) {
        ToolIcon(system: "eye.slash", label: L("hide_toolbars")) {
          withAnimation(.easeOut(duration: 0.2)) {
            panel = nil
            hidden = true
          }
        }
        // ⋯ always last, in the top-right corner.
        ToolIcon(system: "ellipsis", label: L("more")) { moreOpen = true }
          .accessibilityIdentifier("more")
          .popover(isPresented: $moreOpen, arrowEdge: .top) {
            MoreMenu(
              paged: notebook.pages != nil, paper: $paper, dark: $dark,
              fingerDraws: Binding(get: { fingerDraws }, set: { fingerDrawsRaw = $0 == nil ? -1 : ($0! ? 1 : 0) }),
              smartUndo: $smartUndo, between: $between, fullScreen: $fullScreen,
              onPages: {
                moreOpen = false
                withAnimation(Ease.outStrong(duration: 0.24)) { showPages = true }
              },
              onExport: {
                moreOpen = false
                withAnimation(Ease.outStrong(duration: 0.24)) { exporting = true }
              },
              onFit: {
                moreOpen = false
                command = .fitZoom
              },
              onViewOnly: {
                moreOpen = false
                ViewOnly.set(notebook.id, true)
                withAnimation(.spring(response: 0.32, dampingFraction: 0.85)) {
                  panel = nil
                  viewing = true
                }
              }
            )
            .environment(\.tali, barColors)
            .presentationCompactAdaptation(.popover)
            // The menu's own surface (Android's white or mist menu), not the system's popover colour.
            .presentationBackground(barColors.surface)
          }
      }
    }
  }
}

/// A floating bar (Android's `FloatingBar`): a cloud surface with 22 pt corners, 52 pt tall.
struct FloatingBar<Content: View>: View {
  var crown: CloudCrown = .none
  var height: CGFloat = 52
  @ViewBuilder var content: Content

  var body: some View {
    HStack(spacing: 0) { content }
      .padding(.horizontal, 6).padding(.vertical, 4)
      .frame(height: height)
      .cloudSurface(radius: 22, crown: crown)
  }
}

/// A 44 pt icon button with 14 pt corners and a 22 pt icon (Android's `ToolButton`).
struct ToolIcon: View {
  var system: String
  var label: String
  var enabled = true
  var action: () -> Void
  @Environment(\.tali) private var c

  var body: some View {
    Button(action: action) {
      Image(systemName: system).font(.system(size: 19)).foregroundStyle(enabled ? c.ink : c.inkFaint.opacity(0.5))
        .frame(width: 44, height: 44).contentShape(RoundedRectangle(cornerRadius: 14))
    }
    .buttonStyle(PressStyle(scale: 0.9))
    .disabled(!enabled)
    .accessibilityLabel(label)
  }
}

func penName(_ t: PenType) -> String {
  switch t {
  case .FINELINER: L("pen_fineliner")
  case .FOUNTAIN: L("pen_fountain")
  case .PENCIL: L("pen_pencil")
  case .CALLIGRAPHY: L("pen_calligraphy")
  case .HIGHLIGHTER: L("pen_highlighter")
  case .DASHED: L("pen_fineliner")
  }
}

/// Which notebooks this phone writes in straight away (Android's `phone_view` prefs): kept on the
/// phone only, never synced, so the tablet isn't affected.
@MainActor
enum PhoneWriting {
  static var onPhone: Bool { UIDevice.current.userInterfaceIdiom == .phone }

  /// On a phone everything opens for looking until Write; on a tablet a PDF, picture or scan does
  /// until she first taps Write there (Android's `writeOn`), and anything set to View only.
  static func opensViewOnly(_ id: String, kind: DocKind = .notebook) -> Bool {
    if onPhone { return !(UserDefaults.standard.stringArray(forKey: "phoneWriting") ?? []).contains(id) }
    if kind != .notebook && !(UserDefaults.standard.stringArray(forKey: "writeOn") ?? []).contains(id) { return true }
    return ViewOnly.contains(id)
  }

  static func startWriting(_ id: String) {
    let key = onPhone ? "phoneWriting" : "writeOn"
    var list = UserDefaults.standard.stringArray(forKey: key) ?? []
    if !list.contains(id) { list.append(id) }
    UserDefaults.standard.set(list, forKey: key)
  }
}

/// Items set to View only from the ⋯ menu (Android's `AppSettings.viewOnly`), on a tablet.
enum ViewOnly {
  static func contains(_ id: String) -> Bool { (UserDefaults.standard.stringArray(forKey: "viewOnly") ?? []).contains(id) }
  static func set(_ id: String, _ on: Bool) {
    var list = UserDefaults.standard.stringArray(forKey: "viewOnly") ?? []
    list.removeAll { $0 == id }
    if on { list.append(id) }
    UserDefaults.standard.set(list, forKey: "viewOnly")
  }
}

/// The pens, kept between launches.
enum PenStore {
  static func load() -> [PenSlot] {
    guard let d = UserDefaults.standard.data(forKey: "pens"), let p = try? JSONDecoder().decode([PenSlot].self, from: d), !p.isEmpty else {
      return PenSlot.defaults
    }
    return p
  }
  static func save(_ p: [PenSlot]) {
    if let d = try? JSONEncoder().encode(p) { UserDefaults.standard.set(d, forKey: "pens") }
  }
}
