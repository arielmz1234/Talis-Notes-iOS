import SwiftUI
import TaliCore

/// A notebook: the canvas with its pages, the top bar (back, name, undo/redo) and the main toolbar
/// (pens, eraser, lasso) floating over it.
struct NotebookView: View {
  var notebook: NotebookMeta
  var onBack: () -> Void

  init(notebook: NotebookMeta, onBack: @escaping () -> Void) {
    self.notebook = notebook
    self.onBack = onBack
    _viewing = State(initialValue: PhoneWriting.opensViewOnly(notebook.id))
  }
  @Environment(Library.self) private var lib
  @Environment(\.tali) private var c
  @State private var tool: Tool = .pen("p1")
  @State private var pens: [PenSlot] = PenStore.load()
  @State private var canUndo = false
  @State private var canRedo = false
  @State private var pageCount = 1
  @State private var command: CanvasCommand?
  @State private var editingPen: String?
  /// On a phone a notebook opens just for looking until Write is tapped (remembered per notebook, on this phone only).
  @State private var viewing: Bool
  /// Toolbars hidden with the eye (Android's focus mode).
  @State private var hidden = false
  @Environment(\.colorScheme) private var scheme

  var body: some View {
    GeometryReader { geo in
      let narrow = geo.size.width < 900
      ZStack(alignment: .top) {
        Color(uiColor: notebook.dark ? UIColor(argb: Int32(bitPattern: 0xFF2A_2338)) : UIColor(c.desk)).ignoresSafeArea()
        NoteCanvas(
          notebook: notebook, db: lib.db, tool: tool, pens: pens, viewOnly: viewing,
          onUndoState: { u, r in
            canUndo = u
            canRedo = r
          },
          onPageCount: { pageCount = $0 }, command: $command
        )
        .ignoresSafeArea(edges: .bottom)
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
            toolbar.frame(maxWidth: .infinity)
              .transition(.move(edge: .top).combined(with: .opacity))
          } else {
            ZStack(alignment: .top) {
              HStack(spacing: 10) {
                leftBars
                Spacer(minLength: 10)
                rightBars(showName: true)
              }
              .frame(height: 60)
              toolbar
            }
            .transition(.opacity)
          }
          if !hidden, !viewing, let id = editingPen, let i = pens.firstIndex(where: { $0.id == id }) {
            PenPanel(pen: $pens[i]) { editingPen = nil }
              .transition(.asymmetric(insertion: .opacity.combined(with: .offset(y: -8)), removal: .opacity))
          }
        }
        .padding(.horizontal, 16)
        .padding(.top, 20)
      }
    }
    .environment(\.tali, barColors)
    .onChange(of: pens) { _, new in PenStore.save(new) }
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
            Text(notebook.title).font(TaliType.titleSmall).foregroundStyle(barColors.ink).lineLimit(1).frame(maxWidth: 200, alignment: .leading)
            Image(systemName: "pencil").font(.system(size: 14)).foregroundStyle(barColors.inkFaint)
          }
          .padding(.leading, 10).padding(.trailing, 8).padding(.vertical, 6)
        }
      }
      FloatingBar(crown: .softEdge) {
        ToolIcon(system: "eye.slash", label: L("hide_toolbars")) {
          withAnimation(.easeOut(duration: 0.2)) {
            editingPen = nil
            hidden = true
          }
        }
      }
    }
  }

  private var toolbar: some View {
    HStack(spacing: 6) {
      ForEach(pens) { pen in
        PenButton(pen: pen, on: tool == .pen(pen.id)) {
          if tool == .pen(pen.id) {
            withAnimation(.easeOut(duration: 0.2)) { editingPen = editingPen == pen.id ? nil : pen.id }
          } else {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
              tool = .pen(pen.id)
              editingPen = nil
            }
          }
        }
      }
      Divider().frame(height: 30).padding(.horizontal, 4)
      ToolButton(icon: "eraser", label: L("eraser"), on: tool == .eraser) { select(.eraser) }
      ToolButton(icon: "lasso", label: L("lasso"), on: tool == .lasso) { select(.lasso) }
    }
    .padding(.horizontal, 6)
    .frame(height: 60)
    .cloudSurface(radius: 22, crown: .edge)
  }

  private func select(_ t: Tool) {
    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
      tool = t
      editingPen = nil
    }
  }
}

/// A pen in the toolbar: the pen drawn in its colour, raised when in use.
struct PenButton: View {
  var pen: PenSlot
  var on: Bool
  var action: () -> Void
  @Environment(\.tali) private var c

