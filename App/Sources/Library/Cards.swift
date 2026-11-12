import SwiftUI
import TaliCore

let starGold = Color(argb: 0xFFF5_B83D)

/// The library's left side, as Android's `Sidebar`: no panel of its own (it shares the sky and page),
/// the wordmark, All notebooks and Starred, then the folder tree, Recently deleted (only when
/// something's in it), Settings and the backup status. One highlight glides between the rows,
/// taking on each folder's own colour.
struct Sidebar: View {
  @Environment(Library.self) private var lib
  @Environment(\.tali) private var c
  var onNewFolder: (String?) -> Void
  var onRenameFolder: (Folder) -> Void
  var onMoveFolder: (Folder) -> Void
  var onDeleteFolder: (Folder) -> Void
  var onPicked: () -> Void
  var onBackups: () -> Void = {}
  var onSettings: () -> Void = {}
  var vanishing: Set<String> = []
  var fresh: Set<String> = []
  @AppStorage("minimal") private var minimal = false
  @State private var collapsed: Set<String> = []
  @Namespace private var nav

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Spacer().frame(height: minimal ? 44 : 120)
      Wordmark().padding(.leading, 8)
      Spacer().frame(height: 30)
      NavRow(label: L("all_notebooks"), count: lib.notebooks.count, selected: lib.shelf == .all, nav: nav, key: Shelf.all) {
        Image(systemName: "book.pages").font(.system(size: 17)).foregroundStyle(lib.shelf == .all ? c.blue : c.inkMuted)
      } action: { pick(.all) }
      .accessibilityIdentifier("shelf-all")
      Spacer().frame(height: 4)
      NavRow(
        label: L("starred_notebooks"), count: lib.notebooks.filter { lib.starred.contains($0.id) }.count, selected: lib.shelf == .starred, nav: nav,
        key: Shelf.starred
      ) {
        Image(systemName: lib.shelf == .starred ? "star.fill" : "star").font(.system(size: 17)).foregroundStyle(lib.shelf == .starred ? starGold : c.inkMuted)
      } action: { pick(.starred) }
      .accessibilityIdentifier("shelf-starred")
      Spacer().frame(height: 22)
      HStack(spacing: 0) {
        SectionLabel(text: L("folders"))
        Button { onNewFolder(nil) } label: {
          Image(systemName: "plus").font(.system(size: 15)).foregroundStyle(c.inkMuted).frame(width: 30, height: 30).contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(L("new_folder"))
        .accessibilityIdentifier("sidebar-new-folder")
      }
      .padding(.leading, 10)
      Spacer().frame(height: 6)
      ScrollView {
        VStack(alignment: .leading, spacing: 0) {
          if lib.folders.isEmpty {
            Text(L("make_a_folder_for_each_course")).font(TaliType.bodySmall).foregroundStyle(c.inkFaint)
              .padding(.horizontal, 10).padding(.vertical, 6)
            Button(L("new_folder")) { onNewFolder(nil) }.font(TaliType.labelLarge).foregroundStyle(c.accent)
              .padding(.horizontal, 10).padding(.vertical, 6)
          }
          ForEach(tree, id: \.folder.id) { f, depth in folderRow(f).padding(.leading, CGFloat(depth) * 16) }
        }
      }
      .scrollIndicators(.hidden)
      .slidingClip(in: nav)
      if !lib.trash.isEmpty {
        NavRow(label: L("recently_deleted"), count: lib.trash.count, selected: lib.shelf == .trash, nav: nav, key: Shelf.trash) {
          Image(systemName: "trash").font(.system(size: 16)).foregroundStyle(lib.shelf == .trash ? c.blue : c.inkMuted)
        } action: { pick(.trash) }
        .accessibilityIdentifier("shelf-trash")
        Spacer().frame(height: 4)
      }
      Button {
        onPicked()
        onSettings()
      } label: {
        HStack(spacing: 10) {
          Image(systemName: "gearshape").font(.system(size: 16)).foregroundStyle(c.inkMuted).frame(width: 18)
          Text(L("settings")).font(TaliType.labelLarge).foregroundStyle(c.inkMuted)
          Spacer()
        }
        .padding(10).contentShape(RoundedRectangle(cornerRadius: 14))
      }
      .buttonStyle(.plain)
      .accessibilityIdentifier("settings")
      Button {
        onPicked()
        onBackups()
      } label: {
        HStack(spacing: 8) {
          Image(systemName: "checkmark.circle").font(.system(size: 15)).foregroundStyle(c.blue)
          VStack(alignment: .leading, spacing: 1) {
            Text(L("saved_on_this_tablet")).font(TaliType.labelMedium).foregroundStyle(c.inkMuted)
            Text(L("tap_for_backups")).font(TaliType.bodySmall).foregroundStyle(c.inkFaint)
          }
          Spacer()
          Image(systemName: "chevron.forward").font(.system(size: 13)).foregroundStyle(c.inkFaint)
        }
        .padding(10).contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .accessibilityIdentifier("backups")
      .padding(.bottom, 10)
    }
    .padding(.horizontal, 18)
    .slidingHighlight(nav, selected: lib.shelf, fill: .across([c.lilac, c.sky]), corner: 14)
  }

