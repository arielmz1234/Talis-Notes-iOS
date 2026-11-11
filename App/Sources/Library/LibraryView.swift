import PhotosUI
import SwiftUI
import UniformTypeIdentifiers
import TaliCore

/// The one card over the library at a time.
enum LibraryDialog: Equatable {
  case newNotebook, backups, settings, emptyTrash
  case rename(NotebookMeta)
  case delete(NotebookMeta)
  case deletePicked(Set<String>)
  case trash(NotebookMeta)
  case newFolder(parent: String?)
  case renameFolder(Folder)
  case moveFolder(Folder)
  case deleteFolder(Folder)

  /// Confirmations add no tint behind them (Android's `dim = false`).
  var dims: Bool {
    switch self {
    case .delete, .deletePicked, .trash, .emptyTrash, .deleteFolder: false
    default: true
    }
  }
}

/// The library, laid out like Android's `LibraryScreen`: one continuous sky across the top of the
/// whole screen with the sidebar and notebooks below it; a greeting, the way back up out of a
/// folder, the big heading and a count line; search, sort and + beside it (under it when narrow);
/// a ruler; then the folders and notebooks. On a phone the sidebar is a drawer (☰).
struct LibraryView: View {
  @Environment(Library.self) private var lib
  @Environment(\.tali) private var c
  @Environment(\.layoutDirection) private var direction
  var onOpen: (NotebookMeta) -> Void
  @State private var dialog: LibraryDialog?
  @State private var adding = false
  /// The + menu's File: the system file picker, then what was picked becomes an item of its own.
  @State private var importing = false
  /// The + menu's Photo: the system photo picker (up to 30, as on Android).
  @State private var pickingPhotos = false
  @State private var photos: [PhotosPickerItem] = []
  /// The + menu's Camera.
  @State private var camera = false
  @State private var importNote: String?
  @State private var drawer = false
  /// Picking several notebooks (Select): the ones ticked, or nil when not picking.
  @State private var picked: Set<String>?
  /// Notebooks and folders on their way out (puffing away), and a folder that has just been made.
  @State private var vanishing: Set<String> = []
  @State private var fresh: Set<String> = []
  @State private var knownFolders: Set<String>?
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
    .overlayPreferenceValue(AddButtonBounds.self) { anchor in addLayer(anchor) }
    .puffLayerHost()
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
    .photosPicker(isPresented: $pickingPhotos, selection: $photos, maxSelectionCount: 30, matching: .images)
    .onChange(of: photos) { _, items in
      guard !items.isEmpty else { return }
      photos = []
      Task { @MainActor in
        var data: [Data] = []
        for item in items {
          if let d = try? await item.loadTransferable(type: Data.self) { data.append(d) }
        }
        if await lib.importPictures(data: data) == nil { importNote = L("couldn_t_open_that_file") }
      }
    }
    .fullScreenCover(isPresented: $camera) {
      CameraPicker(
        onPhoto: { image in
          // A photo comes out the way the camera holds it; drawn upright before it's kept.
          let upright = UIGraphicsImageRenderer(size: image.size).image { _ in image.draw(at: .zero) }
          guard let data = upright.jpegData(compressionQuality: 0.9) else { return }
          Task { @MainActor in _ = await lib.importPictures(data: [data]) }
        },
        onClose: { camera = false }
      )
      .ignoresSafeArea()
    }
    .alert(importNote ?? "", isPresented: Binding(get: { importNote != nil }, set: { if !$0 { importNote = nil } })) {
      Button(L("close")) { importNote = nil }
    }
    .overlay {
      if let d = dialog {
        DialogOverlay(dim: d.dims, onClose: { close() }) { card(for: d) }
      }
    }
    // Changing folder or opening Recently deleted ends picking.
    .onChange(of: lib.shelf) { _, _ in picked = nil }
    .onChange(of: lib.folders.map(\.id), initial: true) { _, ids in noteNewFolder(Set(ids)) }
  }

  // MARK: Dialogs

  private func show(_ d: LibraryDialog) {
    withAnimation(Ease.outStrong(duration: 0.24)) { dialog = d }
  }

  private func close() {
    withAnimation(.easeOut(duration: 0.16)) { dialog = nil }
  }

  @ViewBuilder private func card(for d: LibraryDialog) -> some View {
    switch d {
    case .newNotebook:
      NewNotebookCard(onClose: { close() }, folderName: lib.openFolder?.name, suggestedName: lib.freeNotebookName, defaultCover: lib.nextCover) {
        title, paper, pages, landscape, dark, cover in
        let n = lib.create(title: title, paper: paper, pages: pages, landscape: landscape, dark: dark, cover: cover)
        close()
        onOpen(n)
      }
    case .backups: BackupCard(onClose: { close() })
    case .settings: SettingsCard(onClose: { close() })
    case .rename(let n):
      NameCard(title: L("rename_notebook"), initial: n.title, placeholder: L("notebook_name"), confirm: L("rename"), onClose: { close() }) {
        lib.rename(n.id, to: $0)
        close()
      }
    case .delete(let n):
      ConfirmCard(
        title: L("delete_n", n.title), message: L("it_moves_to_recently_deleted_where", trashDays), confirm: L("delete"), destructive: true,
        onClose: { close() }
      ) {
        close()
        vanish(n.id) { lib.moveToTrash(n.id) }
      }
    case .deletePicked(let ids):
      ConfirmCard(
        title: ids.count == 1 ? L("delete_1_notebook") : L("delete_n_notebooks", ids.count), message: L("they_move_to_recently_deleted_where", trashDays),
        confirm: L("delete"), destructive: true, onClose: { close() }
      ) {
        close()
        picked = nil
        for id in ids { vanish(id) { lib.moveToTrash(id) } }
      }
    case .trash(let n):
      TrashCard(
        notebook: n, onClose: { close() },
        onErase: {
          lib.eraseForGood(n.id)
          close()
        },
        onRestore: {
          lib.restore(n.id)
          close()
        })
    case .emptyTrash:
      ConfirmCard(
        title: L("empty_recently_deleted"),
        message: lib.trash.count == 1 ? L("t_1_notebook_will_be_deleted_for") : L("n_notebooks_will_be_deleted_for", lib.trash.count),
        confirm: L("delete_forever"), destructive: true, onClose: { close() }
      ) {
        lib.emptyTrash()
        close()
      }
    case .newFolder(let parent):
      NewFolderCard(
        title: lib.folder(parent).map { L("new_folder_in_n", $0.name) } ?? L("new_folder"), placeholder: lib.freeFolderName(in: parent),
        initialColor: lib.nextFolderColor(in: parent), onClose: { close() }
      ) { name, color in
        withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) { lib.createFolder(name: name, color: color, parent: parent) }
        close()
      }
    case .renameFolder(let f):
      NameCard(title: L("rename_folder"), initial: f.name, placeholder: L("folder_name"), confirm: L("rename"), onClose: { close() }) {
        lib.renameFolder(f.id, to: $0)
        close()
      }
    case .moveFolder(let f):
      MoveFolderCard(folder: f, folders: lib.folders, onClose: { close() }) {
        lib.moveFolder(f.id, to: $0)
        close()
      }
    case .deleteFolder(let f):
      ConfirmCard(
        title: L("delete_the_n_folder", f.name),
        message: lib.folder(f.parentId).map { L("nothing_inside_is_deleted_its_notebooks", $0.name) } ?? L("nothing_inside_is_deleted_its_notebooks_2"),
        confirm: L("delete_folder"), destructive: true, onClose: { close() }
      ) {
        close()
        vanish(f.id) { lib.deleteFolder(f.id) }
      }
    }
  }

  /// Plays [id]'s puff of mist, then does [then] once it has gone (Android's `vanish`).
  private func vanish(_ id: String, then: @escaping () -> Void) {
    vanishing.insert(id)
    DispatchQueue.main.asyncAfter(deadline: .now() + PuffTiming.leave) {
      withAnimation(.spring(response: 0.36, dampingFraction: 0.9)) { then() }
      vanishing.remove(id)
    }
  }

  /// One new folder is one she just made (not the list loading in): it arrives on a puff.
  private func noteNewFolder(_ ids: Set<String>) {
    if let old = knownFolders {
      let new = ids.subtracting(old)
      if new.count == 1 {
        fresh = new
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { if fresh == new { fresh = [] } }
      }
    }
    knownFolders = ids
  }

  // MARK: The + card

  @ViewBuilder private func addLayer(_ anchor: Anchor<CGRect>?) -> some View {
    let rtl = direction == .rightToLeft
    GeometryReader { g in
      let b = anchor.map { g[$0] } ?? .zero
      let width = min(330, g.size.width - 16)
      let x = min(max(rtl ? b.minX : b.maxX - width, 8), max(g.size.width - width - 8, 8))
      ZStack(alignment: .topLeading) {
        if adding {
          Color.clear.contentShape(Rectangle())
            .onTapGesture { withAnimation(Ease.outStrong(duration: 0.24)) { adding = false } }
            .accessibilityHidden(true)
        }
        if adding, anchor != nil {
          AddCard(choices: AddChoice.allCases.filter { $0 != .camera || CameraPicker.available }) { pickAdd($0) }
            .frame(width: width)
            .environment(\.layoutDirection, direction)
            .transition(
              .asymmetric(
                insertion: .scale(scale: 0.9, anchor: rtl ? .topLeading : .topTrailing).combined(with: .opacity),
                removal: .scale(scale: 0.95, anchor: rtl ? .topLeading : .topTrailing).combined(with: .opacity).animation(.easeOut(duration: 0.13))))
            .offset(x: x, y: b.maxY + 8)
        }
      }
      .frame(width: g.size.width, height: g.size.height, alignment: .topLeading)
    }
    .environment(\.layoutDirection, .leftToRight)
  }

  private func pickAdd(_ choice: AddChoice) {
    withAnimation(Ease.outStrong(duration: 0.24)) { adding = false }
    switch choice {
    case .notebook: show(.newNotebook)
    case .file: importing = true
    case .camera: camera = true
    case .photo: pickingPhotos = true
    }
  }

  // MARK: The screen

  private func sidebar(phone: Bool) -> some View {
    Sidebar(
      onNewFolder: { parent in
        closeDrawer(phone)
        show(.newFolder(parent: parent))
      },
      onRenameFolder: { show(.renameFolder($0)) },
      onMoveFolder: { show(.moveFolder($0)) },
      onDeleteFolder: { show(.deleteFolder($0)) },
      onPicked: { closeDrawer(phone) },
      onBackups: { show(.backups) }, onSettings: { show(.settings) },
      vanishing: vanishing, fresh: fresh)
  }

  private func closeDrawer(_ phone: Bool) {
    if phone { withAnimation(.easeOut(duration: 0.18)) { drawer = false } }
  }

  @ViewBuilder private func main(width: CGFloat, phone: Bool) -> some View {
    let side: CGFloat = phone ? 16 : 36
    VStack(alignment: .leading, spacing: 0) {
      VStack(alignment: .leading, spacing: 0) {
        if phone {
          Spacer().frame(height: minimal ? 8 : 64)
          Button { withAnimation(Ease.outStrong(duration: 0.26)) { drawer = true } } label: {
            Image(systemName: "line.3.horizontal").font(.system(size: 20)).foregroundStyle(c.ink)
              .frame(width: 44, height: 44).background(RoundedRectangle(cornerRadius: 14).fill(c.surface.opacity(0.7)))
          }
          .accessibilityLabel(L("folders"))
          .accessibilityIdentifier("drawer")
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
      }
      ScrollView {
        content(phone: phone).padding(.bottom, 40)
      }
      .scrollIndicators(.hidden)
      // Cut along the top only, as Compose's grid is: cards slide under the ruler, not over the
      // heading, while their shadows keep room at the sides and the list runs on under the home bar.
      .scrollClipDisabled()
      .mask(Rectangle().padding(.horizontal, -48).padding(.bottom, -200))
    }
    .padding(.horizontal, side)
  }

  private var heading: some View {
    VStack(alignment: .leading, spacing: 0) {
      if lib.shelf != .trash {
        GreetingLine()
        Spacer().frame(height: 2)
      }
      // Inside a folder within a folder: the way back up, one tap per level.
      let path = Array(FolderTree.path(to: lib.openFolder?.id, in: lib.folders).dropLast())
      if !path.isEmpty {
        Breadcrumb(path: path) { id in lib.shelf = id.map(Shelf.folder) ?? .all }
        Spacer().frame(height: 4)
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
      count = lib.count(in: id)
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
    ZStack {
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
          onDelete: { show(.deletePicked(chosen)) },
          onDone: { picked = nil }
        )
        .transition(.asymmetric(insertion: .opacity.combined(with: .offset(y: 10)).animation(Ease.outStrong(duration: 0.22).delay(0.06)), removal: .opacity.animation(.easeOut(duration: 0.12))))
      } else {
        HStack(spacing: 0) {
          SearchField(text: $lib.search).frame(width: searchWidth).frame(maxWidth: searchWidth == nil ? .infinity : nil)
          if lib.shelf != .trash {
            Spacer().frame(width: 8)
            SortButton()
          }
          Spacer().frame(width: 12)
          if lib.shelf == .trash {
            Button(L("empty")) { show(.emptyTrash) }.buttonStyle(QuietButtonStyle(warning: true)).accessibilityIdentifier("empty-trash")
          } else {
            if !lib.shown.isEmpty {
              Button(L("select")) { picked = [] }.buttonStyle(QuietButtonStyle()).accessibilityIdentifier("select")
              Spacer().frame(width: 8)
            }
            AddButton(open: $adding)
          }
        }
        .transition(.asymmetric(insertion: .opacity.combined(with: .offset(y: 10)).animation(Ease.outStrong(duration: 0.22).delay(0.06)), removal: .opacity.animation(.easeOut(duration: 0.12))))
      }
    }
    .animation(Ease.outStrong(duration: 0.22), value: picked == nil)
  }

  @ViewBuilder private func content(phone: Bool) -> some View {
    let items = lib.shown
    let open = lib.openFolder
    let subfolders: [Folder] = open == nil || !lib.search.isEmpty ? [] : lib.folders.filter { $0.parentId == open?.id }
    if lib.notebooks.isEmpty && lib.shelf != .trash && lib.folders.isEmpty {
      EmptyLibrary { show(.newNotebook) }
    } else if items.isEmpty && !lib.search.isEmpty {
      Text(L("no_notebooks_match_n", lib.search)).font(TaliType.bodyLarge).foregroundStyle(c.inkMuted)
    } else if items.isEmpty && lib.shelf == .starred {
      EmptyStarred()
    } else if items.isEmpty && subfolders.isEmpty, let open {
      EmptyFolder(onCreate: { show(.newNotebook) }, onNewFolder: { show(.newFolder(parent: open.id)) })
    } else if items.isEmpty && subfolders.isEmpty {
      EmptyLibrary { show(.newNotebook) }
    } else {
      let columns = [GridItem(.adaptive(minimum: phone ? 150 : 210), spacing: 24, alignment: .top)]
      LazyVGrid(columns: columns, alignment: .leading, spacing: 28) {
        if let open, lib.search.isEmpty {
          Section {
            ForEach(subfolders) { f in
              FolderTile(folder: f, count: lib.count(in: f.id), inner: lib.folders.filter { $0.parentId == f.id }.count)
                .onTapGesture { lib.shelf = .folder(f.id) }
                .contextMenu {
                  FolderMenu(
                    folder: f, onNewFolder: { show(.newFolder(parent: f.id)) }, onRename: { show(.renameFolder(f)) }, onMove: { show(.moveFolder(f)) },
                    onRecolor: { lib.recolorFolder(f.id, $0) }, onDelete: { show(.deleteFolder(f)) })
                }
                .puffBox(leaving: vanishing.contains(f.id), appearing: fresh.contains(f.id))
            }
            NewFolderTile { show(.newFolder(parent: open.id)) }
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
                  show(.trash(n))
                } else {
                  onOpen(n)
                }
              }
              // Only while picking or in Recently deleted: otherwise holding opens its menu.
              .gesture(
                LongPressGesture(minimumDuration: 0.5).onEnded { _ in
                  if let chosen = picked { togglePick(n.id, in: chosen) } else { show(.trash(n)) }
                }, including: picked != nil || lib.shelf == .trash ? .all : .subviews
              )
              .contextMenu { if lib.shelf != .trash && picked == nil { menu(for: n) } }
              .puffBox(leaving: vanishing.contains(n.id))
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

  /// A notebook's hold menu, in Android's order.
  @ViewBuilder private func menu(for n: NotebookMeta) -> some View {
    Button { picked = [n.id] } label: { Label(L("select"), systemImage: "checkmark.circle") }
    Button { lib.toggleStar(n.id) } label: {
      Label(L(lib.starred.contains(n.id) ? "remove_star" : "star"), systemImage: lib.starred.contains(n.id) ? "star.fill" : "star")
    }
    Button { show(.rename(n)) } label: { Label(L("rename"), systemImage: "pencil") }
    Button { lib.duplicate(n.id) } label: { Label(L("duplicate"), systemImage: "doc.on.doc") }
    Menu {
      MoveTargets(folders: lib.folders, here: n.folderId) { lib.move(n.id, to: $0) }
    } label: {
      Label(L("move_to_folder"), systemImage: "folder")
    }
    // Only a notebook has a cover (its spine).
    if n.kind == .notebook { ColourPalette(current: n.cover) { lib.setCover(n.id, $0) } }
    Divider()
    Button(role: .destructive) { show(.delete(n)) } label: { Label(L("delete"), systemImage: "trash") }
  }

  @ViewBuilder private var drawerLayer: some View {
    if drawer {
      c.scrim.ignoresSafeArea()
        .onTapGesture { closeDrawer(true) }
        .transition(.opacity)
      sidebar(phone: true)
        .frame(width: 268)
        .frame(maxHeight: .infinity)
        .background(
          UnevenRoundedRectangle(bottomTrailingRadius: 24, topTrailingRadius: 24)
            .fill(LinearGradient(colors: [c.background, c.sidebarEnd], startPoint: .top, endPoint: .bottom)).ignoresSafeArea()
        )
        .transition(.move(edge: .leading))
    }
  }
}

/// "No folder", then every folder in tree order, in a hold menu (Android's move list).
struct MoveTargets: View {
  var folders: [Folder]
  var here: String?
  var onMove: (String?) -> Void

  var body: some View {
    Section(L("move_to")) {
      Button { onMove(nil) } label: { Label(L("no_folder"), systemImage: "book.pages") }
      ForEach(FolderTree.ordered(folders), id: \.folder.id) { f, depth in
        Button { onMove(f.id) } label: {
          Label(String(repeating: "    ", count: depth) + (f.id == here ? L("n_here", f.name) : f.name), systemImage: "folder")
        }
      }
      if folders.isEmpty { Text(L("no_folders_yet_add_one_from")) }
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
    // On one line when it fits; on a phone the actions go under the count rather than cut it short.
    ViewThatFits(in: .horizontal) {
      HStack(spacing: 0) {
        counted
        Spacer().frame(width: 10)
        actions
      }
      VStack(alignment: .leading, spacing: 10) {
        counted
        actions
      }
    }
  }

  private var counted: some View {
    HStack(spacing: 0) {
      Text(count == 1 ? L("t_1_selected") : L("n_selected", count)).font(TaliType.titleMedium).foregroundStyle(c.ink).lineLimit(1).fixedSize()
      Spacer().frame(width: 12)
      Button(allPicked ? L("select_none") : L("select_all"), action: onAll).buttonStyle(QuietButtonStyle())
    }
  }

  private var actions: some View {
    HStack(spacing: 0) {
      HStack(spacing: 0) {
        Menu {
          MoveTargets(folders: folders, here: nil, onMove: onMove)
        } label: {
          Image(systemName: "folder").font(.system(size: 19)).foregroundStyle(count > 0 ? c.ink : c.inkFaint.opacity(0.5)).frame(width: 44, height: 44)
        }
        .disabled(count == 0)
        .accessibilityLabel(L("move_to_folder"))
        ToolIcon(system: "doc.on.doc", label: L("duplicate"), enabled: count > 0, action: onDuplicate)
        ToolIcon(system: "trash", label: L("delete"), enabled: count > 0, action: onDelete).accessibilityIdentifier("pick-delete")
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
              Text(L("n_tap_again_to_turn_it", way(s)))
            } else {
              Text(label(s))
            }
          }
          .accessibilityIdentifier("sort-\(s.rawValue)")
        }
      }
    } label: {
      Image(systemName: "line.3.horizontal.decrease").font(.system(size: 18)).foregroundStyle(c.inkMuted)
        .frame(width: 48, height: 48)
        .background(RoundedRectangle(cornerRadius: 16).fill(c.surface))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(c.line, lineWidth: 1))
    }
    // Staying open after a tap shows the list re-sort behind it, and lets her turn it round.
    .menuActionDismissBehavior(.disabled)
    .accessibilityLabel(L("sort_notebooks"))
    .accessibilityIdentifier("sort")
  }

  /// Which way round the sort in use goes, as its menu says it.
  private func way(_ s: LibrarySort) -> String {
    if s == .NAME { return lib.sortReversed ? L("z_to_a") : L("a_to_z") }
    return lib.sortReversed ? L("oldest_first") : L("newest_first")
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

/// Nothing in the library yet (Android's `EmptyLibrary`): an empty engineering page between two
/// clouds, and New notebook.
struct EmptyLibrary: View {
  var onCreate: () -> Void
  @Environment(\.tali) private var c

  var body: some View {
    VStack(spacing: 0) {
      ZStack {
        RoundedRectangle(cornerRadius: 18).fill(LinearGradient(colors: [c.accentSoft, c.sky], startPoint: .topLeading, endPoint: .bottomTrailing))
          .opacity(c.isDark ? 0.15 : 1)
          .overlay(PaperPreview(style: .ENGINEERING, zoom: 1).padding(14))
          .frame(width: 200, height: 150)
          .clipShape(RoundedRectangle(cornerRadius: 18))
        DriftingCloud(width: 96, variant: 1, drift: 8).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading).offset(y: 6)
        DriftingCloud(width: 110, variant: 0, drift: 10, period: 12)
          .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing).offset(y: -4)
        Sparkle(size: 12, color: c.blue.opacity(0.6)).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing).offset(x: -30, y: 18)
      }
      .frame(width: 320, height: 190)
      Spacer().frame(height: 20)
      Text(L("start_your_first_notebook")).font(TaliType.headlineMedium).foregroundStyle(c.ink)
      Spacer().frame(height: 8)
      Text(L("a4_pages_that_keep_coming_as")).font(TaliType.bodyLarge).foregroundStyle(c.inkMuted)
      Spacer().frame(height: 24)
      Button(action: onCreate) { Label(L("new_notebook"), systemImage: "plus") }.buttonStyle(PrimaryButtonStyle()).accessibilityIdentifier("empty-new")
    }
    .multilineTextAlignment(.center)
    .frame(maxWidth: .infinity)
    .padding(.top, 50)
  }
}

