import SwiftUI
import TaliCore

/// A name field (Android's `TitleField`): 52 pt, 14 pt corners on the page colour, the placeholder
/// in faint ink. It takes the keyboard when it appears, with what's there already picked.
struct TitleField: View {
  @Binding var text: String
  var placeholder: String
  var autoFocus = true
  var onDone: () -> Void
  @Environment(\.tali) private var c
  @FocusState private var focused: Bool

  var body: some View {
    TextField("", text: $text, prompt: Text(placeholder).foregroundStyle(c.inkFaint))
      .font(TaliType.bodyLarge).foregroundStyle(c.ink).tint(c.accent)
      .focused($focused).submitLabel(.done).onSubmit(onDone)
      .padding(.horizontal, 16).frame(height: 52)
      .background(RoundedRectangle(cornerRadius: 14).fill(c.background))
      .overlay(RoundedRectangle(cornerRadius: 14).stroke(c.line, lineWidth: 1))
      .onAppear {
        guard autoFocus else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { focused = true }
      }
      .onReceive(NotificationCenter.default.publisher(for: UITextField.textDidBeginEditingNotification)) { note in
        (note.object as? UITextField)?.selectAll(nil)
      }
  }
}

/// One name to type, for renaming (Android's `NameDialog`).
struct NameCard: View {
  var title: String
  var initial: String
  var placeholder: String
  var confirm: String
  var onClose: () -> Void
  var onConfirm: (String) -> Void
  @State private var text = ""
  @Environment(\.tali) private var c

  var body: some View {
    DialogCard {
      Text(title).font(TaliType.titleLarge).foregroundStyle(c.ink)
      Spacer().frame(height: 18)
      TitleField(text: $text, placeholder: placeholder) { onConfirm(text) }
        .accessibilityIdentifier("name-field")
      Spacer().frame(height: 24)
      CardButtons {
        Button(L("cancel"), action: onClose).buttonStyle(QuietButtonStyle())
        Button(confirm) { onConfirm(text) }.buttonStyle(PrimaryButtonStyle()).accessibilityIdentifier("name-confirm")
      }
    }
    .onAppear { text = initial }
  }
}

/// Are you sure? (Android's `ConfirmDialog`): a title, a line, Cancel and the action, which is a
/// soft red button when it can't be taken back. It adds no tint behind it.
struct ConfirmCard: View {
  var title: String
  var message: String
  var confirm: String
  var destructive = false
  var onClose: () -> Void
  var onConfirm: () -> Void
  @Environment(\.tali) private var c

  var body: some View {
    DialogCard(width: 460) {
      Text(title).font(TaliType.titleLarge).foregroundStyle(c.ink)
      Spacer().frame(height: 10)
      Text(message).font(TaliType.bodyMedium).foregroundStyle(c.inkMuted).fixedSize(horizontal: false, vertical: true)
      Spacer().frame(height: 24)
      CardButtons {
        Button(L("cancel"), action: onClose).buttonStyle(QuietButtonStyle())
        if destructive {
          Button(confirm, action: onConfirm).buttonStyle(QuietButtonStyle(warning: true)).accessibilityIdentifier("confirm")
        } else {
          Button(confirm, action: onConfirm).buttonStyle(PrimaryButtonStyle()).accessibilityIdentifier("confirm")
        }
      }
    }
  }
}

/// Naming a new folder and choosing its colour (Android's `NewFolderDialog`).
struct NewFolderCard: View {
  var title: String
  var placeholder: String
  var initialColor: UInt32
  var onClose: () -> Void
  var onCreate: (String, UInt32) -> Void
  @State private var name = ""
  @State private var color: UInt32 = 0
  @Environment(\.tali) private var c

  var body: some View {
    DialogCard(width: 480) {
      HStack(spacing: 14) {
        FolderGlyph(open: false).fill(Color(argb: color), style: FillStyle(eoFill: true)).frame(width: 24, height: 24)
          .frame(width: 44, height: 44)
          .background(RoundedRectangle(cornerRadius: 14).fill(folderWash(Color(argb: color), dark: c.isDark)))
        Text(title).font(TaliType.titleLarge).foregroundStyle(c.ink)
      }
      Spacer().frame(height: 18)
      TitleField(text: $name, placeholder: placeholder) { create() }
        .accessibilityIdentifier("folder-name")
      Spacer().frame(height: 16)
      SectionLabel(text: L("colour"))
      Spacer().frame(height: 6)
      CoverSwatches(current: color, perRow: 9) { color = $0 }.padding(.vertical, 6)
      Spacer().frame(height: 22)
      CardButtons {
        Button(L("cancel"), action: onClose).buttonStyle(QuietButtonStyle())
        Button(L("create")) { create() }.buttonStyle(PrimaryButtonStyle()).accessibilityIdentifier("folder-create")
      }
    }
    .onAppear { color = initialColor }
  }

