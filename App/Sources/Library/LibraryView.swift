import SwiftUI
import TaliCore

/// The library: a sidebar of shelves and folders, the sky with its clouds, a greeting and heading,
/// search and sort, then the notebooks. On a phone the sidebar is a drawer (☰).
struct LibraryView: View {
  @Environment(Library.self) private var lib
  @Environment(\.tali) private var c
  var onOpen: (NotebookMeta) -> Void
  @State private var creating = false
  @State private var drawer = false
  @State private var renaming: NotebookMeta?
  @State private var moving: NotebookMeta?
  @State private var deleting: NotebookMeta?
  @State private var newFolder = false
  @State private var backups = false

  var body: some View {
    GeometryReader { geo in
      let phone = geo.size.width < Layout.phoneWidth
      ZStack(alignment: .topLeading) {
        c.background.ignoresSafeArea()
        HStack(spacing: 0) {
          if !phone {
            Sidebar(onNewFolder: { newFolder = true }, onPicked: {}, onBackups: { backups = true })
              .frame(width: 264)
          }
          main(width: phone ? geo.size.width : geo.size.width - 264, phone: phone)
        }
        if phone { drawerLayer }
      }
    }
    .sheet(isPresented: $creating) {
      NewNotebookCard { title, paper, pages, landscape, cover in
        let n = lib.create(title: title, paper: paper, pages: pages, landscape: landscape, cover: cover)
        creating = false
        onOpen(n)
      }
      .presentationDetents([.large])
    }
    .sheet(isPresented: $backups) { BackupCard() }
    .alert(L("rename"), isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } }), presenting: renaming) { n in
      RenameField(initial: n.title) { lib.rename(n.id, to: $0) }
    }
    .alert(L("new_folder"), isPresented: $newFolder) {
      RenameField(initial: "") { name in
        let parent: String? = if case .folder(let id) = lib.shelf { id } else { nil }
        lib.createFolder(name: name, color: Covers.soft[lib.folders.count % Covers.soft.count], parent: parent)
      }
    }
    .confirmationDialog(
      L("move_to_folder"), isPresented: Binding(get: { moving != nil }, set: { if !$0 { moving = nil } }), presenting: moving
    ) { n in
      Button(L("no_folder")) { lib.move(n.id, to: nil) }
      ForEach(lib.folders) { f in Button(f.name) { lib.move(n.id, to: f.id) } }
    }
    .confirmationDialog(
      L("delete"), isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }), presenting: deleting
    ) { n in
      Button(L("delete"), role: .destructive) { withAnimation(.easeOut(duration: 0.22)) { lib.moveToTrash(n.id) } }
    } message: { _ in
      Text(L("it_moves_to_recently_deleted_where", trashDays))
    }
  }

  @ViewBuilder private func main(width: CGFloat, phone: Bool) -> some View {
    let side: CGFloat = phone ? 16 : 32
    ScrollView {
      ZStack(alignment: .topLeading) {
        SkyBand(height: 320)
        SkyClouds(width: width)
        VStack(alignment: .leading, spacing: 14) {
          if phone {
            Button { withAnimation(.easeOut(duration: 0.24)) { drawer = true } } label: {
              Image(systemName: "line.3.horizontal").font(.title2).foregroundStyle(c.ink).frame(width: 44, height: 44)
            }
            .accessibilityLabel(L("folders"))
          }
          GreetingLine().padding(.top, phone ? 4 : 112)
          HStack(alignment: .firstTextBaseline) {
            Text(heading).font(TaliFont.heading(phone ? 30 : 38)).foregroundStyle(c.ink).lineLimit(1).minimumScaleFactor(0.6)
            Spacer()
          }
          toolsRow(phone: phone)
          content(phone: phone)
        }
        .padding(.horizontal, side)
        .padding(.bottom, 40)
      }
    }
    .scrollIndicators(.hidden)
    .overlay(alignment: .bottomTrailing) {
      if lib.shelf != .trash {
        AddButton { creating = true }.padding(side)
      }
    }
  }

  private var heading: String {
    switch lib.shelf {
    case .all: return L("all_notebooks")
    case .starred: return L("starred_notebooks")
    case .trash: return L("recently_deleted")
    case .folder(let id): return lib.folder(id)?.name ?? L("all_notebooks")
    }
  }

  @ViewBuilder private func toolsRow(phone: Bool) -> some View {
    @Bindable var lib = lib
    HStack(spacing: 10) {
      HStack(spacing: 8) {
        Image(systemName: "magnifyingglass").foregroundStyle(c.inkFaint)
        TextField(L("search_notebooks"), text: $lib.search).font(TaliFont.body(16)).foregroundStyle(c.ink)
          .textInputAutocapitalization(.never).autocorrectionDisabled()
        if !lib.search.isEmpty {
          Button { lib.search = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(c.inkFaint) }
            .accessibilityLabel(L("clear_search"))
        }
      }
      .padding(.horizontal, 16).frame(height: 46).frame(maxWidth: 420)
      .cloudSurface(radius: 23, crown: .softEdge, shadowDepth: 4)
      SortButton()
      if lib.shelf == .trash, !lib.trash.isEmpty {
        Button(L("empty")) { lib.emptyTrash() }.buttonStyle(QuietButtonStyle(warning: true))
      }
      Spacer(minLength: 0)
    }
  }

  @ViewBuilder private func content(phone: Bool) -> some View {
    let items = lib.shown
    let folders = lib.subfolders
    let columns = [GridItem(.adaptive(minimum: phone ? 150 : 190, maximum: 260), spacing: phone ? 14 : 22, alignment: .top)]
    if items.isEmpty && folders.isEmpty {
      EmptyShelf(shelf: lib.shelf, searching: !lib.search.isEmpty, search: lib.search) { creating = true }
        .frame(maxWidth: .infinity).padding(.top, 40)
    } else {
      LazyVGrid(columns: columns, alignment: .leading, spacing: phone ? 18 : 26) {
        ForEach(folders) { f in
          FolderCard(folder: f, count: lib.notebooks.filter { $0.folderId == f.id }.count)
            .onTapGesture { withAnimation(.easeOut(duration: 0.22)) { lib.shelf = .folder(f.id) } }
            .contextMenu {
              Button(role: .destructive) { lib.deleteFolder(f.id) } label: { Label(L("delete_folder"), systemImage: "trash") }
            }
        }
        ForEach(items) { n in
          NotebookCard(notebook: n, starred: lib.starred.contains(n.id), inTrash: lib.shelf == .trash)
            .onTapGesture { if lib.shelf != .trash { onOpen(n) } }
            .contextMenu { menu(for: n) }
            .transition(.opacity.combined(with: .scale(scale: 0.93)).combined(with: .offset(y: -10)))
        }
      }
      .padding(.top, 6)
    }
  }

  @ViewBuilder private func menu(for n: NotebookMeta) -> some View {
    if lib.shelf == .trash {
      Button { lib.restore(n.id) } label: { Label(L("restore"), systemImage: "arrow.uturn.backward") }
      Button(role: .destructive) { lib.eraseForGood(n.id) } label: { Label(L("delete_forever"), systemImage: "trash") }
    } else {
      Button { onOpen(n) } label: { Label(L("open"), systemImage: "book") }
      Button { lib.toggleStar(n.id) } label: {
        Label(L(lib.starred.contains(n.id) ? "remove_star" : "star"), systemImage: lib.starred.contains(n.id) ? "star.slash" : "star")
      }
      Button { renaming = n } label: { Label(L("rename"), systemImage: "pencil") }
      Button { moving = n } label: { Label(L("move_to_folder"), systemImage: "folder") }
      Button { lib.duplicate(n.id) } label: { Label(L("duplicate"), systemImage: "plus.square.on.square") }
      Button(role: .destructive) { deleting = n } label: { Label(L("delete"), systemImage: "trash") }
    }
  }

  @ViewBuilder private var drawerLayer: some View {
    if drawer {
      c.scrim.ignoresSafeArea()
        .onTapGesture { withAnimation(.easeOut(duration: 0.2)) { drawer = false } }
        .transition(.opacity)
      Sidebar(onNewFolder: { newFolder = true }, onPicked: { withAnimation(.easeOut(duration: 0.2)) { drawer = false } }, onBackups: { backups = true })
        .frame(width: 290)
        .frame(maxHeight: .infinity)
        .background(c.sidebar)
        .transition(.move(edge: .leading))
    }
  }
}