  private func folderRow(_ f: Folder) -> some View {
    let selected = lib.shelf == .folder(f.id)
    let tint = Color(argb: f.color)
    let hasChildren = lib.folders.contains { $0.parentId == f.id }
    let expanded = !collapsed.contains(f.id) || openPath.contains(f.id)
    return NavRow(
      label: f.name, count: lib.count(in: f.id, deep: true), selected: selected, nav: nav, key: Shelf.folder(f.id),
      fill: .across(folderWashColors(tint, dark: c.isDark)), clipped: true, trailing: hasChildren
    ) {
      FolderGlyph(open: selected).fill(tint, style: FillStyle(eoFill: true)).frame(width: 20, height: 20)
    } action: {
      pick(.folder(f.id))
    } more: {
      Button {
        withAnimation(Ease.outStrong(duration: 0.24)) {
          if collapsed.contains(f.id) { collapsed.remove(f.id) } else { collapsed.insert(f.id) }
        }
      } label: {
        Image(systemName: "chevron.down").font(.system(size: 12, weight: .semibold)).foregroundStyle(c.inkFaint)
          .rotationEffect(.degrees(expanded ? 0 : -90))
          .environment(\.layoutDirection, .leftToRight)
          .scaleEffect(x: rtl && !expanded ? -1 : 1)
          .frame(width: 28, height: 28).contentShape(Circle())
      }
      .buttonStyle(.plain)
      .accessibilityLabel(expanded ? L("fold") : L("unfold"))
    }
    .contextMenu {
      FolderMenu(
        folder: f, onNewFolder: { onNewFolder(f.id) }, onRename: { onRenameFolder(f) }, onMove: { onMoveFolder(f) },
        onRecolor: { lib.recolorFolder(f.id, $0) }, onDelete: { onDeleteFolder(f) })
    }
    .puffBox(leaving: vanishing.contains(f.id), appearing: fresh.contains(f.id))
    .accessibilityIdentifier("sidebar-folder-\(f.name)")
  }

  @Environment(\.layoutDirection) private var direction
  private var rtl: Bool { direction == .rightToLeft }

  private func pick(_ s: Shelf) {
    lib.shelf = s
    onPicked()
  }

  private var openPath: Set<String> {
    guard case .folder(let id) = lib.shelf else { return [] }
    return Set(FolderTree.path(to: id, in: lib.folders).map(\.id))
  }

  /// Folders in tree order; ones inside a folded folder are hidden, unless the open folder is there.
  private var tree: [(folder: Folder, depth: Int)] {
    let path = openPath
    return FolderTree.ordered(lib.folders).filter { f, _ in
      !FolderTree.path(to: f.parentId, in: lib.folders).contains { collapsed.contains($0.id) && !path.contains($0.id) }
    }
  }
}

/// Mixes two colours ([t] of the way from [a] to [b]).
func mix(_ a: Color, _ b: Color, _ t: CGFloat) -> Color {
  let x = UIColor(a), y = UIColor(b)
  var r1: CGFloat = 0, g1: CGFloat = 0, b1: CGFloat = 0, a1: CGFloat = 0
  var r2: CGFloat = 0, g2: CGFloat = 0, b2: CGFloat = 0, a2: CGFloat = 0
  x.getRed(&r1, green: &g1, blue: &b1, alpha: &a1)
  y.getRed(&r2, green: &g2, blue: &b2, alpha: &a2)
  let r: CGFloat = r1 + (r2 - r1) * t
  let g: CGFloat = g1 + (g2 - g1) * t
  let bl: CGFloat = b1 + (b2 - b1) * t
  let al: CGFloat = a1 + (a2 - a1) * t
  return Color(red: r, green: g, blue: bl, opacity: al)
}

