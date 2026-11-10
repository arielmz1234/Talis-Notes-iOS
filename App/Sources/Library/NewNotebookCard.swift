import SwiftUI
import TaliCore

/// The new-notebook card: name, paper, pages and orientation side by side, cover colours, then
/// Cancel / Create. Fits a landscape tablet without scrolling.
struct NewNotebookCard: View {
  var onCreate: (String, PaperStyle, Bool, Bool, UInt32) -> Void
  @Environment(\.dismiss) private var dismiss
  @Environment(\.tali) private var c
  @State private var title = ""
  @AppStorage("defaultPaper") private var paperRaw = PaperStyle.GRID.rawValue
  @AppStorage("defaultLandscape") private var landscape = false
  @State private var paged = true
  @State private var cover = Covers.soft[0]
  @FocusState private var nameFocused: Bool
  @Environment(\.horizontalSizeClass) private var sizeClass
  private var compact: Bool { sizeClass == .compact }

  private var paper: PaperStyle { PaperStyle(rawValue: paperRaw) ?? .GRID }

  var body: some View {
    VStack(alignment: .leading, spacing: 18) {
      let titleRow = compact ? AnyLayout(VStackLayout(alignment: .leading, spacing: 10)) : AnyLayout(HStackLayout(spacing: 14))
      titleRow {
        Text(L("new_notebook")).font(TaliFont.heading(26)).foregroundStyle(c.ink)
        TextField(English.newNotebook, text: $title)
          .font(TaliFont.body(17)).focused($nameFocused).submitLabel(.done)
          .padding(.horizontal, 14).frame(height: 46)
          .background(RoundedRectangle(cornerRadius: 14).fill(c.sunken))
          .accessibilityLabel(L("notebook_name"))
      }
      section(L("paper")) {
        ScrollView(.horizontal) {
          HStack(spacing: 12) {
            ForEach(PaperStyle.allCases, id: \.self) { p in
              Button { withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { paperRaw = p.rawValue } } label: {
                VStack(spacing: 6) {
                  PaperPreview(style: p, zoom: 2.4).frame(width: 74, height: 74).clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(p == paper ? c.accent : c.line, lineWidth: p == paper ? 2.5 : 1))
                  Text(paperName(p)).font(TaliFont.body(13, p == paper ? .semibold : .regular)).foregroundStyle(p == paper ? c.accent : c.inkMuted)
                }
              }
              .buttonStyle(.plain)
            }
          }
          .padding(4)
        }
        .scrollIndicators(.hidden)
      }
      let pagesRow = compact ? AnyLayout(VStackLayout(alignment: .leading, spacing: 14)) : AnyLayout(HStackLayout(alignment: .top, spacing: 24))
      pagesRow {
        section(L("pages")) {
          Picker(L("pages"), selection: $paged) {
            Text(L("a4_pages")).tag(true)
            Text(L("endless")).tag(false)
          }
          .pickerStyle(.segmented)
        }
        section(L("orientation")) {
          Picker(L("orientation"), selection: $landscape) {
            Text(L("portrait")).tag(false)
            Text(L("landscape")).tag(true)
          }
          .pickerStyle(.segmented)
          .disabled(!paged)
        }
        .opacity(paged ? 1 : 0.35)
      }
      Text(L(paged ? (landscape ? "wide_a4_pages_on_their_side" : "upright_a4_pages_one_under_the") : "one_page_that_goes_on_forever"))
        .font(TaliFont.body(14)).foregroundStyle(c.inkMuted)
      section(L("cover")) {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 30, maximum: 36), spacing: 6)], alignment: .leading, spacing: 10) {
          ForEach(Covers.all, id: \.self) { col in
            Button { withAnimation(.spring(response: 0.28, dampingFraction: 0.78)) { cover = col } } label: {
              Circle().fill(Color(argb: col)).frame(width: 26, height: 26)
                .overlay(Circle().stroke(c.accent, lineWidth: 2.5).padding(-4).opacity(col == cover ? 1 : 0))
            }
            .buttonStyle(.plain)
          }
        }
        .padding(.vertical, 4)
      }
      HStack {
        Spacer()
        Button(L("cancel")) { dismiss() }.buttonStyle(QuietButtonStyle())
        Button(L("create")) { onCreate(title, paper, paged, landscape, cover) }.buttonStyle(PrimaryButtonStyle())
          .accessibilityIdentifier("create")
      }
    }
    .padding(compact ? 20 : 28)
    .frame(maxWidth: 680)
    .cloudSurface(radius: 28, crown: .edge)
    .padding(compact ? 12 : 20)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(Color.clear)
    .presentationBackground(.clear)
  }

  private func section<Content: View>(_ label: String, @ViewBuilder _ content: () -> Content) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      Text(label).font(TaliFont.body(14, .bold)).foregroundStyle(c.inkMuted)
      content()
    }
  }
}

func paperName(_ p: PaperStyle) -> String { L("paper_" + p.rawValue.lowercased()) }
