import SwiftUI
import TaliCore

/// A notebook: its pages in one column on the desk, with the top bar floating over them.
/// (First step: pages and paper with scrolling and zoom; writing comes next, see PLAN.md.)
struct NotebookView: View {
  var notebook: NotebookMeta
  var onBack: () -> Void
  @Environment(\.tali) private var c
  @State private var zoom: CGFloat = 1
  @GestureState private var pinch: CGFloat = 1

  var body: some View {
    GeometryReader { geo in
      let layout = notebook.pageLayout
      let count = max(notebook.pages ?? 1, 1)
      let fit = min((geo.size.width - 48) / CGFloat(layout.width), 1.2)
      let scale = fit * zoom * pinch
      ZStack(alignment: .top) {
        c.desk.ignoresSafeArea()
        ScrollView([.vertical, .horizontal]) {
          VStack(spacing: CGFloat(Pages.gap) * scale) {
            ForEach(0..<count, id: \.self) { i in
              Canvas { ctx, size in
                let r = layout.rect(i)
                PaperPainter.draw(
                  notebook.paper, page: CGRect(x: CGFloat(r.left), y: CGFloat(r.top), width: CGFloat(r.width), height: CGFloat(r.height)),
                  in: ctx, origin: CGPoint(x: 0, y: CGFloat(r.top)), scale: scale, dark: notebook.dark)
              }
              .frame(width: CGFloat(layout.width) * scale, height: CGFloat(layout.height) * scale)
              .shadow(color: c.glow.opacity(0.12), radius: 10, y: 4)
            }
          }
          .padding(.top, 110)
          .padding(.bottom, 60)
          .frame(minWidth: geo.size.width)
        }
        .scrollIndicators(.hidden)
        .gesture(
          MagnifyGesture()
            .updating($pinch) { v, s, _ in s = v.magnification }
            .onEnded { v in zoom = min(max(zoom * v.magnification, 0.3), 6) })
        TopBar(title: notebook.title, onBack: onBack)
          .padding(.horizontal, 16).padding(.top, 8)
      }
    }
  }
}

/// Back and the notebook's name on the left (more tools join it as they're ported).
private struct TopBar: View {
  var title: String
  var onBack: () -> Void
  @Environment(\.tali) private var c

  var body: some View {
    HStack(spacing: 10) {
      Button(action: onBack) {
        Image(systemName: "chevron.backward").font(.system(size: 19, weight: .semibold)).foregroundStyle(c.ink)
          .frame(width: 48, height: 48).cloudSurface(radius: 24, crown: .little, shadowDepth: 4)
      }
      .accessibilityLabel(L("back"))
      .accessibilityIdentifier("back")
      Text(title).font(TaliFont.body(17, .semibold)).foregroundStyle(c.ink).lineLimit(1)
        .padding(.horizontal, 18).frame(height: 48).cloudSurface(radius: 24, crown: .softEdge, shadowDepth: 4)
      Spacer()
    }
  }
}