/// "Tali's Notes" with a lilac highlighter swipe behind "Notes".
struct Wordmark: View {
  @Environment(\.tali) private var c
  var body: some View {
    Text(L("tali_s_notes")).font(TaliType.headlineMedium).tracking(-0.28).foregroundStyle(c.ink)
      .background {
        GeometryReader { g in
          let w = g.size.width
          let h = g.size.height * 0.42
          let top = g.size.height * 0.52
          let left = g.size.width * 0.44
          Path { p in
            p.move(to: CGPoint(x: left, y: top + h * 0.15))
            p.addLine(to: CGPoint(x: w + 6, y: top))
            p.addLine(to: CGPoint(x: w + 4, y: top + h))
            p.addLine(to: CGPoint(x: left - 2, y: top + h * 1.05))
            p.closeSubpath()
          }
          .fill(LinearGradient(colors: [c.lilac, c.sky], startPoint: .leading, endPoint: .trailing))
        }
      }
  }
}

/// A sidebar row (Android's `NavRow`): icon, label, count, and a fold arrow for a folder with
/// folders inside. It has no background of its own: the sidebar's gliding highlight sits under the
/// one picked.
struct NavRow<Icon: View, More: View>: View {
  var label: String
  var count: Int
  var selected: Bool
  var nav: Namespace.ID
  var key: Shelf
  var fill: SlideFill? = nil
  var clipped = false
  var trailing = false
  @ViewBuilder var icon: Icon
  var action: () -> Void
  @ViewBuilder var more: More
  @Environment(\.tali) private var c

  var body: some View {
    HStack(spacing: 0) {
      icon.frame(width: 20, height: 20)
      Spacer().frame(width: 12)
      Text(label).font(TaliType.titleSmall).foregroundStyle(selected ? c.ink : c.inkMuted).lineLimit(1)
        .animation(.easeOut(duration: 0.22), value: selected)
      Spacer(minLength: 4)
      Text("\(count)").font(TaliType.labelMedium).foregroundStyle(c.inkFaint)
      if trailing {
        Spacer().frame(width: 2)
        more
      }
    }
    .padding(.leading, 12).padding(.trailing, trailing ? 4 : 12)
    .frame(height: 44)
    .contentShape(RoundedRectangle(cornerRadius: 14))
    .onTapGesture(perform: action)
    .slidingOption(key, in: nav, fill: fill, clipped: clipped)
    .accessibilityElement(children: .contain)
    .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
  }
}

extension NavRow where More == EmptyView {
  init(label: String, count: Int, selected: Bool, nav: Namespace.ID, key: Shelf, @ViewBuilder icon: () -> Icon, action: @escaping () -> Void) {
    self.init(label: label, count: count, selected: selected, nav: nav, key: key, icon: icon, action: action, more: { EmptyView() })
  }
}

/// A notebook in the library (Android's `NotebookCard`): a landscape card of its first page with a
/// cover-colour spine stitched in white, a gold star chip when starred, then its name and when it
/// was edited.
struct NotebookCard: View {
  var notebook: NotebookMeta
  var starred: Bool
  var inTrash: Bool
  var picking = false
  var picked = false
  @Environment(\.tali) private var c

  @Environment(\.layoutDirection) private var direction

