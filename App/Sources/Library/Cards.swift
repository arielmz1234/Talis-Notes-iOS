import SwiftUI
import TaliCore

/// The library's left side: the app's name, All notebooks, Starred, Recently deleted, then folders.
struct Sidebar: View {
  @Environment(Library.self) private var lib
  @Environment(\.tali) private var c
  var onNewFolder: () -> Void
  var onPicked: () -> Void
  var onBackups: () -> Void = {}
  @AppStorage("minimal") private var minimal = false

  var body: some View {
    VStack(alignment: .leading, spacing: 4) {
      Text(L("app_name")).font(TaliFont.heading(26)).foregroundStyle(c.ink)
        .padding(.horizontal, 12).padding(.top, minimal ? 44 : 120).padding(.bottom, 18)
      row(.all, L("all_notebooks"), "books.vertical", count: lib.notebooks.count)
      row(.starred, L("starred_notebooks"), "star", count: lib.notebooks.filter { lib.starred.contains($0.id) }.count)
      row(.trash, L("recently_deleted"), "trash", count: lib.trash.count)
      HStack {
        Text(L("folders")).font(TaliFont.body(13, .bold)).foregroundStyle(c.inkFaint).textCase(.uppercase)
        Spacer()
        Button(action: onNewFolder) { Image(systemName: "folder.badge.plus").foregroundStyle(c.accent) }
          .accessibilityLabel(L("new_folder"))
      }
      .padding(.horizontal, 12).padding(.top, 22).padding(.bottom, 6)
      ScrollView {
        VStack(alignment: .leading, spacing: 2) {
          ForEach(tree, id: \.0.id) { f, depth in
            row(.folder(f.id), f.name, "folder.fill", count: lib.notebooks.filter { $0.folderId == f.id }.count, tint: Color(argb: f.color))
              .padding(.leading, CGFloat(depth) * 16)
          }
        }
      }
      Spacer(minLength: 0)
      Button {
        onPicked()
        onBackups()
      } label: {
        HStack(spacing: 12) {
          Image(systemName: "externaldrive.badge.icloud").frame(width: 22).foregroundStyle(c.inkMuted)
          Text(L("backups")).font(TaliFont.body(16)).foregroundStyle(c.inkMuted)
          Spacer()
        }
        .padding(.horizontal, 12).frame(height: 44).contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .accessibilityIdentifier("backups")
      .padding(.bottom, 12)
    }
    .padding(.horizontal, 12)
    .frame(maxHeight: .infinity, alignment: .top)
    .background(LinearGradient(colors: [c.sidebar, c.sidebarEnd], startPoint: .top, endPoint: .bottom).ignoresSafeArea())
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

  private func row(_ shelf: Shelf, _ title: String, _ icon: String, count: Int, tint: Color? = nil) -> some View {
    let on = lib.shelf == shelf
    return Button {
      withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) { lib.shelf = shelf }
      onPicked()
    } label: {
      HStack(spacing: 12) {
        Image(systemName: icon).frame(width: 22).foregroundStyle(tint ?? (on ? c.accent : c.inkMuted))
        Text(title).font(TaliFont.body(16, on ? .semibold : .regular)).foregroundStyle(on ? c.ink : c.inkMuted).lineLimit(1)
        Spacer(minLength: 4)
        if count > 0 { Text("\(count)").font(TaliFont.body(13)).foregroundStyle(c.inkFaint) }
      }
      .padding(.horizontal, 12).frame(height: 44)
      .background {
        if on {
          RoundedRectangle(cornerRadius: 14).fill(c.surface.opacity(c.isDark ? 0.5 : 0.9))
            .shadow(color: c.glow.opacity(0.10), radius: 8, y: 3)
        }
      }
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
  }
}

/// A notebook in the library: its first page with a cover-colour spine, then its name and when it
/// was edited. A PDF, picture or scan shows as a sheet with a folded corner instead.
struct NotebookCard: View {
  var notebook: NotebookMeta
  var starred: Bool
  var inTrash: Bool
  @Environment(\.tali) private var c
  @Environment(\.layoutDirection) private var direction

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      ZStack(alignment: .bottomTrailing) {
        HStack(spacing: 0) {
          if notebook.kind == .notebook {
            Rectangle().fill(Color(argb: notebook.cover)).frame(width: 12)
          }
          PaperPreview(style: notebook.paper, landscape: notebook.landscape, dark: notebook.dark, zoom: notebook.landscape ? 1 : 1.25)
        }
        .aspectRatio(0.78, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(c.line, lineWidth: 1))
        .shadow(color: c.glow.opacity(c.isDark ? 0.4 : 0.14), radius: 12, x: 0, y: 6)
        if starred {
          Image(systemName: "star.fill").font(.system(size: 13)).foregroundStyle(c.amber).padding(8)
        }
      }
      Text(notebook.title).font(TaliFont.body(16, .semibold)).foregroundStyle(c.ink).lineLimit(2)
      Text(subtitle).font(TaliFont.body(13)).foregroundStyle(c.inkFaint).lineLimit(1)
    }
    .contentShape(Rectangle())
    .accessibilityElement(children: .combine)
    .accessibilityIdentifier("notebook-\(notebook.title)")
  }

