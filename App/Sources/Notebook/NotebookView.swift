import SwiftUI
import TaliCore

/// A notebook, laid out like Android's `NotebookScreen`: the canvas with its pages; at the top, back
/// and undo/redo on the left, the main toolbar in the middle (under them when narrow), the name and
/// the eye on the right; the active tool's panel hanging below; the page and zoom chips at the bottom.
struct NotebookView: View {
  var notebook: NotebookMeta
  var onBack: () -> Void

  init(notebook: NotebookMeta, onBack: @escaping () -> Void) {
    self.notebook = notebook
    self.onBack = onBack
    _viewing = State(initialValue: PhoneWriting.opensViewOnly(notebook.id))
    _title = State(initialValue: notebook.title)
  }
  @Environment(Library.self) private var lib
  @Environment(\.tali) private var c
  @Environment(\.colorScheme) private var scheme
  @State private var tool: Tool = .pen(PenStore.load().first?.id ?? "p1")
  @State private var pens: [PenSlot] = PenStore.load()
  @State private var panel: PanelKind?
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

  var body: some View {
    GeometryReader { geo in
      let narrow = geo.size.width < 900
      ZStack(alignment: .top) {
        Color(uiColor: notebook.dark ? UIColor(argb: Int32(bitPattern: 0xFF2A_2338)) : UIColor(c.desk)).ignoresSafeArea()
        NoteCanvas(
          notebook: notebook, db: lib.db, tool: tool, pens: pens, viewOnly: viewing,
          eraser: EraserSettings(precise: eraserPrecise, size: Float(eraserSize)),
          onUndoState: { u, r in
            canUndo = u
            canRedo = r
          },
          onPageCount: { pageCount = $0 },
          onView: { p, z in
            page = p
            zoom = z
          },
          command: $command
        )
        .ignoresSafeArea(edges: .bottom)
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
  }

  private var activePenIndex: Int? {
    if case .pen(let id) = tool { return pens.firstIndex { $0.id == id } }
    return nil
  }

  private func mainToolbar(showColors: Bool) -> some View {
    MainToolbar(pens: $pens, tool: $tool, panel: $panel, showColors: showColors)
  }

  /// In dark mode the bars over a white page are the soft mist, as on Android.
  private var barColors: TaliColors {
    let f = ColorTheme.current
    return scheme == .dark && !notebook.dark ? f.mist : (scheme == .dark ? f.dark : f.light)
  }

  /// Back on a little cloud of its own, then undo and redo (Android's `TitlePill`).
  private var leftBars: some View {
    HStack(spacing: 10) {
      FloatingBar(crown: .little) {
        ToolIcon(system: "arrow.backward", label: L("back"), action: onBack).accessibilityIdentifier("back")
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

  static func opensViewOnly(_ id: String) -> Bool {
    onPhone && !(UserDefaults.standard.stringArray(forKey: "phoneWriting") ?? []).contains(id)
  }

  static func startWriting(_ id: String) {
    var list = UserDefaults.standard.stringArray(forKey: "phoneWriting") ?? []
    if !list.contains(id) { list.append(id) }
    UserDefaults.standard.set(list, forKey: "phoneWriting")
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
