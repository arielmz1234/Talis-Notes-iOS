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
    _customPaper = State(initialValue: notebook.customPaper)
    _dark = State(initialValue: notebook.dark)
    _endless = State(initialValue: notebook.pages == nil)
  }
  @Environment(Library.self) private var lib
  @Environment(\.tali) private var c
  @Environment(\.colorScheme) private var scheme
  @State private var tool: Tool = .pen(PenStore.load().first?.id ?? "p1")
  @State private var pens: [PenSlot] = PenStore.load()
  @State private var panel: PanelKind?
  /// The Shapes tool's shape (Android's `lastShape`).
  @AppStorage("lastShape") private var shapeKindRaw = ShapeKind.RECTANGLE.rawValue
  private var shapeKind: ShapeKind { ShapeKind(rawValue: shapeKindRaw) ?? .RECTANGLE }
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
  /// Where each bar last sat, and the mist playing where they are or were.
  @State private var bars = BarFrames()
  @State private var puff: BarPuff?
  /// The notebook's name as shown (tapping the name pill renames it, as on Android).
  @State private var title: String
  @State private var renaming = false
  /// The notebook's paper and dark paper, changed from the ⋯ menu.
  @State private var paper: PaperStyle
  /// One of her own papers, drawn instead of [paper] while it exists.
  @State private var customPaper: String?
  @State private var paperCard: PaperCard?
  @State private var dark: Bool
  /// One endless page instead of A4 pages, switched from the ⋯ menu.
  @State private var endless: Bool
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
        // An endless canvas is paper all the way to the screen's edges; pages lie on the desk.
        Color(uiColor: endless ? paperSpec.paperColor : dark ? UIColor(argb: Int32(bitPattern: 0xFF0E_0C13)) : UIColor(c.desk)).ignoresSafeArea()
        NoteCanvas(
          notebook: canvasNotebook, db: lib.db, tool: tool, pens: pens, viewOnly: viewing,
          topClearance: narrow ? 164 : 104,
          settings: CanvasSettings(
            paper: paperSpec, fingerDraws: fingerDraws, smartUndo: smartUndo, between: between, pageGuides: PaperSettings.shared.pageGuides),
          bridge: bridge,
          eraser: EraserSettings(precise: eraserPrecise, size: Float(eraserSize)),
          shapeKind: shapeKind,
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
          } else if narrow {
            HStack(spacing: 10) {
              if !hidden { leftBars.bar("title", 0, bars) }
              Spacer(minLength: 10)
              if !hidden { rightBars(showName: !PhoneWriting.onPhone).bar("undo", 2, bars) }
            }
            if !hidden { mainToolbar(showColors: !PhoneWriting.onPhone).bar("tools", 1, bars) }
          } else {
            ZStack(alignment: .top) {
              HStack(spacing: 10) {
                if !hidden { leftBars.bar("title", 0, bars) }
                Spacer(minLength: 10)
                if !hidden { rightBars(showName: true).bar("undo", 2, bars) }
              }
              .frame(height: 60)
              // Over the name pill, also while both are leaving.
              if !hidden { mainToolbar(showColors: true).bar("tools", 1, bars).zIndex(1) }
            }
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
                ShapesPanel(kind: Binding(get: { shapeKind }, set: { shapeKindRaw = $0.rawValue })) {
                  // Choosing a shape closes the panel so she can draw it straight away.
                  withAnimation(.easeOut(duration: 0.12)) { panel = nil }
                }
              }
            }
            .transition(
              .asymmetric(
                insertion: .opacity.combined(with: .scale(scale: 0.97, anchor: .top)).combined(with: .offset(y: -6)),
                removal: .opacity.combined(with: .scale(scale: 0.98, anchor: .top))))
          }
        }
        .padding(.horizontal, 16)
        .padding(.top, 20)
        if let puff {
          BarPuffs(puff: puff).ignoresSafeArea()
        }
        if hidden, !viewing {
          ShowToolbarsButton { setHidden(false) }
            .padding(.top, 26).padding(.trailing, 22)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
            .transition(
              .asymmetric(
                insertion: .opacity.combined(with: .scale(scale: 0.9)).animation(Ease.outStrong(duration: 0.24).delay(0.08)),
                removal: .opacity.combined(with: .scale(scale: 0.95)).animation(Ease.outStrong(duration: 0.14))))
        }
        if let sel = selection, !hidden, !viewing {
          SelectionMenuLayer(selection: sel, narrow: narrow) { command = $0 }
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
        if let card = paperCard {
          DialogOverlay(onClose: closePaperCard) {
            switch card {
            case .builtIn(let style): BuiltInPaperCard(style: style, onDone: closePaperCard)
            case .new, .edit:
              NewPaperCard(
                editing: card.editing,
                onSave: { p in
                  if card.editing != nil {
                    PaperSettings.shared.update(p)
                  } else {
                    PaperSettings.shared.add(p)
                    paperChoice.wrappedValue = .custom(p.id)
                  }
                  closePaperCard()
                }, onCancel: closePaperCard)
            }
          }
          .transition(.opacity)
        }
        if exporting {
          DialogOverlay(onClose: { withAnimation(.easeOut(duration: 0.16)) { exporting = false } }) {
            ExportCard(bridge: bridge, paged: !endless) { withAnimation(.easeOut(duration: 0.16)) { exporting = false } }
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
              if !endless {
                PageChip(page: page, count: pageCount, onGo: { command = .goToPage($0) }) {
                  withAnimation(Ease.outStrong(duration: 0.24)) { showPages = true }
                }
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
    .onChange(of: paperColumn) { _, p in try? lib.db.run("UPDATE notebooks SET paper=? WHERE id=?", [.text(p), .text(notebook.id)]) }
    .onChange(of: dark) { _, d in try? lib.db.run("UPDATE notebooks SET dark=? WHERE id=?", [.int(d ? 1 : 0), .text(notebook.id)]) }
    .statusBarHidden(fullScreen)
    .persistentSystemOverlays(fullScreen ? .hidden : .automatic)
  }

  /// The notebook as the canvas should lay it out: A4 pages or one endless page.
  private var canvasNotebook: NotebookMeta {
    var n = notebook
    n.pages = endless ? nil : max(notebook.pages ?? 1, 1)
    return n
  }

  private var paperSpec: PaperSpec {
    let papers = PaperSettings.shared
    return papers.spec(paper, custom: papers.custom(customPaper), dark: dark)
  }

  /// What the notebook's paper column holds (Android's "custom:<id>" for one of hers).
  private var paperColumn: String { customPaper.map { CustomPaper.prefix + $0 } ?? paper.rawValue }

  /// Choosing a paper also makes it the one new notebooks start with, as on Android.
  private var paperChoice: Binding<PaperChoice> {
    Binding(
      get: { customPaper.map(PaperChoice.custom) ?? .style(paper) },
      set: { choice in
        switch choice {
        case .style(let s):
          paper = s
          customPaper = nil
          UserDefaults.standard.set(s.rawValue, forKey: "defaultPaper")
          PaperSettings.shared.defaultCustomPaper = nil
        case .custom(let id):
          paper = .BLANK
          customPaper = id
          PaperSettings.shared.defaultCustomPaper = id
        }
      })
  }

  private func openPaperCard(_ card: PaperCard) {
    moreOpen = false
    withAnimation(Ease.outStrong(duration: 0.24)) { paperCard = card }
  }

  private func closePaperCard() { withAnimation(.easeOut(duration: 0.16)) { paperCard = nil } }

  /// Hides or brings back the toolbars, with a puff of mist where each bar is: fuller when they go.
  private func setHidden(_ h: Bool) {
    let shot = BarPuff(spots: Array(bars.frames.values), strength: h ? 0.85 : 0.5)
    puff = shot
    withAnimation(Ease.outStrong(duration: 0.26)) {
      panel = nil
      hidden = h
    }
    Task { @MainActor in
      try? await Task.sleep(for: .seconds(PuffTiming.subtlePuff))
      if puff?.id == shot.id { puff = nil }
    }
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
    MainToolbar(pens: $pens, tool: $tool, panel: $panel, shapeKind: shapeKind, onKeyboard: { panel = nil; command = .newText }, showColors: showColors, compactTools: PhoneWriting.onPhone)
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
        ToolIcon(system: "eye.slash", label: L("hide_toolbars")) { setHidden(true) }
          .accessibilityIdentifier("hide-toolbars")
        // ⋯ always last, in the top-right corner.
        ToolIcon(system: "ellipsis", label: L("more")) { moreOpen = true }
          .accessibilityIdentifier("more")
          .popover(isPresented: $moreOpen, arrowEdge: .top) {
            MoreMenu(
              paged: !endless,
              papers: {
                PaperPicker(
                  choice: paperChoice, customs: PaperSettings.shared.customPapers, dark: dark || barColors.isDark,
                  onAdd: { openPaperCard(.new) },
                  onRemove: { PaperSettings.shared.remove($0.id) },
                  onEditCurrent: {
                    if let id = customPaper, let p = PaperSettings.shared.custom(id) { openPaperCard(.edit(p)) } else { openPaperCard(.builtIn(paper)) }
                  })
              },
              dark: $dark,
              fingerDraws: Binding(get: { fingerDraws }, set: { fingerDrawsRaw = $0 == nil ? -1 : ($0! ? 1 : 0) }),
              smartUndo: $smartUndo, between: $between,
              pageGuides: Binding(get: { PaperSettings.shared.pageGuides }, set: { PaperSettings.shared.pageGuides = $0 }), fullScreen: $fullScreen,
              onEndless: { on in
                endless = on
                command = .setEndless(on)
                show(on ? L("endless_canvas_write_anywhere") : L("a4_pages"))
              },
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

/// The paper card open over the notebook: a built-in paper's, a new paper of hers, or one of hers.
enum PaperCard: Equatable {
  case builtIn(PaperStyle)
  case new
  case edit(CustomPaper)

  var editing: CustomPaper? {
    if case .edit(let p) = self { return p }
    return nil
  }
}

/// Where each toolbar last sat on screen (Android's plain map: written while bars move, so it
/// mustn't redraw anything).
final class BarFrames {
  var frames: [String: CGRect] = [:]
}

/// The mist over the bars as they hide or come back.
struct BarPuff: Identifiable {
  let id = UUID()
  let start = Date()
  var spots: [CGRect]
  var strength: Double
}

struct BarPuffs: View {
  var puff: BarPuff

  var body: some View {
    GeometryReader { g in
      let origin = g.frame(in: .global).origin
      ForEach(Array(puff.spots.enumerated()), id: \.offset) { _, r in
        PuffPlayer(start: puff.start, duration: PuffTiming.subtlePuff, strength: puff.strength)
          .frame(width: r.width, height: r.height)
          .position(x: r.midX - origin.x, y: r.midY - origin.y)
      }
    }
    .allowsHitTesting(false)
  }
}

/// While the toolbars are hidden, the one thing left (Android's `ShowToolbarsButton`): a small
/// frosted circle in the corner with the eye, which brings them back.
struct ShowToolbarsButton: View {
  var action: () -> Void
  @Environment(\.tali) private var c

  var body: some View {
    Button(action: action) {
      Image(systemName: "eye").font(.system(size: 17)).foregroundStyle(c.inkMuted)
        .frame(width: 40, height: 40)
        .background(Circle().fill(c.surface.opacity(0.72)))
        .overlay(Circle().stroke(c.line, lineWidth: 1))
        .contentShape(Circle())
    }
    .buttonStyle(PressStyle(scale: 0.9))
    .accessibilityLabel(L("show_toolbars"))
    .accessibilityIdentifier("show-toolbars")
  }
}

/// A bar arriving lifts in from its own top edge, growing from 96%; the bars follow one another by
/// 40 ms and leave together, quicker (Android's `Modifier.bar`).
private struct BarLift: ViewModifier {
  var shown: Double

  func body(content: Content) -> some View {
    content.opacity(shown).scaleEffect(0.96 + 0.04 * shown, anchor: .top).offset(y: (1 - shown) * -10)
  }
}

extension View {
  fileprivate func bar(_ key: String, _ order: Int, _ frames: BarFrames) -> some View {
    onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { frames.frames[key] = $0 }
      .transition(
        .asymmetric(
          insertion: .modifier(active: BarLift(shown: 0), identity: BarLift(shown: 1)).animation(Ease.outStrong(duration: 0.26).delay(0.04 * Double(order))),
          removal: .modifier(active: BarLift(shown: 0), identity: BarLift(shown: 1)).animation(Ease.outStrong(duration: 0.17))))
  }
}