  var body: some View {
    let document = notebook.kind != .notebook
    let rtl = direction == .rightToLeft
    // A PDF, picture or scan is a sheet with a folded corner; a notebook has a spine.
    let shape = document ? AnyShape(DogEarShape(radius: 18, fold: dogEar, rtl: rtl)) : AnyShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    VStack(alignment: .leading, spacing: 0) {
      ZStack(alignment: .topLeading) {
        if let thumb = ThumbnailCache.shared.image(id: notebook.id, version: notebook.thumbVersion) {
          // Its first page with the writing on it, from the top (Android's crop, top centre).
          Color.clear.overlay(alignment: .top) { Image(uiImage: thumb).resizable().scaledToFill() }.clipped()
        } else {
          PaperPreview(
            style: notebook.paper, landscape: notebook.landscape, dark: notebook.dark, zoom: 1, custom: PaperSettings.shared.custom(notebook.customPaper))
        }
        if document {
          // The folded-over corner, and what it is (PDF, picture, scan) in a small badge.
          Canvas { ctx, size in
            let w = size.width
            var flap = Path()
            if rtl {
              flap.move(to: CGPoint(x: w, y: 0))
              flap.addLine(to: CGPoint(x: w, y: w))
              flap.addLine(to: CGPoint(x: 0, y: w))
            } else {
              flap.move(to: .zero)
              flap.addLine(to: CGPoint(x: 0, y: w))
              flap.addLine(to: CGPoint(x: w, y: w))
            }
            flap.closeSubpath()
            ctx.fill(flap, with: .color(c.sunken))
            ctx.stroke(flap, with: .color(c.line), lineWidth: 1)
          }
          .frame(width: dogEar, height: dogEar)
          .frame(maxWidth: .infinity, alignment: .topTrailing)
          KindBadge(kind: notebook.kind).padding(8)
        } else {
          Rectangle().fill(Color(argb: notebook.cover)).frame(width: 9)
          Canvas { ctx, size in
            var y: CGFloat = 6
            while y < size.height {
              ctx.fill(Path(roundedRect: CGRect(x: size.width / 2 - 0.75, y: y, width: 1.5, height: 5), cornerRadius: 1), with: .color(.white.opacity(0.55)))
              y += 11
            }
          }
          .frame(width: 9)
        }
      }
      .frame(maxWidth: .infinity)
      .aspectRatio(1.32, contentMode: .fit)
      .background(c.paper)
      .clipShape(shape)
      .overlay(shape.stroke(picked ? c.accent : c.line, lineWidth: picked ? 2.5 : 1))
      .overlay(alignment: .topTrailing) {
        if picking {
          ZStack {
            Circle().fill(picked ? c.accent : Color.white.opacity(0.85))
            Circle().stroke(picked ? c.accent : c.inkFaint, lineWidth: 1.5)
            if picked { Image(systemName: "checkmark").font(.system(size: 13, weight: .bold)).foregroundStyle(.white) }
          }
          .frame(width: 28, height: 28)
          .shadow(color: .black.opacity(0.15), radius: 3, y: 1)
          .padding(10)
          .transition(.scale(scale: 0.7).combined(with: .opacity))
        }
      }
      .animation(Ease.outStrong(duration: 0.2), value: picking)
      .overlay(alignment: .bottomTrailing) {
        if starred && !inTrash {
          Image(systemName: "star.fill").font(.system(size: 13)).foregroundStyle(starGold)
            .frame(width: 26, height: 26).background(Circle().fill(c.surface.opacity(0.92)).shadow(color: .black.opacity(0.12), radius: 2, y: 1))
            .padding(8)
            .transition(.scale(scale: 0.6).combined(with: .opacity))
        }
      }
      .animation(.spring(response: 0.3, dampingFraction: 0.5), value: starred)
      .shadow(color: c.accent.opacity(0.2), radius: 12, x: 0, y: 6)
      .scaleEffect(picked ? 0.955 : 1)
      Spacer().frame(height: 10)
      Text(notebook.title).font(TaliType.titleMedium).foregroundStyle(c.ink).lineLimit(1).padding(.leading, 2)
      // A PDF, picture or scan says what it is first: "PDF · Edited 3 h ago".
      Text(document ? L("n_n_2", KindBadge.label(notebook.kind), subtitle) : subtitle).font(TaliType.bodySmall).foregroundStyle(c.inkFaint).lineLimit(1)
        .padding(.leading, 2)
    }
    .contentShape(Rectangle())
    .accessibilityElement(children: .combine)
    .accessibilityIdentifier("notebook-\(notebook.title)")
  }

  /// How far a PDF's, picture's or scan's corner is folded over.
  private let dogEar: CGFloat = 24

  private var subtitle: String {
    let millis = inTrash ? (notebook.deleted ?? notebook.updated) : notebook.updated
    let word = relativeTime(millis)
    return (inTrash ? L("deleted") : L("edited")) + word.prefix(1).lowercased() + word.dropFirst()
  }
}

/// A card's outline with rounded corners, except the top one at the end (right, or left in Hebrew
/// and Arabic), which is cut off where the corner is folded over (Android's `DogEarShape`).
struct DogEarShape: Shape {
  var radius: CGFloat
  var fold: CGFloat
  var rtl = false

  func path(in rect: CGRect) -> Path {
    let r = radius, f = fold, w = rect.width, h = rect.height
    var p = Path()
    p.move(to: CGPoint(x: r, y: 0))
    p.addLine(to: CGPoint(x: w - f, y: 0))
    p.addLine(to: CGPoint(x: w, y: f))
    p.addLine(to: CGPoint(x: w, y: h - r))
    p.addQuadCurve(to: CGPoint(x: w - r, y: h), control: CGPoint(x: w, y: h))
    p.addLine(to: CGPoint(x: r, y: h))
    p.addQuadCurve(to: CGPoint(x: 0, y: h - r), control: CGPoint(x: 0, y: h))
    p.addLine(to: CGPoint(x: 0, y: r))
    p.addQuadCurve(to: CGPoint(x: r, y: 0), control: .zero)
    p.closeSubpath()
    let mirrored = rtl ? p.applying(CGAffineTransform(scaleX: -1, y: 1).translatedBy(x: -w, y: 0)) : p
    return mirrored.offsetBy(dx: rect.minX, dy: rect.minY)
  }
}