/// "Good morning" by the device's clock (no name: other people may use the app).
struct GreetingLine: View {
  @Environment(\.tali) private var c
  var body: some View {
    TimelineView(.periodic(from: .now, by: 30)) { ctx in
      Text(L(Greeting.forHour(Calendar.current.component(.hour, from: ctx.date)).rawValue))
        .font(TaliFont.body(17, .semibold)).foregroundStyle(c.inkMuted)
    }
  }
}

/// The round + that starts a new notebook.
struct AddButton: View {
  var action: () -> Void
  @Environment(\.tali) private var c
  var body: some View {
    Button(action: action) {
      Image(systemName: "plus").font(.system(size: 26, weight: .semibold)).foregroundStyle(c.onAccent)
        .frame(width: 64, height: 64)
        .background(Circle().fill(c.accentGradient))
        .shadow(color: c.glow.opacity(0.3), radius: 12, y: 6)
    }
    .buttonStyle(PressStyle())
    .accessibilityLabel(L("new_notebook"))
    .accessibilityIdentifier("add")
  }
}

/// Sort: Last edited, Last opened, Date created, Name; picking the one in use turns it round.
struct SortButton: View {
  @Environment(Library.self) private var lib
  @Environment(\.tali) private var c
  var body: some View {
    Menu {
      ForEach(LibrarySort.allCases, id: \.self) { s in
        Button {
          if lib.sort == s { lib.sortReversed.toggle() } else {
            lib.sort = s
            lib.sortReversed = false
          }
        } label: {
          if lib.sort == s { Label(label(s), systemImage: lib.sortReversed ? "arrow.up" : "arrow.down") } else { Text(label(s)) }
        }
      }
    } label: {
      Image(systemName: "arrow.up.arrow.down").font(.system(size: 17, weight: .semibold)).foregroundStyle(c.accent)
        .frame(width: 46, height: 46).cloudSurface(radius: 23, crown: .little, shadowDepth: 4)
    }
    .accessibilityLabel(L("sort_notebooks"))
  }