/// Nothing starred yet (Android's `EmptyStarred`).
struct EmptyStarred: View {
  @Environment(\.tali) private var c

  var body: some View {
    VStack(spacing: 0) {
      ZStack {
        Image(systemName: "star").font(.system(size: 52)).foregroundStyle(starGold).frame(width: 64, height: 64).offset(y: 18)
        DriftingCloud(width: 72, variant: 2, drift: 6).offset(x: 34, y: -22)
      }
      Spacer().frame(height: 16)
      Text(L("no_starred_notebooks_yet")).font(TaliType.headlineMedium).foregroundStyle(c.ink)
      Spacer().frame(height: 8)
      Text(L("hold_a_notebook_and_choose_star")).font(TaliType.bodyLarge).foregroundStyle(c.inkMuted)
    }
    .multilineTextAlignment(.center)
    .frame(maxWidth: .infinity)
    .padding(.top, 60)
  }
}

/// An empty folder (Android's `EmptyFolder`): a folder inside, or a new notebook.
struct EmptyFolder: View {
  var onCreate: () -> Void
  var onNewFolder: () -> Void
  @Environment(\.tali) private var c

  var body: some View {
    VStack(spacing: 0) {
      ZStack {
        FolderGlyph(open: true).fill(c.blue.opacity(0.6), style: FillStyle(eoFill: true)).frame(width: 64, height: 64).offset(y: 18)
        DriftingCloud(width: 72, variant: 2, drift: 6).offset(x: 34, y: -22)
      }
      Spacer().frame(height: 16)
      Text(L("this_folder_is_empty")).font(TaliType.headlineMedium).foregroundStyle(c.ink)
      Spacer().frame(height: 8)
      Text(L("create_a_notebook_here_or_move")).font(TaliType.bodyLarge).foregroundStyle(c.inkMuted)
      Spacer().frame(height: 24)
      HStack(spacing: 10) {
        Button(L("folder_inside"), action: onNewFolder).buttonStyle(QuietButtonStyle()).accessibilityIdentifier("empty-folder-inside")
        Button(action: onCreate) { Label(L("new_notebook"), systemImage: "plus") }.buttonStyle(PrimaryButtonStyle())
      }
    }
    .multilineTextAlignment(.center)
    .frame(maxWidth: .infinity)
    .padding(.top, 60)
  }
}
