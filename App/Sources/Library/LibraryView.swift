import SwiftUI
import UniformTypeIdentifiers
import TaliCore

/// The library, laid out like Android's `LibraryScreen`: one continuous sky across the top of the
/// whole screen with the sidebar and notebooks below it; a greeting, the big heading and a count
/// line; search, sort and + beside it (under it when narrow); a ruler; then the notebooks. On a phone
/// the sidebar is a drawer (☰).
struct LibraryView: View {
  @Environment(Library.self) private var lib
  @Environment(\.tali) private var c
  var onOpen: (NotebookMeta) -> Void
  @State private var creating = false
  /// The + menu's File: the system file picker, then what was picked becomes an item of its own.
  @State private var importing = false
  @State private var importNote: String?
  @State private var drawer = false
  @State private var renaming: NotebookMeta?
  @State private var moving: NotebookMeta?
  @State private var deleting: NotebookMeta?
  @State private var restoring: NotebookMeta?
  @State private var newFolder = false
  @State private var backups = false
  @State private var settings = false
  /// Picking several notebooks (Select): the ones ticked, or nil when not picking.
  @State private var picked: Set<String>?
  @State private var deletingPicked = false
  @AppStorage("minimal") private var minimal = false

  var body: some View {
    GeometryReader { geo in
      let phone = geo.size.width < Layout.phoneWidth
      ZStack(alignment: .topLeading) {
        LinearGradient(
          stops: [.init(color: c.background, location: 0), .init(color: c.background, location: 0.7), .init(color: c.sidebarEnd, location: 1)],
          startPoint: .top, endPoint: .bottom
        )
        .ignoresSafeArea()
        if !minimal {
          ZStack(alignment: .topLeading) {
            SkyBand(height: 360)
            SkyClouds(width: geo.size.width + geo.safeAreaInsets.leading + geo.safeAreaInsets.trailing)
          }
          .ignoresSafeArea()
        }
        HStack(alignment: .top, spacing: 0) {
          if !phone {
            sidebar(phone: false).frame(width: 268)
          }
          main(width: phone ? geo.size.width : geo.size.width - 268, phone: phone)
        }
        if phone { drawerLayer }
      }
    }
    .fileImporter(isPresented: $importing, allowedContentTypes: [.pdf, .image], allowsMultipleSelection: true) { result in
      guard case .success(let urls) = result, !urls.isEmpty else { return }
      Task { @MainActor in
        // Each PDF becomes an item of its own; pictures picked together become one.
        for u in urls where u.pathExtension.lowercased() == "pdf" {
          do {
            try await lib.importPDF(u)
          } catch Library.ImportError.message(let m) {
            importNote = m
          } catch {
            importNote = L("couldn_t_open_that_file")
          }
        }
        let pictures = urls.filter { $0.pathExtension.lowercased() != "pdf" }
        if !pictures.isEmpty, await lib.importPictures(pictures) == nil { importNote = L("couldn_t_open_that_file") }
      }
    }
    .alert(importNote ?? "", isPresented: Binding(get: { importNote != nil }, set: { if !$0 { importNote = nil } })) {
      Button(L("close")) { importNote = nil }
    }
    .overlay {
      if creating {
        DialogOverlay(onClose: { creating = false }) {
          NewNotebookCard(onClose: { closeDialogs() }, folderName: openFolderName) { title, paper, pages, landscape, dark, cover in
            let n = lib.create(title: title, paper: paper, pages: pages, landscape: landscape, dark: dark, cover: cover)
            closeDialogs()
            onOpen(n)
          }
        }
      } else if backups {
        DialogOverlay(onClose: { closeDialogs() }) { BackupCard(onClose: { closeDialogs() }) }
      } else if settings {
        DialogOverlay(onClose: { closeDialogs() }) { SettingsCard(onClose: { closeDialogs() }) }
      }
    }
    .alert(L("rename"), isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } }), presenting: renaming) { n in
      RenameField(initial: n.title) { lib.rename(n.id, to: $0) }
    }
    .alert(L("new_folder"), isPresented: $newFolder) {
      RenameField(initial: "") { name in
        let parent: String? = if case .folder(let id) = lib.shelf { id } else { nil }
        lib.createFolder(name: name, color: Covers.soft[lib.folders.count % Covers.soft.count], parent: parent)
      }
    }
    .confirmationDialog(L("move_to"), isPresented: Binding(get: { moving != nil }, set: { if !$0 { moving = nil } }), presenting: moving) { n in
      Button(L("no_folder")) { lib.move(n.id, to: nil) }
      ForEach(lib.folders) { f in Button(f.name) { lib.move(n.id, to: f.id) } }
    }
    .confirmationDialog(L("delete"), isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }), presenting: deleting) { n in
      Button(L("delete"), role: .destructive) { withAnimation(.easeOut(duration: 0.22)) { lib.moveToTrash(n.id) } }
    } message: { _ in
      Text(L("it_moves_to_recently_deleted_where", trashDays))
    }
    .confirmationDialog(
      restoring?.title ?? "", isPresented: Binding(get: { restoring != nil }, set: { if !$0 { restoring = nil } }), titleVisibility: .visible,
      presenting: restoring
    ) { n in
      Button(L("restore")) { withAnimation(.easeOut(duration: 0.22)) { lib.restore(n.id) } }
      Button(L("delete_forever"), role: .destructive) { withAnimation(.easeOut(duration: 0.22)) { lib.eraseForGood(n.id) } }
    }
  }

  private var openFolderName: String? {
    if case .folder(let id) = lib.shelf { return lib.folder(id)?.name }
    return nil
  }

  private func closeDialogs() {
    withAnimation(.easeOut(duration: 0.16)) {
      creating = false
      backups = false
      settings = false
    }
  }

  private func sidebar(phone: Bool) -> some View {
    Sidebar(
      onNewFolder: { newFolder = true },
      onPicked: { if phone { withAnimation(.easeOut(duration: 0.2)) { drawer = false } } },
      onBackups: { withAnimation(Ease.outStrong(duration: 0.24)) { backups = true } }, onSettings: { withAnimation(Ease.outStrong(duration: 0.24)) { settings = true } })
  }

  @ViewBuilder private func main(width: CGFloat, phone: Bool) -> some View {
    let side: CGFloat = phone ? 16 : 36
    VStack(alignment: .leading, spacing: 0) {
      if phone {
        Spacer().frame(height: minimal ? 8 : 64)
        Button { withAnimation(.easeOut(duration: 0.24)) { drawer = true } } label: {
          Image(systemName: "line.3.horizontal").font(.system(size: 20)).foregroundStyle(c.ink)
            .frame(width: 44, height: 44).background(RoundedRectangle(cornerRadius: 14).fill(c.surface.opacity(0.7)))
        }
        .accessibilityLabel(L("folders"))
        Spacer().frame(height: 12)
      } else {
        Spacer().frame(height: minimal ? 36 : 112)
      }
      // Narrow, there isn't room for all of it on one line: the search and buttons go underneath.
      if phone || width < 732 {
        heading
        Spacer().frame(height: 16)
        actions(searchWidth: nil)
      } else {
        HStack(alignment: .bottom, spacing: 0) {
          heading.frame(maxWidth: .infinity, alignment: .leading)
          actions(searchWidth: 240)
        }
      }
      Spacer().frame(height: 18)
      RulerDivider()
      Spacer().frame(height: 22)
      ScrollView {
        content(phone: phone).padding(.bottom, 40)
      }
      .scrollIndicators(.hidden)
    }
    .padding(.horizontal, side)
  }

  private var heading: some View {
    VStack(alignment: .leading, spacing: 0) {
      if lib.shelf != .trash {
        GreetingLine()
        Spacer().frame(height: 2)
      }
      Text(headingText).font(TaliType.displayLarge).tracking(-1.04).foregroundStyle(c.ink)
        .lineLimit(1).minimumScaleFactor(0.62)
      Spacer().frame(height: 6)
      Text(countLine).font(TaliType.bodyLarge).foregroundStyle(c.inkMuted).lineLimit(2)
    }
  }

  private var headingText: String {
    switch lib.shelf {
    case .all: return L("all_notebooks")
    case .starred: return L("starred_notebooks")
    case .trash: return L("recently_deleted")
    case .folder(let id): return lib.folder(id)?.name ?? L("all_notebooks")
    }
  }

  /// "4 notebooks · Monday, 9 November" (or how long Recently deleted keeps things).
  private var countLine: String {
    if lib.shelf == .trash { return L("notebooks_stay_here_for_n_days", trashDays) }
    let count: Int
    var inside = 0
    switch lib.shelf {
    case .all: count = lib.notebooks.count
    case .starred: count = lib.notebooks.filter { lib.starred.contains($0.id) }.count
    case .folder(let id):
      count = lib.notebooks.filter { $0.folderId == id }.count
      inside = lib.folders.filter { $0.parentId == id }.count
    case .trash: count = 0
    }
    var counts = count == 1 ? L("t_1_notebook") : L("n_notebooks", count)
    if inside == 1 { counts += L("t_1_folder") } else if inside > 1 { counts += L("n_folders", inside) }
    let today = Date().formatted(Date.FormatStyle().weekday(.wide).day().month(.wide))
    return L("n_n_2", counts, today)
  }

  @ViewBuilder private func actions(searchWidth: CGFloat?) -> some View {
    @Bindable var lib = lib
    if let chosen = picked {
      PickBar(
        count: chosen.count, allPicked: !lib.shown.isEmpty && lib.shown.allSatisfy { chosen.contains($0.id) }, folders: lib.folders,
        onAll: {
          let ids = Set(lib.shown.map(\.id))
          picked = ids.isSubset(of: chosen) ? [] : ids
        },
        onMove: { folder in
          for id in chosen { lib.move(id, to: folder) }
          picked = nil
        },
        onDuplicate: {
          for id in chosen { lib.duplicate(id) }
          picked = nil
        },
        onDelete: { deletingPicked = true },
        onDone: { withAnimation(.easeOut(duration: 0.2)) { picked = nil } }
      )
      .transition(.opacity.combined(with: .offset(y: 8)))
    } else {
      HStack(spacing: 0) {
        SearchField(text: $lib.search).frame(width: searchWidth).frame(maxWidth: searchWidth == nil ? .infinity : nil)
        if lib.shelf != .trash {
          Spacer().frame(width: 8)
          SortButton()
        }
        Spacer().frame(width: 12)
        if lib.shelf == .trash {
          if !lib.trash.isEmpty { Button(L("empty")) { lib.emptyTrash() }.buttonStyle(QuietButtonStyle(warning: true)) }
        } else {
          if !lib.shown.isEmpty {
            Button(L("select")) { withAnimation(.easeOut(duration: 0.2)) { picked = [] } }.buttonStyle(QuietButtonStyle())
            Spacer().frame(width: 8)
          }
          AddMenu(
            onNotebook: { withAnimation(Ease.outStrong(duration: 0.24)) { creating = true } },
            onFile: { importing = true })
        }
      }
      .transition(.opacity.combined(with: .offset(y: 8)))
    }
  }

  @ViewBuilder private func content(phone: Bool) -> some View {
    let items = lib.shown
    let folders: [Folder] = lib.search.isEmpty ? lib.subfoldersOfOpenFolder : []
    if items.isEmpty && folders.isEmpty {
      EmptyShelf(shelf: lib.shelf, searching: !lib.search.isEmpty, search: lib.search) { creating = true }
        .frame(maxWidth: .infinity).padding(.top, 30)
    } else {
      let columns = [GridItem(.adaptive(minimum: phone ? 150 : 210), spacing: 24, alignment: .top)]
      LazyVGrid(columns: columns, alignment: .leading, spacing: 28) {
        if !folders.isEmpty {
          Section {
            ForEach(folders) { f in
              FolderTile(folder: f, count: lib.notebooks.filter { $0.folderId == f.id }.count, inner: lib.folders.filter { $0.parentId == f.id }.count)
                .onTapGesture { withAnimation(.easeOut(duration: 0.22)) { lib.shelf = .folder(f.id) } }
                .contextMenu { Button(role: .destructive) { lib.deleteFolder(f.id) } label: { Label(L("delete_folder"), systemImage: "trash") } }
            }
          } header: {
            SectionLabel(text: L("folders"))
          }
        }
        if !items.isEmpty {
          Section {
            ForEach(items) { n in
              NotebookCard(
                notebook: n, starred: lib.starred.contains(n.id), inTrash: lib.shelf == .trash, picking: picked != nil,
                picked: picked?.contains(n.id) == true
              )
              .onTapGesture {
                if let chosen = picked {
                  togglePick(n.id, in: chosen)
                } else if lib.shelf == .trash {
                  restoring = n
                } else {
                  onOpen(n)
                }
              }
              .contextMenu { if lib.shelf != .trash && picked == nil { menu(for: n) } }
                .transition(.opacity.combined(with: .scale(scale: 0.93)).combined(with: .offset(y: -10)))
            }
          } header: {
            SectionLabel(text: sectionTitle)
          }
        }
      }
    }
  }

  /// Ticks or unticks a notebook; unticking the last one ends picking, as on Android.
  private func togglePick(_ id: String, in chosen: Set<String>) {
    var next = chosen
    if next.contains(id) { next.remove(id) } else { next.insert(id) }
    withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) { picked = next.isEmpty ? nil : next }
  }

  private var sectionTitle: String {
    switch lib.shelf {
    case .trash: return L("tap_a_notebook_to_bring_it")
    case .folder: return L("notebooks")
    default:
      if lib.sort == .EDITED && !lib.sortReversed { return L("recent") }
      if lib.sort == .OPENED && !lib.sortReversed { return L("recently_opened") }
      return L("notebooks")
    }
  }

  @ViewBuilder private func menu(for n: NotebookMeta) -> some View {
    Button { withAnimation(.easeOut(duration: 0.2)) { picked = [n.id] } } label: { Label(L("select"), systemImage: "checkmark.circle") }
    Button { lib.toggleStar(n.id) } label: {
      Label(L(lib.starred.contains(n.id) ? "remove_star" : "star"), systemImage: lib.starred.contains(n.id) ? "star.fill" : "star")
    }
    Button { renaming = n } label: { Label(L("rename"), systemImage: "pencil") }
    Button { lib.duplicate(n.id) } label: { Label(L("duplicate"), systemImage: "doc.on.doc") }
    Button { moving = n } label: { Label(L("move_to_folder"), systemImage: "folder") }
    Divider()
    Button(role: .destructive) { deleting = n } label: { Label(L("delete"), systemImage: "trash") }
  }

  @ViewBuilder private var drawerLayer: some View {
    if drawer {
      c.scrim.ignoresSafeArea()
        .onTapGesture { withAnimation(.easeOut(duration: 0.2)) { drawer = false } }
        .transition(.opacity)
      sidebar(phone: true)
        .frame(width: 290)
        .frame(maxHeight: .infinity)
        .background(LinearGradient(colors: [c.background, c.sidebarEnd], startPoint: .top, endPoint: .bottom).ignoresSafeArea())
        .transition(.move(edge: .leading))
    }
  }
}

