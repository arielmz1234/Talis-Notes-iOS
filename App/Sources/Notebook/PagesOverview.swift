import PencilKit
import SwiftUI
import TaliCore

/// Lets SwiftUI views ask the canvas for things it alone has (page pictures).
@MainActor
final class CanvasBridge {
  weak var coordinator: NoteCanvas.Coordinator?
  /// Called once the pages have been laid out again, so page pictures can be redrawn.
  var pagesChanged: () -> Void = {}

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
  /// The only page is cleared instead.
  func deletePage(_ i: Int) { rearrangePages(Pages.withoutPages(pageCount, [i])) }

  /// Lays the pages out again as [order] (old page numbers, top to bottom) with everything on them
  /// (Android's `rearrangePages`): a page left out is deleted, one listed twice is copied. One undo step.
  func rearrangePages(_ order: [Int]) {
    saveNow()
    let before = (try? parent.db.items(of: parent.notebook.id)) ?? []
    var z = before.map(\.z).max() ?? 0
    let plan = layout.rearranged(before, count: pageCount, order: order, newId: { newId() }, nextZ: &z)
    let kept = Set(before.map(\.id))
    replaceRows(
      remove: plan.removed, put: plan.written, count: plan.count,
      back: (remove: plan.written.map(\.id).filter { !kept.contains($0) }, put: before, count: pageCount))
  }

  private func replaceRows(remove: [String], put: [ItemRow], count: Int, back: (remove: [String], put: [ItemRow], count: Int)) {
    for id in remove { try? parent.db.removeItem(id) }
    for r in put { try? parent.db.put(r, in: parent.notebook.id) }
    pageCount = count
    persistPages()
    canvas?.undoManager?.registerUndo(withTarget: self) { coord in
      MainActor.assumeIsolated { coord.replaceRows(remove: back.remove, put: back.put, count: back.count, back: (remove, put, count)) }
    }
    clearSelection()
    load()
    touch()
    parent.bridge?.pagesChanged()
  }
}

/// All the pages at a glance (Android's `PagesOverview`): tap one to look closer, then go to it or
/// delete it; hold one and drag it to move it (the others make way); Select picks several to
/// duplicate or delete together; Add page at the end.
struct PagesOverview: View {
  var count: Int
  var current: Int
  /// The pages' width over height.
  var aspect: CGFloat
  var bridge: CanvasBridge
  var onGo: (Int) -> Void
  var onAdd: () -> Void
  /// The pages laid out again (old page numbers, top to bottom), and what to tell her.
  var onRearrange: ([Int], String) -> Void
  var onClose: () -> Void
  @Environment(\.tali) private var c
  @State private var peek: Int?
  @State private var confirming: Int?
  /// Pages picked to duplicate or delete; nil when not picking.
  @State private var picked: Set<Int>?
  @State private var deletingPicked = false
  /// The order while a page is being dragged, and the one held.
  @State private var order: [Int]?
  @State private var held: Int?
  @State private var version = 0

  /// A drag let go outside the pages never drops, and SwiftUI doesn't say so: an order left over
  /// from it counts only while it still lists every page, and goes at the next tap.
  private var shown: [Int] {
    if let order, order.count == count { return order }
    return Array(0..<count)
  }