/// "Just now", "5 min ago", "3 h ago", "Yesterday", or the date (Android's `relativeTime`).
func relativeTime(_ millis: Int64) -> String {
  let diff = nowMillis() - millis
  let minute: Int64 = 60_000
  let hour = 60 * minute
  let day = 24 * hour
  if diff < minute { return L("just_now") }
  if diff < hour { return L("n_min_ago", diff / minute) }
  if diff < day { return L("n_h_ago", diff / hour) }
  if diff < 2 * day { return L("yesterday") }
  return Date(timeIntervalSince1970: TimeInterval(millis) / 1000).formatted(.dateTime.day().month(.abbreviated))
}

/// Presses in a little, quickly.
struct PressStyle: ButtonStyle {
  var scale: CGFloat = 0.96
  func makeBody(configuration: Configuration) -> some View {
    configuration.label.scaleEffect(configuration.isPressed ? scale : 1)
      .animation(.easeOut(duration: configuration.isPressed ? 0.09 : 0.16), value: configuration.isPressed)
  }
}

/// The main action (Android's `PrimaryButton`): 48 pt, 16 pt corners, violet to blue.
struct PrimaryButtonStyle: ButtonStyle {
  @Environment(\.tali) private var c
  func makeBody(configuration: Configuration) -> some View {
    configuration.label.font(TaliType.labelLarge).foregroundStyle(c.onAccent).lineLimit(1).fixedSize(horizontal: true, vertical: false)
      .padding(.horizontal, 20).frame(minHeight: 48)
      .background(RoundedRectangle(cornerRadius: 16).fill(c.accentGradient))
      .scaleEffect(configuration.isPressed ? 0.96 : 1)
      .animation(.easeOut(duration: configuration.isPressed ? 0.09 : 0.16), value: configuration.isPressed)
  }
}

/// A soft lilac button with accent text (Android's `QuietButton`): 44 pt, 14 pt corners, no outline;
/// in light mode the wash is a touch deeper so it shows on the pale sky.
struct QuietButtonStyle: ButtonStyle {
  var warning = false
  @Environment(\.tali) private var c
  func makeBody(configuration: Configuration) -> some View {
    let wash = warning ? c.danger.opacity(c.isDark ? 0.12 : 0.15) : (c.isDark ? c.accentSoft : mix(c.accentSoft, c.accent, 0.12))
    configuration.label.font(TaliType.labelLarge).foregroundStyle(warning ? c.danger : c.accent).lineLimit(1).fixedSize(horizontal: true, vertical: false)
      .padding(.horizontal, 18).frame(minHeight: 44)
      .background(RoundedRectangle(cornerRadius: 14).fill(wash))
      .scaleEffect(configuration.isPressed ? 0.96 : 1)
      .animation(.easeOut(duration: configuration.isPressed ? 0.09 : 0.16), value: configuration.isPressed)
  }
}


/// What a PDF, picture or scan is, on its card (Android's `KindBadge`, `kindTint`, `kindIcon`).
struct KindBadge: View {
  var kind: DocKind
  @Environment(\.tali) private var c

  static func tint(_ kind: DocKind, dark: Bool) -> Color {
    switch kind {
    case .notebook: Color(argb: 0xFF7A_4ED6)
    case .pdf: Color(argb: dark ? 0xFFFF_8E8A : 0xFFD9_443F)
    case .picture: Color(argb: dark ? 0xFFF2_A0C4 : 0xFFC9_3B7A)
    case .scan: Color(argb: dark ? 0xFF6F_D3B5 : 0xFF1C_8466)
    }
  }

  static func label(_ kind: DocKind) -> String {
    switch kind {
    case .notebook: L("notebook")
    case .pdf: "PDF"
    case .picture: L("picture")
    case .scan: L("add_scan")
    }
  }

  private var icon: String {
    switch kind {
    case .notebook: "book.closed"
    case .pdf: "doc.richtext"
    case .picture: "photo"
    case .scan: "doc.viewfinder"
    }
  }

  var body: some View {
    let tint = KindBadge.tint(kind, dark: c.isDark)
    HStack(spacing: 4) {
      Image(systemName: icon).font(.system(size: 11, weight: .semibold))
      Text(KindBadge.label(kind)).font(TaliType.labelMedium)
    }
    .foregroundStyle(tint)
    .padding(.leading, 6).padding(.trailing, 8).padding(.vertical, 3)
    .background(RoundedRectangle(cornerRadius: 10).fill(c.surface.opacity(0.92)))
    .overlay(RoundedRectangle(cornerRadius: 10).stroke(tint.opacity(0.25), lineWidth: 1))
  }
}