/// While picking: "N selected", Select all/none, then move, duplicate and delete together in one
/// frosted pill, and Done (Android's `PickBar`).
struct PickBar: View {
  var count: Int
  var allPicked: Bool
  var folders: [Folder]
  var onAll: () -> Void
  var onMove: (String?) -> Void
  var onDuplicate: () -> Void
  var onDelete: () -> Void
  var onDone: () -> Void
  @Environment(\.tali) private var c

  var body: some View {
    HStack(spacing: 0) {
      Text(count == 1 ? L("t_1_selected") : L("n_selected", count)).font(TaliType.titleMedium).foregroundStyle(c.ink).lineLimit(1)
      Spacer().frame(width: 12)
      Button(allPicked ? L("select_none") : L("select_all"), action: onAll).buttonStyle(QuietButtonStyle())
      Spacer().frame(width: 10)
      HStack(spacing: 0) {
        Menu {
          Section(L("move_to")) {
            Button(L("no_folder")) { onMove(nil) }
            ForEach(folders) { f in Button(f.name) { onMove(f.id) } }
          }
        } label: {
          Image(systemName: "folder").font(.system(size: 19)).foregroundStyle(count > 0 ? c.ink : c.inkFaint.opacity(0.5)).frame(width: 44, height: 44)
        }
        .disabled(count == 0)
        .accessibilityLabel(L("move_to_folder"))
        ToolIcon(system: "doc.on.doc", label: L("duplicate"), enabled: count > 0, action: onDuplicate)
        ToolIcon(system: "trash", label: L("delete"), enabled: count > 0, action: onDelete)
      }
      .padding(.horizontal, 4)
      .background(RoundedRectangle(cornerRadius: 16).fill(c.surface.opacity(0.72)))
      Spacer().frame(width: 10)
      Button(L("done"), action: onDone).buttonStyle(PrimaryButtonStyle())
    }
  }
}