  private var subtitle: String {
    let when = Date(timeIntervalSince1970: TimeInterval((inTrash ? notebook.deleted ?? notebook.updated : notebook.updated)) / 1000)
    let day: String
    if Calendar.current.isDateInToday(when) {
      day = when.formatted(date: .omitted, time: .shortened)
    } else if Calendar.current.isDateInYesterday(when) {
      day = L("yesterday")
    } else {
      day = when.formatted(.dateTime.day().month(.abbreviated))
    }
    return L("edited") + day
  }
}

struct FolderCard: View {
  var folder: Folder
  var count: Int
  @Environment(\.tali) private var c

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      ZStack {
        RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color(argb: folder.color).opacity(c.isDark ? 0.35 : 0.22))
        Image(systemName: "folder.fill").font(.system(size: 54)).foregroundStyle(Color(argb: folder.color))
      }
      .aspectRatio(0.78, contentMode: .fit)
      Text(folder.name).font(TaliFont.body(16, .semibold)).foregroundStyle(c.ink).lineLimit(2)
      Text(L("n_notebooks", count)).font(TaliFont.body(13)).foregroundStyle(c.inkFaint)
    }
    .contentShape(Rectangle())
    .accessibilityElement(children: .combine)
  }
}

/// Presses in a little, quickly.
struct PressStyle: ButtonStyle {
  func makeBody(configuration: Configuration) -> some View {
    configuration.label.scaleEffect(configuration.isPressed ? 0.96 : 1)
      .animation(.easeOut(duration: configuration.isPressed ? 0.08 : 0.18), value: configuration.isPressed)
  }
}

/// The violet-to-blue pill for the main action.
struct PrimaryButtonStyle: ButtonStyle {
  @Environment(\.tali) private var c
  func makeBody(configuration: Configuration) -> some View {
    configuration.label.font(TaliFont.body(16, .semibold)).foregroundStyle(c.onAccent)
      .padding(.horizontal, 22).frame(minHeight: 46)
      .background(Capsule().fill(c.accentGradient))
      .scaleEffect(configuration.isPressed ? 0.96 : 1)
      .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
  }
}

/// A soft lilac pill with accent text (Android's `QuietButton`).
struct QuietButtonStyle: ButtonStyle {
  var warning = false
  @Environment(\.tali) private var c
  func makeBody(configuration: Configuration) -> some View {
    configuration.label.font(TaliFont.body(16, .semibold)).foregroundStyle(warning ? c.danger : c.accent)
      .padding(.horizontal, 20).frame(minHeight: 44)
      .background(Capsule().fill(warning ? c.danger.opacity(0.12) : c.accentSoft))
      .scaleEffect(configuration.isPressed ? 0.96 : 1)
      .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
  }
}