  var body: some View {
    ZStack {
      VStack(alignment: .leading, spacing: 14) {
        header
        ScrollView {
          LazyVGrid(columns: [GridItem(.adaptive(minimum: 132), spacing: 18)], spacing: 18) {
            ForEach(Array(shown.enumerated()), id: \.element) { at, i in
              PageTile(
                index: i, number: at + 1, aspect: aspect, selected: i == current && picked == nil, picking: picked != nil,
                picked: picked?.contains(i) == true, bridge: bridge, version: version
              ) {
                order = nil
                held = nil
                if var p = picked {
                  if p.contains(i) { p.remove(i) } else { p.insert(i) }
                  picked = p
                } else {
                  withAnimation(Ease.outStrong(duration: 0.24)) { peek = i }
                }
              }
              .onDrag {
                held = i
                order = Array(0..<count)
                return NSItemProvider(object: "\(i)" as NSString)
              }
              .onDrop(of: [.text], delegate: PageDrop(target: i, held: $held, order: $order, onDrop: finishMove))
            }
            if picked == nil { addTile }
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
          index: i, aspect: aspect, bridge: bridge, single: count == 1,
          onGo: {
            onGo(i)
            onClose()
          },
          onDelete: { confirming = i }
        )
        .transition(.opacity.combined(with: .scale(scale: 0.96)))
      }
    }
    .onChange(of: count) { _, _ in
      picked = nil
      order = nil
      held = nil
    }
    .onAppear { bridge.pagesChanged = { version += 1 } }
    .onDisappear { bridge.pagesChanged = {} }
    .confirmationDialog(
      count == 1 ? L("clear_this_page") : L("delete_page_n", (confirming ?? 0) + 1),
      isPresented: Binding(get: { confirming != nil }, set: { if !$0 { confirming = nil } }), titleVisibility: .visible
    ) {
      Button(count == 1 ? L("clear_page") : L("delete_page"), role: .destructive) {
        if let i = confirming { onRearrange(Pages.withoutPages(count, [i]), L("page_n_deleted_undo_brings_the", i + 1)) }
        withAnimation(.easeOut(duration: 0.16)) { peek = nil }
        version += 1
      }
    } message: {
      Text(count == 1 ? L("everything_on_it_is_removed_undo") : L("the_page_and_everything_on_it"))
    }
    .confirmationDialog(pickedTitle, isPresented: $deletingPicked, titleVisibility: .visible) {
      Button(picked?.count == count ? L("clear_pages") : L("delete"), role: .destructive) {
        let gone = picked ?? []
        let all = gone.count == count
        picked = nil
        onRearrange(
          Pages.withoutPages(count, gone),
          all ? L("pages_cleared_undo_brings_them_back") : gone.count == 1 ? L("page_deleted_undo_brings_it_back") : L("n_pages_deleted_undo_brings_them", gone.count))
      }
    } message: {
      Text(picked?.count == count ? L("everything_on_them_is_removed_and") : L("they_go_with_everything_on_them"))
    }
  }

  private var pickedTitle: String {
    let n = picked?.count ?? 0
    return n == count ? L("clear_every_page") : n == 1 ? L("delete_1_page") : L("delete_n_pages", n)
  }

  /// The title beside its buttons; on a phone, the buttons under it.
  private var header: some View {
    ViewThatFits(in: .horizontal) {
      HStack(alignment: .center) {
        heading
        Spacer(minLength: 12)
        actions
      }
      VStack(alignment: .leading, spacing: 10) {
        heading
        actions.frame(maxWidth: .infinity, alignment: .trailing)
      }
    }
    .animation(Ease.outStrong(duration: 0.22), value: picked != nil)
  }

  private var heading: some View {
    VStack(alignment: .leading, spacing: 2) {
      Text(L("pages")).font(TaliType.titleLarge).foregroundStyle(c.ink)
      Text(picked != nil ? L("tap_pages_to_pick_them") : (count == 1 ? L("t_1_page") : L("n_pages", count)) + L("tap_a_page_to_look_closer"))
        .font(TaliType.bodyMedium).foregroundStyle(c.inkMuted)
    }
  }

  @ViewBuilder private var actions: some View {
    if let chosen = picked {
      ViewThatFits(in: .horizontal) {
        HStack(spacing: 10) {
          pickedCount(chosen)
          pickedButtons(chosen)
        }
        VStack(alignment: .trailing, spacing: 8) {
          pickedCount(chosen)
          pickedButtons(chosen)
        }
      }
      .transition(.opacity.combined(with: .offset(y: 8)))
    } else {
      HStack(spacing: 8) {
        if count > 1 { Button(L("select")) { picked = [] }.buttonStyle(QuietButtonStyle()).fixedSize().accessibilityIdentifier("pages-select") }
        Button(L("done"), action: onClose).buttonStyle(QuietButtonStyle()).fixedSize()
      }
      .transition(.opacity)
    }
  }

  private func pickedCount(_ chosen: Set<Int>) -> some View {
    HStack(spacing: 10) {
      Text(chosen.count == 1 ? L("t_1_selected") : L("n_selected", chosen.count)).font(TaliType.titleMedium).foregroundStyle(c.ink).fixedSize()
      Button(chosen.count == count ? L("select_none") : L("select_all")) { picked = chosen.count == count ? [] : Set(0..<count) }
        .buttonStyle(QuietButtonStyle()).fixedSize()
    }
  }

  private func pickedButtons(_ chosen: Set<Int>) -> some View {
    HStack(spacing: 10) {
      HStack(spacing: 0) {
        ToolIcon(system: "doc.on.doc", label: L("duplicate"), enabled: !chosen.isEmpty) {
          picked = nil
          onRearrange(Pages.withCopies(count, chosen), chosen.count == 1 ? L("page_duplicated") : L("n_pages_duplicated", chosen.count))
        }
        ToolIcon(system: "trash", label: L("delete"), enabled: !chosen.isEmpty) { deletingPicked = true }
      }
      .padding(.horizontal, 4)
      .background(RoundedRectangle(cornerRadius: 16).fill(c.sunken.opacity(0.7)))
      Button(L("done")) { picked = nil }.buttonStyle(PrimaryButtonStyle()).fixedSize()
    }
  }

  private var addTile: some View {
    Button(action: {
      onAdd()
      version += 1
    }) {
      VStack(spacing: 8) {
        RoundedRectangle(cornerRadius: 10).strokeBorder(c.inkFaint.opacity(0.6), style: StrokeStyle(lineWidth: 1.5, dash: [8, 6]))
          .aspectRatio(aspect, contentMode: .fit)
          .overlay(Image(systemName: "plus").font(.system(size: 26)).foregroundStyle(c.accent))
        Text(L("add_page")).font(TaliType.labelLarge).foregroundStyle(c.inkMuted)
      }
    }
    .buttonStyle(PressStyle())
    .accessibilityLabel(L("add_a_page"))
  }

  /// Let go: the held page and everything on it moves to where it was dropped.
  private func finishMove() {
    defer {
      order = nil
      held = nil
    }
    guard let o = order, let h = held, o != Array(0..<count), let to = o.firstIndex(of: h) else { return }
    onRearrange(o, L("page_n_moved_to_n", h + 1, to + 1))
  }
}

/// A held page passing over another takes its place; the others make way.
private struct PageDrop: DropDelegate {
  var target: Int
  @Binding var held: Int?
  @Binding var order: [Int]?
  var onDrop: () -> Void