/// "Good morning" in the accent colour, by the device's clock (no name: other people may use the app).
struct GreetingLine: View {
  @Environment(\.tali) private var c
  var body: some View {
    TimelineView(.periodic(from: .now, by: 30)) { ctx in
      Text(L(Greeting.forHour(Calendar.current.component(.hour, from: ctx.date)).rawValue))
        .font(TaliType.titleMedium).foregroundStyle(c.accent)
    }
  }
}

/// The search box: white with a hairline edge and 16 pt corners (no cloud), as on Android.
struct SearchField: View {
  @Binding var text: String
  @Environment(\.tali) private var c
  var body: some View {
    HStack(spacing: 10) {
      Image(systemName: "magnifyingglass").font(.system(size: 17)).foregroundStyle(c.inkFaint)
      TextField("", text: $text, prompt: Text(L("search_notebooks")).foregroundStyle(c.inkFaint))
        .font(TaliType.bodyMedium).foregroundStyle(c.ink).tint(c.accent)
        .textInputAutocapitalization(.never).autocorrectionDisabled()
      if !text.isEmpty {
        Button { text = "" } label: { Image(systemName: "xmark").font(.system(size: 14, weight: .medium)).foregroundStyle(c.inkMuted) }
          .accessibilityLabel(L("clear_search"))
      }
    }
    .padding(.horizontal, 14)
    .frame(minHeight: 48)
    .background(RoundedRectangle(cornerRadius: 16).fill(c.surface))
    .overlay(RoundedRectangle(cornerRadius: 16).stroke(c.line, lineWidth: 1))
  }
}

