import SwiftUI
import TaliCore

/// A PDF or picture opened from another app and not saved yet (Android's `PdfViewerBar`): back, its
/// name with "N pages · Not saved", a big Save, and ⋯ with All pages, Fit to screen and Dark paper.
struct DraftBar: View {
  var title: String
  var pages: Int?
  @Binding var dark: Bool
  var onBack: () -> Void
  var onSave: () -> Void
  var onPages: (() -> Void)?
  var onFit: () -> Void
  @Environment(\.tali) private var c
  @State private var shown = false

  var body: some View {
    HStack(spacing: 10) {
      FloatingBar(crown: .little) {
        ToolIcon(system: "arrow.backward", label: L("back"), action: onBack).accessibilityIdentifier("back")
      }
      .arrive(0, shown)
      FloatingBar(crown: .none) {
        VStack(alignment: .leading, spacing: 0) {
          Text(title).font(TaliType.titleSmall).foregroundStyle(c.ink).lineLimit(1)
          Text([pages.map { $0 == 1 ? L("t_1_page") : L("n_pages", $0) }, L("not_saved")].compactMap { $0 }.joined(separator: " · "))
            .font(TaliType.bodySmall).foregroundStyle(c.inkFaint).lineLimit(1)
        }
        .padding(.horizontal, 10)
      }
      .frame(maxWidth: 380, alignment: .leading)
      .fixedSize(horizontal: true, vertical: false)
      .arrive(1, shown)
      Spacer(minLength: 10)
      Button(action: onSave) { Label(L("save"), systemImage: "square.and.arrow.down").font(TaliType.labelLarge) }
        .buttonStyle(PrimaryButtonStyle())
        .frame(height: 52)
        .accessibilityIdentifier("draft-save")
        .arrive(2, shown)
      FloatingBar(crown: .softEdge) {
        Menu {
          if let onPages { Button(L("all_pages"), systemImage: "square.grid.2x2", action: onPages) }
          Button(L("fit_to_screen"), systemImage: "arrow.up.left.and.arrow.down.right", action: onFit)
          Toggle(isOn: $dark) { Label(L("dark_paper"), systemImage: "moon") }
        } label: {
          Image(systemName: "ellipsis").font(.system(size: 19)).foregroundStyle(c.ink).frame(width: 44, height: 44)
        }
        .accessibilityLabel(L("more"))
      }
      .arrive(3, shown)
    }
    .onAppear { shown = true }
  }
}

extension View {
  /// The viewer's pieces lift in 40 ms apart, like the toolbars.
  fileprivate func arrive(_ order: Int, _ shown: Bool) -> some View {
    opacity(shown ? 1 : 0)
      .offset(y: shown ? 0 : -10)
      .scaleEffect(shown ? 1 : 0.96, anchor: .top)
      .animation(Ease.outStrong(duration: 0.26).delay(0.04 * Double(order)), value: shown)
  }
}

/// Save (Android's `SavePdfDialog`): the name, ready to change, and which folder it goes into.
struct SaveDraftCard: View {
  var title: String
  var onCancel: () -> Void
  var onSave: (String, String?) -> Void
  @Environment(Library.self) private var lib
  @Environment(\.tali) private var c
  @State private var name = ""
  @State private var folder: String?
  @FocusState private var focused: Bool

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Text(L("save_to_your_notebooks")).font(TaliType.titleLarge).foregroundStyle(c.ink)
      Spacer().frame(height: 6)
      Text(L("it_goes_into_your_notebooks_ready")).font(TaliType.bodySmall).foregroundStyle(c.inkMuted)
      Spacer().frame(height: 16)
      TextField(L("notebook_name"), text: $name)
        .font(TaliType.titleMedium).foregroundStyle(c.ink)
        .focused($focused)
        .submitLabel(.done)
        .onSubmit { onSave(name, folder) }
        .padding(.horizontal, 14).frame(height: 48)
        .background(RoundedRectangle(cornerRadius: 14).fill(c.sunken))
        .accessibilityIdentifier("draft-name")
      if !lib.folders.isEmpty {
        Spacer().frame(height: 14)
        HStack {
          Text(L("folder")).font(TaliType.titleSmall).foregroundStyle(c.inkMuted)
          Spacer()
          Menu {
            Button(L("no_folder")) { folder = nil }
            ForEach(lib.folders) { f in Button(f.name) { folder = f.id } }
          } label: {
            HStack(spacing: 6) {
              Text(lib.folders.first { $0.id == folder }?.name ?? L("no_folder")).font(TaliType.titleSmall).foregroundStyle(c.ink).lineLimit(1)
              Image(systemName: "chevron.up.chevron.down").font(.system(size: 12)).foregroundStyle(c.inkFaint)
            }
          }
        }
      }
      Spacer().frame(height: 24)
      HStack(spacing: 8) {
        Spacer()
        Button(L("cancel"), action: onCancel).buttonStyle(QuietButtonStyle())
        Button(L("save")) { onSave(name, folder) }.buttonStyle(PrimaryButtonStyle()).accessibilityIdentifier("draft-save-confirm")
      }
    }
    .padding(28)
    .frame(maxWidth: 480)
    .cloudSurface(radius: 24, crown: .none, shadowDepth: 12)
    .onAppear {
      name = title
      focused = true
    }
  }
}

/// Leaving unsaved (Android's `LeavePdfDialog`): Keep looking, Leave without saving, or Save.
struct LeaveDraftCard: View {
  var title: String
  var onStay: () -> Void
  var onLeave: () -> Void
  var onSave: () -> Void
  @Environment(\.tali) private var c

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Text(L("leave_without_saving")).font(TaliType.titleLarge).foregroundStyle(c.ink)
      Spacer().frame(height: 8)
      Text(L("n_isn_t_in_your_notebooks", title)).font(TaliType.bodyMedium).foregroundStyle(c.inkMuted)
      Spacer().frame(height: 24)
      HStack(spacing: 8) {
        Button(L("keep_looking"), action: onStay).buttonStyle(QuietButtonStyle())
        Spacer()
        Button(action: onLeave) { Text(L("leave_without_saving_2")).foregroundStyle(c.danger) }.buttonStyle(QuietButtonStyle())
          .accessibilityIdentifier("draft-leave")
        Button(L("save"), action: onSave).buttonStyle(PrimaryButtonStyle())
      }
    }
    .padding(28)
    .frame(maxWidth: 560)
    .cloudSurface(radius: 24, crown: .none, shadowDepth: 12)
  }
}