  func dropEntered(info: DropInfo) {
    guard let h = held, h != target, var o = order, let from = o.firstIndex(of: h), let to = o.firstIndex(of: target) else { return }
    o.remove(at: from)
    o.insert(h, at: to)
    withAnimation(Ease.outStrong(duration: 0.22)) { order = o }
  }

  func dropUpdated(info: DropInfo) -> DropProposal? { DropProposal(operation: .move) }

  func performDrop(info: DropInfo) -> Bool {
    onDrop()
    return true
  }
}

private struct PageTile: View {
  var index: Int
  var number: Int
  var aspect: CGFloat
  var selected: Bool
  var picking: Bool
  var picked: Bool
  var bridge: CanvasBridge
  var version: Int
  var action: () -> Void
  @Environment(\.tali) private var c
  @State private var image: UIImage?

  var body: some View {
    Button(action: action) {
      VStack(spacing: 8) {
        Color.white
          .aspectRatio(aspect, contentMode: .fit)
          .overlay { if let image { Image(uiImage: image).resizable().scaledToFill() } }
          .clipShape(RoundedRectangle(cornerRadius: 10))
          .overlay(RoundedRectangle(cornerRadius: 10).stroke(selected || picked ? c.accent : c.line, lineWidth: selected || picked ? 2.5 : 1))
          .overlay(alignment: .topTrailing) {
            // While picking, a check circle in the corner: filled when picked.
            if picking {
              Circle().fill(picked ? c.accent : Color.white.opacity(0.9))
                .overlay(Circle().stroke(picked ? c.accent : c.inkFaint, lineWidth: 1.5))
                .overlay { if picked { Image(systemName: "checkmark").font(.system(size: 12, weight: .bold)).foregroundStyle(.white) } }
                .frame(width: 26, height: 26)
                .shadow(color: .black.opacity(0.15), radius: 3)
                .padding(8)
                .transition(.opacity.combined(with: .scale(scale: 0.7)))
            }
          }
          .shadow(color: c.accent.opacity(0.2), radius: selected ? 10 : 5, y: 3)
        Text("\(number)").font(TaliType.labelLarge).foregroundStyle(selected ? c.onAccent : c.inkMuted)
          .padding(.horizontal, 10).padding(.vertical, 2)
          .background(RoundedRectangle(cornerRadius: 10).fill(selected ? c.accent : .clear))
      }
      .animation(.easeOut(duration: 0.15), value: picked)
      .animation(Ease.outStrong(duration: 0.2), value: picking)
    }
    .buttonStyle(PressStyle())
    .accessibilityLabel(picking ? L("pick_page_n", number) : L("look_at_page_n", number))
    .accessibilityAddTraits(picked ? .isSelected : [])
    .task(id: version) { image = bridge.pageImage(index, width: 240) }
  }
}

/// One page large over the dimmed overview, with Delete and Go to page above it.
private struct PagePeek: View {
  var index: Int
  var aspect: CGFloat
  var bridge: CanvasBridge
  var single: Bool
  var onGo: () -> Void
  var onDelete: () -> Void
  @Environment(\.tali) private var c
  @State private var image: UIImage?

  var body: some View {
    GeometryReader { geo in
      let w = min((geo.size.height - 72) * 0.92 * aspect, geo.size.width * 0.8)
      VStack(spacing: 10) {
        HStack {
          Text(L("page_n", index + 1)).font(TaliType.titleMedium).foregroundStyle(c.inkFaint)
          Spacer()
          round("trash", single ? L("clear_page") : L("delete_page"), c.danger, onDelete)
          round("arrow.up.right", L("go_to_page"), c.accent, onGo)
        }
        Color.white
          .aspectRatio(aspect, contentMode: .fit)
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