  private func create() { onCreate(name.trimmingCharacters(in: .whitespaces).isEmpty ? placeholder : name, color) }
}

/// Where a folder goes: the top level or any folder that isn't inside it (Android's `MoveFolderDialog`).
struct MoveFolderCard: View {
  var folder: Folder
  var folders: [Folder]
  var onClose: () -> Void
  var onMove: (String?) -> Void
  @Environment(\.tali) private var c

  var body: some View {
    let blocked = FolderTree.descendants(of: folder.id, in: folders).union([folder.id])
    DialogCard(width: 460) {
      Text(L("move_n", folder.name)).font(TaliType.titleLarge).foregroundStyle(c.ink)
      Spacer().frame(height: 12)
      CardBody(maxHeight: 420) {
        MoveTarget(label: L("top_level"), icon: .book, tint: c.inkMuted, depth: 0, current: folder.parentId == nil) { onMove(nil) }
        ForEach(FolderTree.ordered(folders).filter { !blocked.contains($0.folder.id) }, id: \.folder.id) { target, depth in
          MoveTarget(label: target.name, icon: .folder, tint: Color(argb: target.color), depth: depth + 1, current: target.id == folder.parentId) {
            onMove(target.id)
          }
        }
      }
      Spacer().frame(height: 16)
      CardButtons { Button(L("cancel"), action: onClose).buttonStyle(QuietButtonStyle()) }
    }
  }
}

private struct MoveTarget: View {
  enum Icon { case book, folder }
  var label: String
  var icon: Icon
  var tint: Color
  var depth: Int
  var current: Bool
  var action: () -> Void
  @Environment(\.tali) private var c

  var body: some View {
    Button(action: action) {
      HStack(spacing: 12) {
        switch icon {
        case .book: Image(systemName: "book.pages").font(.system(size: 17)).foregroundStyle(tint).frame(width: 20, height: 20)
        case .folder: FolderGlyph(open: false).fill(tint, style: FillStyle(eoFill: true)).frame(width: 20, height: 20)
        }
        Text(label).font(TaliType.titleSmall).foregroundStyle(current ? c.inkFaint : c.ink).lineLimit(1)
        Spacer(minLength: 0)
        if current { Text(L("here_now")).font(TaliType.labelMedium).foregroundStyle(c.inkFaint) }
      }
      .padding(.horizontal, 12)
      .frame(height: 44)
      .contentShape(RoundedRectangle(cornerRadius: 12))
    }
    .buttonStyle(.plain)
    .disabled(current)
    .padding(.leading, CGFloat(depth) * 18)
  }
}

/// A notebook in Recently deleted, tapped: how long it has left, Delete forever or Restore.
struct TrashCard: View {
  var notebook: NotebookMeta
  var onClose: () -> Void
  var onErase: () -> Void
  var onRestore: () -> Void
  @Environment(\.tali) private var c

  var body: some View {
    let deleted = notebook.deleted ?? 0
    let left = trashDays - Int((nowMillis() - deleted) / 86_400_000)
    let word = relativeTime(deleted)
    let when = word.prefix(1).lowercased() + word.dropFirst()
    DialogCard(width: 480) {
      Text("“\(notebook.title)”").font(TaliType.titleLarge).foregroundStyle(c.ink)
      Spacer().frame(height: 8)
      Text(left <= 1 ? L("deleted_when_for_good_in_one_day", when) : L("deleted_when_for_good_in_days", when, left))
        .font(TaliType.bodyMedium).foregroundStyle(c.inkMuted).fixedSize(horizontal: false, vertical: true)
      Spacer().frame(height: 24)
      CardButtons {
        Button(L("delete_forever"), action: onErase).buttonStyle(QuietButtonStyle(warning: true))
        Button(L("restore"), action: onRestore).buttonStyle(PrimaryButtonStyle()).accessibilityIdentifier("restore")
      }
    }
  }
}

/// A name field with Cancel and Done for a system alert (the notebook screen's rename).
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
