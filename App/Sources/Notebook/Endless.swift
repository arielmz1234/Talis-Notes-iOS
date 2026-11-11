import PencilKit
import TaliCore
import UIKit

/// The endless canvas (Android's `pageCount == null`): one page with paper all over it, reaching a
/// screen past everything written and everything seen, so she can always keep going right and down.
extension NoteCanvas.Coordinator {
  /// Everything on the canvas: the writing, and the shapes, pictures and text under it.
  private var contentBounds: CGRect {
    guard let canvas, let under = pages?.pages.under else { return .null }
    var r = canvas.drawing.bounds
    for s in under.shapes { if let b = s.geometry.bounds(s.size) { r = r.union(CGRect(b)) } }
    for p in under.pictures { r = r.union(p.rect) }
    for p in under.pdfPages { r = r.union(p.rect) }
    for t in under.texts { r = r.union(TextLook.frame(t)) }
    return r
  }

  /// How big the endless canvas is now. It only grows, so nothing jumps while she looks around.
  func endlessSize() -> CGSize {
    guard let canvas else { return CGSize(width: CGFloat(A4.width), height: CGFloat(A4.height)) }
    let z = max(canvas.zoomScale, 0.01)
    let view = CGSize(width: canvas.bounds.width / z, height: canvas.bounds.height / z)
    let seen = CGPoint(x: (canvas.contentOffset.x + canvas.bounds.width) / z, y: (canvas.contentOffset.y + canvas.bounds.height) / z)
    let content = contentBounds
    let right = max(CGFloat(A4.width), seen.x, content.isNull ? 0 : content.maxX) + view.width
    let bottom = max(CGFloat(A4.height), seen.y, content.isNull ? 0 : content.maxY) + view.height
    let old = pages?.pages.endless ?? .zero
    return CGSize(width: max(right, old.width), height: max(bottom, old.height))
  }

  /// Scrolled within half a screen of the edge: the canvas grows.
  func growEndless() {
    guard !paged, let canvas, let world = pages?.pages.endless else { return }
    let z = max(canvas.zoomScale, 0.01)
    let right = (canvas.contentOffset.x + canvas.bounds.width * 1.5) / z
    let bottom = (canvas.contentOffset.y + canvas.bounds.height * 1.5) / z
    if right > world.width || bottom > world.height { updateContent() }
  }

  /// Switches between A4 pages and one endless page (the ⋯ menu's Endless canvas). The notebook
  /// given to the canvas has already switched.
  func setEndless(_ on: Bool) {
    if on {
      try? parent.db.run("UPDATE notebooks SET pages=NULL WHERE id=?", [.text(parent.notebook.id)])
      // Writing is no longer hidden past page edges.
      saveNow()
      load()
    } else {
      convertToPages()
    }
    updateChrome()
  }

  /// Turns the endless canvas into A4 pages (Android's `convertToPages`): writing left of, above or
  /// wider than the first page comes onto the pages, centred when it fits (one undo step), and
  /// there are as many pages as it needs.
  private func convertToPages() {
    guard let canvas else { return }
    saveNow()
    let before = (try? parent.db.items(of: parent.notebook.id)) ?? []
    let content = before.reduce(Rect?.none) { r, i in
      let b = Rect(i.l, i.t, i.r, i.b)
      return r.map { Rect(min($0.left, b.left), min($0.top, b.top), max($0.right, b.right), max($0.bottom, b.bottom)) } ?? b
    }
    let shift = layout.shiftOntoPages(content)
    if shift.x != 0 || shift.y != 0 {
      let after = before.map { $0.translated(shift.x, shift.y) }
      write(after)
      canvas.undoManager?.registerUndo(withTarget: self) { coord in
        MainActor.assumeIsolated {
          coord.write(before)
          coord.load()
        }
      }
    }
    let moved = content.map { Rect($0.left + shift.x, $0.top + shift.y, $0.right + shift.x, $0.bottom + shift.y) }
    pageCount = layout.needed(moved)
    persistPages()
    load()
    // The page she was on, across the screen with its top under the toolbars.
    let z = canvas.zoomScale
    let page = min(max(layout.indexAt(Float((canvas.contentOffset.y + canvas.contentInset.top) / z)), 0), pageCount - 1)
    let fit = min((canvas.bounds.width * 0.94) / CGFloat(layout.width), 1.5)
    canvas.setZoomScale(fit, animated: false)
    updateContent()
    canvas.setContentOffset(CGPoint(x: -canvas.contentInset.left, y: CGFloat(layout.rect(page).top) * fit - canvas.contentInset.top), animated: false)
  }

  private func write(_ rows: [ItemRow]) {
    for r in rows { try? parent.db.put(r, in: parent.notebook.id) }
  }

  /// Everything on an endless canvas on screen at once (Android's `fitContent`).
  func fitEverything() {
    guard let canvas else { return }
    let content = contentBounds
    guard !content.isNull, content.width > 1 || content.height > 1 else { return }
    let r = content.insetBy(dx: -24, dy: -24)
    let room = CGSize(width: canvas.bounds.width - 32, height: canvas.bounds.height - parent.topClearance - 40)
    let fit = min(max(min(room.width / r.width, room.height / r.height), canvas.minimumZoomScale), 1.5)
    canvas.setZoomScale(fit, animated: false)
    updateContent()
    canvas.setContentOffset(CGPoint(x: r.minX * fit - (canvas.bounds.width - r.width * fit) / 2, y: r.minY * fit - canvas.contentInset.top), animated: true)
  }
}
