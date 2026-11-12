import SwiftUI
import TaliCore

/// Quick open (Android's `QuickOpen`): a little cloud with two puffs beside Back (so the two little
/// clouds side by side don't match), opening the notebooks she opened last, topped up with the most
/// recently edited, up to eight. One tap swaps the open notebook; Back still goes to the library.
struct QuickOpen: View {
  var current: String
  var onOpen: (NotebookMeta) -> Void
  @Environment(Library.self) private var lib
  @Environment(\.tali) private var c
  @State private var open = false

  static let recentMax = 8

  private var recent: [NotebookMeta] {
    let byId = Dictionary(uniqueKeysWithValues: lib.notebooks.map { ($0.id, $0) })
    let opened = lib.opened.filter { $0 != current }.compactMap { byId[$0] }
    let openedIds = Set(opened.map(\.id))
    let rest = lib.notebooks.sorted { $0.updated > $1.updated }.filter { $0.id != current && !openedIds.contains($0.id) }
    return Array((opened + rest).prefix(QuickOpen.recentMax))
  }

  var body: some View {
    FloatingBar(crown: .littleTwin) {
      ToolIcon(system: "clock.arrow.circlepath", label: L("recent_notebooks")) { open = true }
        .accessibilityIdentifier("quick-open")
    }
    .popover(isPresented: $open, arrowEdge: .top) {
      VStack(alignment: .leading, spacing: 0) {
        Text(L("recent_notebooks").uppercased()).font(TaliType.labelSmall).tracking(0.66).foregroundStyle(c.inkFaint)
          .padding(.horizontal, 16).padding(.top, 10).padding(.bottom, 6)
        let list = recent
        if list.isEmpty {
          Text(L("notebooks_you_open_show_up_here")).font(TaliType.bodySmall).foregroundStyle(c.inkMuted)
            .frame(maxWidth: 260, alignment: .leading).padding(.horizontal, 16).padding(.bottom, 10)
        }
        ForEach(Array(list.enumerated()), id: \.element.id) { i, nb in
          QuickOpenRow(notebook: nb, order: i) {
            open = false
            onOpen(nb)
          }
        }
      }
      .padding(.bottom, 6)
      .frame(minWidth: 260, maxWidth: 340)
      .environment(\.tali, c)
      .presentationCompactAdaptation(.popover)
      .presentationBackground(c.surface)
    }
  }
}

/// One recent notebook: its page with the cover-colour spine, its name and when it was edited.
/// Rows drift in 30 ms apart, as on Android.
private struct QuickOpenRow: View {
  var notebook: NotebookMeta
  var order: Int
  var action: () -> Void
  @Environment(\.tali) private var c
  @State private var shown = false

  var body: some View {
    Button(action: action) {
      HStack(spacing: 12) {
        ZStack(alignment: .leading) {
          PaperPreview(style: notebook.paper, landscape: notebook.landscape, dark: notebook.dark, zoom: 1.6)
          Rectangle().fill(Color(argb: notebook.cover)).frame(width: 4)
        }
        .frame(width: 52, height: 38)
        .clipShape(RoundedRectangle(cornerRadius: 7))
        .overlay(RoundedRectangle(cornerRadius: 7).stroke(c.line, lineWidth: 1))
        VStack(alignment: .leading, spacing: 0) {
          Text(notebook.title.isEmpty ? L("untitled") : notebook.title).font(TaliType.titleSmall).foregroundStyle(c.ink).lineLimit(1)
          let word = relativeTime(notebook.updated)
          Text(L("edited") + word.prefix(1).lowercased() + word.dropFirst()).font(TaliType.bodySmall).foregroundStyle(c.inkFaint).lineLimit(1)
        }
        Spacer(minLength: 0)
      }
      .padding(.horizontal, 12).padding(.vertical, 6)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain).contentShape(Rectangle())
    .accessibilityLabel(L("open_n", notebook.title))
    .opacity(shown ? 1 : 0)
    .offset(y: shown ? 0 : -10)
    .onAppear {
      withAnimation(Ease.outStrong(duration: 0.24).delay(Double(min(order, 6)) * 0.03)) { shown = true }
    }
  }
}
