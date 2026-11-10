import PencilKit
import SwiftUI
import TaliCore

/// Lets SwiftUI views ask the canvas for things it alone has (page pictures).
@MainActor
final class CanvasBridge {
  weak var coordinator: NoteCanvas.Coordinator?

  func pageImage(_ i: Int, width: CGFloat) -> UIImage? { coordinator?.pageImage(i, width: width) }
}

extension NoteCanvas.Coordinator {
  /// Page [i] with its paper and writing, [width] points wide.
  func pageImage(_ i: Int, width: CGFloat) -> UIImage? {
    guard let canvas, let pages else { return nil }
    let r = CGRect(layout.rect(i))
    let scale = width / r.width
    let size = CGSize(width: width, height: (r.height * scale).rounded())
    return UIGraphicsImageRenderer(size: size).image { ctx in
      let cg = ctx.cgContext
      cg.saveGState()
      cg.scaleBy(x: scale, y: scale)
      cg.translateBy(x: -r.minX, y: -r.minY)
      cg.clip(to: r)
      pages.pages.draw(in: cg)
      cg.restoreGState()
      canvas.drawing.image(from: r, scale: scale * 2).draw(in: CGRect(origin: .zero, size: size))
    }
  }

  /// Deletes page [i] with everything on it; the pages after it move up (Android's `deletePage`).
  /// The only page is cleared instead. One undo step brings it back.
  func deletePage(_ i: Int) {
    guard let canvas else { return }
    let before = canvas.drawing
    let oldCount = pageCount
    let pitch = layout.pitch
    let shift = pageCount > 1
    if shift { pageCount -= 1 }
    var strokes: [PKStroke] = []
    for (k, pk) in before.strokes.enumerated() {
      guard k < stored.count else { continue }
      let s = stored[k].stroke
      let page = layout.indexAt(s.inputs.points.first?.y ?? 0)
      if page == i { continue }
      if page > i, shift {
        var moved = s
        moved.inputs.points = s.inputs.points.map { var p = $0; p.y -= pitch; return p }
        let fresh = moved.pkStroke(mask: mask(for: moved))
        pending[StrokeKey(fresh)] = moved
        strokes.append(fresh)
      } else {
        strokes.append(pk)
      }
    }
    clearSelection()
    canvas.undoManager?.registerUndo(withTarget: self) { coord in
      MainActor.assumeIsolated {
        coord.pageCount = oldCount
        coord.updateContent()
        coord.persistPageCount()
        coord.canvas?.drawing = before
        coord.reportUndo()
      }
    }
    updateContent()
    persistPageCount()
    canvas.drawing = PKDrawing(strokes: strokes)
    reportUndo()
  }

  func persistPageCount() {
    try? parent.db.run("UPDATE notebooks SET pages=? WHERE id=?", [.int(Int64(pageCount)), .text(parent.notebook.id)])
  }
}

/// All the pages at a glance (Android's `PagesOverview`): tap one to look closer, then go to it or
/// delete it; Add page at the end.
struct PagesOverview: View {
  var count: Int
  var current: Int
  var bridge: CanvasBridge
  var onGo: (Int) -> Void
  var onAdd: () -> Void
  var onDelete: (Int) -> Void
  var onClose: () -> Void
  @Environment(\.tali) private var c
  @State private var peek: Int?
  @State private var confirming: Int?
  @State private var version = 0

