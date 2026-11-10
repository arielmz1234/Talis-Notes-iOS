import SwiftUI
import TaliCore

let starGold = Color(argb: 0xFFF5_B83D)

/// The library's left side, as Android's `Sidebar`: no panel of its own (it shares the sky and page),
/// the wordmark, All notebooks and Starred, then folders, Recently deleted (only when something's
/// in it), Settings and the backup status.
struct Sidebar: View {
  @Environment(Library.self) private var lib
  @Environment(\.tali) private var c
  var onNewFolder: () -> Void
  var onPicked: () -> Void
  var onBackups: () -> Void = {}
  var onSettings: () -> Void = {}
  @AppStorage("minimal") private var minimal = false

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Spacer().frame(height: minimal ? 44 : 120)
      Wordmark().padding(.leading, 8)
      Spacer().frame(height: 30)
      NavRow(
        icon: "book.pages", iconTint: lib.shelf == .all ? c.blue : c.inkMuted, label: L("all_notebooks"), count: lib.notebooks.count,
        selected: lib.shelf == .all
      ) { pick(.all) }
      Spacer().frame(height: 4)
      NavRow(
        icon: lib.shelf == .starred ? "star.fill" : "star", iconTint: lib.shelf == .starred ? starGold : c.inkMuted, label: L("starred_notebooks"),
        count: lib.notebooks.filter { lib.starred.contains($0.id) }.count, selected: lib.shelf == .starred
      ) { pick(.starred) }
      Spacer().frame(height: 22)
      HStack {
        SectionLabel(text: L("folders"))
        Button(action: onNewFolder) {
          Image(systemName: "plus").font(.system(size: 15)).foregroundStyle(c.inkMuted).frame(width: 30, height: 30).contentShape(Circle())
        }
        .accessibilityLabel(L("new_folder"))
      }
      .padding(.leading, 10)
      Spacer().frame(height: 6)
      ScrollView {
        VStack(alignment: .leading, spacing: 0) {
          if lib.folders.isEmpty {
            Text(L("make_a_folder_for_each_course")).font(TaliType.bodySmall).foregroundStyle(c.inkFaint)
              .padding(.horizontal, 10).padding(.vertical, 6)
            Button(L("new_folder"), action: onNewFolder).font(TaliType.labelLarge).foregroundStyle(c.accent)
              .padding(.horizontal, 10).padding(.vertical, 6)
          }
          ForEach(tree, id: \.0.id) { f, depth in
            NavRow(
              icon: "folder", iconTint: Color(argb: f.color), label: f.name,
              count: lib.notebooks.filter { $0.folderId == f.id }.count, selected: lib.shelf == .folder(f.id), wash: folderWash(Color(argb: f.color))
            ) { pick(.folder(f.id)) }
            .padding(.leading, CGFloat(depth) * 16)
          }
        }
      }
      .scrollIndicators(.hidden)
      if !lib.trash.isEmpty {
        NavRow(icon: "trash", iconTint: lib.shelf == .trash ? c.blue : c.inkMuted, label: L("recently_deleted"), count: lib.trash.count, selected: lib.shelf == .trash) {
          pick(.trash)
        }
        Spacer().frame(height: 4)
      }
      Button {
        onPicked()
        onSettings()
      } label: {
        HStack(spacing: 10) {
          Image(systemName: "gearshape").font(.system(size: 16)).foregroundStyle(c.inkMuted)
          Text(L("settings")).font(TaliType.labelLarge).foregroundStyle(c.inkMuted)
          Spacer()
        }
        .padding(10).contentShape(Rectangle())
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
  }

