import SwiftUI
import TaliCore

/// The new-notebook card, as Android's `NewNotebookDialog`: the title with a little drifting cloud,
/// the name field, the papers, Pages beside Orientation (which fades out for an endless canvas but
/// keeps its place), a line saying what that means, Dark paper, the cover colours, Cancel / Create.
/// It fits a landscape tablet without scrolling; on a short screen the middle scrolls.
struct NewNotebookCard: View {
  var onClose: () -> Void = {}
  /// In the folder being looked at, shown under the title.
  var folderName: String? = nil
  /// What it's called if she leaves the name empty (shown as the hint).
  var suggestedName = English.newNotebook
  var defaultCover = Covers.soft[0]
  var onCreate: (_ title: String, _ paper: PaperStyle, _ paged: Bool, _ landscape: Bool, _ dark: Bool, _ cover: UInt32) -> Void
  @Environment(\.tali) private var c
  @State private var title = ""
  @AppStorage("defaultPaper") private var paperRaw = PaperStyle.GRID.rawValue
  @AppStorage("defaultLandscape") private var landscape = false
  @AppStorage("defaultPaged") private var paged = true
  @State private var dark = false
  @State private var cover: UInt32 = 0
  @FocusState private var nameFocused: Bool

  private var paper: Binding<PaperStyle> {
    Binding(get: { PaperStyle(rawValue: paperRaw) ?? .GRID }, set: { paperRaw = $0.rawValue })
  }

  private var pagesChoice: some View {
    VStack(alignment: .leading, spacing: 6) {
      SectionLabel(text: L("pages"))
      Segmented(options: [true, false], selected: $paged) { $0 ? L("a4_pages") : L("endless") }
    }
  }

  /// Fades out for an endless canvas but keeps its place, so nothing below jumps.
  private var orientationChoice: some View {
    VStack(alignment: .leading, spacing: 6) {
      SectionLabel(text: L("orientation"))
      Segmented(options: [false, true], selected: Binding(get: { landscape }, set: { if paged { landscape = $0 } })) {
        $0 ? L("landscape") : L("portrait")
      }
    }
    .opacity(paged ? 1 : 0)
    .animation(.easeOut(duration: paged ? 0.2 : 0.14), value: paged)
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      CardBody {
        HStack(alignment: .top) {
          VStack(alignment: .leading, spacing: 4) {
            Text(L("new_notebook")).font(TaliType.titleLarge).foregroundStyle(c.ink)
            if let folderName { Text(L("in_n", folderName)).font(TaliType.bodyMedium).foregroundStyle(c.inkMuted) }
          }
          Spacer()
          DriftingCloud(width: 64, variant: 2, drift: 4)
        }
        Spacer().frame(height: 10)
        TextField("", text: $title, prompt: Text(suggestedName).foregroundStyle(c.inkFaint))
          .font(TaliType.bodyLarge).foregroundStyle(c.ink).tint(c.accent)
          .focused($nameFocused).submitLabel(.done).onSubmit { nameFocused = false }
          .padding(.horizontal, 16).frame(height: 52)
          .background(RoundedRectangle(cornerRadius: 14).fill(c.background))
          .overlay(RoundedRectangle(cornerRadius: 14).stroke(c.line, lineWidth: 1))
          .accessibilityLabel(L("notebook_name"))
        Spacer().frame(height: 14)
        SectionLabel(text: L("paper"))
        Spacer().frame(height: 4)
        PaperPicker(style: paper, tileWidth: PhoneWriting.onPhone ? 62 : 80, perRow: 7, dark: dark || c.isDark)
        Spacer().frame(height: 12)
        // Side by side, or one under the other on a narrow phone.
        ViewThatFits(in: .horizontal) {
          HStack(alignment: .top, spacing: 14) {
            pagesChoice
            orientationChoice
          }
          VStack(alignment: .leading, spacing: 10) {
            pagesChoice
            orientationChoice
          }
        }
        Spacer().frame(height: 6)
        Text(L(!paged ? "one_page_that_goes_on_forever" : (landscape ? "wide_a4_pages_on_their_side" : "upright_a4_pages_one_under_the")))
          .font(TaliType.bodySmall).foregroundStyle(c.inkMuted)
        Spacer().frame(height: 6)
        ToggleRow(label: L("dark_paper"), on: $dark, detail: L("a_black_page_your_pens_switch"))
        Spacer().frame(height: 8)
        SectionLabel(text: L("cover"))
        Spacer().frame(height: 6)
        CoverSwatches(current: cover, spacing: 6) { cover = $0 }
          .padding(.leading, 3).padding(.vertical, 4)
      }
      Spacer().frame(height: 16)
      HStack(spacing: 10) {
        Spacer()
        Button(L("cancel"), action: onClose).buttonStyle(QuietButtonStyle())
        Button(L("create")) {
          onCreate(title.trimmingCharacters(in: .whitespaces).isEmpty ? suggestedName : title, paper.wrappedValue, paged, paged && landscape, dark, cover)
        }
          .buttonStyle(PrimaryButtonStyle())
          .accessibilityIdentifier("create")
      }
    }
    .padding(28)
    .frame(maxWidth: 640)
    .cloudSurface(radius: 24, crown: .none, shadowDepth: 12)
    .onAppear { cover = defaultCover }
  }
}

func paperName(_ p: PaperStyle) -> String { L("paper_" + p.rawValue.lowercased()) }