  private func label(_ s: LibrarySort) -> String {
    switch s {
    case .EDITED: return L("sort_edited")
    case .OPENED: return L("sort_opened")
    case .CREATED: return L("sort_created")
    case .NAME: return L("sort_name")
    }
  }
}

struct RenameField: View {
  var initial: String
  var onDone: (String) -> Void
  @State private var text = ""
  var body: some View {
    TextField("", text: $text).onAppear { text = initial }
    Button(L("cancel"), role: .cancel) {}
    Button(L("done")) { onDone(text) }
  }
}

struct EmptyShelf: View {
  var shelf: Shelf
  var searching: Bool
  var search: String
  var onCreate: () -> Void
  @Environment(\.tali) private var c

  var body: some View {
    VStack(spacing: 14) {
      if searching {
        Text(L("no_notebooks_match_n", search)).font(TaliFont.body(17)).foregroundStyle(c.inkMuted)
      } else {
        switch shelf {
        case .trash: Text(L("notebooks_stay_here_for_n_days", trashDays)).font(TaliFont.body(17)).foregroundStyle(c.inkMuted)
        case .starred:
          Text(L("no_starred_notebooks_yet")).font(TaliFont.heading(22)).foregroundStyle(c.ink)
          Text(L("hold_a_notebook_and_choose_star")).font(TaliFont.body(16)).foregroundStyle(c.inkMuted)
        case .folder:
          Text(L("this_folder_is_empty")).font(TaliFont.heading(22)).foregroundStyle(c.ink)
          Button(L("new_notebook"), action: onCreate).buttonStyle(PrimaryButtonStyle())
        case .all:
          PaperPreview(style: .ENGINEERING, zoom: 2.2).frame(width: 220, height: 150).clipShape(RoundedRectangle(cornerRadius: 14))
            .shadow(color: c.glow.opacity(0.15), radius: 14, y: 6)
          Text(L("start_your_first_notebook")).font(TaliFont.heading(24)).foregroundStyle(c.ink)
          Button(L("new_notebook"), action: onCreate).buttonStyle(PrimaryButtonStyle())
        }
      }
    }
    .multilineTextAlignment(.center)
  }
}