  var body: some View {
    ZStack {
      VStack(alignment: .leading, spacing: 14) {
        HStack(alignment: .firstTextBaseline) {
          VStack(alignment: .leading, spacing: 2) {
            Text(L("pages")).font(TaliType.titleLarge).foregroundStyle(c.ink)
            Text(count == 1 ? L("t_1_page") : L("n_pages", count)).font(TaliType.bodySmall).foregroundStyle(c.inkMuted)
          }
          Spacer()
          Button(L("done"), action: onClose).buttonStyle(QuietButtonStyle())
        }
        ScrollView {
          LazyVGrid(columns: [GridItem(.adaptive(minimum: 132), spacing: 18)], spacing: 18) {
            ForEach(0..<count, id: \.self) { i in
              PageTile(index: i, selected: i == current, bridge: bridge, version: version) { withAnimation(Ease.outStrong(duration: 0.24)) { peek = i } }
            }
            Button(action: {
              onAdd()
              version += 1
            }) {
              VStack(spacing: 8) {
                RoundedRectangle(cornerRadius: 10).strokeBorder(c.inkFaint.opacity(0.6), style: StrokeStyle(lineWidth: 1.5, dash: [8, 6]))
                  .aspectRatio(CGFloat(A4.width / A4.height), contentMode: .fit)
                  .overlay(Image(systemName: "plus").font(.system(size: 26)).foregroundStyle(c.accent))
                Text(L("add_page")).font(TaliType.labelLarge).foregroundStyle(c.inkMuted)
              }
            }
            .buttonStyle(PressStyle())
            .accessibilityLabel(L("add_a_page"))
          }
          .padding(4)
        }
      }
      .padding(24)
      .frame(maxWidth: 900, maxHeight: .infinity)
      .cloudSurface(radius: 24, crown: .none, shadowDepth: 12)
      .padding(24)
      if let i = peek {
        c.scrim.ignoresSafeArea().onTapGesture { withAnimation(.easeOut(duration: 0.16)) { peek = nil } }
        PagePeek(
          index: i, bridge: bridge, single: count == 1,
          onGo: {
            onGo(i)
            onClose()
          },
          onDelete: { confirming = i }
        )
        .transition(.opacity.combined(with: .scale(scale: 0.96)))
      }
    }
    .confirmationDialog(
      count == 1 ? L("clear_this_page") : L("delete_page_n", (confirming ?? 0) + 1),
      isPresented: Binding(get: { confirming != nil }, set: { if !$0 { confirming = nil } }), titleVisibility: .visible
    ) {
      Button(count == 1 ? L("clear_page") : L("delete_page"), role: .destructive) {
        if let i = confirming { onDelete(i) }
        withAnimation(.easeOut(duration: 0.16)) { peek = nil }
        version += 1
      }
    } message: {
      Text(count == 1 ? L("everything_on_it_is_removed_undo") : L("the_page_and_everything_on_it"))
    }
  }
}

private struct PageTile: View {
  var index: Int
  var selected: Bool
  var bridge: CanvasBridge
  var version: Int
  var action: () -> Void
  @Environment(\.tali) private var c
  @State private var image: UIImage?

  var body: some View {
    Button(action: action) {
      VStack(spacing: 8) {
        Color.white
          .aspectRatio(CGFloat(A4.width / A4.height), contentMode: .fit)
          .overlay { if let image { Image(uiImage: image).resizable().scaledToFill() } }
          .clipShape(RoundedRectangle(cornerRadius: 10))
          .overlay(RoundedRectangle(cornerRadius: 10).stroke(selected ? c.accent : c.line, lineWidth: selected ? 2.5 : 1))
          .shadow(color: c.accent.opacity(0.2), radius: selected ? 10 : 5, y: 3)
        Text("\(index + 1)").font(TaliType.labelLarge).foregroundStyle(selected ? c.onAccent : c.inkMuted)
          .padding(.horizontal, 10).padding(.vertical, 2)
          .background(RoundedRectangle(cornerRadius: 10).fill(selected ? c.accent : .clear))
      }
    }
    .buttonStyle(PressStyle())
    .accessibilityLabel(L("look_at_page_n", index + 1))
    .task(id: version) { image = bridge.pageImage(index, width: 240) }
  }
}

/// One page large over the dimmed overview, with Delete and Go to page above it.
private struct PagePeek: View {
  var index: Int
  var bridge: CanvasBridge
  var single: Bool
  var onGo: () -> Void
  var onDelete: () -> Void
  @Environment(\.tali) private var c
  @State private var image: UIImage?

  var body: some View {
    GeometryReader { geo in
      let w = min((geo.size.height - 72) * 0.92 * CGFloat(A4.width / A4.height), geo.size.width * 0.8)
      VStack(spacing: 10) {
        HStack {
          Text(L("page_n", index + 1)).font(TaliType.titleMedium).foregroundStyle(c.inkFaint)
          Spacer()
          round("trash", single ? L("clear_page") : L("delete_page"), c.danger, onDelete)
          round("arrow.up.right", L("go_to_page"), c.accent, onGo)
        }
        Color.white
          .aspectRatio(CGFloat(A4.width / A4.height), contentMode: .fit)
          .overlay { if let image { Image(uiImage: image).resizable().scaledToFill() } }
          .clipShape(RoundedRectangle(cornerRadius: 14))
          .shadow(color: .black.opacity(0.25), radius: 24)
      }
      .frame(width: w)
      .frame(width: geo.size.width, height: geo.size.height)
    }
    .task { image = bridge.pageImage(index, width: 1100) }
  }

  private func round(_ icon: String, _ label: String, _ tint: Color, _ action: @escaping () -> Void) -> some View {
    Button(action: action) {
      Image(systemName: icon).font(.system(size: 18)).foregroundStyle(tint)
        .frame(width: 44, height: 44).background(Circle().fill(.white).shadow(color: .black.opacity(0.15), radius: 6))
    }
    .buttonStyle(PressStyle())
    .accessibilityLabel(label)
  }
}