  var body: some View {
    Button(action: action) {
      ZStack(alignment: .bottom) {
        PenGlyph(type: pen.type, color: Color(uiColor: UIColor(argb: pen.color)))
          .frame(width: 22, height: 44)
          .offset(y: on ? 2 : 12)
      }
      .frame(width: 40, height: 52)
      .clipped()
      .background {
        if on { RoundedRectangle(cornerRadius: 14).fill(c.accentSoft) }
      }
    }
    .buttonStyle(.plain)
    .accessibilityLabel(penName(pen.type))
  }
}

/// A simple pen drawn upright: body, a band in its colour, and the tip.
struct PenGlyph: View {
  var type: PenType
  var color: Color
  @Environment(\.tali) private var c

  var body: some View {
    Canvas { ctx, s in
      let w = s.width, h = s.height
      let body = CGRect(x: w * 0.22, y: h * 0.28, width: w * 0.56, height: h * 0.72)
      ctx.fill(Path(roundedRect: body, cornerRadius: w * 0.12), with: .color(c.isDark ? Color(white: 0.85) : .white))
      ctx.stroke(Path(roundedRect: body, cornerRadius: w * 0.12), with: .color(c.line), lineWidth: 1)
      ctx.fill(Path(CGRect(x: body.minX, y: h * 0.36, width: body.width, height: h * 0.12)), with: .color(color))
      var tip = Path()
      let tipWidth: CGFloat = type == .HIGHLIGHTER ? 0.5 : 0.3
      tip.move(to: CGPoint(x: w * (0.5 - tipWidth / 2), y: h * 0.28))
      tip.addLine(to: CGPoint(x: w * (0.5 + tipWidth / 2), y: h * 0.28))
      tip.addLine(to: CGPoint(x: w * 0.5 + (type == .HIGHLIGHTER ? w * 0.12 : 1), y: h * 0.04))
      tip.addLine(to: CGPoint(x: w * 0.5 - (type == .HIGHLIGHTER ? w * 0.12 : 1), y: h * 0.04))
      tip.closeSubpath()
      ctx.fill(tip, with: .color(color.opacity(type == .HIGHLIGHTER ? 0.75 : 1)))
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

struct ToolButton: View {
  var icon: String
  var label: String
  var on: Bool
  var action: () -> Void
  @Environment(\.tali) private var c

  var body: some View {
    Button(action: action) {
      Image(systemName: icon).font(.system(size: 19, weight: .medium)).foregroundStyle(on ? c.accent : c.ink)
        .frame(width: 44, height: 44)
        .background { if on { RoundedRectangle(cornerRadius: 14).fill(c.accentSoft) } }
    }
    .buttonStyle(.plain)
    .accessibilityLabel(label)
  }
}

/// A pen's settings: type, colour and thickness.
struct PenPanel: View {
  @Binding var pen: PenSlot
  var onClose: () -> Void
  @Environment(\.tali) private var c

  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      HStack(spacing: 8) {
        ForEach(PenType.offered, id: \.self) { t in
          Button {
            withAnimation(.spring(response: 0.28, dampingFraction: 0.8)) {
              pen.type = t
              pen.size = min(max(pen.size, 0.5), t.maxSize)
            }
          } label: {
            VStack(spacing: 4) {
              PenGlyph(type: t, color: Color(uiColor: UIColor(argb: pen.color))).frame(width: 18, height: 36)
              Text(penName(t)).font(TaliFont.body(12, t == pen.type ? .semibold : .regular)).foregroundStyle(t == pen.type ? c.accent : c.inkMuted)
                .lineLimit(1).minimumScaleFactor(0.7)
            }
            .frame(width: 74, height: 64)
            .background { if t == pen.type { RoundedRectangle(cornerRadius: 14).fill(c.accentSoft) } }
          }
          .buttonStyle(.plain)
        }
      }
      LazyVGrid(columns: Array(repeating: GridItem(.fixed(30), spacing: 10), count: 11), spacing: 10) {
        ForEach(PenSlot.defaultColors, id: \.self) { col in
          let on = UInt32(bitPattern: pen.color) | 0xFF00_0000 == col
          Button { pen.color = Int32(bitPattern: col) } label: {
            Circle().fill(Color(argb: col)).frame(width: 26, height: 26)
              .overlay(Circle().stroke(c.accent, lineWidth: 2.5).padding(-4).opacity(on ? 1 : 0))
          }
          .buttonStyle(.plain)
        }
      }
      HStack(spacing: 12) {
        Text(L("thickness")).font(TaliFont.body(14, .bold)).foregroundStyle(c.inkMuted)
        Slider(value: Binding(get: { Double(pen.size) }, set: { pen.size = Float(($0 * 2).rounded() / 2) }), in: 0.5...Double(pen.type.maxSize))
        Text(String(format: "%.1f", pen.size)).font(TaliFont.body(14)).foregroundStyle(c.ink).frame(width: 36)
      }
    }
    .padding(20)
    .frame(width: 440)
    .cloudSurface(radius: 24, crown: .center)
    .padding(.top, 12)
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