  private func pick(_ s: Shelf) {
    withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) { lib.shelf = s }
    onPicked()
  }

  /// Folders in order, each followed by the ones inside it.
  private var tree: [(Folder, Int)] {
    var out: [(Folder, Int)] = []
    func add(_ parent: String?, _ depth: Int) {
      for f in lib.folders where f.parentId == parent {
        out.append((f, depth))
        if depth < 8 { add(f.id, depth + 1) }
      }
    }
    add(nil, 0)
    return out
  }

  /// The soft gradient behind a selected folder, in its own colour.
  private func folderWash(_ color: Color) -> LinearGradient {
    let from = c.isDark ? color.opacity(0.42) : mix(.white, color, 0.42)
    let to = c.isDark ? color.opacity(0.14) : mix(.white, color, 0.14)
    return LinearGradient(colors: [from, to], startPoint: .leading, endPoint: .trailing)
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

/// A sidebar row: icon, label, count; the one picked sits on a soft lilac-to-sky wash.
struct NavRow: View {
  var icon: String
  var iconTint: Color
  var label: String
  var count: Int
  var selected: Bool
  var wash: LinearGradient? = nil
  var action: () -> Void
  @Environment(\.tali) private var c

  var body: some View {
    Button(action: action) {
      HStack(spacing: 12) {
        Image(systemName: icon).font(.system(size: 17)).foregroundStyle(iconTint).frame(width: 20)
        Text(label).font(TaliType.titleSmall).foregroundStyle(selected ? c.ink : c.inkMuted).lineLimit(1)
        Spacer(minLength: 4)
        Text("\(count)").font(TaliType.labelMedium).foregroundStyle(c.inkFaint)
      }
      .padding(.horizontal, 12)
      .frame(height: 44)
      .background {
        if selected {
          RoundedRectangle(cornerRadius: 14).fill(wash ?? LinearGradient(colors: [c.lilac, c.sky], startPoint: .leading, endPoint: .trailing))
            .transition(.opacity)
        }
      }
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
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

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      ZStack(alignment: .topLeading) {
        if let thumb = ThumbnailCache.shared.image(id: notebook.id, version: notebook.thumbVersion) {
          // Its first page with the writing on it, from the top (Android's crop, top centre).
          Color.clear.overlay(alignment: .top) { Image(uiImage: thumb).resizable().scaledToFill() }.clipped()
        } else {
          PaperPreview(style: notebook.paper, landscape: notebook.landscape, dark: notebook.dark, zoom: 1)
        }
        if notebook.kind == .notebook {
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
      .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
      .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(picked ? c.accent : c.line, lineWidth: picked ? 2.5 : 1))
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
      .overlay(alignment: .bottomTrailing) {
        if starred && !inTrash {
          Image(systemName: "star.fill").font(.system(size: 13)).foregroundStyle(starGold)
            .frame(width: 26, height: 26).background(Circle().fill(c.surface.opacity(0.92)).shadow(color: .black.opacity(0.12), radius: 2, y: 1))
            .padding(8)
        }
      }
      .shadow(color: c.accent.opacity(0.2), radius: 12, x: 0, y: 6)
      .scaleEffect(picked ? 0.955 : 1)
      Spacer().frame(height: 10)
      Text(notebook.title).font(TaliType.titleMedium).foregroundStyle(c.ink).lineLimit(1).padding(.leading, 2)
      Text(subtitle).font(TaliType.bodySmall).foregroundStyle(c.inkFaint).lineLimit(1).padding(.leading, 2)
    }
    .contentShape(Rectangle())
    .accessibilityElement(children: .combine)
    .accessibilityIdentifier("notebook-\(notebook.title)")
  }

  private var subtitle: String {
    let millis = inTrash ? (notebook.deleted ?? notebook.updated) : notebook.updated
    let word = relativeTime(millis)
    return (inTrash ? L("deleted") : L("edited")) + word.prefix(1).lowercased() + word.dropFirst()
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

/// A folder inside the open folder (Android's `FolderTile`): a 76 pt row tinted with its colour.
struct FolderTile: View {
  var folder: Folder
  var count: Int
  var inner: Int
  @Environment(\.tali) private var c

  var body: some View {
    let tint = Color(argb: folder.color)
    let notebooks = count == 1 ? L("t_1_notebook") : L("n_notebooks", count)
    let folders: String? = inner == 0 ? nil : (inner == 1 ? L("t_1_folder_2") : L("n_folders_2", inner))
    HStack(spacing: 12) {
      Image(systemName: "folder").font(.system(size: 26)).foregroundStyle(tint)
      VStack(alignment: .leading, spacing: 0) {
        Text(folder.name).font(TaliType.titleMedium).foregroundStyle(c.ink).lineLimit(1)
        Text([notebooks, folders].compactMap { $0 }.joined(separator: " · ")).font(TaliType.bodySmall).foregroundStyle(c.inkFaint)
      }
      Spacer(minLength: 0)
    }
    .padding(.horizontal, 16)
    .frame(height: 76)
    .background(
      RoundedRectangle(cornerRadius: 18).fill(c.surface)
        .overlay(RoundedRectangle(cornerRadius: 18).fill(LinearGradient(colors: [tint.opacity(0.22), tint.opacity(0.06)], startPoint: .leading, endPoint: .trailing)))
    )
    .overlay(RoundedRectangle(cornerRadius: 18).stroke(c.line, lineWidth: 1))
    .shadow(color: c.accent.opacity(0.16), radius: 8, y: 4)
    .contentShape(Rectangle())
  }
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
    configuration.label.font(TaliType.labelLarge).foregroundStyle(c.onAccent)
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
    configuration.label.font(TaliType.labelLarge).foregroundStyle(warning ? c.danger : c.accent)
      .padding(.horizontal, 18).frame(minHeight: 44)
      .background(RoundedRectangle(cornerRadius: 14).fill(wash))
      .scaleEffect(configuration.isPressed ? 0.96 : 1)
      .animation(.easeOut(duration: configuration.isPressed ? 0.09 : 0.16), value: configuration.isPressed)
  }
}