/// Sort, beside the search box and shaped like it.
struct SortButton: View {
  @Environment(Library.self) private var lib
  @Environment(\.tali) private var c
  var body: some View {
    Menu {
      Section(L("sort_by")) {
        ForEach(LibrarySort.allCases, id: \.self) { s in
          Button {
            if lib.sort == s { lib.sortReversed.toggle() } else {
              lib.sort = s
              lib.sortReversed = false
            }
          } label: {
            if lib.sort == s {
              Label(label(s), systemImage: lib.sortReversed ? "arrow.up" : "arrow.down")
            } else {
              Text(label(s))
            }
          }
        }
      }
    } label: {
      Image(systemName: "line.3.horizontal.decrease").font(.system(size: 18)).foregroundStyle(c.inkMuted)
        .frame(width: 48, height: 48)
        .background(RoundedRectangle(cornerRadius: 16).fill(c.surface))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(c.line, lineWidth: 1))
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

/// The + (Android's `AddButton` and its card): a system menu with Notebook (the new-notebook card)
/// and File (PDFs and pictures from her files). A native menu on iOS rather than Android's card.
struct AddMenu: View {
  var onNotebook: () -> Void
  var onFile: () -> Void
  @Environment(\.tali) private var c

  var body: some View {
    Menu {
      Button(action: onNotebook) { Label(L("notebook"), systemImage: "book.closed") }
        .accessibilityIdentifier("add-notebook")
      Button(action: onFile) { Label(L("add_file"), systemImage: "doc.badge.plus") }
        .accessibilityIdentifier("add-file")
    } label: {
      Image(systemName: "plus").font(.system(size: 22, weight: .medium)).foregroundStyle(c.onAccent)
        .frame(width: 48, height: 48)
        .background(RoundedRectangle(cornerRadius: 16).fill(c.accentGradient))
    }
    .accessibilityLabel(L("add"))
    .accessibilityIdentifier("add")
  }
}

/// The + : a 48 pt rounded square in the violet-to-blue gradient.
struct AddButton: View {
  var action: () -> Void
  @Environment(\.tali) private var c
  var body: some View {
    Button(action: action) {
      Image(systemName: "plus").font(.system(size: 22, weight: .medium)).foregroundStyle(c.onAccent)
        .frame(width: 48, height: 48)
        .background(RoundedRectangle(cornerRadius: 16).fill(c.accentGradient))
    }
    .buttonStyle(PressStyle(scale: 0.94))
    .accessibilityLabel(L("add"))
  }
}

/// A ruler along the top of the notebooks (Android's `RulerDivider`): ticks, taller every fifth,
/// numbered every tenth.
struct RulerDivider: View {
  @Environment(\.tali) private var c
  var body: some View {
    Canvas { ctx, size in
      let step: CGFloat = 6.3 / 1.6
      let base = size.height - 0.5
      var line = Path()
      line.move(to: CGPoint(x: 0, y: base))
      line.addLine(to: CGPoint(x: size.width, y: base))
      ctx.stroke(line, with: .color(c.line), lineWidth: 1)
      var i = 0
      var x: CGFloat = 0
      while x <= size.width {
        let h: CGFloat = i % 10 == 0 ? 9 : (i % 5 == 0 ? 6 : 3.5)
        var t = Path()
        t.move(to: CGPoint(x: x, y: base))
        t.addLine(to: CGPoint(x: x, y: base - h))
        ctx.stroke(t, with: .color(i % 10 == 0 ? c.blue.opacity(0.55) : c.line), lineWidth: 1)
        if i % 10 == 0 && i > 0 {
          ctx.draw(Text("\(i / 10)").font(TaliFont.body(9, .semibold)).foregroundStyle(c.inkFaint), at: CGPoint(x: x + 3, y: 0), anchor: .topLeading)
        }
        i += 1
        x += step
      }
    }
    .frame(height: 22)
    .environment(\.layoutDirection, .leftToRight)
    .accessibilityHidden(true)
  }
}

/// A small upper-case label over a section.
struct SectionLabel: View {
  var text: String
  @Environment(\.tali) private var c
  var body: some View {
    Text(text.uppercased()).font(TaliType.labelSmall).tracking(0.66).foregroundStyle(c.inkFaint)
      .frame(maxWidth: .infinity, alignment: .leading)
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
        Text(L("no_notebooks_match_n", search)).font(TaliType.bodyLarge).foregroundStyle(c.inkMuted)
      } else {
        switch shelf {
        case .trash: EmptyView()
        case .starred:
          Text(L("no_starred_notebooks_yet")).font(TaliType.titleLarge).foregroundStyle(c.ink)
          Text(L("hold_a_notebook_and_choose_star")).font(TaliType.bodyMedium).foregroundStyle(c.inkMuted)
        case .folder:
          Text(L("this_folder_is_empty")).font(TaliType.titleLarge).foregroundStyle(c.ink)
          Button(L("new_notebook"), action: onCreate).buttonStyle(PrimaryButtonStyle())
        case .all:
          PaperPreview(style: .ENGINEERING, zoom: 2.2).frame(width: 220, height: 150).clipShape(RoundedRectangle(cornerRadius: 14))
            .shadow(color: c.glow.opacity(0.15), radius: 14, y: 6)
          Text(L("start_your_first_notebook")).font(TaliType.titleLarge).foregroundStyle(c.ink)
          Button(L("new_notebook"), action: onCreate).buttonStyle(PrimaryButtonStyle())
        }
      }
    }
    .multilineTextAlignment(.center)
  }
}
